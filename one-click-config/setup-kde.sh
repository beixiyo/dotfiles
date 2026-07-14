#!/usr/bin/env bash
# 一键部署 KDE MacTahoe 主题（主题 + 图标 + Kvantum + GTK + 桌面特效）
#
# 用法：
#   ./setup-kde.sh           # 安装全部
#   ./setup-kde.sh --theme   # 仅安装主题 + 图标
#   ./setup-kde.sh --deps    # 仅安装依赖包
#   ./setup-kde.sh --apply   # 仅应用主题
#   ./setup-kde.sh --icons   # 仅替换自定义图标
#
# 前提：
#   - Arch Linux + KDE Plasma 6
#   - paru 或 yay（AUR helper）已安装
#   - dotfiles 仓库已 clone 到 ~

# 重启 KDE 应用更改
# # 重启 Plasma 桌面（面板/主题/配色）
# killall plasmashell && plasmashell &disown
# # 重载 KWin（窗口装饰/特效/圆角）
# qdbus6 org.kde.KWin /KWin reconfigure
# # 刷新图标缓存
# kbuildsycoca6

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
SRC_DIR="$HOME/src"
ASSETS_DIR="$SCRIPT_DIR/assets/icons"
ICON_BASE="$HOME/.local/share/icons"
ICON_THEMES=("MacTahoe-dark" "MacTahoe")

for lib_file in common download repos packages; do
  source "$LIB_DIR/${lib_file}.sh"
done
init_colors

install_deps() {
  log "Installing KDE theme dependencies ..."
  install_package sassc
  install_package kvantum
  install_package kvantum-qt5
  local aur_pkgs=(mactahoe-gtk-theme plasma6-applets-appgrid plasma6-applets-caraoke-git)

  if [ "$PKG_MANAGER" = 'paru' ] || [ "$PKG_MANAGER" = 'yay' ]; then
    for pkg in "${aur_pkgs[@]}"; do
      install_package "$pkg"
    done
  else
    log_warn "No AUR helper (paru/yay) found, skipping: ${aur_pkgs[*]}"
  fi

  log_ok "Dependencies installed"
}

install_theme() {
  mkdir -p "$SRC_DIR"

  ensure_git_repo "https://github.com/vinceliuice/MacTahoe-icon-theme.git" "$SRC_DIR/MacTahoe-icon-theme"
  cd "$SRC_DIR/MacTahoe-icon-theme" && ./install.sh
  log_ok "MacTahoe icon theme installed"

  ensure_git_repo "https://github.com/vinceliuice/MacTahoe-kde.git" "$SRC_DIR/MacTahoe-kde"
  cd "$SRC_DIR/MacTahoe-kde" && ./install.sh
  log_ok "MacTahoe KDE theme installed"
}

replace_icon() {
  local src="$1"
  local icon_name="$2"
  local theme_dir="$3"
  local backup_dir="$theme_dir/.backup"

  if [[ ! -f "$src" ]]; then
    log_warn "Replacement icon not found: $src"
    return 1
  fi

  local count=0
  while IFS= read -r -d '' target; do
    local rel="${target#$theme_dir/}"
    local backup="$backup_dir/$rel"

    if [[ ! -f "$backup" ]]; then
      mkdir -p "$(dirname "$backup")"
      cp "$target" "$backup"
    fi

    cp "$src" "$target"
    count=$((count + 1))
  done < <(find "$theme_dir" -path '*/.backup' -prune -o -name "$icon_name" -print0 2>/dev/null || true)

  if [[ $count -gt 0 ]]; then
    log_ok "Replaced $count '$icon_name' in $(basename "$theme_dir")"
  fi
}

patch_icons() {
  log "Patching custom icons ..."

  for theme in "${ICON_THEMES[@]}"; do
    local theme_dir="$ICON_BASE/$theme"
    [[ ! -d "$theme_dir" ]] && continue

    replace_icon "$ASSETS_DIR/start-here.svg" "start-here.svg" "$theme_dir"
    replace_icon "$ASSETS_DIR/system-file-manager.svg" "system-file-manager.svg" "$theme_dir"
  done

  kbuildsycoca6 2>/dev/null || true
  log_ok "Icon patch complete"
}

install_title_bar() {
  local plugin_id="com.github.antroids.application-title-bar"
  local plasmoid_url="https://github.com/antroids/application-title-bar/releases/latest/download/application-title-bar.plasmoid"
  local tmp="/tmp/application-title-bar.plasmoid"

  # kpackagetool6 缺失则跳过（与本文件其它 KDE 工具一致地做存在性守卫）：
  # 否则 set -e 下后面无守卫地调用它会以 127 中止整脚本，并残留已下载的临时文件
  if ! command -v kpackagetool6 >/dev/null 2>&1; then
    log_warn "kpackagetool6 not found (Plasma 6 missing?); skipping application-title-bar"
    return 0
  fi

  log "Installing application-title-bar widget ..."

  # 无论成功失败都清理临时文件
  trap 'rm -f "$tmp"' RETURN

  if ! wget -q "$plasmoid_url" -O "$tmp"; then
    log_warn "Failed to download application-title-bar plasmoid; skipping"
    return 0
  fi

  if kpackagetool6 -t Plasma/Applet -l 2>/dev/null | grep -q "$plugin_id"; then
    kpackagetool6 -t Plasma/Applet -u "$tmp"
  else
    kpackagetool6 -t Plasma/Applet -i "$tmp"
  fi

  log_ok "application-title-bar installed"
}

apply_theme() {
  log "Applying MacTahoe-Dark global theme ..."
  plasma-apply-lookandfeel -a com.github.vinceliuice.MacTahoe-Dark 2>/dev/null \
    || log_warn "plasma-apply-lookandfeel failed (run inside a Plasma session)"

  if command -v kvantummanager &>/dev/null; then
    log "Setting Kvantum theme to MacTahoeDark ..."
    mkdir -p "$HOME/.config/Kvantum"
    printf '[General]\ntheme=MacTahoeDark\n' > "$HOME/.config/Kvantum/kvantum.kvconfig"
  fi

  log_ok "Theme applied. Reboot or run: killall plasmashell && plasmashell &disown"
}

main() {
  local mode="${1:-all}"

  case "$mode" in
    --deps)  install_deps ;;
    --theme) install_theme ;;
    --icons) patch_icons ;;
    --apply) apply_theme ;;
    all|*)   install_deps; install_theme; patch_icons; install_title_bar; apply_theme ;;
  esac
}

main "$@"
