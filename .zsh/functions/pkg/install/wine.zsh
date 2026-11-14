# Wine exe 安装：ins <path/to/app.exe>

_install_wine_exe() {
  local src="$1"
  [[ -z "$src" ]] && { echo "Usage: ins <path/to/app.exe> or ins <url.exe>"; return 1; }

  require wine || return 1

  local filename="${${src:t}%%[?#]*}"

  if [[ "$src" == http://* || "$src" == https://* ]]; then
    local tmp="/tmp/$filename"
    log "downloading $filename ..."
    download "$src" "$tmp" || return 1
    src="$tmp"
  fi

  [[ -f "$src" ]] || { log_err "file not found: $src"; return 1; }

  local app_name="${${filename:l}%.exe}"
  app_name="${app_name%%-[0-9]*}"
  app_name="${app_name%%_[0-9]*}"
  app_name="${app_name%%_x64}"
  app_name="${app_name%%_x86}"
  [[ -z "$app_name" ]] && app_name="app"

  if is_tty; then
    echo "Detected app name: \033[1;33m${app_name}\033[0m  (edit and press Enter)"
    vared -p "App name: " app_name
  fi
  [[ -z "$app_name" ]] && { log_err "app name cannot be empty"; return 1; }

  local install_dir="$HOME/.local/share/wine-apps/${app_name}"
  local src_dir="${src:h}"
  local exe_name="${src:t}"

  mkdir -p "$install_dir"

  local copy_dir=0

  if ls "$src_dir"/*.dll &>/dev/null; then
    copy_dir=1
    log "DLLs detected in source directory, copying entire folder"
  fi

  if is_tty; then
    if (( copy_dir )); then
      confirm "Copy entire directory ${src_dir}?" && copy_dir=1 || copy_dir=0
    else
      confirm "Copy only the exe? (n = copy entire directory)" || copy_dir=1
    fi
  fi

  if (( copy_dir )); then
    log "copying directory: $src_dir -> $install_dir"
    cp -r "$src_dir"/* "$install_dir/"
  else
    cp "$src" "$install_dir/"
  fi

  local exe_path="$install_dir/$exe_name"

  local icon="wine"
  local icon_file
  for icon_file in "$install_dir"/**/*.(png|ico|svg)(N[1]); do
    if [[ -n "$icon_file" ]]; then
      icon="$icon_file"
      break
    fi
  done

  local desktop_dir="$HOME/.local/share/applications"
  mkdir -p "$desktop_dir"

  local display_name="${(C)app_name}"

  cat > "$desktop_dir/${app_name}.desktop" << EOF
[Desktop Entry]
Name=${display_name}
Comment=Windows application via Wine
Exec=wine ${exe_path}
Icon=${icon}
Type=Application
Categories=Utility;
StartupWMClass=${app_name}.exe
EOF

  _pkg_refresh_desktop
  log_ok "${display_name} installed (Wine)"
  log_dim "directory: $install_dir"
  log_dim "launcher:  $desktop_dir/${app_name}.desktop"
  log_dim "run:       wine $exe_path"
}
