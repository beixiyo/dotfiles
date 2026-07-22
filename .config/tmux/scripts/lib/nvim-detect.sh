# 判定一个 pane 里到底是不是「nvim 正占着终端前台」
#
# POSIX sh，供 pane-nav.sh 和 send-to-pane.sh 共用。只提供判定，不做任何动作
#
# ── 为什么不读 @pane-is-vim ──
# 那是 smart-splits 写的「状态」而不是事实。nvim 被 kill、崩溃，或插件 on_exit
# 里把 0 写错了 pane（它的 display-message 没带 -t，取到的是当前活动 pane 而不是
# nvim 自己那个），都会留下 @pane-is-vim=1 的残留。带着残留的 pane 会被永久误判
# 成 vim —— 导航切不出去，send-to-pane 也找不到投递目标
#
# ── 为什么不用 `ps -t <tty> | grep vim` ──
# 那是 vim-tmux-navigator 的经典做法，能顺带覆盖 sudo / 包装脚本，但它扫的是整个
# tty 上的所有进程：claude / codex 这类 AI CLI 在后台拉起的 nvim 会被算成前台 vim，
# 等于换个形式复现上面那个「切不出去」的 bug
#
# ── 实际采用的判定 ──
# 1. 前台进程本身就是 nvim                → 是（99% 的情况）
# 2. 前台是已知会把编辑器拉起来当子进程的程序（sudo / git / yazi / 包装脚本…）
#    → 再往下找后代里有没有 nvim，且该 nvim 必须在终端的前台进程组里、没被挂起
# 3. 其余（claude / codex / zsh 空闲 / 任意程序）→ 不是
# 关键在第 2 步的白名单：claude 之流不在名单里，它们的子进程压根不会被扫到

# nvim 家族的进程名
is_nvim_name() {
  case ${1##*/} in
    nvim|vim|vi|view|vimdiff|nvimdiff|gvim|gview|*nvim*) return 0 ;;
    *) return 1 ;;
  esac
}

# 远端会话。本地无从得知对面跑什么，由调用方决定怎么对待
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
# （claude / codex 这类 AI CLI 正是这么拉起 nvim 的）
is_headless_nvim() {
  case $(ps -o args= -p "$1" 2>/dev/null || true) in
    *--headless*|*--embed*) return 0 ;;
    *) return 1 ;;
  esac
}

# 这个进程是不是「真的在前台跑」：属于终端当前的前台进程组（pgid == tpgid），
# 且没被挂起或僵死（状态不含 T/X/Z）。用来排除 C-z 挂起的 nvim 和 `nvim &`
is_running_in_foreground() {
  read -r _state _pgid _tpgid <<EOF
$(ps -o state=,pgid=,tpgid= -p "$1" 2>/dev/null || echo 'X 0 -1')
EOF
  [ "$_pgid" = "$_tpgid" ] || return 1
  case $_state in *[TXZ]*) return 1 ;; esac
  return 0
}

# 从 $2 往下递归找名字满足 $1（判定函数名）的后代，命中的必须确实在前台跑
descendant_match() {
  for _child in $(pgrep -P "$2" 2>/dev/null || true); do
    _name=$(ps -o comm= -p "$_child" 2>/dev/null || true)
    [ -n "$_name" ] || continue

    if "$1" "$_name"; then
      if is_running_in_foreground "$_child" && ! is_headless_nvim "$_child"; then
        return 0
      fi
    fi
    descendant_match "$1" "$_child" && return 0
  done
  return 1
}

_is_nvim_or_remote() {
  is_nvim_name "$1" || is_remote "$1"
}

# 这个 pane 前台是不是 nvim。用法：pane_runs_nvim <pane_pid> <pane_current_command>
# 远端会话不算 —— 对 send-to-pane 来说 ssh 是合法的投递目标
pane_runs_nvim() {
  is_nvim_name "$2" && ! is_headless_nvim "$1" && return 0
  opens_editor_as_child "$2" && descendant_match is_nvim_name "$1" && return 0
  return 1
}

# 这个 pane 该不该吃掉导航键。用法：pane_wants_nav_keys <pane_pid> <pane_current_command>
# 比 pane_runs_nvim 多认远端会话：本地不知道对面跑什么，键交给对面自己处理
pane_wants_nav_keys() {
  is_nvim_name "$2" && ! is_headless_nvim "$1" && return 0
  is_remote "$2" && return 0
  opens_editor_as_child "$2" && descendant_match _is_nvim_or_remote "$1" && return 0
  return 1
}
