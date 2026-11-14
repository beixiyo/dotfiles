# macOS dmg 安装：ins <url-or-path.dmg>

# 把已挂载 dmg 里的内容装好：.app 复制到应用目录，.pkg 交给 installer
# 用法：_install_dmg_payload <mountpoint>
_install_dmg_payload() {
  local mnt="$1"
  # 应用目录默认 /Applications（macOS 固定位置），可用 _INS_APP_DIR 覆盖（如 ~/Applications 或测试目录）
  local app_dir="${_INS_APP_DIR:-/Applications}"
  # (/) 只取真实目录，排除指向镜像外部的符号链接
  local -a apps=("$mnt"/*.app(N/))
  local -a pkgs=("$mnt"/*.pkg(N))

  if (( ${#apps} )); then
    local app="${apps[1]}"

    if (( ${#apps} > 1 )) && is_tty; then
      log "apps found:"
      local i
      for i in {1..${#apps}}; do
        echo "  [$i] ${apps[$i]:t}"
      done
      local choice
      vared -p "Install which [1]: " choice
      choice="${choice:-1}"
      [[ "$choice" == <-> ]] && (( choice >= 1 && choice <= ${#apps} )) || { log_err "invalid selection"; return 1; }
      app="${apps[$choice]}"
    fi

    local name="${app:t}"
    # 后面要 rm -rf 目标路径，名字异常时直接拒绝
    [[ "$name" == ?*.app && -d "$app_dir" ]] || { log_err "invalid install target: $app_dir/$name"; return 1; }

    local dest="$app_dir/$name"
    local stage="$app_dir/.$name.ins-$$"

    if [[ -e "$dest" || -L "$dest" ]]; then
      if is_tty; then
        confirm "$dest already exists, overwrite?" || { log_dim "skipped"; return 0; }
      else
        log_err "already installed: $dest"
        return 1
      fi
    fi

    # 目录不可写，或已装版本属于别的用户（如 root 安装）时走 sudo
    local -a as_root=()
    [[ -w "$app_dir" && ( ! -e "$dest" || -O "$dest" ) ]] || as_root=(sudo)

    # 先完整复制到同目录的暂存位置，成功后再替换，复制失败或中断都不破坏已装版本
    log "copying $name to $app_dir ..."
    {
      $as_root ditto "$app" "$stage" || { log_err "failed to copy $name"; return 1; }

      if [[ -e "$dest" || -L "$dest" ]]; then
        $as_root rm -rf "$dest" || { log_err "failed to remove existing $dest"; return 1; }
      fi

      $as_root mv "$stage" "$dest" || { log_err "failed to move $name into $app_dir"; return 1; }
    } always {
      [[ -e "$stage" ]] && $as_root rm -rf "$stage"
    }

    log_ok "${name%.app} installed"
    log_dim "app: $dest"
    return 0
  fi

  if (( ${#pkgs} )); then
    log "running installer for ${pkgs[1]:t} ..."
    sudo installer -pkg "${pkgs[1]}" -target / && log_ok "${pkgs[1]:t} installed"
    return
  fi

  log_err "no .app or .pkg found in the disk image"
  return 1
}

# 挂载 dmg（URL 先下载），装好里面的 .app / .pkg，任何退出路径都会卸载镜像并清理临时文件
# 用法：_install_dmg <url-or-localpath>
_install_dmg() {
  local src="$1"
  [[ -z "$src" ]] && { echo "Usage: ins <url-or-path.dmg>"; return 1; }
  is_mac || { log_err "dmg is only supported on macOS"; return 1; }

  local filename="${${src:t}%%[?#]*}"
  local tmpdir="" mnt="" err=""
  local -i attached=0

  # always 块保证任何失败路径（含 Ctrl-C）都卸载镜像并清理临时目录
  {
    if [[ "$src" == http://* || "$src" == https://* ]]; then
      tmpdir="$(mktemp -d)" || return 1
      log "downloading $filename ..."
      download "$src" "$tmpdir/$filename" || return 1
      src="$tmpdir/$filename"
    fi

    [[ -f "$src" ]] || { log_err "file not found: $src"; return 1; }
    src="${src:a}"

    # 加密镜像会让 hdiutil 一直等口令（stdin 已被下面的 Y 占用），提前拒绝
    if [[ "$(hdiutil isencrypted "$src" 2>/dev/null)" == *YES* ]]; then
      log_err "encrypted disk image is not supported, mount it manually: $filename"
      return 1
    fi

    mnt="$(mktemp -d)" || return 1

    # 带许可协议的 dmg 需要应答 Y 才能挂载
    if ! err="$(echo Y | hdiutil attach "$src" -nobrowse -readonly -mountpoint "$mnt" 2>&1 >/dev/null)"; then
      log_err "failed to mount: $filename"
      [[ -n "$err" ]] && log_dim "$err"
      return 1
    fi
    attached=1

    _install_dmg_payload "$mnt"
  } always {
    if (( attached )); then
      hdiutil detach "$mnt" -quiet 2>/dev/null || hdiutil detach "$mnt" -force -quiet 2>/dev/null
    fi
    [[ -n "$mnt" ]] && rmdir "$mnt" 2>/dev/null
    [[ -n "$tmpdir" ]] && rm -rf "$tmpdir"
  }
}
