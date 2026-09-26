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

# tmux 是否存在经 ssh attach 的客户端（客户端进程父链为 sshd）
# 用途：本地 tmux 被远程 ssh attach 时，剪贴板应走 OSC52 跟随对端
is_tmux_ssh_attached() {
  [[ -n "${TMUX:-}" ]] || return 1

  local client_pid parent_comm
  for client_pid in $(tmux list-clients -F '#{client_pid}' 2>/dev/null); do
    parent_comm=$(ps -o comm= -p "$(ps -o ppid= -p "$client_pid" 2>/dev/null)" 2>/dev/null)
    [[ "$parent_comm" == sshd* ]] && return 0
  done

  return 1
}
