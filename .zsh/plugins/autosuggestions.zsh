ZSH_PLUGIN_DIR="${ZSH_PLUGIN_DIR:-$HOME/.zsh/plugins}"

# 不完整 clone（无主文件）时删掉重试一次，避免 "no such file or directory"
if [[ ! -f "$ZSH_PLUGIN_DIR/zsh-autosuggestions/zsh-autosuggestions.zsh" ]]; then
  rm -rf "$ZSH_PLUGIN_DIR/zsh-autosuggestions"
  git clone --depth=1 --single-branch --no-tags \
    https://github.com/zsh-users/zsh-autosuggestions \
    "$ZSH_PLUGIN_DIR/zsh-autosuggestions"
fi

if [[ -f "$ZSH_PLUGIN_DIR/zsh-autosuggestions/zsh-autosuggestions.zsh" ]]; then
  source "$ZSH_PLUGIN_DIR/zsh-autosuggestions/zsh-autosuggestions.zsh"
  # 用显式 truecolor 灰，避免 ANSI color 8 在某些终端（如 nvim toggleterm，
  # tokyonight 主题把 terminal_color_8 设成 #191815，几乎与背景同色）下不可见
  ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#6c6c6c'
fi
