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

# tmux 是否存在经 ssh / mosh attach 的客户端（client 进程祖先链含 sshd / mosh-server，判据见 ~/.local/bin/remote-session）
# 用途：本地 tmux 被远程 ssh attach 时，剪贴板应走 OSC52 跟随对端
is_tmux_ssh_attached() {
  [[ -n "${TMUX:-}" ]] || return 1
  "$HOME/.local/bin/remote-session" tmux-any
}
