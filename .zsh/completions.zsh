# 自定义命令补全
# 必须在 options.zsh 的 compinit 之后 source(见 zshrc)

# ── check-pkgbuild: 补全 AUR helper 缓存里的包名 ──────────────────────────────
# 让 `check-pkgbuild <Tab>` 列出 ~/.cache/paru/clone(或 yay/pikaur)下的包名
_check_pkgbuild() {
  local cache
  for cache in \
    ~/.cache/paru/clone \
    ~/.cache/yay \
    ~/.cache/pikaur/aur
  do
    [[ -d $cache ]] && { compadd -- ${cache}/*(/N:t); return; }
  done
}
compdef _check_pkgbuild check-pkgbuild
