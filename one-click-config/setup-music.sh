#!/usr/bin/env bash
# 安装 MPD/rmpc，Linux 下同时安装 mpd-mpris；随后初始化已部署的用户配置
# 用法：bash setup-music.sh [--deps-only]；不包含 Pigma，不复制或覆盖配置
# 仅自动管理 Linux systemd 用户服务；其他平台提示手动配置

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for lib_file in common packages; do
  # shellcheck disable=SC1090 # 文件名来自上方固定列表
  source "$SCRIPT_DIR/lib/$lib_file.sh"
done

# 按命令探测缺失项，沿用通用包管理器的提权和按需同步机制
install_music_dependencies() {
  local with_mpris="$1"
  local commands=(mpd rmpc)
  if [ "$with_mpris" -eq 1 ]; then
    commands+=(mpd-mpris)
  fi

  local cmd
  for cmd in "${commands[@]}"; do
    if command -v "$cmd" >/dev/null 2>&1; then
      log_ok "[skip] $cmd already installed"
      continue
    fi

    if [ -z "$PKG_MANAGER" ]; then
      PKG_MANAGER="$(detect_package_manager)"
    fi
    case "$cmd:$PKG_MANAGER" in
      mpd:paru|mpd:yay|mpd:pacman|mpd:brew|mpd:apt|mpd:apt-get|mpd:dnf|mpd:yum|mpd:zypper \
        |rmpc:paru|rmpc:yay|rmpc:pacman|rmpc:brew \
        |mpd-mpris:paru|mpd-mpris:yay|mpd-mpris:pacman)
        ;;
      *)
        log_err "Automatic installation of $cmd is not configured for ${PKG_MANAGER:-this system}; install it manually and rerun setup-music.sh"
        return 1
        ;;
    esac

    log "Installing $cmd ..."
    install_package "$cmd"
    if ! command -v "$cmd" >/dev/null 2>&1; then
      log_err "$cmd is still unavailable after installation; check the package manager output and PATH"
      return 1
    fi
    log_ok "[installed] $cmd"
  done
}

# 检查部署内容和现有实例后，创建运行目录并启用选定的用户服务
setup_music_services() {
  local with_mpris="$1"
  local config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
  local state_home="${XDG_STATE_HOME:-$HOME/.local/state}"
  local source_config="$SCRIPT_DIR/../.config/mpd/mpd.conf"
  local source_bridge="$SCRIPT_DIR/../.config/systemd/user/mpd-mpris.service.d/mpd-socket.conf"
  local target_config="$config_home/mpd/mpd.conf"
  local target_bridge="$config_home/systemd/user/mpd-mpris.service.d/mpd-socket.conf"
  local services=(mpd.service)

  if [ "$(uname -s)" != 'Linux' ]; then
    log_warn 'Automatic music service setup requires Linux/systemd; configure MPD manually on this platform'
    return
  fi

  local tool
  for tool in systemctl pgrep cmp mpd; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      log_err "$tool unavailable; configure service prerequisites manually (cmp is provided by diffutils)"
      return 1
    fi
  done

  if [ "$with_mpris" -eq 1 ]; then
    if ! command -v mpd-mpris >/dev/null 2>&1; then
      log_err 'mpd-mpris unavailable; rerun setup-music.sh to install music dependencies'
      return 1
    fi
    services+=(mpd-mpris.service)
  fi

  if [ ! -f "$source_config" ] || { [ "$with_mpris" -eq 1 ] && [ ! -f "$source_bridge" ]; }; then
    log_warn 'Music configs are missing from dotfiles; skipping service setup'
    return
  fi

  if [ ! -f "$target_config" ] || { [ "$with_mpris" -eq 1 ] && [ ! -f "$target_bridge" ]; }; then
    log_warn 'Music configs are not deployed; run setup-user.sh first, then rerun setup-music.sh with the same options'
    return
  fi

  if ! cmp -s "$source_config" "$target_config"; then
    log_warn 'MPD config differs from dotfiles; preserving it and skipping service setup'
    return
  fi
  if [ "$with_mpris" -eq 1 ] && ! cmp -s "$source_bridge" "$target_bridge"; then
    log_warn 'mpd-mpris config differs from dotfiles; preserving it and skipping service setup'
    return
  fi

  if pgrep -u "$(id -u)" -x mpd >/dev/null 2>&1 \
    || { [ "$with_mpris" -eq 1 ] && pgrep -u "$(id -u)" -x mpd-mpris >/dev/null 2>&1; } \
    || systemctl --user is-active --quiet "${services[@]}"; then
    log_warn 'MPD or selected bridge is already running; preserving the existing session and skipping service setup'
    return
  fi

  # MPD 配置固定使用这些 HOME 路径，不跟随 XDG_STATE_HOME
  mkdir -p "$HOME/Music" "$HOME/.config/mpd/playlists" "$HOME/.local/state/mpd"
  if ! cmp -s "$source_config" "$target_config" \
    || { [ "$with_mpris" -eq 1 ] && ! cmp -s "$source_bridge" "$target_bridge"; }; then
    log_warn 'Music config changed during setup; preserving it and skipping service setup'
    return
  fi

  if [ "$config_home" != "$HOME/.config" ] || [ "$state_home" != "$HOME/.local/state" ]; then
    log_warn 'MPD uses ~/.config and ~/.local/state; ensure the user service manager uses the same XDG_CONFIG_HOME'
  fi

  if ! systemctl --user daemon-reload || ! systemctl --user enable --now "${services[@]}"; then
    log_err "Could not start music services; inspect systemctl --user status ${services[*]}"
    return 1
  fi

  local service
  for service in "${services[@]}"; do
    if ! systemctl --user is-active --quiet "$service"; then
      log_err "$service is not active; inspect systemctl --user status $service"
      return 1
    fi
  done
  log_ok "Music user services enabled and running: ${services[*]}"
}

main() {
  init_colors
  local with_mpris=0
  local deps_only=0
  if [ "$(uname -s)" = 'Linux' ]; then
    with_mpris=1
  fi

  local arg
  for arg in "$@"; do
    case "$arg" in
      --deps-only) deps_only=1 ;;
      --mpris) ;; # 兼容旧入口：Linux 已默认包含桥接，其他平台仍不安装桥接
      -h|--help)
        printf 'Usage: bash %s [--deps-only]\n' "$0"
        printf 'Installs MPD/rmpc and, on Linux, mpd-mpris; initializes deployed user configs unless --deps-only.\n'
        return
        ;;
      *)
        log_err "Unknown option: $arg"
        return 1
        ;;
    esac
  done

  install_music_dependencies "$with_mpris"
  if [ "$deps_only" -eq 0 ]; then
    setup_music_services "$with_mpris"
  fi
}

main "$@"
