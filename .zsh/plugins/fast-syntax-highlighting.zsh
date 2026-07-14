# Deprecated: 已弃用，改用 zsh-users/zsh-syntax-highlighting（见 syntax-highlighting.zsh）
# 原因：和任何使用 `add-zle-hook-widget line-finish` 的插件（如 softmoth/zsh-vim-mode、
#      marlonrichert/zsh-hist）会形成 hook 链死循环，每次按回车触发
#      "maximum nested function level reached; increase FUNCNEST?"
# 现代 CPU 下 FSH 的"快 10 倍"在交互场景完全无感，故切回原版
# Refs:
#   https://github.com/zdharma-continuum/fast-syntax-highlighting/issues/65
#   https://github.com/softmoth/zsh-vim-mode/issues/8

ZSH_PLUGIN_DIR="${ZSH_PLUGIN_DIR:-$HOME/.zsh/plugins}"

# 不完整 clone（无主文件）时删掉重试一次，避免 "no such file or directory"
if [[ ! -f "$ZSH_PLUGIN_DIR/fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh" ]]; then
  rm -rf "$ZSH_PLUGIN_DIR/fast-syntax-highlighting"
  git clone --depth=1 --single-branch --no-tags \
    https://github.com/zdharma-continuum/fast-syntax-highlighting \
    "$ZSH_PLUGIN_DIR/fast-syntax-highlighting"
fi

if [[ -f "$ZSH_PLUGIN_DIR/fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh" ]]; then
  source "$ZSH_PLUGIN_DIR/fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh"
  # 内置默认已与原 z-sy-h 一致：command=green、unknown-token=red,bold
fi
