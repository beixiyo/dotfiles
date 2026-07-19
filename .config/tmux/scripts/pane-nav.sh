#!/bin/sh
# Ctrl+Alt+hjkl / Ctrl+Alt+方向键 的统一入口：决定这次按键是
#   透传给 pane 里的程序（nvim 的 smart-splits、或远端会话自己处理）
#   还是由 tmux 自己切 pane / 调大小
#
# 用法：pane-nav.sh <move|resize> <h|j|k|l> <pane_id>
#
# ── 为什么不用 @pane-is-vim ──
# 那是 smart-splits 写的「状态」。nvim 被 kill、崩溃，或插件退出时把 0 写错了
# pane（它 on_exit 里的 display-message 没带 -t，取到的是当前活动 pane 而不是
# nvim 自己那个），都会留下 @pane-is-vim=1 的残留，这个 pane 从此再也切不出去
#
# ── 为什么不直接 `ps -t <tty> | grep vim` ──
# 那是 vim-tmux-navigator 的经典做法，能顺带覆盖 sudo / 包装脚本，但它扫的是
# 整个 tty 上的所有进程：claude / codex 这类 AI CLI 在后台拉起的 nvim 会被算成
# 前台 vim，等于换个形式复现上面那个「切不出去」的 bug
#
# ── 实际采用的判定 ──
# 1. 前台进程本身就是 nvim              → 透传（99% 的情况）
# 2. 前台是远端会话（ssh/mosh）         → 透传，本地无从得知对面跑什么，交给对面
# 3. 前台是已知会把编辑器拉起来当子进程的程序（sudo / git / yazi / 包装脚本…）
#    → 再往下找后代里有没有 nvim，且该 nvim 必须在终端的前台进程组里、没被挂起
# 4. 其余（claude / codex / zsh 空闲 / 任意程序）→ tmux 自己切
# 关键在第 3 步的白名单：claude 之流不在名单里，它们的子进程压根不会被扫到

set -eu

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

# nvim 家族的进程名
is_nvim_name() {
  case ${1##*/} in
    nvim|vim|vi|view|vimdiff|nvimdiff|gvim|gview|*nvim*) return 0 ;;
    *) return 1 ;;
  esac
}

# 远端会话：对面的 nvim / tmux 自己会处理这个键；对面只是普通 shell 的话
# 这个键被吃掉，代价可接受
is_remote() {
  case ${1##*/} in
    ssh|sshpass|autossh|mosh|mosh-client|et|kitten) return 0 ;;
    *) return 1 ;;
  esac
}

# 会把 $EDITOR 当前台子进程拉起来的程序。只有名单内的进程才值得往下扫后代，
# 名单外一律不扫 —— 这是不把 AI CLI 的后台 nvim 误判成前台 vim 的关键
opens_editor_as_child() {
  case ${1##*/} in
    # 权限 / 环境包装
    sudo|doas|su|env|nice|nohup|stdbuf|time|script) return 0 ;;
    # 会调用 $EDITOR 的工具：git commit / rebase -i、lazygit、crontab -e 等
    git|lazygit|gitui|jj|hg|crontab|fzf) return 0 ;;
    # 文件管理器：在里面回车打开文件
    yazi|lf|ranger|nnn|vifm) return 0 ;;
    # 不 exec 的包装脚本，前台进程名会是脚本用的那个 shell
    sh|bash|zsh|dash|ksh|fish) return 0 ;;
    *) return 1 ;;
  esac
}

# --headless / --embed 的 nvim 不接管终端，纯粹是被别的程序当后端用的
# （claude / codex 这类 AI CLI 正是这么拉起 nvim 的），键透传过去只会石沉大海
is_headless_nvim() {
  case $(ps -o args= -p "$1" 2>/dev/null || true) in
    *--headless*|*--embed*) return 0 ;;
    *) return 1 ;;
  esac
}

# 这个进程是不是「真的在前台跑」：属于终端当前的前台进程组（pgid == tpgid），
# 且没被挂起或僵死（状态不含 T/X/Z）。用来排除 C-z 挂起的 nvim 和 `nvim &`
is_running_in_foreground() {
  read -r _state _pgid _tpgid <<EOF2
$(ps -o state=,pgid=,tpgid= -p "$1" 2>/dev/null || echo 'X 0 -1')
EOF2
  [ "$_pgid" = "$_tpgid" ] || return 1
  case $_state in *[TXZ]*) return 1 ;; esac
  return 0
}

# 从 pane 的顶层进程往下递归找 nvim，命中的必须确实在前台跑
descendant_nvim() {
  for _child in $(pgrep -P "$1" 2>/dev/null || true); do
    _name=$(ps -o comm= -p "$_child" 2>/dev/null || true)
    [ -n "$_name" ] || continue

    if is_nvim_name "$_name" || is_remote "$_name"; then
      if is_running_in_foreground "$_child" && ! is_headless_nvim "$_child"; then
        return 0
      fi
    fi
    descendant_nvim "$_child" && return 0
  done
  return 1
}

should_pass_through() {
  is_nvim_name "$pane_cmd" && ! is_headless_nvim "$pane_pid" && return 0
  is_remote "$pane_cmd" && return 0
  opens_editor_as_child "$pane_cmd" && descendant_nvim "$pane_pid" && return 0
  return 1
}

if should_pass_through; then
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
