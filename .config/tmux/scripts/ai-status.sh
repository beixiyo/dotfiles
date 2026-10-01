#!/usr/bin/env bash
# tmux AI 状态：维护 pane 顶部提示、window tab badge
# 用法: ai-status.sh <done|wait|focus-pane|focus-window> [pane] [-]
#   done：AI 完成（✓ <agent> done）；wait：AI 在等你（权限确认 / 提问，● <agent> needs you）
#   两层提示，语义分开：
#     pane 顶部文案（@ai_pane_done / @ai_pane_label）：光标真正进入该 pane 才清除（focus-pane；切回 window 时只清当时的活动 pane）
#     tab badge（@ai_window_done）：“去这个 window 看看”，进入该 window 即清除（focus-window）
#   第三个参数为 "-" 时从 stdin 读 hook JSON：带 agent_id（subagent / teammate）的 done 事件忽略；
#   wait 不过滤（subagent 的权限请求同样需要用户处理）
#   不传 "-" 则不碰 stdin，留给同一命令里后续的 main.sh 读取

socket="${TMUX%%,*}"
action="$1"
target="${2:-${TMUX_PANE:-}}"

[[ -n "$socket" && -n "$target" ]] || exit 0

if [[ "$action" == done && "$3" == "-" && ! -t 0 ]]; then
  agent_id=$(jq -r '.agent_id // empty' 2>/dev/null)
  [[ -n "$agent_id" ]] && exit 0
fi

clear_pane() {
  local pane="$1" window
  tmux -S "$socket" set-option -p -u -t "$pane" @ai_pane_done 2>/dev/null
  tmux -S "$socket" set-option -p -u -t "$pane" @ai_agent_name 2>/dev/null
  tmux -S "$socket" set-option -p -u -t "$pane" @ai_pane_label 2>/dev/null
  window=$(tmux -S "$socket" display-message -p -t "$pane" '#{window_id}' 2>/dev/null)

  if ! tmux -S "$socket" list-panes -t "$window" -F '#{@ai_pane_done}' 2>/dev/null | grep -qx 1; then
    tmux -S "$socket" set-option -w -u -t "$window" @ai_window_done 2>/dev/null
    tmux -S "$socket" set-option -w -u -t "$window" pane-border-status 2>/dev/null
    tmux -S "$socket" set-option -w -u -t "$window" pane-border-style 2>/dev/null
    tmux -S "$socket" set-option -w -u -t "$window" pane-active-border-style 2>/dev/null
  fi
}

# mark_pane <label>: 给 target pane 打提示
#   任一 client 光标正停在该 pane → 视为已看到，清除而不绘制
#   有 client 停在同一 window 的其他 pane → 只打 pane 顶部文案，不点 tab badge（人已在该 window）
# SSH attach 的 client 同样算在场：badge 画在 tmux 里，远程看着该 pane 也就看到了
mark_pane() {
  local label="$1" window cwin cpane in_window=0
  window=$(tmux -S "$socket" display-message -p -t "$target" '#{window_id}' 2>/dev/null)
  [[ -n "$window" ]] || return 0
  while read -r cwin cpane; do
    if [[ "$cpane" == "$target" ]]; then
      clear_pane "$target"
      return 0
    fi
    [[ "$cwin" == "$window" ]] && in_window=1
  done < <(tmux -S "$socket" list-clients -F '#{window_id} #{pane_id}' 2>/dev/null)

  tmux -S "$socket" set-option -p -t "$target" @ai_pane_done 1
  tmux -S "$socket" set-option -p -t "$target" @ai_agent_name "${AI_AGENT_NAME:-AI}"
  tmux -S "$socket" set-option -p -t "$target" @ai_pane_label "$label"
  tmux -S "$socket" set-option -w -t "$window" pane-border-status top
  tmux -S "$socket" set-option -w -t "$window" pane-border-style 'fg=#1e1e2e'
  tmux -S "$socket" set-option -w -t "$window" pane-active-border-style 'fg=#1e1e2e'
  (( in_window )) || tmux -S "$socket" set-option -w -t "$window" @ai_window_done 1
}

case "$action" in
  done)
    mark_pane "✓ ${AI_AGENT_NAME:-AI} done"
    ;;
  wait)
    mark_pane "● ${AI_AGENT_NAME:-AI} needs you"
    ;;
  focus-pane)
    clear_pane "$target"
    ;;
  focus-window)
    # 进入 window：清 tab badge，并清当时的活动 pane（切 window 不触发 after-select-pane）；
    # 同 window 其他 pane 的顶部文案保留，等光标真正进入时由 focus-pane 清除
    active_pane=$(tmux -S "$socket" display-message -p -t "$target" '#{pane_id}' 2>/dev/null)
    [[ -n "$active_pane" ]] && clear_pane "$active_pane"
    tmux -S "$socket" set-option -w -u -t "$target" @ai_window_done 2>/dev/null
    ;;
esac

tmux -S "$socket" refresh-client -S 2>/dev/null || true
