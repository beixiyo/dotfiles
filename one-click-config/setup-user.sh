#!/usr/bin/env bash
# 一键为目标用户部署 dotfiles 配置（zsh + starship）
#
# 用法：
#   ./setup-user.sh              # 交互询问是否创建用户
#   ./setup-user.sh alice        # 指定用户
#   ./setup-user.sh alice bob    # 批量处理多个用户
# 说明：
#   - 若脚本在 dotfiles 仓库内运行，直接使用本地仓库作为源（不 clone）
#   - 新用户会交互执行 passwd 设置密码

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
for lib_file in common packages sudoers download repos; do
  # shellcheck disable=SC1090 # 路径由固定的 lib_file 列表组成
  source "$LIB_DIR/${lib_file}.sh"
done

DOTFILES_REPO_URL='https://github.com/beixiyo/dotfiles.git'
STARSHIP_PRESET_GRUVBOX_RAINBOW_URL='https://starship.rs/presets/toml/gruvbox-rainbow.toml'
DOTFILES_LOCAL_SOURCE=""  # 若脚本在 dotfiles 仓库内，自动设为仓库根目录

run_as_user() {
  local user="$1"
  local cmd="$2"
  if [ "$(id -un)" = "$user" ]; then
    bash -lc "$cmd"
    return
  fi
  if command -v runuser >/dev/null 2>&1; then
    runuser -u "$user" -- bash -lc "$cmd"
  else
    su - "$user" -c "$cmd"
  fi
}

ensure_user_shell() {
  local user="$1"
  local zsh_path
  zsh_path="$(command -v zsh 2>/dev/null || true)"
  if [ -z "$zsh_path" ]; then
    log_warn 'zsh not found; skipping chsh (install zsh and set login shell later)'
    return 0
  fi

  if chsh -s "$zsh_path" "$user" 2>/dev/null; then
    log_ok "Default shell for $user set to zsh"
  else
    log_warn "chsh failed for $user (zsh may be missing from /etc/shells)"
  fi
}

# 需要链接到 /root 的配置项（源存在才链接，不存在则跳过）
LINK_ITEMS=(
  # 源（相对于用户家目录）     目标（绝对路径）            [mkdir=部署时预创建]
  '.config/nvim                 /root/.config/nvim'
  '.config/starship.toml        /root/.config/starship.toml'
  '.config/btop                 /root/.config/btop'
  '.config/yazi                 /root/.config/yazi'
  '.local/share/nvim            /root/.local/share/nvim      mkdir'
  '.local/state/nvim            /root/.local/state/nvim      mkdir'
  '.config/mise                 /root/.config/mise'
  '.local/share/mise            /root/.local/share/mise      mkdir'
  '.local/state/mise            /root/.local/state/mise      mkdir'
  '.cache/mise                  /root/.cache/mise            mkdir'
  '.zsh                         /root/.zsh'
  '.zshrc                       /root/.zshrc'
  '.vimrc                       /root/.vimrc'
  '.vim                         /root/.vim'
)

link_user_config_to_root() {
  local user_home="$1"
  local rel_src dst flag src
  local owner group
  owner="$(stat -c '%U' "$user_home" 2>/dev/null || stat -f '%Su' "$user_home")"
  group="$(stat -c '%G' "$user_home" 2>/dev/null || stat -f '%Sg' "$user_home")"

  for entry in "${LINK_ITEMS[@]}"; do
    read -r rel_src dst flag <<< "$entry"
    src="$user_home/$rel_src"

    if [ ! -e "$src" ]; then
      if [ "$flag" = 'mkdir' ]; then
        mkdir -p "$src"
        chown "$owner:$group" "$src"
      else
        continue
      fi
    fi

    mkdir -p "$(dirname "$dst")"
    # 目标已是真实文件/目录（非软链）时不强制覆盖：提醒用户手动处理
    # 否则 ln -sfn 会删掉 root 已有真实文件造成不可逆数据丢失（文件型目标），
    # 或把链接错建到真实目录内部（dst/<name>）导致 /root 仍用旧配置、共享失效（目录型目标）
    if [ -e "$dst" ] && [ ! -L "$dst" ]; then
      log_warn "Skip $dst: a real file/dir already exists; not overwriting. Back it up & remove manually, then re-run to symlink it to $src"
      continue
    fi
    ln -sfn "$src" "$dst"
    log_ok "Linked $dst -> $src"
  done

  # root 通过符号链接共享用户的数据目录时，首次 nvim 会以 root 身份创建子目录/文件
  # （如 parser-info/、queries/ 等），导致用户后续写入失败。递归修正所有 mkdir 条目的属主
  for entry in "${LINK_ITEMS[@]}"; do
    read -r rel_src _ flag <<< "$entry"
    [ "$flag" = 'mkdir' ] || continue
    src="$user_home/$rel_src"
    [ -d "$src" ] && chown -R "$owner:$group" "$src"
  done

  # mise 信任用户配置目录（避免切换用户后报 untrusted 错误）
  if command -v mise >/dev/null 2>&1 && [ -d "$user_home/.config/mise" ]; then
    mise trust "$user_home" 2>/dev/null && \
      log_ok "mise trust: $user_home" || true
  fi
}

