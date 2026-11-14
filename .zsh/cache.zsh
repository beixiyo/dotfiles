# init 缓存与 Homebrew 环境
# 必须在 options.zsh 的 compinit 之前 source：brew shellenv 要先把补全目录放进 fpath
#
# 缓存：shell 集成脚本只在工具升级时重建，平时直接 source
# 失效条件：缓存不存在或为空、缓存首行记录的工具真实路径变了（brew 升级会换 Cellar 版本目录）、工具 binary 比缓存新
# 手动强制刷新：zsh-cache-flush
_init_cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/init"
mkdir -p "$_init_cache_dir"

# 生成并 source 一份缓存：_cache_source <缓存名> <工具路径> <生成命令参数...>
_cache_source() {
  local name=$1 bin=$2; shift 2
  local cache="$_init_cache_dir/${name}.zsh"
  local stamp="# cache-bin: ${bin:A}"
  local first=""
  [[ -s $cache ]] && read -r first < "$cache"

  if [[ $first != "$stamp" || $bin -nt $cache ]]; then
    # 先写临时文件再原子替换：生成失败或被中断都不会留下空文件或半截文件
    local out tmp="$cache.$$"
    if out="$("$bin" "$@" 2>/dev/null)" && [[ -n $out ]]; then
      print -r -- "$stamp"$'\n'"$out" >| "$tmp" && mv -f "$tmp" "$cache" || rm -f "$tmp"
    fi
  fi

  [[ -s $cache ]] && source "$cache"
}

# 按命令名缓存：_cached_eval <命令> <参数...>，命令不存在则跳过
_cached_eval() {
  local bin
  bin=$(command -v "$1" 2>/dev/null) || return 0
  _cache_source "$1" "$bin" "${@:2}"
}

zsh-cache-flush() {
  rm -f "$_init_cache_dir"/*.zsh
  print "zsh init cache flushed — reopen shell to rebuild"
}


# Homebrew（Apple Silicon / Intel / Linux 常见路径，未安装则跳过）
for _brew in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew; do
  if [[ -x $_brew ]]; then
    _cache_source brew "$_brew" shellenv zsh
    break
  fi
done
unset _brew
