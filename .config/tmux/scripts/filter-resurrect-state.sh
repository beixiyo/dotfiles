#!/bin/sh
# 从 tmux-resurrect 布局快照中排除跟随运行时所有者的临时 session

set -eu

state_file="${1:-}"
[ -n "$state_file" ] && [ -f "$state_file" ] || exit 0

tmp_file="${state_file}.filter.$$"
trap 'rm -f "$tmp_file"' EXIT HUP INT TERM

awk -F '\t' '
  function transient(name) {
    return name == "_nvd_park" || name ~ /^popup-/
  }

  ($1 == "pane" || $1 == "window") && transient($2) { next }
  $1 == "grouped_session" && (transient($2) || transient($3)) { next }
  $1 == "state" && (transient($2) || transient($3)) { next }
  { print }
' "$state_file" > "$tmp_file"

mv "$tmp_file" "$state_file"
trap - EXIT HUP INT TERM
