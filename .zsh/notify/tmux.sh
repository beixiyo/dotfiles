#!/usr/bin/env bash
# tmux.sh — tmux pane 判断与切换
# 被 main.sh source，不可单独执行
# 依赖调用方 scope 中已设置：_saved_pane, _tmux_socket

# _user_present: 用户当前正盯着发起通知的终端 pane 时返回 0
# 规则：niri 可用且焦点不在终端 → 明确不在场；否则看 tmux 活动 pane 是否仍是本 pane
_user_present() {
  _niri_up && ! _focused_is_terminal && return 1
  [[ -z "$_saved_pane" ]] && return 0

  # 遍历所有 client，避免后台进程没有 client 上下文导致无 -c 时返回空
  local _cl _cur
  while IFS= read -r _cl; do
    _cur=$(tmux -S "$_tmux_socket" display-message -c "$_cl" -p '#{pane_id}' 2>/dev/null)
    [[ "$_cur" == "$_saved_pane" ]] && return 0
  done < <(tmux -S "$_tmux_socket" list-clients -F '#{client_name}' 2>/dev/null)
  return 1
}

# _pid_under_sshd <pid>: 进程祖先链（最多 25 层）中出现 sshd* 则返回 0（该会话来自 SSH）
# 依赖 Linux /proc；非 Linux（如 macOS 无 /proc）读取失败而返回 1，交由 SSH_CONNECTION 兜底
_pid_under_sshd() {
  local _pid="$1" _comm _i=0
  while [[ -n "$_pid" && "$_pid" != 0 && "$_pid" != 1 && $_i -lt 25 ]]; do
    _comm=$(cat "/proc/$_pid/comm" 2>/dev/null) || return 1
    case "$_comm" in sshd*) return 0 ;; esac
    _pid=$(awk '/^PPid:/{print $2}' "/proc/$_pid/status" 2>/dev/null)
    _i=$((_i + 1))
  done
  return 1
}

_is_loopback_host() {
  local _host="${1,,}"
  [[ "$_host" == "localhost" || "$_host" == "::1" || "$_host" == 127.* ]]
}

# _is_remote_session: 用户正通过 SSH 远程驱动（通知发到物理机 mako、远程看不到）时返回 0
# 主判据：任一【在连】tmux 客户端的进程祖先含 sshd —— 能识别「公司 kitty 本地起 tmux、
#   家里 wezterm SSH attach 复用」这种场景：复用已存在的 pane 时其环境里【没有】SSH_CONNECTION
#   （tmux 服务器是本地起的，环境被冻结），只有客户端进程祖先链才暴露远程身份
# 兜底：非 tmux 场景，Claude 直接跑在 SSH shell 里 → 看 SSH_CONNECTION / SSH_TTY
# 依赖调用方 scope 的 _tmux_socket
_is_remote_session() {
  if [[ -n "$_tmux_socket" ]] && command -v tmux &>/dev/null; then
    local _cpid
    while IFS= read -r _cpid; do
      [[ -n "$_cpid" ]] || continue
      _pid_under_sshd "$_cpid" && return 0
    done < <(tmux -S "$_tmux_socket" list-clients -F '#{client_pid}' 2>/dev/null)
  fi

  if [[ -n "${SSH_CONNECTION:-}" ]]; then
    local _src _src_port _dst _dst_port
    read -r _src _src_port _dst _dst_port <<< "$SSH_CONNECTION"
    _is_loopback_host "$_src" && _is_loopback_host "$_dst" && return 1
    return 0
  fi

  [[ -n "${SSH_TTY:-}" ]] && return 0
  return 1
}

# _switch_tmux_pane <pane> <socket>: 切换到指定 tmux pane
_switch_tmux_pane() {
  local pane="$1" socket="$2"
  [[ -z "$pane" || -z "$socket" ]] && return

  local session window
  session=$(tmux -S "$socket" display-message -t "$pane" -p '#{session_name}' 2>/dev/null)
  window=$(tmux -S "$socket" display-message -t "$pane" -p '#{window_index}' 2>/dev/null)
  [[ -z "$session" || -z "$window" ]] && return

  tmux -S "$socket" switch-client -t "${session}:${window}" 2>/dev/null
  tmux -S "$socket" select-pane -t "$pane" 2>/dev/null
}
