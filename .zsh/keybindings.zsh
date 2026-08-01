# 依赖 plugins.zsh 中的 zsh-history-substring-search
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down

# Ctrl+Right：逐词接受 zsh-autosuggestions
bindkey '^[[1;5C' vi-forward-word

# Shift+Tab：直接进入 fzf 补全
_fzf_force_completion() {
  local FZF_COMPLETION_TRIGGER=''
  zle fzf-completion
}
zle -N _fzf_force_completion
bindkey '^[[Z' _fzf_force_completion

# clear screen
bindkey '^L' clear-screen
