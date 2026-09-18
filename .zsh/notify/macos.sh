#!/usr/bin/env bash
# macos.sh — macOS terminal-notifier 通知 + 点击跳转 tmux pane + 回到 pane 自动关闭
# 被 main.sh source，不可单独执行
#
# 与 linux.sh 同构：terminal-notifier ≥ 3.0 的 -action 会阻塞等待用户操作并把结果打到 stdout
# （点击本体 → @ACTIONCLICKED，点按钮 → 按钮名，关闭 → @CLOSED，超时 → @TIMEOUT），
# 跳转只在真实点击时发生；后台 watcher 发现用户已回到发起 pane 时用 -remove 关掉通知
# 2.0.0（2017 年、基于已废弃 NSUserNotification）在 macOS 26 上点击回调全废，必须 ≥ 3.0
#
# 一次性准备：brew 安装的 app bundle 不在 /Applications，首次请求权限会被拒
# （"Notifications are not allowed for this application"），需手动注册到 LaunchServices：
#   /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
#     -f /opt/homebrew/Cellar/terminal-notifier/<ver>/terminal-notifier.app
# 之后 `terminal-notifier -diagnose` 应显示 authorized

# _dbg <msg>: NOTIFY_DEBUG=1 时追加到调试日志（排查通知不显示 / 跳转不触发）
_dbg() {
  [[ "${NOTIFY_DEBUG:-0}" == 1 ]] && echo "[$(date)] $*" >> /tmp/notify-debug.log
  return 0
}

# _macos_map <app>: _TERM_APPS 候选名 → "bundleId|appName"（osascript activate 用）
_macos_map() {
  case "$1" in
    kitty)   printf 'net.kovidgoyal.kitty|kitty' ;;
    ghostty) printf 'com.mitchellh.ghostty|Ghostty' ;;
    wezterm) printf 'com.github.wez.wezterm|WezTerm' ;;
    *)       printf '|' ;;
  esac
}

# _macos_term: 按 _TERM_APPS 优先级返回首个【正在运行】的终端 "bundleId|appName"
# 都没运行则退回 macOS 内置 Terminal（保证聚焦目标始终有值，且不会拉起第三方终端）
_macos_term() {
  local _app _name
  for _app in "${_TERM_APPS[@]}"; do
    _name=$(_macos_map "$_app"); _name=${_name##*|}
    [[ -z "$_name" ]] && continue
    if [[ "$(osascript -e "application \"$_name\" is running" 2>/dev/null)" == "true" ]]; then
      _macos_map "$_app"; return
    fi
  done
  printf 'com.apple.Terminal|Terminal'
}

# _macos_front_bundle: 输出前台 App 的 bundleID，拿不到输出空并返回 1
# 优先 lsappinfo（免权限、轻量，轮询友好）：macOS 26 的 lsappinfo front 只给 ASN，需再查一次；
# info 输出是多行信息块（"kitty" ASN... / bundleID="..." / bundle path=...），必须正则提取 bundleID，
# 不能按单行剥前缀。lsappinfo 无输出时退化 osascript System Events（需自动化权限）
_macos_front_bundle() {
  local _out _front
  _out=$(lsappinfo info -only-bundleid "$(lsappinfo front 2>/dev/null)" 2>/dev/null)
  [[ "$_out" =~ bundleID=\"([^\"]+)\" ]] && _front=${BASH_REMATCH[1]}
  if [[ -z "$_front" ]]; then
    _front=$(osascript -e 'tell application "System Events" to get bundle identifier of first application process whose frontmost is true' 2>/dev/null)
  fi
  [[ -n "$_front" ]] || return 1
  printf '%s' "$_front"
}

# _macos_front_is_terminal: 前台 App 是终端时返回 0
_macos_front_is_terminal() {
  local _front
  _front=$(_macos_front_bundle) || return 1
  case "$_front" in
    net.kovidgoyal.kitty|com.mitchellh.ghostty|com.github.wez.wezterm|com.apple.Terminal) return 0 ;;
    *) return 1 ;;
  esac
}

# _macos_focus_not_terminal: 前台 App 明确不是终端时返回 0（发通知）；
# 拿不到前台信息（权限被拒/工具缺失）返回 1（unknown，不拦截，交由 tmux 判定）
_macos_focus_not_terminal() {
  [[ "$(uname)" == "Darwin" ]] || return 1
  local _front
  _front=$(_macos_front_bundle) || return 1
  case "$_front" in
    net.kovidgoyal.kitty|com.mitchellh.ghostty|com.github.wez.wezterm|com.apple.Terminal) return 1 ;;
    *) return 0 ;;
  esac
}

