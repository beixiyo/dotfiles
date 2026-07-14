#!/usr/bin/env bash

# 共享常量
STARSHIP_INSTALL_URL='https://starship.rs/install.sh'

init_colors() {
  # 彩色输出（仅终端生效，重定向时关闭）
  if [ -t 2 ]; then
    C_RED='\033[0;31m'
    C_GREEN='\033[0;32m'
    C_YELLOW='\033[0;33m'
    C_CYAN='\033[0;36m'
    C_RESET='\033[0m'
  else
    C_RED=''
    C_GREEN=''
    C_YELLOW=''
    C_CYAN=''
    C_RESET=''
  fi
}

log() {
  # 统一日志输出格式，普通信息用青色
  printf '[%s] %b%s%b\n' "$(date +'%F %T')" "$C_CYAN" "$*" "$C_RESET" >&2
}

log_err() {
  printf '[%s] %b%s%b\n' "$(date +'%F %T')" "$C_RED" "$*" "$C_RESET" >&2
}

log_warn() {
  printf '[%s] %b%s%b\n' "$(date +'%F %T')" "$C_YELLOW" "$*" "$C_RESET" >&2
}

log_ok() {
  printf '[%s] %b%s%b\n' "$(date +'%F %T')" "$C_GREEN" "$*" "$C_RESET" >&2
}

require_root() {
  # 必须以 root 身份运行，否则很多操作会失败
  if [ "$(id -u)" -ne 0 ]; then
    log_err 'This script requires root; run with sudo or as root'
    exit 1
  fi
}

ensure_dir() {
  # 确保目录存在，权限由后续统一处理
  local dir="$1"
  if [ -d "$dir" ]; then
    log "Directory exists: $dir"
  else
    log "Creating directory: $dir"
    mkdir -p "$dir"
  fi
}

get_user_home() {
  # 获取用户 home 目录，不存在返回空字符串
  local user="$1"

  if command -v getent >/dev/null 2>&1; then
    getent passwd "$user" 2>/dev/null | cut -d: -f6
    return 0
  fi

  if command -v dscl >/dev/null 2>&1; then
    dscl . -read "/Users/$user" NFSHomeDirectory 2>/dev/null | awk '{print $2}'
    return 0
  fi

  eval "echo ~$user" 2>/dev/null || true
}

ensure_user_in_group() {
  # 将用户加入指定组
  # 参数：
  #   $1：用户名
  #   $2：组名
  #   $3：1 表示失败需退出，0 表示仅告警
  local user="$1"
  local group="$2"
  local required="${3:-0}"

  local is_member=0
  if id -nG "$user" 2>/dev/null | tr ' ' '\n' | grep -Fx "$group" >/dev/null 2>&1; then
    is_member=1
  fi

  if [ "$is_member" = '1' ]; then
    log "User $user already in group $group; skipping"
    return 0
  fi

  if command -v usermod >/dev/null 2>&1; then
    if usermod -aG "$group" "$user" 2>/dev/null; then
      log_ok "Added $user to group $group"
      return 0
    fi
  fi

  if command -v dseditgroup >/dev/null 2>&1; then
    if dseditgroup -o edit -a "$user" -t user "$group" >/dev/null 2>&1; then
      log_ok "Added $user to group $group"
      return 0
    fi
  fi

  if [ "$required" = '1' ]; then
    log_err "Failed to add $user to group $group"
    exit 1
  fi

  log_warn "Failed to add $user to $group (may already be a member or user locked)"
}
