#!/usr/bin/env bash
# tmux AI 完成状态：维护 pane 提示、window badge 和可选终端 BEL

socket="${TMUX%%,*}"
action="$1"
target="${2:-${TMUX_PANE:-}}"

[[ -n "$socket" && -n "$target" ]] || exit 0

pid_under_sshd() {
  local pid="$1" comm i=0
  while [[ -n "$pid" && "$pid" != 0 && "$pid" != 1 && $i -lt 25 ]]; do
    comm=$(cat "/proc/$pid/comm" 2>/dev/null) || return 1
    [[ "$comm" == sshd* ]] && return 0
    pid=$(awk '/^PPid:/{print $2}' "/proc/$pid/status" 2>/dev/null)
    i=$((i + 1))
  done
  return 1
}

clear_pane() {
  local pane="$1" window
  tmux -S "$socket" set-option -p -u -t "$pane" @ai_agent_done 2>/dev/null
  tmux -S "$socket" set-option -p -u -t "$pane" @ai_agent_name 2>/dev/null
  window=$(tmux -S "$socket" display-message -p -t "$pane" '#{window_id}' 2>/dev/null)

  if ! tmux -S "$socket" list-panes -t "$window" -F '#{@ai_agent_done}' 2>/dev/null | grep -qx 1; then
    tmux -S "$socket" set-option -w -u -t "$window" pane-border-status 2>/dev/null
    tmux -S "$socket" set-option -w -u -t "$window" pane-border-style 2>/dev/null
    tmux -S "$socket" set-option -w -u -t "$window" pane-active-border-style 2>/dev/null
  fi
}

case "$action" in
  done)
    agent="${AI_AGENT_NAME:-AI}"
    window=$(tmux -S "$socket" display-message -p -t "$target" '#{window_id}' 2>/dev/null)
    [[ -n "$window" ]] || exit 0
    while read -r pid pane; do
      pid_under_sshd "$pid" && continue
      if [[ "$pane" == "$target" ]]; then
        clear_pane "$target"
        tmux -S "$socket" set-option -w -u -t "$window" @ai_agent_done 2>/dev/null
        exit 0
      fi
    done < <(tmux -S "$socket" list-clients -F '#{client_pid} #{pane_id}' 2>/dev/null)

    tmux -S "$socket" set-option -p -t "$target" @ai_agent_done 1
    tmux -S "$socket" set-option -p -t "$target" @ai_agent_name "$agent"
    tmux -S "$socket" set-option -w -t "$window" pane-border-status top
    tmux -S "$socket" set-option -w -t "$window" pane-border-style 'fg=#1e1e2e'
    tmux -S "$socket" set-option -w -t "$window" pane-active-border-style 'fg=#1e1e2e'

    current_window=$(tmux -S "$socket" display-message -p '#{window_id}' 2>/dev/null)
    if [[ "$current_window" != "$window" ]]; then
      tmux -S "$socket" set-option -w -t "$window" @ai_agent_done 1
    fi
    ;;
  focus-pane)
    clear_pane "$target"
    ;;
  focus-window)
    tmux -S "$socket" set-option -w -u -t "$target" @ai_agent_done 2>/dev/null
    ;;
esac

tmux -S "$socket" refresh-client -S 2>/dev/null || true
