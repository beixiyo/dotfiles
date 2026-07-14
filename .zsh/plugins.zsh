ZSH_PLUGIN_DIR="${ZSH_PLUGIN_DIR:-$HOME/.zsh/plugins}"
mkdir -p "$ZSH_PLUGIN_DIR"

# 按加载顺序 source（仓库在 ZSH_PLUGIN_DIR=~/.zsh/plugins，配置在 ~/.zsh/plugins/*.zsh）
source ~/.zsh/plugins/autosuggestions.zsh
source ~/.zsh/plugins/history-substring-search.zsh
source ~/.zsh/plugins/syntax-highlighting.zsh
# source ~/.zsh/plugins/fast-syntax-highlighting.zsh

# 和 fzf 冲突
source ~/.zsh/plugins/vi-mode.zsh
