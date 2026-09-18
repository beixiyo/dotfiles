#!/usr/bin/env bash
# macos.sh — macOS 通知 + 点击/切回跳转 tmux pane
# 被 main.sh source，不可单独执行
#
# 通知经 kitty OSC 99 写发起 pane 的 tty（通知归属 kitty，点击前置 kitty），拿不到 pane tty 时
# 退化为 osascript display notification。不用 terminal-notifier：2.0.0 在 macOS 26 上点击回调全废
# 跳转不依赖通知回调，由「前台从非终端变为终端」的变化沿检测承担：
# 用户点击通知或主动切回终端 → 自动 switch-client + select-pane 到发起 pane

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

# _macos_front_is_terminal: 前台 App 是终端时返回 0（轮询用）
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

# _pct_encode: kitty OSC 99 payload 安全编码（; % \ 三字符）
_pct_encode() {
  local _s="$1"
  _s=${_s//%/%25}
  _s=${_s//;/%3B}
  printf '%s' "${_s//\\/%5C}"
}

# _osc99_notify <tty> <title> <body>: 写入指定 tty 的 kitty OSC 99 桌面通知
# 通知归属 kitty，点击由 macOS 前置 kitty（不会打开无关 App）；
# 写 tmux pane tty 必须经 DCS passthrough 包装（tmux 拦截后转发给外层终端），
# 且 tmux 需 allow-passthrough all：为 on 时 pane 所在 window 不是当前 window 会被静默丢弃
# i= 每次调用唯一：同 id 会替换上一条（macOS 上非无缝），多个 agent 相继完成时会互相覆盖
_osc99_notify() {
  local _tty="$1" _title="$2" _body="$3" _id="n$$"
  _title=$(_pct_encode "$_title")
  _body=$(_pct_encode "$_body")
  local _seq=$'\e]99;i='"${_id}"':d=0;'"${_title}"$'\e\\'$'\e]99;i='"${_id}"':d=1:p=body;'"${_body}"$'\e\\'
  printf '%s' $'\ePtmux;'"${_seq//$'\e'/$'\e\e'}"$'\e\\' > "$_tty" 2>/dev/null
}

# _notify_macos <desc> <body> <saved_pane> <tmux_socket>
_notify_macos() {
  local desc="$1"
  local body="$2"
  local saved_pane="$3"
  local tmux_socket="$4"

  # 按优先级确定要聚焦的终端（沿触发跳转后 osascript activate 用）
  local _term _name
  _term=$(_macos_term); _name=${_term##*|}

  # 通知显示：OSC 99 写发起 pane 的 tty（kitty 原生，点击前置 kitty）；
  # 拿不到 pane tty（非 tmux / 已关闭）则退化 osascript
  local _pane_tty
  _pane_tty=$(tmux -S "${tmux_socket}" display-message -t "${saved_pane}" -p '#{pane_tty}' 2>/dev/null)
  if [[ -n "$_pane_tty" && -w "$_pane_tty" ]]; then
    _dbg "osc99 pane=${saved_pane} tty=${_pane_tty} passthrough=$(tmux -S "${tmux_socket}" show -gv allow-passthrough 2>/dev/null)"
    _osc99_notify "$_pane_tty" "$desc" "$body"
  else
    local _esc_desc=${desc//\\/\\\\}; _esc_desc=${_esc_desc//\"/\\\"}
    local _esc_body=${body//\\/\\\\}; _esc_body=${_esc_body//\"/\\\"}
    osascript -e "display notification \"${_esc_body}\" with title \"${_esc_desc}\"" &
  fi

  [[ -n "$saved_pane" && -n "$tmux_socket" ]] || return 0

  (
    _dbg "start pane=${saved_pane} socket=${tmux_socket}"

    local _deadline=$(( SECONDS + 300 ))
    # 前台沿检测：记录初始状态，仅「非终端 → 终端」变化沿触发跳转，
    # 避免用户一直在终端里其它 window 干活时被误拽
    local _was_terminal=0
    _macos_front_is_terminal && _was_terminal=1
    while (( SECONDS < _deadline )); do
      local _cl _cur _now_terminal=0
      # 每轮只采样一次前台状态：沿判断与状态更新共用同一次结果，
      # 否则切换恰好落在两次采样之间会被记成「一直在终端」而错过沿
      _macos_front_is_terminal && _now_terminal=1

      # 沿检测优先：前台从非终端变为终端（点击通知或主动切回）→ 直接带到发起 pane
      # 必须在 user_back 之前：否则用户回终端后顺手点进发起 pane 会抢先触发 user_back
      # 退出，跳转永远轮不到；沿触发时 active 已是 saved 则 select 无害
      if ! (( _was_terminal )) && (( _now_terminal )); then
        _dbg "front switched to terminal, jumping to pane"
        local _sess _win
        _sess=$(tmux -S "$tmux_socket" display-message -t "$saved_pane" -p '#{session_name}' 2>/dev/null)
        _win=$(tmux -S "$tmux_socket" display-message -t "$saved_pane" -p '#{window_index}' 2>/dev/null)
        _dbg "sess=${_sess} win=${_win}"
        if [[ -n "$_sess" && -n "$_win" ]]; then
          while IFS= read -r _cl; do
            [[ -n "$_cl" ]] && tmux -S "$tmux_socket" switch-client -c "$_cl" -t "${_sess}:${_win}" 2>/dev/null \
              && _dbg "switched client=${_cl}"
          done < <(tmux -S "$tmux_socket" list-clients -F '#{client_name}' 2>/dev/null)
        fi
        tmux -S "$tmux_socket" select-pane -t "$saved_pane" 2>/dev/null
        osascript -e "tell application \"${_name}\" to activate" 2>/dev/null
        exit 0
      fi

      # 前台一直是终端（未离开过）：用户已在发起 pane（自己切回来了）→ 结束等待
      if (( _was_terminal )); then
        while IFS= read -r _cl; do
          _cur=$(tmux -S "$tmux_socket" display-message -c "$_cl" -p '#{pane_id}' 2>/dev/null)
          if [[ "$_cur" == "$saved_pane" ]]; then
            _dbg "user switched back manually"
            exit 0
          fi
        done < <(tmux -S "$tmux_socket" list-clients -F '#{client_name}' 2>/dev/null)
      fi
      _was_terminal=$_now_terminal

      sleep 0.5
    done
    _dbg "timeout, no action"
  ) </dev/null >/dev/null 2>&1 &
  disown $!
}
