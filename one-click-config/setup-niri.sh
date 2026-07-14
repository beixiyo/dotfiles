#!/usr/bin/env bash
# 一键部署 Niri 桌面环境（Arch Linux）
#
# 用法：
#   ./setup-niri.sh           # 安装全部
#   ./setup-niri.sh --deps    # 仅安装依赖包
#   ./setup-niri.sh --locale  # 仅生成 zh_CN locale
#
# 前提：
#   - Arch Linux + paru/yay
#   - dotfiles 仓库已 clone 到 ~（配置文件自动就位）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
for lib_file in common packages; do
  source "$LIB_DIR/${lib_file}.sh"
done

init_colors

# ── 包列表 ────────────────────────────────────────────────────

CORE_PACKAGES=(
  niri
  xdg-desktop-portal-gnome
  xdg-desktop-portal-gtk
  xwayland-satellite
)

UI_PACKAGES=(
  waybar
  fuzzel
  mako
  libnotify
  polkit-gnome
  awww
  imagemagick
  swayosd
)

LOCK_IDLE_PACKAGES=(
  hyprlock
  swayidle
)

CLIPBOARD_PACKAGES=(
  wl-clipboard
  cliphist
  quickshell
  xdg-user-dirs
)

# 视频缩略图 + 元数据（clipboard PreviewOverlay 用；不装则视频条目无缩略图）
# 注意：ffprobe 由 ffmpeg 提供，无独立同名包，单独安装会 target not found 并在 set -e 下中止整脚本
CLIPBOARD_VIDEO_PACKAGES=(
  ffmpeg
)

MEDIA_PACKAGES=(
  brightnessctl
  cava
  playerctl
)

KEYRING_PACKAGES=(
  gnome-keyring
  libsecret
)

THEME_PACKAGES=(
  matugen
)

SCREENSHOT_PACKAGES=(
  mark-shot
)

WAYBAR_EXTRA_PACKAGES=(
  gnome-clocks
  gnome-calendar
  bluetui
  pavucontrol
)

# ── 函数 ──────────────────────────────────────────────────────

install_packages() {
  local -n pkgs=$1
  local label="$2"
  log "Installing $label ..."
  for pkg in "${pkgs[@]}"; do
    if pacman -Qi "$pkg" &>/dev/null; then
      log "  $pkg already installed, skipping"
    else
      log "  Installing $pkg ..."
      install_package "$pkg"
    fi
  done
  log_ok "$label done"
}

setup_deps() {
  install_packages CORE_PACKAGES "核心（合成器 + Portal + XWayland）"
  install_packages UI_PACKAGES "UI 工具（Waybar + Fuzzel + Mako + 壁纸 + 通知）"
  install_packages LOCK_IDLE_PACKAGES "锁屏与空闲管理"
  install_packages CLIPBOARD_PACKAGES "剪贴板"
  install_packages CLIPBOARD_VIDEO_PACKAGES "剪贴板视频支持（ffmpeg，含 ffprobe）"
  install_packages MEDIA_PACKAGES "媒体控制（亮度 + Cava + Playerctl）"
  install_packages KEYRING_PACKAGES "密钥环（gnome-keyring + libsecret）"
  install_packages THEME_PACKAGES "动态配色（Matugen）"

  printf '\n' >&2
  printf '[%s] Install Waybar extras (gnome-clocks, bluetui ...)? [y/N] ' "$(date +'%F %T')" >&2
  read -r resp || resp=''
  if [[ "$resp" =~ ^[yY] ]]; then
    install_packages WAYBAR_EXTRA_PACKAGES "Waybar 增强模块"
  else
    log "Skipping Waybar extras"
  fi

  printf '\n' >&2
  printf '[%s] Install mark-shot (截图+标注)? [y/N] ' "$(date +'%F %T')" >&2
  read -r resp || resp=''
  if [[ "$resp" =~ ^[yY] ]]; then
    install_packages SCREENSHOT_PACKAGES "截图标注工具"

    printf '[%s] Set up OCR backend (rapidocr via pip) for copy image text? [y/N] ' "$(date +'%F %T')" >&2
    read -r resp || resp=''
    if [[ "$resp" =~ ^[yY] ]]; then
      log "Setting up OCR Python venv ..."
      python3 -m venv ~/.local/share/mark-shot/ocr-venv
      ~/.local/share/mark-shot/ocr-venv/bin/pip install -U pip rapidocr onnxruntime
      log_ok "OCR backend installed"
    else
      log "Skipping OCR backend; mark-shot will use tesseract if available, or OCR will be unavailable"
    fi
  else
    log "Skipping mark-shot"
  fi
}

setup_locale() {
  log "Generating zh_CN.UTF-8 locale ..."
  if locale -a 2>/dev/null | grep -q "zh_CN.utf8"; then
    log "zh_CN.UTF-8 already generated, skipping"
    return
  fi
  sudo cp /etc/locale.gen "/etc/locale.gen.bak.$(date +%s)" || log_warn 'could not back up /etc/locale.gen'
  sudo sed -i 's/^#zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' /etc/locale.gen
  sudo locale-gen
  log_ok "zh_CN.UTF-8 locale generated"
}

show_summary() {
  printf '\n' >&2
  log "═══════════════════════════════════════════"
  log "  Niri 部署完成"
  log "═══════════════════════════════════════════"
  log ""
  log "  配置文件已在 dotfiles 仓库中，无需额外操作："
  log "    ~/.config/niri/       合成器配置"
  log "    ~/.config/waybar/     状态栏"
  log "    ~/.config/hypr/       锁屏"
  log "    ~/.config/fuzzel/     启动器"
  log "    ~/.config/mako/       通知"
  log "    ~/.config/swayosd/    音量/亮度 OSD"
  log "    ~/.config/matugen/    动态配色模板"
  log "    ~/.config/quickshell/ 剪贴板弹窗（qs-popup clipboard）"
  log ""
  log "  启动方式（任选一种）："
  log "    - TTY 启动：niri-session"
  log "    - 显示管理器：装 greetd / SDDM 等，选 Niri 会话"
  log "    详见 display-manager.md"
  log ""
  log "  首次启动建议运行壁纸初始化："
  log "    matugen image ~/Pictures/壁纸.png --prefer saturation -q"
  log ""
}

# ── 入口 ──────────────────────────────────────────────────────

case "${1:-all}" in
  --deps)   setup_deps ;;
  --locale) setup_locale ;;
  all)
    setup_deps
    setup_locale
    show_summary
    ;;
  *)
    echo "Usage: $0 [--deps|--locale]" >&2
    exit 1
    ;;
esac
