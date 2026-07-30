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
  noctalia-git
  libnotify
  wl-clipboard
  xdg-user-dirs
)

MEDIA_PACKAGES=(
  brightnessctl
  playerctl
)

KEYRING_PACKAGES=(
  gnome-keyring
)

# XEmbed 托盘桥由 plasma-workspace 提供，将旧协议图标转换为 StatusNotifierItem
COMPAT_PACKAGES=(
  plasma-workspace
)

SCREENSHOT_PACKAGES=(
  mark-shot
)

# ── 旧桌面方案（仅作回退参考，不再默认安装）───────────────
#
# Noctalia 已统一接管状态栏、启动器、通知、Polkit、壁纸、动态配色、
# 锁屏、空闲管理、OSD 和剪贴板。下列软件的配置仍保留在 dotfiles 中，
# 但 setup-niri.sh 不会安装它们
LEGACY_DESKTOP_PACKAGES=(
  waybar
  fuzzel
  mako
  polkit-gnome
  awww
  imagemagick
  swayosd
  hyprlock
  swayidle
  cliphist
  quickshell
  ffmpeg
  cava
  matugen
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
  install_packages UI_PACKAGES "Noctalia 桌面 Shell 与基础集成"
  install_packages MEDIA_PACKAGES "媒体控制（亮度 + Playerctl）"
  install_packages KEYRING_PACKAGES "密钥环（加密剪贴板历史）"
  install_packages COMPAT_PACKAGES "旧托盘图标兼容桥"

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

setup_noctalia_service() {
  local service_file="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/noctalia.service"

  if ! command -v systemctl >/dev/null 2>&1; then
    log_warn "systemctl not found; enable noctalia.service manually"
    return
  fi

  if [ ! -f "$service_file" ]; then
    log_warn "$service_file not found; deploy dotfiles before enabling Noctalia"
    return
  fi

  log "Enabling Noctalia user service ..."
  if systemctl --user daemon-reload && systemctl --user enable noctalia.service; then
    log_ok "Noctalia user service enabled"
  else
    log_warn "Could not enable noctalia.service; run systemctl --user enable noctalia.service after login"
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
  log "    ~/.config/noctalia/   状态栏、通知、启动器、锁屏、壁纸与动态配色"
  log "    ~/.config/systemd/user/noctalia.service"
  log ""
  log "  启动方式（任选一种）："
  log "    - TTY 启动：niri-session"
  log "    - 显示管理器：装 greetd / SDDM 等，选 Niri 会话"
  log ""
  log "  Noctalia 会随图形会话启动，并从 ~/Pictures 选择壁纸和生成主题。"
  log "  Waybar、Mako、Awww、Matugen、Hyprlock 等旧配置仅保留作回退。"
  log ""
}

# ── 入口 ──────────────────────────────────────────────────────

case "${1:-all}" in
  --deps)   setup_deps ;;
  --locale) setup_locale ;;
  all)
    setup_deps
    setup_locale
    setup_noctalia_service
    show_summary
    ;;
  *)
    echo "Usage: $0 [--deps|--locale]" >&2
    exit 1
    ;;
esac
