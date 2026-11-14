# 有 fastfetch 则启动时执行一次（系统信息概览）
command -v fastfetch &>/dev/null && fastfetch

# ------- 自动设置终端标题为当前目录名 -------
_set_term_title() {
  print -Pn "\033]0;$(basename "$PWD")\033\\"
}
autoload -Uz add-zsh-hook
add-zsh-hook precmd _set_term_title
add-zsh-hook preexec _set_term_title

# Kitty native 模式用 user-var 把 pane 键透传给 Nvim；shell 重新拿回前台时清理，
# 覆盖 Nvim 被 kill / 崩溃、来不及执行 VimLeavePre 的情况。嵌入 Nvim 的终端保留
# 外层标记，tmux 模式则由 tmux 路由
_clear_kitty_nvim_var() {
  [[ -n "${KITTY_WINDOW_ID:-}" && -z "${TMUX:-}" && -z "${NVIM:-}" ]] || return
  print -n $'\e]1337;SetUserVar=IS_NVIM\a'
}
add-zsh-hook precmd _clear_kitty_nvim_var


# Prompt 美化 / 运行时管理 / 智能 cd（未安装则跳过，不报错）；缓存机制见 cache.zsh
_cached_eval starship init zsh
_cached_eval zoxide   init --cmd cd zsh
# mise activate 的输出带有生成时的整份 PATH 快照，缓存后会覆盖之后新增的 PATH 项，所以不走缓存
command -v mise &>/dev/null && eval "$(mise activate zsh)"
_cached_eval fzf      --zsh

# mise 的 precmd hook 会重新整理 PATH，保持用户入口优先
_prepend_local_bin() {
  [[ $path[1] == "$HOME/.local/bin" ]] && return
  path=("$HOME/.local/bin" $path)
  export PATH
  rehash
}

add-zsh-hook precmd _prepend_local_bin
_prepend_local_bin
