# Shared helpers for the pkg module

# ── Arch AUR helper ────────────────────────────────────

_pkg_arch_helper() {
  if has paru; then echo paru
  elif has yay; then echo yay
  else echo pacman
  fi
}


# ── Distro family detection ────────────────────────────────────

# Outputs: arch / debian / fedora / suse / alpine / unknown
_pkg_distro_family() {
  if [[ -r /etc/os-release ]]; then
    local id id_like
    id=$(grep -E '^ID=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')
    id_like=$(grep -E '^ID_LIKE=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')

    case "$id $id_like" in
      *arch*)   echo arch ;;
      *debian*|*ubuntu*|*mint*|*pop*) echo debian ;;
      *fedora*|*rhel*|*centos*)       echo fedora ;;
      *opensuse*|*suse*)              echo suse ;;
      *alpine*)                       echo alpine ;;
      *)
        if has pacman; then echo arch
        elif has apt;    then echo debian
        elif has dnf;    then echo fedora
        elif has zypper; then echo suse
        elif has apk;    then echo alpine
        else echo unknown
        fi
        ;;
    esac
  else
    echo unknown
  fi
}


# ── Package manager command builder ────────────────────────────────────

# Usage: _pkg_cmd install|remove|upgrade
# Outputs the command string; caller splits with: cmd=(${=result})
_pkg_cmd() {
  local action="$1"
  local family=$(_pkg_distro_family)

  case "$family" in
    arch)
      local helper=$(_pkg_arch_helper)
      case "$action" in
        install)  echo "$helper -S --needed" ;;
        remove)   echo "$helper -Rns" ;;
        upgrade)  echo "$helper -S --needed" ;;
        sysupgrade) echo "$helper -Syu" ;;
      esac
      ;;
    debian)
      case "$action" in
        install) echo "sudo apt install -y" ;;
        remove)  echo "sudo apt remove -y" ;;
        upgrade) echo "sudo apt install --only-upgrade -y" ;;
      esac
      ;;
    fedora)
      case "$action" in
        install) echo "sudo dnf install -y" ;;
        remove)  echo "sudo dnf remove -y" ;;
        upgrade) echo "sudo dnf upgrade -y" ;;
      esac
      ;;
    suse)
      case "$action" in
        install) echo "sudo zypper install -y" ;;
        remove)  echo "sudo zypper remove -y" ;;
        upgrade) echo "sudo zypper update -y" ;;
      esac
      ;;
    alpine)
      case "$action" in
        install) echo "sudo apk add" ;;
        remove)  echo "sudo apk del" ;;
        upgrade) echo "sudo apk upgrade" ;;
      esac
      ;;
    *)
      log_err "unrecognized distro, no pacman/apt/dnf/zypper/apk found"
      return 1
      ;;
  esac
}


# ── Desktop database refresh ────────────────────────────────────

_pkg_refresh_desktop() {
  has update-desktop-database && \
    update-desktop-database "$HOME/.local/share/applications" 2>/dev/null
  has kbuildsycoca6 && \
    kbuildsycoca6 2>/dev/null
}


# ── Brew prompt ────────────────────────────────────

# On non-macOS with brew available, ask whether to use brew. Returns 0 = yes.
_pkg_ask_brew() {
  has brew || return 1
  is_mac && return 0
  confirm "Use Homebrew?"
}
