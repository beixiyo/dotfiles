# ── Tarball uninstall ────────────────────────────────────
# 删除 ~/.local/share/<name> 下的手动安装目录，
# 同时清理 ~/.local/bin/ 下的可执行文件和 desktop entry

_uninstall_tarball() {
  local app_name="$1"
  [[ -z "$app_name" ]] && { echo "Usage: uns <app-name>"; return 1; }

  app_name="${app_name:l}"

  local install_dir="$HOME/.local/share/${app_name}"
  local bin_path="$HOME/.local/bin/${app_name}"
  local desktop_path="$HOME/.local/share/applications/${app_name}.desktop"
  local found=0

  [[ -d "$install_dir" ]] && { rm -rf "$install_dir"; log_dim "removed: $install_dir"; found=1; }
  [[ -L "$bin_path" || -f "$bin_path" ]] && { rm -f "$bin_path"; log_dim "removed: $bin_path"; found=1; }
  [[ -f "$desktop_path" ]] && { rm -f "$desktop_path"; log_dim "removed: $desktop_path"; found=1; }

  if (( ! found )); then
    log_err "app not found: $app_name"
    return 1
  fi

  _pkg_refresh_desktop
  log_ok "${(C)app_name} uninstalled"
}


# ── AppImage uninstall ────────────────────────────────────
# 清理 ~/.local/bin/<name>.AppImage 和对应 desktop entry

_uninstall_appimage() {
  local app_name="$1"
  [[ -z "$app_name" ]] && { echo "Usage: uns --appimage <app-name>"; return 1; }

  local raw_name="${app_name%.AppImage}"
  raw_name="${raw_name%.appimage}"

  app_name="${raw_name:l}"

  local bin_path="$HOME/.local/bin/${app_name}.AppImage"
  [[ ! -f "$bin_path" ]] && bin_path="$HOME/.local/bin/${raw_name}.AppImage"

  local desktop_path="$HOME/.local/share/applications/${app_name}.desktop"
  local found=0

  [[ -f "$bin_path" ]] && { rm -f "$bin_path"; log_dim "removed: $bin_path"; found=1; }
  [[ -f "$desktop_path" ]] && { rm -f "$desktop_path"; log_dim "removed: $desktop_path"; found=1; }

  if (( ! found )); then
    log_err "AppImage app not found: $app_name"
    return 1
  fi

  _pkg_refresh_desktop
  log_ok "${(C)app_name} AppImage uninstalled"
}


# ── Wine uninstall ────────────────────────────────────
# 清理 ~/.local/share/wine-apps/<name> 和对应 desktop entry

_uninstall_wine() {
  local app_name="$1"
  [[ -z "$app_name" ]] && { echo "Usage: uns --wine <app-name>"; return 1; }

  app_name="${app_name:l}"

  local install_dir="$HOME/.local/share/wine-apps/${app_name}"
  local desktop_path="$HOME/.local/share/applications/${app_name}.desktop"
  local found=0

  [[ -d "$install_dir" ]] && { rm -rf "$install_dir"; log_dim "removed: $install_dir"; found=1; }
  [[ -f "$desktop_path" ]] && { rm -f "$desktop_path"; log_dim "removed: $desktop_path"; found=1; }

  if (( ! found )); then
    log_err "Wine app not found: $app_name"
    return 1
  fi

  _pkg_refresh_desktop
  log_ok "${(C)app_name} Wine app uninstalled"
}


# ── Main ────────────────────────────────────
#
# 调用方式：
#   uns opencode         → 卸载 opencode（自动判断安装方式）
#   uns --appimage nvim  → 卸载 AppImage 版本 nvim
#   uns --wine wechat    → 卸载 Wine 版本 wechat
#   uns firefox thunderbird → 同时卸载多个（走系统包管理器）
#
# 探测顺序（仅限单包名）：
#   ① AppImage？→ 调用 _uninstall_appimage，命中则返回
#   ② Wine？    → 调用 _uninstall_wine，命中则返回
#   ③ 系统包管理器 → 跑 pacman / apt / dnf / brew 等
#   ④ Tarball  ← 只有 ③ 失败且 ~/.local/share/<name> 存在时才触发

uns() {
  local -A opts
  zmodload zsh/zutil 2>/dev/null
  zparseopts -D -A opts -help -appimage: -wine: || return 1

  if (( ${+opts[--help]} )); then
    echo "Usage: uns [--appimage <name> | --wine <name>] <pkg> [...]"
    return 0
  fi

  if (( ${+opts[--appimage]} && ${+opts[--wine]} )); then
    log_err "Cannot use --appimage and --wine together"
    return 1
  fi

  if (( ${+opts[--appimage]} )); then
    _uninstall_appimage "${opts[--appimage]}"
    return
  fi

  if (( ${+opts[--wine]} )); then
    _uninstall_wine "${opts[--wine]}"
    return
  fi

  if (( ! $# )); then
    echo "Usage: uns [--appimage <name> | --wine <name>] <pkg> [...]"
    return 1
  fi

  # 单包名 → 先试探 AppImage / Wine（根据文件/目录特征判断）
  local name raw
  if (( $# == 1 )); then
    name="${1:l}"
    name="${name%.appimage}"
    raw="${1%.AppImage}"
    raw="${raw%.appimage}"

    # ① AppImage: ~/.local/bin/下有 .AppImage 文件
    [[ -f "$HOME/.local/bin/${name}.AppImage" || -f "$HOME/.local/bin/${raw}.AppImage" ]] \
      && _uninstall_appimage "$1" && return

    # ② Wine: ~/.local/share/wine-apps/下有目录
    [[ -d "$HOME/.local/share/wine-apps/${name}" ]] \
      && _uninstall_wine "$1" && return
  fi

  # ③ 系统包管理器（支持多包名，macOS 走 brew，Linux 自动识别）
  local cmd

  if is_mac; then
    if has brew; then
      cmd=(brew uninstall)
    else
      log_err "Homebrew not installed on macOS"
      return 1
    fi
  elif _pkg_ask_brew; then
    cmd=(brew uninstall)
  fi

  if [[ -z $cmd ]]; then
    local result
    result=$(_pkg_cmd remove) || return 1
    cmd=(${=result})
  fi

  local pm_exit=0
  "${cmd[@]}" "$@" || pm_exit=$?

  # ④ Tarball: 仅当系统包管理器失败（无此包）且为单包名时，
  #    检查 ~/.local/share/<name>/ 目录是否存在，存在则按 tarball 清理
  if (( pm_exit != 0 && $# == 1 )) && [[ -d "$HOME/.local/share/${name}" ]]; then
    _uninstall_tarball "$1"
  fi
}
