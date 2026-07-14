# Universal install: ins <packages...>
# Supports AppImage URLs/paths and Wine .exe files

# ── AppImage install ────────────────────────────────────

# Usage: _install_appimage [--no-sandbox] <url-or-localpath>
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

  # Infer app name: lowercase, strip .appimage suffix and version
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


# ── Wine exe install ────────────────────────────────────

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


# ── Package extract (deb/rpm on unsupported distro) ────────────

_install_pkg_extract() {
  local src="$1" ext="$2"

  require bsdtar || return 1

  local filename="${${src:t}%%[?#]*}"
  local app_name="${filename:l}"
  app_name="${app_name%.${ext}}"
  app_name="${app_name%%-[0-9]*}"
  app_name="${app_name%%_[0-9]*}"
  app_name="${app_name%%_amd64}"
  app_name="${app_name%%_x86_64}"
  app_name="${app_name%%.x86_64}"
  app_name="${app_name%%_arm64}"
  app_name="${app_name%%_aarch64}"
  app_name="${app_name%%.aarch64}"
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

  log "extracting ${ext} package ..."
  local tmp_dir=$(mktemp -d)

  if [[ "$ext" == "deb" ]]; then
    local ar_dir="$tmp_dir/ar"
    mkdir -p "$ar_dir"
    bsdtar -xf "$src" -C "$ar_dir" 2>/dev/null || { log_err "failed to extract deb"; rm -rf "$tmp_dir"; return 1; }

    local data_tar
    for data_tar in "$ar_dir"/data.tar.*(N); do break; done
    [[ -f "$data_tar" ]] || { log_err "no data archive in deb"; rm -rf "$tmp_dir"; return 1; }

    mkdir -p "$tmp_dir/root"
    bsdtar -xf "$data_tar" -C "$tmp_dir/root" || { log_err "data extraction failed"; rm -rf "$tmp_dir"; return 1; }
  else
    mkdir -p "$tmp_dir/root"
    bsdtar -xf "$src" -C "$tmp_dir/root" 2>/dev/null || { log_err "failed to extract rpm"; rm -rf "$tmp_dir"; return 1; }
  fi

  mv "$tmp_dir/root" "$install_dir"
  rm -rf "$tmp_dir"

  # Find executables (skip .so files)
  local -a bins=()
  local f
  while IFS= read -r f; do
    [[ -n "$f" && "${f:t}" != *.so* ]] && bins+=("$f")
  done < <(find "$install_dir" -type f -executable \( -path "*/opt/*" -o -path "*/bin/*" \) 2>/dev/null)

  local main_bin
  for f in "${bins[@]}"; do
    [[ "${f:t}" == "$app_name" ]] && { main_bin="$f"; break; }
  done
  if [[ -z "$main_bin" ]]; then
    for f in "${bins[@]}"; do
      [[ "${f:t}" == *"$app_name"* ]] && { main_bin="$f"; break; }
    done
  fi

  if [[ -z "$main_bin" ]]; then
    if (( ${#bins} == 1 )); then
      main_bin="${bins[1]}"
    elif (( ${#bins} > 1 )) && is_tty; then
      log "executables found:"
      local i
      for i in {1..${#bins}}; do
        echo "  [$i] ${bins[$i]#$install_dir/}"
      done
      local choice
      vared -p "Main binary [1]: " choice
      choice="${choice:-1}"
      main_bin="${bins[$choice]}"
    elif (( ${#bins} > 0 )); then
      main_bin="${bins[1]}"
    fi
  fi

  local bin_dir="$HOME/.local/bin"
  mkdir -p "$bin_dir"

  if [[ -n "$main_bin" && -f "$main_bin" ]]; then
    ln -sf "$main_bin" "$bin_dir/${app_name}"
  fi

  # Install .desktop file
  local desktop_dir="$HOME/.local/share/applications"
  mkdir -p "$desktop_dir"
  local desktop_src desktop_installed=0

  for desktop_src in "$install_dir"/usr/share/applications/*.desktop(N); do
    sed -e "s|^Exec=/|Exec=${install_dir}/|" \
        -e "s|^Icon=/|Icon=${install_dir}/|" \
        "$desktop_src" > "$desktop_dir/${app_name}.desktop"
    if [[ -n "$main_bin" ]]; then
      sed -i "/^Exec=[^/]/s|^Exec=[^ ]*|Exec=${main_bin}|" "$desktop_dir/${app_name}.desktop"
    fi
    desktop_installed=1
    break
  done

  if (( ! desktop_installed )) && [[ -n "$main_bin" ]]; then
    local display_name="${(C)app_name}"
    local icon="$app_name"
    local icon_file
    for icon_file in "$install_dir"/**/*.(png|svg|ico)(N[1]); do
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
  fi

  _pkg_refresh_desktop
  log_ok "${(C)app_name} installed (extracted from ${ext})"
  log_dim "directory: $install_dir"
  [[ -n "$main_bin" ]] && log_dim "binary:   $bin_dir/${app_name} -> $main_bin"
  log_dim "launcher: $desktop_dir/${app_name}.desktop"
}


# ── Deb install ────────────────────────────────────

_install_deb() {
  local src="$1"
  [[ -z "$src" ]] && { echo "Usage: ins <url-or-path.deb>"; return 1; }

  local filename="${${src:t}%%[?#]*}"

  if [[ "$src" == http://* || "$src" == https://* ]]; then
    local tmp="/tmp/$filename"
    log "downloading $filename ..."
    download "$src" "$tmp" || return 1
    src="$tmp"
  fi

  [[ -f "$src" ]] || { log_err "file not found: $src"; return 1; }
  src="${src:a}"

  if has apt; then
    sudo apt install -y "$src"
  elif has dpkg; then
    sudo dpkg -i "$src"
    sudo apt-get install -f -y 2>/dev/null
  else
    _install_pkg_extract "$src" deb
  fi
}


# ── RPM install ────────────────────────────────────

_install_rpm() {
  local src="$1"
  [[ -z "$src" ]] && { echo "Usage: ins <url-or-path.rpm>"; return 1; }

  local filename="${${src:t}%%[?#]*}"

  if [[ "$src" == http://* || "$src" == https://* ]]; then
    local tmp="/tmp/$filename"
    log "downloading $filename ..."
    download "$src" "$tmp" || return 1
    src="$tmp"
  fi

  [[ -f "$src" ]] || { log_err "file not found: $src"; return 1; }
  src="${src:a}"

  if has dnf; then
    sudo dnf install -y "$src"
  elif has zypper; then
    sudo zypper install -y "$src"
  elif has rpm; then
    sudo rpm -i "$src"
  else
    _install_pkg_extract "$src" rpm
  fi
}


# ── Tarball install ────────────────────────────────────

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

  # Find executable candidates (top-level + bin/, exclude .so)
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


# ── Main ────────────────────────────────────

ins() {
  if (( ! $# )); then
    echo "Usage: ins <pkg> [...]"
    echo "       ins [--no-sandbox] <url-or-path.AppImage>"
    echo "       ins <url-or-path.deb>"
    echo "       ins <url-or-path.rpm>"
    echo "       ins <url-or-path.tar.gz|.tar.xz|.tgz>"
    echo "       ins <path/to/app.exe>       # Wine"
    return 1
  fi

  local first_non_flag
  for _arg in "$@"; do
    [[ "$_arg" == --* ]] && continue
    first_non_flag="$_arg"
    break
  done

  local clean="${${first_non_flag:t}%%[?#]*}"
  local lower="${clean:l}"

  case "$lower" in
    *.exe)
      _install_wine_exe "$first_non_flag" ;;
    *.deb)
      _install_deb "$first_non_flag" ;;
    *.rpm)
      _install_rpm "$first_non_flag" ;;
    *.tar.gz|*.tar.xz|*.tar.bz2|*.tgz)
      _install_tarball "$first_non_flag" ;;
    *.appimage)
      _install_appimage "$@" ;;
    *)
      if [[ "$first_non_flag" == http://* || "$first_non_flag" == https://* ]]; then
        _install_appimage "$@"
        return
      fi

      local cmd

      if is_mac; then
        if has brew; then
          cmd=(brew install)
        else
          log_err "Homebrew not installed on macOS"
          return 1
        fi
      elif _pkg_ask_brew; then
        cmd=(brew install)
      fi

      if [[ -z $cmd ]]; then
        local result
        result=$(_pkg_cmd install) || return 1
        cmd=(${=result})
      fi

      "${cmd[@]}" "$@"
      ;;
  esac
}
