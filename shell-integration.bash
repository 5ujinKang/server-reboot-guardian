#!/usr/bin/env bash
# server-manager shell integration
# Provides:  server-lock-on / server-lock-off functions
#            [server-lock]==ON indicator in PS1 when your lock is active
#
# System-wide (run once as root, done by install.sh):
#   echo 'source /usr/local/lib/server-manager/shell-integration.bash' \
#       >> /etc/bash.bashrc
#
# Personal (no root needed):
#   echo 'source ~/server-manager/shell-integration.bash' >> ~/.bashrc

# Locate the server-lock binary
if command -v server-lock &>/dev/null; then
    _SRG_LOCK_BIN="server-lock"
elif [ -x "$HOME/server-manager/server-lock" ]; then
    _SRG_LOCK_BIN="python3 $HOME/server-manager/server-lock"
else
    _SRG_LOCK_BIN=""
fi

_SRG_USER="$(id -un 2>/dev/null)"
_SRG_ORIG_PS1=""
_SRG_PS1_SAVED=0   # set to 1 after first prompt so we capture PS1 only once

__srg_prompt() {
    # Capture the original PS1 on the first prompt (after all rc files have run)
    if [ "$_SRG_PS1_SAVED" = "0" ]; then
        _SRG_ORIG_PS1="$PS1"
        _SRG_PS1_SAVED=1
    fi

    local active=0
    for _d in /var/lib/server-manager/locks /tmp/server-guardian-locks; do
        if [ -f "$_d/$_SRG_USER.json" ]; then
            active=1
            break
        fi
    done

    if [ "$active" = "1" ]; then
        PS1="\[\033[1;31m\][server-lock]==ON\[\033[0m\] ${_SRG_ORIG_PS1}"
    else
        PS1="${_SRG_ORIG_PS1}"
    fi
}

# Append to PROMPT_COMMAND without clobbering existing hooks
PROMPT_COMMAND="${PROMPT_COMMAND:+${PROMPT_COMMAND}; }__srg_prompt"

server-lock() {
    if [ -z "$_SRG_LOCK_BIN" ]; then
        echo "server-lock: binary not found. Run install.sh or set \$_SRG_LOCK_BIN." >&2
        return 1
    fi
    $_SRG_LOCK_BIN "$@"
}

server-lock-on() {
    if [ $# -gt 0 ]; then
        server-lock on "$*"
    else
        server-lock on
    fi
}

server-lock-off() {
    server-lock off
}
