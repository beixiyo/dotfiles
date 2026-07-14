#!/usr/bin/env bash
# Send stdin to the first non-vim pane in the current tmux window.
# When called from Neovide opened by nvd, prefer the tmux window that launched it.

current="${NVD_TMUX_ORIGIN_PANE:-$(tmux display-message -p '#{pane_id}')}"
target_window="${NVD_TMUX_ORIGIN_WINDOW:-}"
target=""

if [[ -n "$target_window" ]]; then
  tmux display-message -p -t "$target_window" '#{window_id}' >/dev/null 2>&1 || target_window=""
fi

list_panes() {
  if [[ -n "$target_window" ]]; then
    tmux list-panes -t "$target_window" -F '#{pane_id}|#{@pane-is-vim}'
    return
  fi

  tmux list-panes -F '#{pane_id}|#{@pane-is-vim}'
}

while IFS='|' read -r id is_vim; do
  if [[ "$id" != "$current" && "$is_vim" != "1" ]]; then
    target="$id"
    break
  fi
done < <(list_panes)

[[ -z "$target" ]] && exit 1

tmux load-buffer -
tmux paste-buffer -t "$target" -p
