#!/usr/bin/env bash
# main.sh — 通用完成通知入口（支持点击跳转 tmux pane + 显示对话上下文）
# 用法: main.sh <app 名> [上下文标题]
# 依赖: macOS: brew install terminal-notifier (可选，无则退化为基础通知)
#       Linux: notify-send (libnotify)

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=niri.sh
source "$_dir/niri.sh"
# shellcheck source=tmux.sh
source "$_dir/tmux.sh"
# shellcheck source=context.sh
source "$_dir/context.sh"
# shellcheck source=linux.sh
source "$_dir/linux.sh"
# shellcheck source=macos.sh
source "$_dir/macos.sh"

# --- 终端偏好顺序（焦点跳转用：动态按序命中第一个存在的终端窗口） ---
# 想改偏好直接调顺序即可；niri/KWin/X11 走子串匹配，macOS 映射见 macos.sh:_macos_map
_TERM_APPS=(kitty ghostty wezterm)

# --- 运行时变量（tmux / niri socket） ---

_saved_pane="$TMUX_PANE"
_tmux_socket="${TMUX%%,*}"

# NIRI_SOCKET 在 tmux 环境里可能丢失，缺失时从运行目录兜底
[[ -z "$NIRI_SOCKET" ]] && \
  NIRI_SOCKET=$(ls -t "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"/niri.wayland-*.sock 2>/dev/null | head -1)
export NIRI_SOCKET

# --- 在场检测：用户已在 Claude 所在的 tmux pane（且终端在焦点）→ 不通知 ---

if [[ -n "$TMUX" ]]; then
  _user_present && exit 0
fi

# --- 远程检测：人在 SSH 远程驱动时，通知只会发到物理机 mako、远程根本看不到、纯堆积 → 跳过 ---
# 判据见 _is_remote_session（优先 tmux 在连客户端的 sshd 祖先，兜底 SSH_CONNECTION）
# 临时想在远程也强制收到通知：NOTIFY_FORCE=1
if [[ -z "${NOTIFY_FORCE:-}" ]] && _is_remote_session; then
  exit 0
fi

# --- 提取通知标题与正文 ---

desc="${1:-终端}"
_body=$(_extract_context "${2:-}")

# --- 分发到平台对应通知模块 ---

if [[ "$(uname)" == "Darwin" ]]; then
  _notify_macos "$desc" "$_body" "$_saved_pane" "$_tmux_socket"
elif command -v notify-send &>/dev/null; then
  _notify_linux "$desc" "$_body" "$_saved_pane" "$_tmux_socket"
fi
