# ── Zsh 内置 vi 模式 ──────────────────────────────────────

# KEYTIMEOUT 单位是百分秒（1/100s），20 = 200ms
# 不要设成 1（10ms），否则 cs"( 等多键 normal 命令会被拆成单键
KEYTIMEOUT=20

bindkey -v

# ── 光标形状 + 模式指示（RPS1）联动 ──────────────────────
# 光标：DECSCUSR 转义，kitty / WezTerm / Ghostty 等均支持
# RPS1：starship 只占用 PS1，RPS1 可自由使用
RPS1='%F{8}[I]%f'

zle-keymap-select() {
  case $KEYMAP in
    vicmd)      print -n '\e[2 q'; RPS1='%F{2}[N]%f' ;;
    visual)     print -n '\e[2 q'; RPS1='%F{4}[V]%f' ;;
    viins|main) print -n '\e[5 q'; RPS1='%F{8}[I]%f' ;;
  esac
  zle reset-prompt
}
# 每行开始重置为 insert 光标（防止上条命令执行后光标形状残留）
zle-line-init() { print -n '\e[5 q' }

zle -N zle-keymap-select
zle -N zle-line-init

# ── 逃逸 & 历史搜索 ──────────────────────────────────────
bindkey -M viins 'jk' vi-cmd-mode

# vicmd 下 ↑↓ 继续走 history-substring-search
bindkey -M vicmd '^[[A' history-substring-search-up
bindkey -M vicmd '^[[B' history-substring-search-down

# ── Surround（zsh 5.0.8+ 内置）──────────────────────────
autoload -Uz surround
zle -N delete-surround surround
zle -N add-surround surround
zle -N change-surround surround
bindkey -a cs change-surround
bindkey -a ds delete-surround
bindkey -a ys add-surround
bindkey -M visual S add-surround

# ── C-g：在 $EDITOR 中编辑当前命令行（zsh 内置）────────
autoload -Uz edit-command-line
zle -N edit-command-line
bindkey -M vicmd '^G' edit-command-line
bindkey -M viins '^G' edit-command-line

# ── Text objects：括号 & 引号（zsh 5.0.8+ 内置）─────────
autoload -Uz select-bracketed select-quoted
zle -N select-bracketed
zle -N select-quoted
for km in viopp visual; do
  for c in {a,i}${(s..)^:-'()[]{}<>bB'}; do
    bindkey -M $km $c select-bracketed
  done
  for c in {a,i}${(s..)^:-\"\'\`\|,./:;=+@}; do
    bindkey -M $km $c select-quoted
  done
done
unset km c
