#!/bin/sh
# 来源 pane 或 Neovim 进程消失后，回收其拥有的 popup session

set -eu

session="${1:-}"
expected_id="${2:-}"
owner_pane="${3:-}"
owner_pid="${4:-}"

[ -n "$session" ] && [ -n "$expected_id" ] && [ -n "$owner_pane" ] || exit 0

while tmux has-session -t "=$session" 2>/dev/null; do
  current_id=$(tmux display-message -p -t "=$session:" '#{session_id}' 2>/dev/null || true)
  [ "$current_id" = "$expected_id" ] || exit 0

  tmux list-panes -a -F '#{pane_id}' 2>/dev/null | grep -Fxq -- "$owner_pane" || break
  if [ -n "$owner_pid" ]; then
    kill -0 "$owner_pid" 2>/dev/null || break
  fi

  # 轮询间隔
  sleep 5
done

current_id=$(tmux display-message -p -t "=$session:" '#{session_id}' 2>/dev/null || true)
[ "$current_id" = "$expected_id" ] || exit 0

if [ -n "$owner_pid" ]; then
  current_owner_pid=$(tmux show-options -p -t "$owner_pane" -qv @nvim_pid 2>/dev/null || true)
  if [ "$current_owner_pid" = "$owner_pid" ]; then
    tmux set-option -p -t "$owner_pane" -u @nvim_cwd 2>/dev/null || true
    tmux set-option -p -t "$owner_pane" -u @nvim_popup_id 2>/dev/null || true
    tmux set-option -p -t "$owner_pane" -u @nvim_pid 2>/dev/null || true
  fi
fi

tmux kill-session -t "=$session" 2>/dev/null || true
