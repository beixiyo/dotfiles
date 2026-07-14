#!/usr/bin/env bash
# 交互式管理 sudoers NOPASSWD 命令白名单
#
# 用法：
#   ./setup-sudoers.sh                     # 交互选择（fzf 可用时多选，否则编号选择）
#   ./setup-sudoers.sh docker systemctl    # 非交互模式，直接添加指定命令
#   ./setup-sudoers.sh --list              # 查看当前已配置的 NOPASSWD 命令

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
for lib_file in common packages sudoers; do
  # shellcheck disable=SC1090 # 路径由固定的 lib_file 列表组成
  source "$LIB_DIR/${lib_file}.sh"
done

# NOPASSWD 候选命令白名单。
# 注意：以无参数限制的 NOPASSWD 授予后，下列多数命令（systemctl/journalctl/dmesg/ip/
# mount/umount/fdisk/包管理器）实际等价于无密码 root——可经 pager 的 !sh、ip netns exec、
# bind-mount 篡改 /etc、挂载分区等方式提权。仅在你信任本机所有本地用户时启用。
SAFE_COMMANDS=(
  systemctl
  docker
  pacman
  apt
  apt-get
  dnf
  yum
  zypper
  mount
  umount
  fdisk
  ip
  ss
  journalctl
  dmesg
  lsblk
  reboot
  shutdown
)

get_existing_nopasswd_names() {
  local p
  read_managed_dropin | awk '
    /^[[:space:]]*#/ { next }
    /NOPASSWD:[[:space:]]*/ {
      sub(/.*NOPASSWD:[[:space:]]*/, "", $0)
      gsub(/[[:space:]]+/, "", $0)
      n = split($0, arr, ",")
      for (i = 1; i <= n; i++) if (arr[i] != "") print arr[i]
      exit
    }
  ' | while IFS= read -r p; do
    [ -n "$p" ] && basename "$p"
  done | awk '!seen[$0]++'
}

read_managed_dropin() {
  local dropin_file='/etc/sudoers.d/oneclickconfig-nopasswd'
  local dropin_dir
  dropin_dir="$(dirname "$dropin_file")"

  if [ -r "$dropin_file" ]; then
    cat "$dropin_file"
    return
  fi

  if [ ! -e "$dropin_file" ] && [ ! -L "$dropin_file" ] && [ -x "$dropin_dir" ]; then
    return 1
  fi
  if [ ! -d "$dropin_dir" ] && [ -x "$(dirname "$dropin_dir")" ]; then
    return 1
  fi

  if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
    if sudo -n -- cat "$dropin_file" 2>/dev/null; then
      return 0
    fi
    if sudo -n -- test ! -e "$dropin_file" 2>/dev/null; then
      return 1
    fi
  fi

  return 2
}

show_current_nopasswd() {
  local content
  local read_rc=0
  content="$(read_managed_dropin)" || read_rc=$?
  case "$read_rc" in
    1)
      log 'No NOPASSWD commands configured yet'
      return 0
      ;;
    2)
      log_warn 'Administrator access is required to inspect the current NOPASSWD configuration; continuing without preselected entries'
      return 0
      ;;
  esac

  log 'Current NOPASSWD configuration:'
  printf '\n'
  printf '%s\n' "$content"
  printf '\n'
}

is_dangerous_command() {
  _is_sudoers_command_denied "$1"
}

select_commands_fzf() {
  local -a existing_names=()
  local name
  while IFS= read -r name; do
    [ -n "$name" ] && existing_names+=("$name")
  done < <(get_existing_nopasswd_names)

  local bind_actions=''
  local pos=1
  for cmd in "${SAFE_COMMANDS[@]}"; do
    for name in "${existing_names[@]}"; do
      if [ "$cmd" = "$name" ]; then
        [ -n "$bind_actions" ] && bind_actions+='+'
        bind_actions+="pos($pos)+toggle"
        break
      fi
    done
    ((pos++))
  done
  [ -n "$bind_actions" ] && bind_actions+="+pos(1)"

  local -a fzf_args=(
    --multi
    --header='Tab: select/deselect  Enter: confirm  Esc: skip'
    --prompt='Select commands for NOPASSWD> '
    --height=~50%
    --reverse
  )
  [ -n "$bind_actions" ] && fzf_args+=(--bind "start:$bind_actions")

  local result
  result="$(printf '%s\n' "${SAFE_COMMANDS[@]}" | fzf "${fzf_args[@]}" 2>/dev/null)" || true

  if [ -n "$result" ]; then
    while IFS= read -r line; do
      [ -n "$line" ] && printf '%s\n' "$line"
    done <<< "$result"
  fi
}

