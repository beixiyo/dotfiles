# Environment detection and dependency checks

has() { command -v "$1" &>/dev/null }

is_mac() { [[ "$(uname)" == Darwin ]] }

is_tty() { [[ -t 0 ]] }

is_wsl() {
  [[ -n "$WSL_DISTRO_NAME" || -n "$WSLENV" ]] || \
    { [[ -r /proc/version ]] && grep -qi microsoft /proc/version }
}

# Require a command to be available, abort with error if missing
# Usage: require bun || return 1
require() {
  has "$1" || { log_err "$1 is required but not installed"; return 1 }
}
