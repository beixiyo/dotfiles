# 有 fastfetch 则启动时执行一次（系统信息概览）
command -v fastfetch &>/dev/null && fastfetch

# ------- 自动设置终端标题为当前目录名 -------
_set_term_title() {
  print -Pn "\033]0;$(basename "$PWD")\033\\"
}
autoload -Uz add-zsh-hook
add-zsh-hook precmd _set_term_title
add-zsh-hook preexec _set_term_title


# ── init 缓存：shell 集成脚本只在工具升级时重建，平时直接 source ──
# 失效条件：缓存文件不存在，或工具 binary 比缓存新
# 手动强制刷新：zsh-cache-flush
_init_cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/init"
mkdir -p "$_init_cache_dir"

_cached_eval() {
  local name=$1; shift
  local bin
  bin=$(command -v "$name" 2>/dev/null) || return 0
  local cache="$_init_cache_dir/${name}.zsh"
  if [[ ! -f $cache || $bin -nt $cache ]]; then
    "$bin" "$@" > "$cache" 2>/dev/null
  fi
  [[ -s $cache ]] && source "$cache"
}

zsh-cache-flush() {
  rm -f "$_init_cache_dir"/*.zsh
  print "zsh init cache flushed — reopen shell to rebuild"
}


# Homebrew（Apple Silicon / Intel / Linux 常见路径，未安装则跳过）
for _brew in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew; do
  if [[ -x $_brew ]]; then
    _brew_cache="$_init_cache_dir/brew.zsh"
    if [[ ! -f $_brew_cache || $_brew -nt $_brew_cache ]]; then
      "$_brew" shellenv zsh > "$_brew_cache" 2>/dev/null
    fi
    [[ -s $_brew_cache ]] && source "$_brew_cache"
    break
  fi
done
unset _brew _brew_cache

# Prompt 美化 / 运行时管理 / 智能 cd（未安装则跳过，不报错）
_cached_eval starship init zsh
_cached_eval zoxide   init --cmd cd zsh
_cached_eval mise     activate zsh
_cached_eval fzf      --zsh
