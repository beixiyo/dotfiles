ZSH_PLUGIN_DIR="${ZSH_PLUGIN_DIR:-$HOME/.zsh/plugins}"

# 不完整 clone（无主文件）时删掉重试一次，避免 "no such file or directory"
if [[ ! -f "$ZSH_PLUGIN_DIR/zsh-history-substring-search/zsh-history-substring-search.zsh" ]]; then
  rm -rf "$ZSH_PLUGIN_DIR/zsh-history-substring-search"
  git clone --depth=1 --single-branch --no-tags \
    https://github.com/zsh-users/zsh-history-substring-search \
    "$ZSH_PLUGIN_DIR/zsh-history-substring-search"
fi

if [[ -f "$ZSH_PLUGIN_DIR/zsh-history-substring-search/zsh-history-substring-search.zsh" ]]; then
  source "$ZSH_PLUGIN_DIR/zsh-history-substring-search/zsh-history-substring-search.zsh"
fi
