#!/usr/bin/env bash
# 通用完成通知脚本（支持点击跳转 tmux pane + 显示对话上下文）
# 用法: notify-stop.sh <app名> [上下文标题]
# 依赖: macOS: brew install terminal-notifier (可选，无则退化为基础通知)
#       Linux: notify-send (libnotify)

_saved_pane="$TMUX_PANE"
_tmux_socket="${TMUX%%,*}"

# NIRI_SOCKET 在 tmux 环境里可能丢失，缺失时从运行目录兜底
[[ -z "$NIRI_SOCKET" ]] && NIRI_SOCKET=$(ls -t "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"/niri.wayland-*.sock 2>/dev/null | head -1)
export NIRI_SOCKET

# niri 是否可用于焦点判断
_niri_up() { [[ -n "$NIRI_SOCKET" ]] && command -v niri &>/dev/null && command -v jq &>/dev/null; }

# niri 当前聚焦的窗口是不是终端
_focused_is_terminal() {
  local _app
  _app=$(niri msg --json focused-window 2>/dev/null | jq -r '.app_id // empty')
  _app=${_app,,}
  [[ "$_app" == *ghostty* || "$_app" == *wezterm* || "$_app" == *kitty* \
     || "$_app" == *foot* || "$_app" == *alacritty* ]]
}

# 用户此刻是否正盯着发起通知的终端 pane（true=在场，不该打扰/可关通知）
# 规则：niri 可用且焦点不在终端 → 明确不在场；否则看 tmux 活动 pane 是否仍是本 pane
_user_present() {
  _niri_up && ! _focused_is_terminal && return 1
  local _cur
  _cur=$(tmux -S "$_tmux_socket" display-message -p '#{pane_id}' 2>/dev/null)
  if [[ -n "$_saved_pane" ]]; then
    [[ "$_cur" == "$_saved_pane" ]]
  else
    return 0   # 无 pane 信息 → 保守视为在场
  fi
}

# 在场就不通知；切 tmux pane、或按 niri 快捷键切到别的窗口/工作区都会通知
if [[ -n "$TMUX" ]]; then
  _user_present && exit 0
fi

desc="${1:-终端}"

# 提取上下文：$2 优先（opencode 传入），否则从 Claude Code Stop hook stdin 读取
_context="${2:-}"
if [[ -z "$_context" ]] && [[ ! -t 0 ]]; then
  _hook_json=$(cat 2>/dev/null)
  _transcript=$(echo "$_hook_json" | jq -r '.transcript_path // empty' 2>/dev/null)
  if [[ -f "$_transcript" ]]; then
    # ai-title：AI 生成的会话标题
    _title=$(grep '"type":"ai-title"' "$_transcript" | tail -1 \
      | jq -r '.aiTitle // empty' 2>/dev/null | tr -d '\n')
    # last-prompt：最后一次用户输入
    _last=$(grep '"type":"last-prompt"' "$_transcript" | tail -1 \
      | jq -r '.lastPrompt // empty' 2>/dev/null | tr -d '\n' | cut -c1-50)
    # 拼接：title · last prompt
    if [[ -n "$_title" ]] && [[ -n "$_last" ]]; then
      _context="${_title}"$'\n'"${_last}"
    elif [[ -n "$_title" ]]; then
      _context="$_title"
    elif [[ -n "$_last" ]]; then
      _context="$_last"
    fi
  fi
fi

_body="${_context:-回复完成，点击跳转}"

_focus_terminal() {
  # niri (wayland)：按 app-id 聚焦终端窗口
  if [[ -n "$NIRI_SOCKET" ]] && command -v niri &>/dev/null && command -v jq &>/dev/null; then
    local _id
    _id=$(niri msg --json windows 2>/dev/null \
      | jq -r 'map(select(.app_id | test("ghostty|wezterm|kitty|foot|alacritty";"i"))) | .[0].id // empty')
    if [[ -n "$_id" ]]; then
      niri msg action focus-window --id "$_id" 2>/dev/null
      return
    fi
  fi
  # KDE (KWin) / X11 回退
  if command -v qdbus6 &>/dev/null; then
    local tmp script_name
    tmp=$(mktemp /tmp/focus-ghostty-XXXX.js)
    script_name="focus-ghostty-$$"
    cat > "$tmp" << 'KWIN'
var wins = workspace.windowList ? workspace.windowList() : workspace.clientList();
for (var i = 0; i < wins.length; i++) {
    if (wins[i].resourceClass.toString().toLowerCase().indexOf("ghostty") >= 0) {
        workspace.activeWindow = wins[i];
        break;
    }
}
KWIN
    qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript "$tmp" "$script_name" &>/dev/null
    qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.start &>/dev/null
    sleep 0.3
    qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript "$script_name" &>/dev/null
    rm -f "$tmp"
  elif command -v wmctrl &>/dev/null; then
    wmctrl -xa "ghostty" 2>/dev/null
  elif command -v xdotool &>/dev/null; then
    xdotool search --classname "ghostty" windowactivate 2>/dev/null
  fi
}

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

