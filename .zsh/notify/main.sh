#!/usr/bin/env bash
# main.sh — 通用完成通知入口（支持点击跳转 tmux pane + 显示对话上下文）
# 用法: main.sh <app 名> [上下文标题]
# 依赖: macOS: brew install terminal-notifier（≥ 3.0，见 macos.sh 头部的一次性 lsregister 步骤；无则退化 osascript 仅显示）
#       Linux: notify-send (libnotify)

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- 用户配置（环境变量可临时覆盖） ---
NOTIFY_WHEN_REMOTE="${NOTIFY_WHEN_REMOTE:-0}" # 1：SSH 远程操作时也通知本机桌面
NOTIFY_TIMEOUT_MINUTES="${NOTIFY_TIMEOUT_MINUTES:-15}" # 通知显示时长（分钟）
NOTIFY_MAX="${NOTIFY_MAX:-10}"                # 同一 app 最多保留数量；0 表示不限
NOTIFY_SOUND="${NOTIFY_SOUND:-0}"             # 1：通过终端 BEL 播放完成提示音
NOTIFY_DESKTOP="${NOTIFY_DESKTOP:-1}"         # 1：发送桌面系统通知
NOTIFY_DEBUG="${NOTIFY_DEBUG:-0}"             # 1：把通知/跳转过程写入 /tmp/notify-debug.log

# shellcheck source=niri.sh
source "$_dir/niri.sh"
# shellcheck source=tmux.sh
source "$_dir/tmux.sh"
# shellcheck source=terminal.sh
source "$_dir/terminal.sh"
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

# --- 读取 hook stdin（只能读一次；context.sh 复用 _hook_json） ---
# 带 agent_id 的事件来自 subagent / teammate，不是“主会话在等你”，直接不通知
# 限时读：非 hook 调用方（如 opencode 插件的 Bun $）会继承父进程 stdin，若是永不关闭的管道，cat 会永久阻塞
_hook_json=""
[[ -t 0 ]] || IFS= read -r -d '' -t 2 _hook_json
# 只过滤“完成”类事件；PermissionRequest / PreToolUse(AskUserQuestion) 等“需要你”的事件即使来自 subagent 也要通知
if [[ -n "$_hook_json" ]]; then
  _agent_id=$(printf '%s' "$_hook_json" | jq -r '.agent_id // empty' 2>/dev/null)
  _hook_event=$(printf '%s' "$_hook_json" | jq -r '.hook_event_name // empty' 2>/dev/null)
  _dbg "hook event=${_hook_event:-?} agent_id=${_agent_id:-<none>}"
  case "$_hook_event" in
    Stop|SubagentStop|TeammateIdle|TaskCompleted) [[ -n "$_agent_id" ]] && exit 0 ;;
  esac
fi

_notify_terminal_sound
[[ "$NOTIFY_DESKTOP" == 1 ]] || exit 0

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
if [[ "$NOTIFY_WHEN_REMOTE" != 1 && -z "${NOTIFY_FORCE:-}" ]] && _is_remote_session; then
  exit 0
fi

# --- 提取通知标题与正文 ---

desc="${1:-${AI_AGENT_NAME:-Terminal}}"
_body=$(_extract_context "${2:-}")
_dbg "notify title=${desc} body=${_body//$'\n'/ | }"

# --- 分发到平台对应通知模块 ---

if [[ "$(uname)" == "Darwin" ]]; then
  _notify_macos "$desc" "$_body" "$_saved_pane" "$_tmux_socket"
elif command -v notify-send &>/dev/null; then
  _notify_linux "$desc" "$_body" "$_saved_pane" "$_tmux_socket"
fi