setup_user() {
  local user="$1"
  local sudo_grp="$2"
  # 用固定合法函数名做执行器，避免把 $user 拼进函数名；用户处理是串行的，每次 setup_user 重定义即可
  # 用户名经 printf %q 转义后再注入函数体，杜绝畸形/含元字符用户名破坏 eval 定义
  local executor='_dotfiles_executor'

  eval "${executor}() { run_as_user $(printf '%q' "$user") \"\$1\"; }"

  log "=== 4. Create or verify target user: $user ==="
  if id "$user" >/dev/null 2>&1; then
    log "User $user already exists; skipping passwd"
  else
    if [ "$(uname -s)" = 'Darwin' ]; then
      log_err 'Automatic user creation is not supported on macOS'
      log_err "Create $user in System Settings, then rerun this script"
      exit 1
    fi

    if ! command -v useradd >/dev/null 2>&1; then
      log_err "useradd not found; create $user manually, then rerun this script"
      exit 1
    fi

    local default_shell
    default_shell="$(get_default_shell)"
    log "Creating user $user (login shell: $default_shell)"
    useradd -m -s "$default_shell" "$user"
    log "Set login password for $user (passwd)"
    passwd "$user"
  fi
  ensure_user_in_group "$user" "$sudo_grp" 1

  local target_home
  target_home="$(get_user_home "$user")"
  if [ -z "$target_home" ] || [ ! -d "$target_home" ]; then
    log_err "Cannot resolve home directory for $user"
    exit 1
  fi

  log "=== 5. Deploy dotfiles to $user home ==="
  deploy_dotfiles "$DOTFILES_REPO_URL" "$target_home" "$executor" "$DOTFILES_LOCAL_SOURCE"

  if [ ! -f "$target_home/.config/starship.toml" ]; then
    log "=== 5b. Download Starship preset (gruvbox-rainbow) ==="
    download_to_file "$STARSHIP_PRESET_GRUVBOX_RAINBOW_URL" \
      "$target_home/.config/starship.toml" "$executor"
  fi

  log "=== 6. Set default shell for $user ==="
  ensure_user_shell "$user"
  log_ok "Done: dotfiles deployed for $user with sudo membership"
}

setup_current_user() {
  local user="$1"
  local target_home
  local executor=''
  target_home="$(get_user_home "$user")"
  if [ -z "$target_home" ] || [ ! -d "$target_home" ]; then
    log_err "Cannot resolve home directory for $user"
    exit 1
  fi

  if [ "$(id -un)" != "$user" ]; then
    executor='_dotfiles_current_user_executor'
    eval "${executor}() { run_as_user $(printf '%q' "$user") \"\$1\"; }"
  fi

  log "=== Deploy dotfiles to current user: $user ==="
  deploy_dotfiles "$DOTFILES_REPO_URL" "$target_home" "$executor" "$DOTFILES_LOCAL_SOURCE"

  if [ ! -f "$target_home/.config/starship.toml" ]; then
    download_to_file "$STARSHIP_PRESET_GRUVBOX_RAINBOW_URL" \
      "$target_home/.config/starship.toml" "$executor"
  fi

  ensure_user_shell "$user"
  log_ok "Done: dotfiles deployed for $user"
}

configure_user_sudo() {
  local user="$1"
  ensure_sudo_installed
  local sudo_grp
  sudo_grp="$(get_sudo_group)"
  ensure_sudoers_group "$sudo_grp"
  ensure_sudoers_nopasswd_commands "$sudo_grp" pacman apt apt-get dnf yum zypper
  ensure_user_in_group "$user" "$sudo_grp" 1
}

