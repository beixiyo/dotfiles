# deb / rpm 安装（含不支持这两种包的发行版上的解包兜底）

# ── 解包安装（不支持 deb/rpm 的发行版） ────────────

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

  # 查找可执行文件（跳过 .so）
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

  # 安装 .desktop 文件
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


# ── Deb 安装 ────────────────────────────────────

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


# ── RPM 安装 ────────────────────────────────────

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
