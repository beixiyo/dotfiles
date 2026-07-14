#!/usr/bin/env bash

# 所有调用方共享的 NOPASSWD 禁止列表，避免库在未注入配置时静默失去保护
SUDOERS_DENY_COMMANDS=(vim nvim vi nano emacs less more man git ftp ssh env bash zsh fish sh)

get_sudo_group() {
  # macOS 默认 admin；Debian/Ubuntu 默认 sudo；Arch 等常见为 wheel
  if command -v dscl >/dev/null 2>&1; then
    if dscl . -read /Groups/admin >/dev/null 2>&1; then
      echo admin
      return 0
    fi
  fi

  if command -v getent >/dev/null 2>&1 && getent group sudo >/dev/null 2>&1; then
    echo sudo
    return 0
  fi

  if grep -qE '^sudo:' /etc/group 2>/dev/null; then
    echo sudo
    return 0
  fi

  if command -v getent >/dev/null 2>&1 && getent group wheel >/dev/null 2>&1; then
    echo wheel
    return 0
  fi

  if grep -qE '^wheel:' /etc/group 2>/dev/null; then
    echo wheel
    return 0
  fi

  echo admin
}

ensure_sudoers_group() {
  # 确保 /etc/sudoers 中已启用对应组（Arch 默认把 %wheel 注释掉会导致 not in sudoers）
  # 规则需插在 @includedir /etc/sudoers.d 之前，避免被 drop-in 里 NOPASSWD 覆盖
  local sudo_grp="$1"
  local sudoers_file='/etc/sudoers'
  local line_pattern="%${sudo_grp} ALL=(ALL:ALL) ALL"

  if [ ! -r "$sudoers_file" ]; then
    log_warn "Cannot read $sudoers_file; skipping sudoers edit (uncomment %${sudo_grp} with visudo manually)"
    return 0
  fi

  local tmp_file
  tmp_file="$(mktemp)"

  # 归一化：删除已有启用的 group 规则（ALL/ALL:ALL 两种写法），并在 includedir 之前插入一条标准规则
  awk -v grp="$sudo_grp" -v rule="$line_pattern" '
    BEGIN {
      inserted = 0
      group_rule = "^[[:space:]]*%" grp "[[:space:]]+ALL=\\(ALL(:ALL)?\\)[[:space:]]+ALL[[:space:]]*$"
      include_rule = "^[[:space:]]*@includedir[[:space:]]+/etc/sudoers.d([[:space:]]+.*)?$"
    }
    $0 ~ group_rule { next }
    {
      if (!inserted && $0 ~ include_rule) {
        print rule
        inserted = 1
      }
      print
    }
    END {
      if (!inserted) print rule
    }
  ' "$sudoers_file" > "$tmp_file"

  if ! visudo -c -q -f "$tmp_file" 2>/dev/null; then
    log_err "Edited sudoers failed visudo check; not writing. Fix manually: visudo, uncomment %${sudo_grp}"
    rm -f "$tmp_file"
    exit 1
  fi

  cp "$tmp_file" "$sudoers_file"
  chmod 0440 "$sudoers_file"
  rm -f "$tmp_file"
  log_ok "Enabled %${sudo_grp} in sudoers (before includedir)"
}

_resolve_cmd_names_to_paths() {
  # 将命令名集合解析成绝对路径集合
  local -a cmd_names=("$@")
  local -a paths=()
  local cmd
  local p

  for cmd in "${cmd_names[@]}"; do
    [ -z "$cmd" ] && continue
    if p="$(command -v "$cmd" 2>/dev/null)"; then
      paths+=("$p")
      # 兼容符号链接与不同发行版路径差异（/usr/bin 与 /usr/sbin）
      p="$(readlink -f "$p" 2>/dev/null || true)"
      [ -n "$p" ] && paths+=("$p")
    fi
    [ -x "/usr/bin/$cmd" ] && paths+=("/usr/bin/$cmd")
    [ -x "/usr/sbin/$cmd" ] && paths+=("/usr/sbin/$cmd")
    [ -x "/bin/$cmd" ] && paths+=("/bin/$cmd")
    [ -x "/sbin/$cmd" ] && paths+=("/sbin/$cmd")
  done

  printf '%s\n' "${paths[@]}" | awk 'NF && !seen[$0]++'
}

