#!/usr/bin/env bash
# macos.sh — macOS terminal-notifier 通知 + 点击跳转 tmux pane
# 被 main.sh source，不可单独执行

# _macos_map <app>: _TERM_APPS 候选名 → "bundleId|appName"（-activate / osascript 用）
_macos_map() {
  case "$1" in
    kitty)   printf 'net.kovidgoyal.kitty|kitty' ;;
    ghostty) printf 'com.mitchellh.ghostty|Ghostty' ;;
    wezterm) printf 'com.github.wez.wezterm|WezTerm' ;;
    *)       printf '|' ;;
  esac
}

# _macos_term: 按 _TERM_APPS 优先级返回首个【正在运行】的终端 "bundleId|appName"
# 都没运行则退回列表首项，保证聚焦目标始终有值
_macos_term() {
  local _app _name
  for _app in "${_TERM_APPS[@]}"; do
    _name=$(_macos_map "$_app"); _name=${_name##*|}
    [[ -z "$_name" ]] && continue
    if [[ "$(osascript -e "application \"$_name\" is running" 2>/dev/null)" == "true" ]]; then
      _macos_map "$_app"; return
    fi
  done
  _macos_map "${_TERM_APPS[0]}"
}

# _notify_macos <desc> <body> <saved_pane> <tmux_socket>
_notify_macos() {
  local desc="$1"
  local body="$2"
  local saved_pane="$3"
  local tmux_socket="$4"

  # 通知持续显示：System Settings > Notifications > terminal-notifier → Alerts（非 Banners）
  if command -v terminal-notifier &>/dev/null; then
    # 按优先级动态确定要聚焦的终端（bundleId 给 -activate，appName 给 osascript）
    local _term _bundle _name
    _term=$(_macos_term); _bundle=${_term%%|*}; _name=${_term##*|}
    (
      local _log="/tmp/notify-debug.log"
      echo "[$(date)] start pane=${saved_pane} socket=${tmux_socket}" >> "$_log"

      local _signal_file="/tmp/notify-jump-${saved_pane//\%/p}.sig"
      rm -f "$_signal_file"

      local _jump_script
      _jump_script=$(mktemp /tmp/notify-jump-XXXX.sh)
      printf '#!/usr/bin/env bash\necho "[$(date)] execute triggered" >> "%s"\ntouch "%s"\nrm -f "$0"\n' \
        "$_log" "$_signal_file" > "$_jump_script"
      chmod +x "$_jump_script"

      terminal-notifier \
        -title "${desc}" \
        -message "${body}" \
        -execute "bash '${_jump_script}'" \
        -activate "$_bundle" \
        -group "claude-notify" &
      local _npid=$!
      echo "[$(date)] terminal-notifier pid=${_npid}" >> "$_log"

      if [[ -n "$saved_pane" && -n "$tmux_socket" ]]; then
        # terminal-notifier 在新版 macOS 发完通知即退出，不能用 kill -0 判活
        # 改用固定时长轮询（5 分钟），独立于 notifier 进程
        local _deadline=$(( SECONDS + 300 ))
        while (( SECONDS < _deadline )); do
          # 用显式 -c client 查各 client 当前 pane，避免无终端上下文时返回错误值
          local _user_back=0
          local _cl _cur
          while IFS= read -r _cl; do
            _cur=$(tmux -S "$tmux_socket" display-message -c "$_cl" -p '#{pane_id}' 2>/dev/null)
            if [[ "$_cur" == "$saved_pane" ]]; then
              _user_back=1; break
            fi
          done < <(tmux -S "$tmux_socket" list-clients -F '#{client_name}' 2>/dev/null)

          if (( _user_back )); then
            echo "[$(date)] user switched back manually" >> "$_log"
            terminal-notifier -remove "claude-notify" 2>/dev/null
            kill "$_npid" 2>/dev/null
            rm -f "$_jump_script" "$_signal_file"
            exit 0
          fi

          if [[ -f "$_signal_file" ]]; then
            rm -f "$_signal_file"
            echo "[$(date)] signal received, switching pane" >> "$_log"
            local _sess _win
            _sess=$(tmux -S "$tmux_socket" display-message -t "$saved_pane" -p '#{session_name}' 2>/dev/null)
            _win=$(tmux -S "$tmux_socket" display-message -t "$saved_pane" -p '#{window_index}' 2>/dev/null)
            echo "[$(date)] sess=${_sess} win=${_win}" >> "$_log"
            if [[ -n "$_sess" && -n "$_win" ]]; then
              while IFS= read -r _cl; do
                [[ -n "$_cl" ]] && tmux -S "$tmux_socket" switch-client -c "$_cl" -t "${_sess}:${_win}" 2>/dev/null \
                  && echo "[$(date)] switched client=${_cl}" >> "$_log"
              done < <(tmux -S "$tmux_socket" list-clients -F '#{client_name}' 2>/dev/null)
            fi
            tmux -S "$tmux_socket" select-pane -t "$saved_pane" 2>/dev/null
            osascript -e "tell application \"$_name\" to activate" 2>/dev/null
            terminal-notifier -remove "claude-notify" 2>/dev/null
            kill "$_npid" 2>/dev/null
            exit 0
          fi

          sleep 0.5
        done
        echo "[$(date)] timeout, no action" >> "$_log"
      fi

      rm -f "$_jump_script" "$_signal_file" 2>/dev/null
    ) </dev/null >/dev/null 2>&1 &
    disown $!
  else
    osascript -e "display notification \"${body}\" with title \"${desc}\"" &
  fi
}
