#!/bin/sh
# 把 stdin 投递到当前 tmux window 里第一个不是 nvim 的 pane
# 从 nvd 拉起的 Neovide 调用时，优先投递回启动它的那个 tmux window
#
# 「哪个 pane 是 nvim」的判定在 lib/nvim-detect.sh。不读 smart-splits 写的
# @pane-is-vim —— 那个状态会在 nvim 被 kill / 崩溃后残留，让整个 window 的
# pane 全被误判成 vim，于是永远找不到投递目标

set -eu

. "$(dirname "$0")/lib/nvim-detect.sh"

# $TMUX_PANE 是 tmux 注入给 pane 内进程的自身 id，比 display-message 更准：
# 后者不带 -t 时取的是「当前活动 pane」，nvim 不在活动 pane 时会认错自己
current="${NVD_TMUX_ORIGIN_PANE:-${TMUX_PANE:-$(tmux display-message -p '#{pane_id}')}}"
target_window="${NVD_TMUX_ORIGIN_WINDOW:-}"

if [ -n "$target_window" ]; then
  tmux display-message -p -t "$target_window" '#{window_id}' >/dev/null 2>&1 || target_window=""
fi

panes=$(tmux list-panes -t "${target_window:-$current}" \
  -F '#{pane_id}|#{pane_pid}|#{pane_current_command}')

# here-doc 喂给 while，不走管道，避免子壳吞掉 target
target=""
while IFS='|' read -r id pid cmd; do
  [ "$id" = "$current" ] && continue
  pane_runs_nvim "$pid" "$cmd" && continue
  target=$id
  break
done <<EOF
$panes
EOF

[ -z "$target" ] && exit 1

tmux load-buffer -
tmux paste-buffer -t "$target" -p