_read_existing_nopasswd_paths() {
  # 从已托管 drop-in 提取 NOPASSWD 路径列表（逗号分隔）
  local dropin_file="$1"
  [ -f "$dropin_file" ] || return 0

  awk '
    /^[[:space:]]*#/ { next }
    /NOPASSWD:[[:space:]]*/ {
      sub(/.*NOPASSWD:[[:space:]]*/, "", $0)
      gsub(/[[:space:]]+/, "", $0)
      n = split($0, arr, ",")
      for (i = 1; i <= n; i++) {
        if (arr[i] != "") print arr[i]
      }
      exit
    }
  ' "$dropin_file" | awk '!seen[$0]++'
}

_is_sudoers_command_denied() {
  local command_path="$1"
  local name="${command_path##*/}"
  local denied

  for denied in "${SUDOERS_DENY_COMMANDS[@]-}"; do
    if [ "$name" = "$denied" ]; then
      return 0
    fi
  done

  local resolved
  resolved="$(readlink -f "$command_path" 2>/dev/null || true)"
  name="${resolved##*/}"
  for denied in "${SUDOERS_DENY_COMMANDS[@]-}"; do
    if [ -n "$resolved" ] && [ "$name" = "$denied" ]; then
      return 0
    fi
  done

  return 1
}

ensure_sudoers_nopasswd_commands() {
  # 为指定命令添加 NOPASSWD（增量合并，不覆盖已托管命令）
  # 参数：
  #   $1：sudo 组名（如 sudo、wheel）
  #   $2...：可选命令名列表（如 pacman、docker）；不传则使用默认包管理器集合
  # 写入位置（托管文件）：
  #   /etc/sudoers.d/oneclickconfig-nopasswd
  # 写入策略：
  #   - 先读取上面文件中已有 NOPASSWD 路径
  #   - 再合并本次命令解析出的路径并去重
  #   - 通过 visudo 校验后覆盖写回该托管文件
  local sudo_grp="$1"
  shift || true

  local dropin_dir='/etc/sudoers.d'
  local dropin_file="${dropin_dir}/oneclickconfig-nopasswd"
  local -a cmd_names=("$@")
  local -a all_paths=()
  local p

  if [ ${#cmd_names[@]} -eq 0 ]; then
    cmd_names=(pacman apt apt-get dnf yum zypper)
  fi

  if [ ! -d "$dropin_dir" ]; then
    return 0
  fi

  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if _is_sudoers_command_denied "$p"; then
      log_warn "Removing dangerous command from managed NOPASSWD configuration: $p"
      continue
    fi
    all_paths+=("$p")
  done < <(_read_existing_nopasswd_paths "$dropin_file")

  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if _is_sudoers_command_denied "$p"; then
      log_warn "Skipped dangerous command path: $p"
      continue
    fi
    all_paths+=("$p")
  done < <(_resolve_cmd_names_to_paths "${cmd_names[@]}")

  if [ ${#all_paths[@]} -eq 0 ]; then
    log_warn "No command paths resolved for NOPASSWD; skipping (commands: ${cmd_names[*]})"
    return 0
  fi

  local -a unique_paths=()
  while IFS= read -r p; do
    [ -n "$p" ] && unique_paths+=("$p")
  done < <(printf '%s\n' "${all_paths[@]}" | awk '!seen[$0]++')

  local nopasswd_line
  nopasswd_line="%${sudo_grp} ALL=(ALL:ALL) NOPASSWD: $(IFS=,; echo "${unique_paths[*]}")"
  local tmp_file
  tmp_file="$(mktemp)"
  printf '# OneClickConfig: managed nopasswd command list\n%s\n' "$nopasswd_line" > "$tmp_file"

  if ! visudo -c -q -f "$tmp_file" 2>/dev/null; then
    log_warn "NOPASSWD line rejected by visudo; skipping. Manual line: $nopasswd_line"
    rm -f "$tmp_file"
    return 0
  fi

  if [ -f "$dropin_file" ]; then
    log "Updating managed sudoers drop-in: $dropin_file"
  else
    log "Creating sudoers drop-in: $dropin_file"
  fi
  cp "$tmp_file" "$dropin_file"
  chown root:root "$dropin_file"
  chmod 0440 "$dropin_file"
  rm -f "$tmp_file"
  log_ok "Updated NOPASSWD for %${sudo_grp} (commands: ${cmd_names[*]}); see $dropin_file"
}
