# Universal update: update [packages...]
# No args = full system upgrade

update() {
  local cmd

  if is_mac; then
    if has brew; then
      if (( $# )); then
        cmd=(brew upgrade)
      else
        brew update && brew upgrade
        return
      fi
    else
      log_err "Homebrew not installed on macOS"
      return 1
    fi
  fi

  if [[ -z $cmd ]] && ! is_mac && _pkg_ask_brew; then
    if (( $# )); then
      cmd=(brew upgrade)
    else
      brew update && brew upgrade
      return
    fi
  fi

  if [[ -z $cmd ]]; then
    local family=$(_pkg_distro_family)

    if (( ! $# )); then
      case "$family" in
        arch)
          local result
          result=$(_pkg_cmd sysupgrade) || return 1
          ${=result}
          return
          ;;
        debian)
          sudo apt update && sudo apt upgrade -y
          return
          ;;
        suse)
          sudo zypper refresh && sudo zypper update -y
          return
          ;;
        alpine)
          sudo apk update && sudo apk upgrade
          return
          ;;
        fedora)
          sudo dnf upgrade -y
          return
          ;;
        *)
          log_err "unrecognized distro, no pacman/apt/dnf/zypper/apk found"
          return 1
          ;;
      esac
    fi

    local result
    result=$(_pkg_cmd upgrade) || return 1
    cmd=(${=result})

    if [[ $family == arch ]]; then
      log_warn "⚠ partial upgrade may break shared library deps"
      log_dim "if you get .so errors, fix with full upgrade: paru -Syu"
    fi
  fi

  "${cmd[@]}" "$@"
}
