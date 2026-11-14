# ── General ──────────────────────────────────────────────
setopt interactivecomments   # 允许命令行输入 # 注释


# ── History ──────────────────────────────────────────────
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000

setopt hist_ignore_all_dups  # 删除重复历史
setopt share_history         # 多终端共享历史
setopt inc_append_history    # 每条命令立即写入 HISTFILE
setopt hist_reduce_blanks    # 压缩多余空格


# ── Completions ──────────────────────────────────────────
setopt prompt_subst          # 允许 PROMPT 中执行命令替换

# zstyle 必须在 compinit 之前设置才生效
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list \
  'm:{a-zA-Z}={A-Za-z}' \
  'r:|[._-]=* r:|=*'

# 统一 ls / 补全颜色（dircolors 由系统或 ~/.dircolors 提供）
command -v dircolors >/dev/null 2>&1 && eval "$(dircolors -b)"
zstyle ':completion:*:default' list-colors ${(s.:.)LS_COLORS}

# zsh/complist 必须在 compinit 之前加载，否则 menu-select widget 不会被重定义
zmodload zsh/complist

# 加载补全系统：.zcompdump 超过 24h 才完整重新扫描 fpath，否则跳过检查直接读缓存（-C）
# -i 忽略不安全目录检查，避免因权限问题跳过补全
# (#q...) 需要 extended_glob，用匿名函数限定作用域，不影响交互 shell 的选项
# 新装工具的补全最多延迟 24h 出现，想立刻生效：rm ~/.zcompdump 后重开 shell
autoload -Uz compinit
() {
  setopt local_options extended_glob
  local -a stale=(${ZDOTDIR:-$HOME}/.zcompdump(N.mh+24))
  if (( $#stale )); then
    compinit -i
  else
    compinit -i -C
  fi
}