select_commands_numbered() {
  local -a existing_names=()
  local name
  while IFS= read -r name; do
    [ -n "$name" ] && existing_names+=("$name")
  done < <(get_existing_nopasswd_names)

  local i=1
  local idx marker

  printf '\nAvailable commands (NOPASSWD safe):\n' >&2
  for cmd in "${SAFE_COMMANDS[@]}"; do
    marker='  '
    for name in "${existing_names[@]}"; do
      if [ "$cmd" = "$name" ]; then
        marker='* '
        break
      fi
    done
    printf '  %s%2d) %s\n' "$marker" "$i" "$cmd" >&2
    ((i++))
  done
  printf '\n* = already configured\n' >&2
  printf 'Enter numbers to select (space-separated, empty to skip): ' >&2
  read -r choices || choices=''

  for idx in $choices; do
    if [[ "$idx" =~ ^[0-9]+$ ]] && [ "$idx" -ge 1 ] && [ "$idx" -le "${#SAFE_COMMANDS[@]}" ]; then
      printf '%s\n' "${SAFE_COMMANDS[$((idx - 1))]}"
    fi
  done
}

prompt_extra_commands() {
  local -a extra=()
  local cmd

  printf 'Add extra commands (space-separated, empty to skip): ' >&2
  read -r input || input=''
  for cmd in $input; do
    [ -z "$cmd" ] && continue
    if is_dangerous_command "$cmd"; then
      log_warn "Skipped '$cmd': can escape to root shell (use sudoedit for editing root files)"
      continue
    fi
    extra+=("$cmd")
  done

  [ ${#extra[@]} -gt 0 ] && printf '%s\n' "${extra[@]}"
}

apply_commands() {
  local -a commands=()
  local cmd
  for cmd in "$@"; do
    if is_dangerous_command "$cmd"; then
      log_warn "Skipped '$cmd': can escape to root shell (use sudoedit for editing root files)"
      continue
    fi
    commands+=("$cmd")
  done

  if [ ${#commands[@]} -eq 0 ]; then
    log 'No valid commands after filtering dangerous ones; nothing to do'
    return 0
  fi

  if [ "$(id -u)" -ne 0 ]; then
    if ! command -v sudo >/dev/null 2>&1; then
      log_err 'sudo is not available; cannot update sudoers'
      exit 1
    fi
    log 'Requesting administrator access to update sudoers ...'
    exec sudo -H bash "$0" --apply "${commands[@]}"
  fi

  local sudo_grp
  sudo_grp="$(get_sudo_group)"
  ensure_sudo_installed
  ensure_sudoers_group "$sudo_grp"
  ensure_sudoers_nopasswd_commands "$sudo_grp" "${commands[@]}"
}

confirm_and_apply() {
  local -a commands=("$@")

  if [ ${#commands[@]} -eq 0 ]; then
    log 'No commands selected; nothing to do'
    return 0
  fi

  printf '\n' >&2
  log "Will add NOPASSWD for: ${commands[*]}"
  printf 'Proceed? [y/N] ' >&2
  read -r resp || resp=''
  if [[ ! "$resp" =~ ^[yY] ]]; then
    log 'Cancelled'
    return 0
  fi

  apply_commands "${commands[@]}"
  printf '\n' >&2
  show_current_nopasswd
}

interactive_mode() {
  local -a selected=()
  local cmd

  log '=== Interactive NOPASSWD configuration ==='

  show_current_nopasswd

  if command -v fzf >/dev/null 2>&1; then
    while IFS= read -r cmd; do
      [ -n "$cmd" ] && selected+=("$cmd")
    done < <(select_commands_fzf)
  else
    while IFS= read -r cmd; do
      [ -n "$cmd" ] && selected+=("$cmd")
    done < <(select_commands_numbered)
  fi

  while IFS= read -r cmd; do
    [ -n "$cmd" ] && selected+=("$cmd")
  done < <(prompt_extra_commands)

  # 去重
  local -a unique=()
  if [ ${#selected[@]} -gt 0 ]; then
    while IFS= read -r cmd; do
      [ -n "$cmd" ] && unique+=("$cmd")
    done < <(printf '%s\n' "${selected[@]}" | awk '!seen[$0]++')
  fi

  confirm_and_apply "${unique[@]}"
}

main() {
  init_colors

  if [ $# -eq 0 ]; then
    interactive_mode
    return
  fi

  if [ "$1" = '--list' ]; then
    shift
    if [ "$#" -ne 0 ]; then
      log_err '--list does not accept additional arguments'
      exit 1
    fi
    show_current_nopasswd
    return
  fi

  if [ "$1" = '--apply' ]; then
    shift
    if [ "$(id -u)" -ne 0 ]; then
      log_err '--apply is an internal privileged mode'
      exit 1
    fi
    if [ "$#" -eq 0 ]; then
      log_err '--apply requires at least one command'
      exit 1
    fi
    apply_commands "$@"
    printf '\n' >&2
    show_current_nopasswd
    log_ok 'Done. Use --list to verify'
    return
  fi

  apply_commands "$@"
  log_ok "Done. Use --list to verify"
}

main "$@"
