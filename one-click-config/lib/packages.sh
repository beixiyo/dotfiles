#!/usr/bin/env bash

PKG_MANAGER=''
PKG_MANAGER_SYNC_DONE=0

run_privileged() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
    return
  fi

  if ! command -v sudo >/dev/null 2>&1; then
    log_err "Administrator access is required to run: $*"
    exit 1
  fi

  log "Requesting administrator access to run: $*"
  sudo -- "$@"
}

run_package_command() {
  if [ "$PKG_MANAGER" = 'paru' ] || [ "$PKG_MANAGER" = 'yay' ] || [ "$PKG_MANAGER" = 'brew' ]; then
    if [ "$(id -u)" -ne 0 ]; then
      "$@"
      return
    fi

    local user="${SUDO_USER:-}"
    if [ -z "$user" ] || [ "$user" = 'root' ] || ! id "$user" >/dev/null 2>&1; then
      log_err "$PKG_MANAGER must run as a non-root user"
      exit 1
    fi

    local command_path
    command_path="$(command -v "$1" 2>/dev/null || true)"
    if [ -z "$command_path" ]; then
      log_err "Cannot resolve package manager command: $1"
      exit 1
    fi
    shift

    local user_home
    user_home="$(get_user_home "$user")"
    if [ -z "$user_home" ] || [ ! -d "$user_home" ]; then
      log_err "Cannot resolve home directory for $user"
      exit 1
    fi

    log "Running $PKG_MANAGER as $user"
    if command -v runuser >/dev/null 2>&1; then
      runuser -u "$user" -- env HOME="$user_home" USER="$user" LOGNAME="$user" "$command_path" "$@"
    else
      local command_string
      printf -v command_string '%q ' "$command_path" "$@"
      su - "$user" -c "$command_string"
    fi
    return
  fi

  if [ "$(id -u)" -eq 0 ]; then
    "$@"
    return
  fi

  if ! command -v sudo >/dev/null 2>&1; then
    log_err "Installing system packages requires root access: $*"
    exit 1
  fi

  log "Requesting administrator access to run: $*"
  sudo -- "$@"
}

detect_package_manager() {
  # 返回当前可用包管理器（Arch 优先 AUR helper，其余按常见发行版排序）
  # paru/yay 不能以 root 运行，root 下直接降级到 pacman
  if [ "$(id -u)" -ne 0 ] && command -v paru >/dev/null 2>&1; then
    echo paru
  elif [ "$(id -u)" -ne 0 ] && command -v yay >/dev/null 2>&1; then
    echo yay
  elif command -v pacman >/dev/null 2>&1; then
    echo pacman
  elif command -v apt-get >/dev/null 2>&1; then
    echo apt-get
  elif command -v apt >/dev/null 2>&1; then
    echo apt
  elif command -v dnf >/dev/null 2>&1; then
    echo dnf
  elif command -v yum >/dev/null 2>&1; then
    echo yum
  elif command -v zypper >/dev/null 2>&1; then
    echo zypper
  elif command -v brew >/dev/null 2>&1; then
    # brew 优先级最低：Linux 上原生包管理器优先，仅 macOS 等只有 brew 时回退到它
    echo brew
  else
    echo ''
  fi
}

sync_package_manager_once() {
  # 首次安装前同步仓库索引，避免安装失败
  if [ "$PKG_MANAGER_SYNC_DONE" = '1' ]; then
    return 0
  fi

  if [ -z "$PKG_MANAGER" ]; then
    PKG_MANAGER="$(detect_package_manager)"
  fi

  case "$PKG_MANAGER" in
    paru)
      log 'Syncing paru databases before first install (paru -Syu)'
      run_package_command paru -Syu --noconfirm
      ;;
    yay)
      log 'Syncing yay databases before first install (yay -Syu)'
      run_package_command yay -Syu --noconfirm
      ;;
    pacman)
      log 'Syncing pacman databases before first install (pacman -Syu)'
      run_package_command pacman -Syu --noconfirm
      ;;
    apt-get)
      log 'Syncing apt-get index before first install (apt-get update)'
      run_package_command apt-get update
      ;;
    apt)
      log 'Syncing apt index before first install (apt update)'
      run_package_command apt update
      ;;
    dnf)
      log 'Syncing dnf cache before first install (dnf makecache)'
      run_package_command dnf makecache
      ;;
    yum)
      log 'Syncing yum cache before first install (yum makecache)'
      run_package_command yum makecache
      ;;
    zypper)
      log 'Syncing zypper repos before first install (zypper refresh)'
      run_package_command zypper refresh
      ;;
    brew)
      log 'Updating brew before first install (brew update)'
      run_package_command brew update || true
      ;;
    *)
      log_err 'Unknown package manager (supported: pacman / apt / dnf / yum / zypper / brew)'
      exit 1
      ;;
  esac

  PKG_MANAGER_SYNC_DONE=1
}

