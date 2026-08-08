#!/bin/sh
# 在 tmux popup 里开一个「持久」scratch 终端，作为 nvim 内置终端的替代
#
# 用法：popup-term.sh <dir> [id] [owner-pane] [owner-pid]
#       可选参数缺省时传 `-`，不能传空串（原因见下方参数归一处）
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

# 可选参数一律用 `-` 占位：tmux 的 #{q:...} 对未设置的选项展开成空串而不是 ''，
# run-shell 的命令行做词分割后参数会整体前移，owner-pane 会被静默挤掉
id="${2:-}"
owner_pane="${3:-}"
owner_pid="${4:-}"
if [ "$id" = '-' ]; then id=''; fi
if [ "$owner_pane" = '-' ]; then owner_pane=''; fi
if [ "$owner_pid" = '-' ]; then owner_pid=''; fi

# popup 跟随来源 pane，而不是 cwd。nvim 会再传入实例级 id 和 PID，确保退出
# nvim 后立即回收；普通 tmux pane 靠 cleanup 脚本轮询来源 pane 是否还在
# tmux session 名里的 . 和 : 有特殊含义（window/pane 分隔符），一律换成 -
base="${id:-${owner_pane:-$(basename "$dir")}}"
base=$(printf '%s' "$base" | sed 's/[^[:alnum:]_-]/-/g')
[ -n "$base" ] || base="root"
name="popup-$base"

# 先在外层把 session 备好，popup 内部只剩一句 attach，出问题好定位
if ! tmux has-session -t "=$name" 2>/dev/null; then
  tmux new-session -d -s "$name" -c "$dir"
  # popup 高度本就吃紧，且这个 session 只有一个窗口，状态栏纯属浪费一行
  # 注意 -t 这里不能带 `=` 精确匹配前缀：has-session / attach / kill-session 认，
  # set-option / show-options 不认，带上只会得到 "no such session"
  tmux set-option -t "$name" status off
fi

# 全局是 detach-on-destroy off，那对常驻 session 合理，对 popup 是灾难：popup 里
# 一旦 session 被销毁（C-M-w kill-pane、nvim 退出时 kill-session、cleanup 回收），
# 客户端不会退出，而是改挂到「最近活跃的其余 session」——也就是外层那个 session
# 本身，于是浮层不关闭反而变成自己套自己的嵌套镜像。每次都设，老 session 也能纠正
tmux set-option -t "$name" detach-on-destroy on

# 这两行读的是「上一任 owner」，带 `=` 会静默读成空，导致每次按键都重复起 cleanup
previous_owner_pane=$(tmux show-options -t "$name" -qv @popup_owner_pane 2>/dev/null || true)
previous_owner_pid=$(tmux show-options -t "$name" -qv @popup_owner_pid 2>/dev/null || true)
tmux set-option -t "$name" @popup_owner_pane "$owner_pane"
tmux set-option -t "$name" @popup_owner_pid "$owner_pid"

if [ -n "$owner_pane" ] \
  && { [ "$previous_owner_pane" != "$owner_pane" ] || [ "$previous_owner_pid" != "$owner_pid" ]; }; then
  session_id=$(tmux display-message -p -t "=$name:" '#{session_id}')
  tmux run-shell -b \
    "~/.config/tmux/scripts/cleanup-popup-sessions.sh '$name' '$session_id' '$owner_pane' '$owner_pid'"
fi

# 标题栏当快捷键提示
#
# 全程单引号，别改成双引号：里面有反引号（^`），双引号下会被 shell 当命令替换
# 键位来源是 conf/pane.conf 和 conf/popup.conf 的 root 表绑定，改键要同步这里
popup_hint='#[align=centre]#[fg=#aaaaaa] Hide #[fg=#C5719D]^`  '\
'#[fg=#aaaaaa]Close #[fg=#C5719D]^⌥w  '\
'#[fg=#aaaaaa]VSplit #[fg=#C5719D]^⌥\  '\
'#[fg=#aaaaaa]HSplit #[fg=#C5719D]^⌥-  '\
'#[fg=#aaaaaa]Focus #[fg=#C5719D]^⌥hjkl  '\
'#[fg=#aaaaaa]Zoom #[fg=#C5719D]^⌥b '

# 内层字符串只嵌 $name，而它已被 sed 洗成 [alnum_-]，不存在再引一层的问题；
# 含空格的 $dir 走 -d 参数，不进 shell 字符串
tmux display-popup -E -w 90% -h 90% -d "$dir" -T "$popup_hint" \
  "TMUX= tmux attach -t '=$name'"
