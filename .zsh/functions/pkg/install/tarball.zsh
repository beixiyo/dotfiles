# tar 包安装：ins <url-or-path.tar.gz|.tar.xz|.tgz>

_install_tarball() {
  local src="$1"
  [[ -z "$src" ]] && { echo "Usage: ins <url-or-path.tar.gz>"; return 1; }

  local filename="${${src:t}%%[?#]*}"

  if [[ "$src" == http://* || "$src" == https://* ]]; then
    local tmp="/tmp/$filename"
    log "downloading $filename ..."
    download "$src" "$tmp" || return 1
    src="$tmp"
  fi

  [[ -f "$src" ]] || { log_err "file not found: $src"; return 1; }

  local app_name="${filename:l}"
  app_name="${app_name%.tar.gz}"
  app_name="${app_name%.tar.xz}"
  app_name="${app_name%.tar.bz2}"
  app_name="${app_name%.tgz}"
  app_name="${app_name%%-[0-9]*}"
  app_name="${app_name%%_[0-9]*}"
  app_name="${app_name%%-linux*}"
  app_name="${app_name%%_linux*}"
  app_name="${app_name%%-x86*}"
  app_name="${app_name%%-x64*}"
  app_name="${app_name%%-amd64*}"
  app_name="${app_name%%-arm64*}"
  app_name="${app_name%%-aarch64*}"
  [[ -z "$app_name" ]] && app_name="app"

  if is_tty; then
    echo "Detected app name: \033[1;33m${app_name}\033[0m  (edit and press Enter)"
    vared -p "App name: " app_name
  fi
  [[ -z "$app_name" ]] && { log_err "app name cannot be empty"; return 1; }

  local install_dir="$HOME/.local/share/${app_name}"

  if [[ -d "$install_dir" ]]; then
    if is_tty; then
      confirm "${install_dir} already exists, overwrite?" || return 0
    fi
    rm -rf "$install_dir"
  fi

  local tmp_dir=$(mktemp -d)
  log "extracting ..."
  tar xf "$src" -C "$tmp_dir" || { log_err "extraction failed"; rm -rf "$tmp_dir"; return 1; }

  local entries=("$tmp_dir"/*(N))
  if (( ${#entries} == 1 )) && [[ -d "${entries[1]}" ]]; then
    mv "${entries[1]}" "$install_dir"
  else
    mkdir -p "$install_dir"
    mv "$tmp_dir"/* "$install_dir/"
  fi
  rm -rf "$tmp_dir" 2>/dev/null

  # 查找可执行候选（顶层 + bin/，排除 .so）
  local -a bins
  local f
  for f in "$install_dir"/*(N*) "$install_dir"/bin/*(N*); do
    [[ -f "$f" && "${f:t}" != *.so* ]] && bins+=("$f")
  done

  if (( ${#bins} == 0 )); then
    log_err "no executable found in $install_dir"
    log_dim "directory: $install_dir"
    return 0
  fi

  local main_bin
  for f in "${bins[@]}"; do
    [[ "${f:t}" == "$app_name" ]] && { main_bin="$f"; break; }
  done

  if [[ -z "$main_bin" ]]; then
    if (( ${#bins} == 1 )); then
      main_bin="${bins[1]}"
    elif is_tty; then
      log "executables found:"
      local i
      for i in {1..${#bins}}; do
        echo "  [$i] ${bins[$i]#$install_dir/}"
      done
      local choice
      vared -p "Main binary [1]: " choice
      choice="${choice:-1}"
      main_bin="${bins[$choice]}"
    else
      main_bin="${bins[1]}"
    fi
  fi

  [[ -z "$main_bin" || ! -f "$main_bin" ]] && { log_err "invalid selection"; return 1; }

  local bin_dir="$HOME/.local/bin"
  mkdir -p "$bin_dir"
  ln -sf "$main_bin" "$bin_dir/${app_name}"

  local desktop_dir="$HOME/.local/share/applications"
  mkdir -p "$desktop_dir"
  local display_name="${(C)app_name}"

  local icon="$app_name"
  local icon_file
  for icon_file in "$install_dir"/**/*.(png|ico|svg)(N[1]); do
    [[ -n "$icon_file" ]] && { icon="$icon_file"; break; }
  done

  cat > "$desktop_dir/${app_name}.desktop" << EOF
[Desktop Entry]
Name=${display_name}
Exec=${main_bin} %U
Icon=${icon}
Type=Application
Categories=Utility;
StartupWMClass=${display_name}
EOF

  _pkg_refresh_desktop
  log_ok "${display_name} installed"
  log_dim "directory: $install_dir"
  log_dim "binary:    $bin_dir/${app_name} -> $main_bin"
  log_dim "launcher:  $desktop_dir/${app_name}.desktop"
}
