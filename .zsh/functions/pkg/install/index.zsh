# 通用安装：ins <packages...>
# 支持 AppImage（URL/路径）、Wine .exe、deb / rpm、tar 包和 macOS .dmg，其余走系统包管理器

() {
  local dir="${${(%):-%x}:A:h}"
  source "$dir/appimage.zsh"
  source "$dir/wine.zsh"
  source "$dir/extract.zsh"
  source "$dir/tarball.zsh"
  source "$dir/dmg.zsh"
}


# 通用安装入口：按扩展名分发到 AppImage / deb / rpm / tar 包 / dmg / Wine exe，其余走系统包管理器
ins() {
  if (( ! $# )); then
    echo "Usage: ins <pkg> [...]"
    echo "       ins [--no-sandbox] <url-or-path.AppImage>"
    echo "       ins <url-or-path.deb>"
    echo "       ins <url-or-path.rpm>"
    echo "       ins <url-or-path.tar.gz|.tar.xz|.tgz>"
    echo "       ins <url-or-path.dmg>       # macOS"
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
    *.dmg)
      _install_dmg "$first_non_flag" ;;
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