# _macos_at_pane <pane> <socket>: 终端在前台且某个 client 的活动 pane 就是发起 pane 时返回 0
# 精确到 window-pane：只切回终端但停在别的 pane 不算回来，与 Linux 侧 _user_present 同粒度
_macos_at_pane() {
  local _pane="$1" _socket="$2" _cl _cur
  _macos_front_is_terminal || return 1
  while IFS= read -r _cl; do
    _cur=$(tmux -S "$_socket" display-message -c "$_cl" -p '#{pane_id}' 2>/dev/null)
    [[ "$_cur" == "$_pane" ]] && return 0
  done < <(tmux -S "$_socket" list-clients -F '#{client_name}' 2>/dev/null)
  return 1
}

# _macos_jump <pane> <socket> <app_name>: 所有在连 client 切到发起 pane 所在 window，选中该 pane，前置终端
# 用 -c 逐 client 切换：后台脚本没有 client 上下文，不带 -c 的 switch-client 无法确定目标
_macos_jump() {
  local _pane="$1" _socket="$2" _name="$3" _sess _win _cl
  _sess=$(tmux -S "$_socket" display-message -t "$_pane" -p '#{session_name}' 2>/dev/null)
  _win=$(tmux -S "$_socket" display-message -t "$_pane" -p '#{window_index}' 2>/dev/null)
  if [[ -n "$_sess" && -n "$_win" ]]; then
    while IFS= read -r _cl; do
      [[ -n "$_cl" ]] && tmux -S "$_socket" switch-client -c "$_cl" -t "${_sess}:${_win}" 2>/dev/null \
        && _dbg "switched client=${_cl}"
    done < <(tmux -S "$_socket" list-clients -F '#{client_name}' 2>/dev/null)
  fi
  tmux -S "$_socket" select-pane -t "$_pane" 2>/dev/null
  osascript -e "tell application \"${_name}\" to activate" 2>/dev/null
}

# _notify_macos <desc> <body> <saved_pane> <tmux_socket>
# 副作用：显示系统通知；用户点击时切换 tmux client/pane 并前置终端；后台进程最长存活 NOTIFY_TIMEOUT_MINUTES
_notify_macos() {
  local desc="$1"
  local body="$2"
  local saved_pane="$3"
  local tmux_socket="$4"

  # 无 terminal-notifier：仅显示（归属 Script Editor），无点击跳转、无自动关闭
  if ! command -v terminal-notifier &>/dev/null; then
    local _esc_desc=${desc//\\/\\\\}; _esc_desc=${_esc_desc//\"/\\\"}
    local _esc_body=${body//\\/\\\\}; _esc_body=${_esc_body//\"/\\\"}
    osascript -e "display notification \"${_esc_body}\" with title \"${_esc_desc}\"" &
    return 0
  fi

  # 按优先级确定点击后要聚焦的终端
  local _term _name
  _term=$(_macos_term); _name=${_term##*|}

  # group 每次唯一：既是 -remove 的句柄，也避免同 app 多条通知互相替换
  local _group="${NOTIFY_APP_NAME:-notify}-$$"
  local _timeout=$(( NOTIFY_TIMEOUT_MINUTES * 60 ))

  (
    _dbg "start pane=${saved_pane} socket=${tmux_socket} group=${_group}"
    local _tmp
    _tmp=$(mktemp -t notify-macos)

    # -action 让 terminal-notifier 阻塞到用户操作或超时，结果写 stdout（见文件头）
    terminal-notifier -title "$desc" -message "${body:-$desc}" -group "$_group" \
      -action '↩ Return to terminal' -timeout "$_timeout" >"$_tmp" 2>/dev/null &
    local _npid=$!

    # watcher：用户【真正回到发起 pane】时关闭通知并结束等待；通知消失或超时后随 _npid 退出
    local _watcher=
    if [[ -n "$saved_pane" && -n "$tmux_socket" ]]; then
      (
        while kill -0 "$_npid" 2>/dev/null; do
          if _macos_at_pane "$saved_pane" "$tmux_socket"; then
            terminal-notifier -remove "$_group" >/dev/null 2>&1
            kill "$_npid" 2>/dev/null
            _dbg "user at pane, notification removed"
            break
          fi
          sleep 1
        done
      ) &
      _watcher=$!
    fi

    wait "$_npid" 2>/dev/null
    local _rc=$?
    [[ -n "$_watcher" ]] && _kill_tree "$_watcher"

    local _action
    _action=$(cat "$_tmp" 2>/dev/null)
    rm -f "$_tmp"
    _dbg "result=${_action:-<none>} rc=${_rc}"

    case "$_action" in
      '@ACTIONCLICKED'|'↩ Return to terminal')
        [[ -n "$saved_pane" && -n "$tmux_socket" ]] && _macos_jump "$saved_pane" "$tmux_socket" "$_name"
        ;;
      '@TIMEOUT')
        # 与 Linux transient 通知到期消失同语义
        terminal-notifier -remove "$_group" >/dev/null 2>&1
        ;;
    esac
  ) </dev/null >/dev/null 2>&1 &
  disown $!
}
