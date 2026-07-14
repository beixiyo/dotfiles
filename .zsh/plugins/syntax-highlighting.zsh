ZSH_PLUGIN_DIR="${ZSH_PLUGIN_DIR:-$HOME/.zsh/plugins}"

# 不完整 clone（无主文件）时删掉重试一次，避免 "no such file or directory"
if [[ ! -f "$ZSH_PLUGIN_DIR/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]]; then
  rm -rf "$ZSH_PLUGIN_DIR/zsh-syntax-highlighting"
  git clone --depth=1 --single-branch --no-tags \
    https://github.com/zsh-users/zsh-syntax-highlighting \
    "$ZSH_PLUGIN_DIR/zsh-syntax-highlighting"
fi

if [[ -f "$ZSH_PLUGIN_DIR/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]]; then
  source "$ZSH_PLUGIN_DIR/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
  ZSH_HIGHLIGHT_STYLES[command]='fg=green'
  ZSH_HIGHLIGHT_STYLES[unknown-token]='fg=red,bold'
fi
