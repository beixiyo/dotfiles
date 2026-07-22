#!/bin/sh
# Ctrl+Alt+hjkl / Ctrl+Alt+方向键 的统一入口：决定这次按键是
#   透传给 pane 里的程序（nvim 的 smart-splits、或远端会话自己处理）
#   还是由 tmux 自己切 pane / 调大小
#
# 用法：pane-nav.sh <move|resize> <h|j|k|l> <pane_id>
#
# 「这个 pane 前台到底是不是 nvim」的判定在 lib/nvim-detect.sh，
# 那边有完整的取舍说明（为什么不读 @pane-is-vim、为什么不扫整个 tty）

set -eu

. "$(dirname "$0")/lib/nvim-detect.sh"

mode=$1
dir=$2
pane=$3

case $dir in
  h) tmux_dir=L; edge=pane_at_left;   move_key=C-M-h; resize_key=C-M-Left  ;;
  j) tmux_dir=D; edge=pane_at_bottom; move_key=C-M-j; resize_key=C-M-Down  ;;
  k) tmux_dir=U; edge=pane_at_top;    move_key=C-M-k; resize_key=C-M-Up    ;;
  l) tmux_dir=R; edge=pane_at_right;  move_key=C-M-l; resize_key=C-M-Right ;;
  *) exit 1 ;;
esac

# 一次 tmux 调用取齐所有信息
read -r pane_pid pane_cmd at_edge <<EOF
$(tmux display-message -p -t "$pane" "#{pane_pid} #{pane_current_command} #{$edge}")
EOF

if pane_wants_nav_keys "$pane_pid" "$pane_cmd"; then
  [ "$mode" = resize ] && key=$resize_key || key=$move_key
  tmux send-keys -t "$pane" "$key"
  exit 0
fi

if [ "$mode" = resize ]; then
  tmux resize-pane -t "$pane" "-$tmux_dir" 3
  exit 0
fi

# 已经在这个方向的边界上就什么都不做，避免绕回对面的 pane
[ "$at_edge" = 1 ] && exit 0
tmux select-pane -t "$pane" "-$tmux_dir"
