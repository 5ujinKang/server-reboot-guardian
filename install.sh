#!/usr/bin/env bash
# install.sh — installs server-manager on a shared Linux server
# Run as root: sudo bash install.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARDIAN_BIN="/usr/local/sbin/server-reboot"
VOTE_BIN="/usr/local/bin/reboot-vote"
CHECK_BIN="/usr/local/bin/check-reboot-changes"
CONTENTION_BIN="/usr/local/bin/show-contention"
LOCK_BIN="/usr/local/bin/server-lock"
SHELL_LIB_DIR="/usr/local/lib/server-manager"
SHELL_LIB="$SHELL_LIB_DIR/shell-integration.bash"
SUDOERS_FILE="/etc/sudoers.d/server-manager"
PROFILE_SCRIPT="/etc/profile.d/reboot-check.sh"
MOTD_SCRIPT="/etc/update-motd.d/90-server-contention"
DATA_DIR="/var/lib/server-manager"
LOCK_DIR="$DATA_DIR/locks"

if [[ $EUID -ne 0 ]]; then
    echo "Run as root: sudo bash install.sh" >&2
    exit 1
fi

echo "Installing server-manager..."

install -o root -g root -m 0755 "$SCRIPT_DIR/server-reboot"   "$GUARDIAN_BIN"
install -o root -g root -m 0755 "$SCRIPT_DIR/reboot-vote"              "$VOTE_BIN"
install -o root -g root -m 0755 "$SCRIPT_DIR/check-reboot-changes"     "$CHECK_BIN"
install -o root -g root -m 0755 "$SCRIPT_DIR/show-contention"          "$CONTENTION_BIN"
install -o root -g root -m 0755 "$SCRIPT_DIR/server-lock"              "$LOCK_BIN"

# Persistent data directory for snapshots (world-readable)
mkdir -p "$DATA_DIR"
chmod 0755 "$DATA_DIR"

# Lock directory: sticky + world-writable so each user manages their own file
mkdir -p "$LOCK_DIR"
chmod 1777 "$LOCK_DIR"

# Shell integration library
mkdir -p "$SHELL_LIB_DIR"
install -o root -g root -m 0644 "$SCRIPT_DIR/shell-integration.bash" "$SHELL_LIB"

echo "Installed binaries:"
echo "  $GUARDIAN_BIN"
echo "  $VOTE_BIN"
echo "  $CHECK_BIN"
echo "  $CONTENTION_BIN"
echo "  $LOCK_BIN"
echo "  $SHELL_LIB"

# Write sudoers drop-in
cat > "$SUDOERS_FILE" << 'EOF'
# server-manager: intercept sudo reboot on shared servers

Defaults!/usr/local/sbin/server-reboot env_keep += "SUDO_USER"

Cmnd_Alias SRG_GUARDIAN = /usr/local/sbin/server-reboot
ALL ALL=(root) NOPASSWD: SRG_GUARDIAN

Cmnd_Alias SRG_REAL_REBOOT = /sbin/reboot, /sbin/reboot -h, /sbin/reboot -f, \
                              /sbin/reboot -h now, /usr/sbin/reboot

ALL ALL=(root) !SRG_REAL_REBOOT
EOF

chmod 0440 "$SUDOERS_FILE"
visudo -c -f "$SUDOERS_FILE"
echo "Sudoers drop-in installed: $SUDOERS_FILE"

# Symlink: "sudo reboot" → guardian
SYMLINK="/usr/local/sbin/reboot"
if [[ ! -e "$SYMLINK" ]]; then
    ln -s "$GUARDIAN_BIN" "$SYMLINK"
    echo "Symlink created: $SYMLINK -> $GUARDIAN_BIN"
else
    echo "Symlink $SYMLINK already exists — skipping."
fi

# MOTD: show server status (load + locks + active workloads) in SSH welcome
cat > "$MOTD_SCRIPT" << 'MOTD_EOF'
#!/bin/sh
# server-manager: server status at login
exec /usr/local/bin/check-reboot-changes --summary-only 2>/dev/null
MOTD_EOF
chmod 0755 "$MOTD_SCRIPT"
echo "MOTD script installed: $MOTD_SCRIPT"

# profile.d: post-reboot hardware diff (shown after MOTD, as the logged-in user)
cat > "$PROFILE_SCRIPT" << 'PROFILE_EOF'
# server-manager: show post-reboot hardware changes at login
if [ -t 1 ] && command -v check-reboot-changes >/dev/null 2>&1; then
    check-reboot-changes --reboot-check-only
fi
PROFILE_EOF
chmod 0644 "$PROFILE_SCRIPT"
echo "Login hook installed: $PROFILE_SCRIPT"

# Shell integration: server-lock-on/off functions + PS1 indicator for all users
BASHRC_MARKER="# server-manager shell integration"
if ! grep -qF "$BASHRC_MARKER" /etc/bash.bashrc; then
    cat >> /etc/bash.bashrc << BASHRC_EOF

$BASHRC_MARKER
if [ -f "$SHELL_LIB" ]; then
    source "$SHELL_LIB"
fi
BASHRC_EOF
    echo "Shell integration added to /etc/bash.bashrc"
else
    echo "Shell integration already in /etc/bash.bashrc — skipping."
fi

echo ""
echo "Done."
echo "  sudo reboot          → triggers the guardian (notify + vote)"
echo "  reboot-vote yes|no   → cast a vote on a pending reboot"
echo "  show-contention      → who is running what + hardware contention"
echo "  server-lock-on       → announce performance-critical work"
echo "  server-lock-off      → clear your lock"
echo "  server-lock status   → show all active locks"
echo "  check-reboot-changes → post-reboot hardware diff"
