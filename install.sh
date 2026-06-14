#!/usr/bin/env bash
# install.sh — installs server-reboot-guardian on a shared Linux server
# Run as root: sudo bash install.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARDIAN_BIN="/usr/local/sbin/server-reboot-guardian"
VOTE_BIN="/usr/local/bin/reboot-vote"
CHECK_BIN="/usr/local/bin/check-reboot-changes"
SUDOERS_FILE="/etc/sudoers.d/server-reboot-guardian"
PROFILE_SCRIPT="/etc/profile.d/reboot-check.sh"
SNAPSHOT_DIR="/var/lib/server-reboot-guardian"

if [[ $EUID -ne 0 ]]; then
    echo "Run as root: sudo bash install.sh" >&2
    exit 1
fi

echo "Installing server-reboot-guardian..."

install -o root -g root -m 0755 "$SCRIPT_DIR/server-reboot-guardian"  "$GUARDIAN_BIN"
install -o root -g root -m 0755 "$SCRIPT_DIR/reboot-vote"              "$VOTE_BIN"
install -o root -g root -m 0755 "$SCRIPT_DIR/check-reboot-changes"     "$CHECK_BIN"

# Persistent directory for pre-reboot hardware snapshots (world-readable)
mkdir -p "$SNAPSHOT_DIR"
chmod 0755 "$SNAPSHOT_DIR"

echo "Installed binaries:"
echo "  $GUARDIAN_BIN"
echo "  $VOTE_BIN"
echo "  $CHECK_BIN"

# Write sudoers drop-in:
#   - sudo reboot (and common aliases) → run the guardian instead
#   - guardian itself can invoke real /sbin/reboot (internal use only)
cat > "$SUDOERS_FILE" << 'EOF'
# server-reboot-guardian: intercept sudo reboot on shared servers

# Guardian runs as root and keeps SUDO_USER so it knows who asked
Defaults!server-reboot-guardian env_keep += "SUDO_USER"

# Allow all users to run the guardian via "sudo reboot"
Cmnd_Alias SRG_GUARDIAN = /usr/local/sbin/server-reboot-guardian
ALL ALL=(root) NOPASSWD: SRG_GUARDIAN

# The guardian internally calls the real reboot — allow it only from the guardian
# (by limiting the command to root-owned, no-arg or standard reboot flags)
Cmnd_Alias SRG_REAL_REBOOT = /sbin/reboot, /sbin/reboot -h, /sbin/reboot -f, \
                              /sbin/reboot -h now, /usr/sbin/reboot

# Block direct sudo reboot so all reboots go through the guardian
ALL ALL=(root) !SRG_REAL_REBOOT
EOF

chmod 0440 "$SUDOERS_FILE"
visudo -c -f "$SUDOERS_FILE"
echo "Sudoers drop-in installed: $SUDOERS_FILE"

# Symlink: "sudo reboot" resolves to the guardian via PATH
# /usr/local/sbin comes before /sbin in most distros' secure_path
SYMLINK="/usr/local/sbin/reboot"
if [[ ! -e "$SYMLINK" ]]; then
    ln -s "$GUARDIAN_BIN" "$SYMLINK"
    echo "Symlink created: $SYMLINK -> $GUARDIAN_BIN"
else
    echo "Symlink $SYMLINK already exists — skipping."
fi

# Install login-time reboot check for all interactive shells
cat > "$PROFILE_SCRIPT" << 'PROFILE_EOF'
# server-reboot-guardian: notify users if server rebooted since last login
if [ -t 1 ] && command -v check-reboot-changes >/dev/null 2>&1; then
    check-reboot-changes
fi
PROFILE_EOF
chmod 0644 "$PROFILE_SCRIPT"
echo "Login hook installed: $PROFILE_SCRIPT"

echo ""
echo "Done."
echo "  sudo reboot         → triggers the guardian (notify + vote)"
echo "  reboot-vote yes|no  → cast a vote on a pending reboot"
echo "  check-reboot-changes → run manually to see post-reboot hardware diff"
echo "  (also runs automatically at each login via $PROFILE_SCRIPT)"