if [[ "$(uname)" == "Darwin" ]]; then
  # 通知持续显示：System Settings > Notifications > terminal-notifier → Alerts（非 Banners）
  if command -v terminal-notifier &>/dev/null; then
    (
      _log="/tmp/notify-debug.log"
      echo "[$(date)] start pane=${_saved_pane} socket=${_tmux_socket}" >> "$_log"

      _signal_file="/tmp/notify-jump-${_saved_pane//\%/p}.sig"
      rm -f "$_signal_file"

      _jump_script=$(mktemp /tmp/notify-jump-XXXX.sh)
      printf '#!/usr/bin/env bash\necho "[$(date)] execute triggered" >> "%s"\ntouch "%s"\nrm -f "$0"\n' \
        "$_log" "$_signal_file" > "$_jump_script"
      chmod +x "$_jump_script"

      terminal-notifier \
        -title "${desc}" \
        -message "${_body}" \
        -execute "bash '${_jump_script}'" \
        -activate "com.mitchellh.ghostty" \
        -group "claude-notify" &
      _npid=$!
      echo "[$(date)] terminal-notifier pid=${_npid}" >> "$_log"

      if [[ -n "$_saved_pane" && -n "$_tmux_socket" ]]; then
        # terminal-notifier 在新版 macOS 发完通知即退出，不能用 kill -0 判活
        # 改用固定时长轮询（5 分钟），独立于 notifier 进程
        _deadline=$(( SECONDS + 300 ))
        while (( SECONDS < _deadline )); do
          # 用显式 -c client 查各 client 当前 pane，避免无终端上下文时返回错误值
          _user_back=0
          while IFS= read -r _cl; do
            _cur=$(tmux -S "$_tmux_socket" display-message -c "$_cl" -p '#{pane_id}' 2>/dev/null)
            if [[ "$_cur" == "$_saved_pane" ]]; then
              _user_back=1; break
            fi
          done < <(tmux -S "$_tmux_socket" list-clients -F '#{client_name}' 2>/dev/null)

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
            _sess=$(tmux -S "$_tmux_socket" display-message -t "$_saved_pane" -p '#{session_name}' 2>/dev/null)
            _win=$(tmux -S "$_tmux_socket" display-message -t "$_saved_pane" -p '#{window_index}' 2>/dev/null)
            echo "[$(date)] sess=${_sess} win=${_win}" >> "$_log"
            if [[ -n "$_sess" && -n "$_win" ]]; then
              while IFS= read -r _cl; do
                [[ -n "$_cl" ]] && tmux -S "$_tmux_socket" switch-client -c "$_cl" -t "${_sess}:${_win}" 2>/dev/null \
                  && echo "[$(date)] switched client=${_cl}" >> "$_log"
              done < <(tmux -S "$_tmux_socket" list-clients -F '#{client_name}' 2>/dev/null)
            fi
            tmux -S "$_tmux_socket" select-pane -t "$_saved_pane" 2>/dev/null
            osascript -e 'tell application "Ghostty" to activate' 2>/dev/null
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
    osascript -e "display notification \"${_body}\" with title \"${desc}\"" &
  fi
elif command -v notify-send &>/dev/null; then
  (
    _tmp=$(mktemp /tmp/notify-action-XXXX)

    # tmux 内：持续显示(-t 0)，靠「切回原 pane」自动消除
    # 非 tmux（如 niri 裸终端）：正常超时自动消失，避免永久挂在右上角
    if [[ -n "$_saved_pane" && -n "$_tmux_socket" ]]; then
      _timeout=0
    else
      _timeout=8000
    fi

    # 动作键用 default：mako 左键点击通知体即触发跳转（见 on-button-left）
    notify-send -t "$_timeout" "${desc}" "${_body}" \
      --action="default=↩ 跳转到终端" \
      --wait >"$_tmp" 2>/dev/null &
    _npid=$!

    # tmux 下：用户真正回到发起的终端(niri 聚焦终端 且 活动 pane 一致)时自动 kill 通知
    if [[ -n "$_saved_pane" && -n "$_tmux_socket" ]]; then
      while kill -0 "$_npid" 2>/dev/null; do
        if _user_present; then
          kill "$_npid" 2>/dev/null
          rm -f "$_tmp"
          exit 0
        fi
        sleep 0.5
      done
    fi

    wait "$_npid" 2>/dev/null
    _action=$(cat "$_tmp" 2>/dev/null)
    rm -f "$_tmp"

    if [[ "$_action" == "default" ]]; then
      _switch_tmux_pane "$_saved_pane" "$_tmux_socket"
      _focus_terminal
    fi
  ) </dev/null >/dev/null 2>&1 &
  disown $!
fi
