# AppImage 安装：ins <url-or-path.AppImage>

# 用法：_install_appimage [--no-sandbox] <url-or-localpath>
_install_appimage() {
  local no_sandbox=0
  local src

  while [[ "$1" == --* ]]; do
    case "$1" in
      --no-sandbox) no_sandbox=1; shift ;;
      *) log_err "unknown option: $1"; return 1 ;;
    esac
  done

  src="$1"
  [[ -z "$src" ]] && { echo "Usage: ins [--no-sandbox] <url-or-.AppImage>"; return 1; }

  local filename="${${src:t}%%[?#]*}"

  # 推断应用名：转小写，去掉 .appimage 后缀和版本号
  # cursor-0.44.0-x86_64.AppImage → cursor
  local app_name="${${filename:l}%.appimage}"
  app_name="${app_name%%-[0-9]*}"
  app_name="${app_name%%_[0-9]*}"
  [[ -z "$app_name" ]] && app_name="app"

  if is_tty; then
    echo "Detected app name: \033[1;33m${app_name}\033[0m  (edit and press Enter)"
    vared -p "App name: " app_name
  fi
  [[ -z "$app_name" ]] && { log_err "app name cannot be empty"; return 1; }

  local install_dir="$HOME/.local/bin"
  local dest="$install_dir/${app_name}.AppImage"
  mkdir -p "$install_dir"

  if [[ "$src" == http://* || "$src" == https://* ]]; then
    log "downloading ${app_name} ..."
    local tmp="/tmp/${filename:-${app_name}.AppImage}"
    download "$src" "$tmp" || return 1
    mv "$tmp" "$dest"
  else
    [[ -f "$src" ]] || { log_err "file not found: $src"; return 1; }
    cp "$src" "$dest"
  fi

  chmod +x "$dest"

  local desktop_dir="$HOME/.local/share/applications"
  mkdir -p "$desktop_dir"

  local exec_cmd="$dest %U"
  (( no_sandbox )) && exec_cmd="$dest --no-sandbox %U"

  local display_name="${(C)app_name}"

  cat > "$desktop_dir/${app_name}.desktop" << EOF
[Desktop Entry]
Name=${display_name}
Exec=${exec_cmd}
Icon=${app_name}
Type=Application
Categories=Utility;
StartupWMClass=${display_name}
EOF

  _pkg_refresh_desktop
  log_ok "${display_name} installed"
  log_dim "binary:   $dest"
  log_dim "launcher: $desktop_dir/${app_name}.desktop"
}