main() {
  init_colors

  if [ "${1:-}" = '--privileged-users' ]; then
    shift
    if [ "$(id -u)" -ne 0 ]; then
      log_err '--privileged-users is an internal mode and requires root'
      exit 1
    fi
    if [ "$#" -lt 2 ]; then
      log_err '--privileged-users requires a source path and at least one user'
      exit 1
    fi
    DOTFILES_LOCAL_SOURCE="${1:-}"
    shift
    ensure_sudo_installed
    local privileged_sudo_grp
    privileged_sudo_grp="$(get_sudo_group)"
    ensure_sudoers_group "$privileged_sudo_grp"
    ensure_sudoers_nopasswd_commands "$privileged_sudo_grp" pacman apt apt-get dnf yum zypper
    local privileged_user
    for privileged_user in "$@"; do
      setup_user "$privileged_user" "$privileged_sudo_grp"
    done
    return
  fi

  if [ "${1:-}" = '--privileged-user-sudo' ]; then
    shift
    if [ "$(id -u)" -ne 0 ]; then
      log_err '--privileged-user-sudo is an internal mode and requires root'
      exit 1
    fi
    if [ "$#" -ne 1 ]; then
      log_err '--privileged-user-sudo requires exactly one user'
      exit 1
    fi
    configure_user_sudo "$1"
    return
  fi

  if [ "${1:-}" = '--privileged-link-root' ]; then
    shift
    if [ "$(id -u)" -ne 0 ]; then
      log_err '--privileged-link-root is an internal mode and requires root'
      exit 1
    fi
    if [ "$#" -ne 1 ]; then
      log_err '--privileged-link-root requires exactly one home path'
      exit 1
    fi
    link_user_config_to_root "$1"
    ensure_user_shell root
    return
  fi

  log '=== 1. Detect script environment ==='
  local repo_root
  repo_root="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "$repo_root" ]; then
    log_ok "Running inside dotfiles repo: $repo_root"
    DOTFILES_LOCAL_SOURCE="$repo_root"
  else
    log "Not in a git repo; will clone from: $DOTFILES_REPO_URL"
  fi

  log '=== 2. Detect / optionally install zsh, git, starship ==='
  ensure_cmd_installed zsh 0
  ensure_cmd_installed git 1
  ensure_starship_installed 0

  local target_users=()

  if [ $# -gt 0 ]; then
    target_users=("$@")
  else
    local current_user="${SUDO_USER:-$(id -un)}"
    if [ "$current_user" != 'root' ]; then
      target_users+=("$current_user")
    fi

    printf 'Create a new user? [y/N] ' >&2
    read -r resp || resp=''
    if [[ "$resp" =~ ^[yY] ]]; then
      printf 'User name(s), space-separated: ' >&2
      local new_users=()
      read -r -a new_users || new_users=()
      if [ "${#new_users[@]}" -gt 0 ]; then
        target_users+=("${new_users[@]}")
      fi
    else
      log 'Skipping user creation'
    fi
  fi

  if [ "${#target_users[@]}" -eq 0 ]; then
    log_warn 'No non-root target user selected; nothing to deploy'
    return 0
  fi

  local user
  local current_user="${SUDO_USER:-$(id -un)}"
  local privileged_users=()
  if [ "${#target_users[@]}" -gt 0 ]; then
    for user in "${target_users[@]}"; do
      [ -z "$user" ] && continue
      if [ "$user" = "$current_user" ] && id "$user" >/dev/null 2>&1; then
        setup_current_user "$user"
        log 'Configuring sudo access for the current user requires administrator access'
        if [ "$(id -u)" -eq 0 ]; then
          configure_user_sudo "$user"
        elif command -v sudo >/dev/null 2>&1; then
          sudo -H bash "$0" --privileged-user-sudo "$user"
        else
          log_err 'sudo is not available; cannot configure sudo access'
          exit 1
        fi
      else
        privileged_users+=("$user")
      fi
    done
  fi

  if [ "${#privileged_users[@]}" -gt 0 ]; then
    log 'Creating or configuring other users requires administrator access'
    if [ "$(id -u)" -eq 0 ]; then
      bash "$0" --privileged-users "$DOTFILES_LOCAL_SOURCE" "${privileged_users[@]}"
    elif command -v sudo >/dev/null 2>&1; then
      sudo -H bash "$0" --privileged-users "$DOTFILES_LOCAL_SOURCE" "${privileged_users[@]}"
    else
      log_err 'sudo is not available; cannot configure other users'
      exit 1
    fi
  fi

  local primary_home
  primary_home="$(get_user_home "${target_users[0]}")"
  if [ -n "${primary_home:-}" ] && [ -d "$primary_home" ]; then
    local link_root='n'

    if [ -n "${DOTFILES_LINK_ROOT:-}" ]; then
      case "$DOTFILES_LINK_ROOT" in
        1|true|TRUE|yes|YES|on|ON)
          link_root='y'
          ;;
        0|false|FALSE|no|NO|off|OFF)
          link_root='n'
          ;;
      esac
    elif [ -r /dev/tty ]; then
      printf 'Link config into /root for sudo sessions? [y/N] ' >&2
      read -r link_root </dev/tty || link_root='n'
    fi

    if [[ "$link_root" =~ ^[yY](es)?$ ]]; then
      log 'Linking config into /root requires administrator access'
      if [ "$(id -u)" -eq 0 ]; then
        bash "$0" --privileged-link-root "$primary_home"
      elif command -v sudo >/dev/null 2>&1; then
        sudo -H bash "$0" --privileged-link-root "$primary_home"
      else
        log_err 'sudo is not available; cannot link config into /root'
        exit 1
      fi
    else
      log '=== Skip symlink config into root ==='
    fi
  fi
}

main "$@"
