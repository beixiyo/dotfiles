#!/usr/bin/env bash
# tmux.sh — tmux pane 判断与切换
# 被 main.sh source，不可单独执行
# 依赖调用方 scope 中已设置：_saved_pane, _tmux_socket

# 远程判定的唯一 shell 实现（逐 client 判 remote / local，tmux 外看自身进程链与环境变量），见脚本头部
_REMOTE_SESSION="${REMOTE_SESSION_BIN:-$HOME/.local/bin/remote-session}"

# _user_present: 用户当前正盯着发起通知的终端 pane 时返回 0
# 规则：niri/macOS 焦点不在终端 → 明确不在场；否则看 tmux 活动 pane 是否仍是本 pane
# macOS 补充：前台已是终端 → 在场（tmux tab 高亮/BEL 已足够提示，不发系统通知）
# niri 下跳过远程 client：物理机桌面在场与否只看本地 client 停在哪
_user_present() {
  _niri_up && ! _focused_is_terminal && return 1
  _macos_focus_not_terminal && return 1
  [[ "$(uname)" == "Darwin" ]] && return 0
  [[ -z "$_saved_pane" ]] && return 0

  # 遍历所有 client，避免后台进程没有 client 上下文导致无 -c 时返回空
  local _cpid _kind _cl _cur
  while read -r _cpid _kind _cl; do
    [[ -n "$_cl" ]] || continue
    _niri_up && [[ "$_kind" == remote ]] && continue
    _cur=$(tmux -S "$_tmux_socket" display-message -c "$_cl" -p '#{pane_id}' 2>/dev/null)
    [[ "$_cur" == "$_saved_pane" ]] && return 0
  done < <("$_REMOTE_SESSION" -S "$_tmux_socket" clients 2>/dev/null)
  return 1
}

# _is_remote_session: 用户正通过 SSH / mosh 远程驱动（通知发到物理机桌面、远程看不到）时返回 0
# 策略：任一在连 tmux client 来自远程即远程；不在 tmux / 无 client 时看自身进程链，再看 SSH 环境变量
#   能识别「本地起的 tmux 被 SSH attach 复用」：此时 pane 环境里没有 SSH_CONNECTION，只有 client 祖先链暴露远程身份
# 依赖调用方 scope 的 _tmux_socket；remote-session 缺失时按本地处理
_is_remote_session() {
  [[ -x "$_REMOTE_SESSION" ]] || return 1
  if [[ -n "$_tmux_socket" ]]; then
    "$_REMOTE_SESSION" -S "$_tmux_socket" any
  else
    TMUX='' "$_REMOTE_SESSION" any
  fi
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
