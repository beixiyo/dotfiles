#!/bin/sh
# 在 tmux popup 里开一个「持久」scratch 终端，作为 nvim 内置终端的替代
#
# 用法：popup-term.sh <dir> [id]
#
# 为什么不是 `display-popup -E $SHELL`：那样每次弹出都是全新 shell，
# 关掉即丢历史与运行中的进程，比 toggleterm 还退步。这里让 popup 内部
# attach 到一个常驻的 scratch session，收起 popup 只是 detach，
# 里面跑着的 build / watch / REPL 全部原样留着，下次弹出接着用
#
# 两个必须踩过才知道的坑：
#   1. popup 内 $TMUX 是设置好的，直接 `tmux attach` 会被拒：
#      "sessions should be nested with care, unset $TMUX to force"
#      —— 所以内层命令必须 `TMUX= tmux attach`
#   2. `-t =name` 的 `=` 前缀（精确匹配，不做前缀模糊匹配）在 zsh 下会被
#      当成 `=command` 路径展开吃掉，必须带引号

set -eu

dir="${1:-$PWD}"
[ -d "$dir" ] || dir="$HOME"

# nvim 会传入实例级 id，使终端跟随该实例销毁；普通 tmux pane 仍按目录复用
# tmux session 名里的 . 和 : 有特殊含义（window/pane 分隔符），一律换成 -
base="${2:-$(basename "$dir")}"
base=$(printf '%s' "$base" | sed 's/[^[:alnum:]_-]/-/g')
[ -n "$base" ] || base="root"
name="popup-$base"

# 先在外层把 session 备好，popup 内部只剩一句 attach，出问题好定位
if ! tmux has-session -t "=$name" 2>/dev/null; then
  tmux new-session -d -s "$name" -c "$dir"
  # popup 高度本就吃紧，且这个 session 只有一个窗口，状态栏纯属浪费一行
  # 注意 -t 这里不能带 `=` 精确匹配前缀：has-session / attach 认，set-option 不认
  tmux set-option -t "$name" status off
fi

# 内层字符串只嵌 $name，而它已被 sed 洗成 [alnum_-]，不存在再引一层的问题；
# 含空格的 $dir 走 -d 参数，不进 shell 字符串
tmux display-popup -E -w 90% -h 90% -d "$dir" -T " $name " \
  "TMUX= tmux attach -t '=$name'"