install_package() {
  # 使用当前发行版包管理器安装指定包（pacman / apt / dnf / yum / zypper）
  local pkg="$1"
  if [ -z "$PKG_MANAGER" ]; then
    PKG_MANAGER="$(detect_package_manager)"
  fi

  sync_package_manager_once

  if [ "$PKG_MANAGER" = 'paru' ]; then
    run_package_command paru -S --needed --noconfirm "$pkg"
  elif [ "$PKG_MANAGER" = 'yay' ]; then
    run_package_command yay -S --needed --noconfirm "$pkg"
  elif [ "$PKG_MANAGER" = 'pacman' ]; then
    run_package_command pacman -S --needed --noconfirm "$pkg"
  elif [ "$PKG_MANAGER" = 'apt-get' ]; then
    run_package_command apt-get install -y "$pkg"
  elif [ "$PKG_MANAGER" = 'apt' ]; then
    run_package_command apt install -y "$pkg"
  elif [ "$PKG_MANAGER" = 'dnf' ]; then
    run_package_command dnf install -y "$pkg"
  elif [ "$PKG_MANAGER" = 'yum' ]; then
    run_package_command yum install -y "$pkg"
  elif [ "$PKG_MANAGER" = 'zypper' ]; then
    run_package_command zypper install -y "$pkg"
  elif [ "$PKG_MANAGER" = 'brew' ]; then
    run_package_command brew install "$pkg"
  else
    log_err "Unknown package manager; install $pkg manually and retry"
    exit 1
  fi
}

ensure_cmd_installed() {
  # 检测命令是否存在，不存在则询问是否安装
  # 参数：
  #   $1：命令名（如 zsh、git）
  #   $2：1 表示必须安装（拒绝则退出），0 表示可跳过
  local name="$1"
  local required="${2:-0}"

  if command -v "$name" >/dev/null 2>&1; then
    log "Found $name at $(command -v "$name"); skipping install"
    return 0
  fi

  log "$name not found"
  printf '[%s] Install %s? [y/N] ' "$(date +'%F %T')" "$name" >&2
  read -r resp || resp=''
  if [[ ! "$resp" =~ ^[yY] ]]; then
    if [ "$required" = '1' ]; then
      log_err "$name is required. Install it and rerun"
      exit 1
    fi
    log "Skipping $name; continuing with system defaults"
    return 0
  fi

  log "Installing $name ..."
  install_package "$name"

  if command -v "$name" >/dev/null 2>&1; then
    log_ok "$name installed: $(command -v "$name")"
  else
    log_err "$name still not on PATH after install; check package manager output"
    exit 1
  fi
}

ensure_starship_installed() {
  # 优先使用系统包管理器安装，失败时回退官方安装脚本
  # 参数：
  #   $1：1 表示必须安装，0 可跳过（默认 0）
  local required="${1:-0}"
  local manager=''
  local install_ok=0

  if command -v starship >/dev/null 2>&1; then
    log "Found starship at $(command -v starship); skipping install"
    return 0
  fi

  manager="$(detect_package_manager)"
  log 'starship not found'
  if [ -n "$manager" ]; then
    printf '[%s] Install starship via %s (fallback: upstream script)? [y/N] ' "$(date +'%F %T')" "$manager" >&2
  else
    printf '[%s] No package manager detected; install starship via upstream script? [y/N] ' "$(date +'%F %T')" >&2
  fi
  read -r resp || resp=''
  if [[ ! "$resp" =~ ^[yY] ]]; then
    if [ "$required" = '1' ]; then
      log_err 'starship is required; aborting'
      exit 1
    fi
    log 'Skipping starship install'
    return 0
  fi

  if [ -n "$manager" ]; then
    log "Installing starship with $manager ..."
    if install_package starship; then
      install_ok=1
    else
      log_warn "$manager install of starship failed; trying upstream script"
    fi
  fi

  if [ "$install_ok" = '0' ]; then
    # 裸调用在 set -e 下会在捕获 $? 前中止整脚本，用 || 捕获退出码（否则下方回退逻辑成死代码）
    local script_rc=0
    run_remote_script "$STARSHIP_INSTALL_URL" || script_rc=$?
    if [ "$script_rc" = '0' ]; then
      install_ok=1
    elif [ "$script_rc" = '2' ] && [ -n "$manager" ]; then
      log 'No aria2c/wget/curl; trying to install aria2 ...'
      if install_package aria2 && command -v aria2c >/dev/null 2>&1; then
        if run_remote_script "$STARSHIP_INSTALL_URL"; then
          install_ok=1
        fi
      fi
    else
      log_warn 'Upstream install script failed; continuing without starship'
    fi
  fi

  if command -v starship >/dev/null 2>&1; then
    log_ok "starship installed: $(command -v starship)"
  elif [ "$install_ok" = '1' ]; then
    log_warn 'Install finished but starship not on PATH in this shell'
    if [ "$required" = '1' ]; then
      exit 1
    fi
  else
    log_warn 'starship install skipped or failed; continuing'
    if [ "$required" = '1' ]; then
      log_err 'starship is required; aborting'
      exit 1
    fi
  fi
}

get_default_shell() {
  # 优先 zsh，其次 bash，否则 /bin/sh（useradd -s 需绝对路径）
  local zsh
  local b
  zsh="$(command -v zsh 2>/dev/null || true)"
  b="$(command -v bash 2>/dev/null || true)"
  if [ -n "$zsh" ]; then
    echo "$zsh"
  elif [ -n "$b" ]; then
    echo "$b"
  else
    echo /bin/sh
  fi
}

ensure_sudo_installed() {
  # 配置 sudoers 需要 sudo 包（提供 visudo、/etc/sudoers）。Arch 等发行版默认未装，此处按需安装
  if command -v visudo >/dev/null 2>&1 && [ -r /etc/sudoers ]; then
    log 'visudo and /etc/sudoers present; skipping sudo package install'
    return 0
  fi
  log 'sudo package missing (visudo or /etc/sudoers); installing ...'
  install_package sudo
  if ! command -v visudo >/dev/null 2>&1; then
    log_err 'visudo still missing after install; install sudo manually (e.g. pacman -S sudo) and retry'
    exit 1
  fi
  log_ok 'sudo package ready'
}
