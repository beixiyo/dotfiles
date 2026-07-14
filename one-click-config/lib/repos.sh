#!/usr/bin/env bash

ensure_git_repo() {
  # 确保某个目录下存在指定 git 仓库：
  #   - 不存在则 clone
  #   - 已经是 git 仓库则执行 git pull
  #   - 若目录存在但不是 git 仓库，给出提示，避免误覆盖
  # 参数：
  #   $1：仓库 URL
  #   $2：目标目录
  #   $3：可选执行器函数名
  local repo_url="$1"
  local target_dir="$2"
  local executor="${3:-}"
  local q_repo
  local q_target

  q_repo="$(printf '%q' "$repo_url")"
  q_target="$(printf '%q' "$target_dir")"

  if [ -d "$target_dir/.git" ]; then
    log "Git repo exists: $target_dir; git pull ..."
    _run_with_executor "git -C $q_target pull --ff-only" "$executor" || {
      log_warn "git pull failed; inspect: $target_dir"
    }
  elif [ -d "$target_dir" ]; then
    log_warn "Directory exists but is not a git repo: $target_dir"
    log_warn 'Back up or remove manually if needed; skipping this repo'
  else
    log "Cloning: $repo_url -> $target_dir"
    _run_with_executor "git clone --depth=1 --single-branch --no-tags $q_repo $q_target" "$executor"
  fi
}

_DEPLOY_OVERWRITE_ALL=0
_DEPLOY_HAS_SKIP=0
_DEPLOY_BACKUP=0          # 是否在覆盖前备份（由 deploy_dotfiles 询问后设置）
_DEPLOY_BACKUP_DIR=""     # 覆盖备份统一存放目录（时间戳）
_DEPLOY_TARGET_HOME=""    # 目标家目录（用于计算备份相对路径）

_deploy_item() {
  # 复制单个配置项到目标路径，已存在则询问是否覆盖
  # 参数：
  #   $1：源路径
  #   $2：目标路径
  #   $3：可选执行器函数名
  local src="$1"
  local dst="$2"
  local executor="${3:-}"
  local name
  name="$(basename "$src")"

  if [ -e "$dst" ] && [ "$_DEPLOY_OVERWRITE_ALL" -eq 0 ]; then
    printf '[%s] %s exists; overwrite? [y/N/a=all] ' "$(date +'%F %T')" "$dst" >&2
    read -r resp || resp=''
    if [[ "$resp" =~ ^[aA] ]]; then
      _DEPLOY_OVERWRITE_ALL=1
    elif [[ ! "$resp" =~ ^[yY] ]]; then
      _DEPLOY_HAS_SKIP=1
      log "Skipped: $name"
      return 0
    fi
  fi

  # 覆盖前备份：把已存在的 dst 统一搬到 _DEPLOY_BACKUP_DIR（保留相对结构）
  # 经执行器执行以保持属主/远端上下文一致（与下方 cp 一致）
  if [ "$_DEPLOY_BACKUP" -eq 1 ] && [ -e "$dst" ] && [ -n "$_DEPLOY_BACKUP_DIR" ] && [ -n "$_DEPLOY_TARGET_HOME" ]; then
    local rel bdst
    rel="${dst#"$_DEPLOY_TARGET_HOME"/}"
    bdst="$_DEPLOY_BACKUP_DIR/$rel"
    if _run_with_executor "mkdir -p $(printf '%q' "$(dirname "$bdst")") && cp -a $(printf '%q' "$dst") $(printf '%q' "$bdst")" "$executor"; then
      log_ok "Backed up: $dst -> $bdst"
    else
      # 备份失败则不覆盖该项，避免无备份地销毁旧配置（标记跳过，使 .git 不同步、提示用户重跑）
      log_warn "Backup failed for $dst; skipping overwrite of this item"
      _DEPLOY_HAS_SKIP=1
      return 0
    fi
  fi

  # 目录 → 已存在目录：合并语义（不删 dst 中多余文件），避免 cp 多一层（如 ~/.config/.config）
  # 若 dotfiles 中删除了某文件，用户目录里的旧文件会残留（保守策略）
  if [ -d "$src" ] && [ -d "$dst" ]; then
    _run_with_executor "cp -a $(printf '%q' "$src")/. $(printf '%q' "$dst")/" "$executor"
  else
    # 类型不一致（文件↔目录）时先删 dst 再整体复制：否则 cp 会把文件拷进目录内（静默错），
    # 或对「目录覆盖已存在文件」报错并在 set -e 下中止整脚本
    # 删除前：若用户选了备份则该项已备份；且用户已对该项确认覆盖（y/a）
    if [ -e "$dst" ] && { { [ -d "$src" ] && [ ! -d "$dst" ]; } || { [ ! -d "$src" ] && [ -d "$dst" ]; }; }; then
      log_warn "Type mismatch at $dst (src is $([ -d "$src" ] && echo dir || echo file)); replacing"
      _run_with_executor "rm -rf $(printf '%q' "$dst")" "$executor"
    fi
    _run_with_executor "cp -a $(printf '%q' "$src") $(printf '%q' "$dst")" "$executor"
  fi
  log_ok "Deployed: $name"
}

deploy_dotfiles() {
  # 将 dotfiles 配置部署到目标家目录
  # 若目标家目录本身就是 dotfiles 仓库，只 git pull
  # 否则从 local_source 或远程仓库获取源，逐项部署
  # 参数：
  #   $1：仓库 URL
  #   $2：目标用户家目录
  #   $3：可选执行器函数名
  #   $4：可选本地源目录（非空则跳过 clone）
  local repo_url="$1"
  local target_home="$2"
  local executor="${3:-}"
  local local_source="${4:-}"
  local q_home
  q_home="$(printf '%q' "$target_home")"

  # 若目标家目录已是 dotfiles 仓库则只 pull，避免重复逐项询问覆盖：
  #   - 首次拷贝部署会把 .git 复制到 ~/.git，其 origin 即 dotfiles URL；
  #   - 或脚本就在目标家目录内运行（toplevel 与 local_source 相同）
  if [ -d "$target_home/.git" ]; then
    local same_repo=0
    local existing_remote
    existing_remote="$(_run_with_executor "git -C ${q_home} config --get remote.origin.url 2>/dev/null || true" "$executor" 2>/dev/null || true)"
    if [ -n "$existing_remote" ] && [ "$existing_remote" = "$repo_url" ]; then
      same_repo=1
    fi
    if [ "$same_repo" -eq 0 ] && [ -n "$local_source" ]; then
      local th ls
      th="$(cd "$target_home" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null || true)"
      ls="$(cd "$local_source" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null || true)"
      if [ -n "$th" ] && [ "$th" = "$ls" ]; then
        same_repo=1
      fi
    fi
    if [ "$same_repo" -eq 1 ]; then
      log "Target home is dotfiles repo; git pull ..."
      _run_with_executor "git -C ${q_home} pull --ff-only" "$executor" || {
        log_warn "git pull failed; inspect: $target_home"
      }
      return 0
    fi
  fi

  local src_dir=""
  local need_cleanup=0

  if [ -n "$local_source" ]; then
    log "Using local repo as source: $local_source"
    src_dir="$local_source"
  else
    src_dir="/tmp/dotfiles-$$"
    need_cleanup=1
    log "Cloning dotfiles to temp: $src_dir"
    _run_with_executor "git clone --depth=1 --single-branch --no-tags $(printf '%q' "$repo_url") $(printf '%q' "$src_dir")" "$executor"
  fi

  log "Deploying into $target_home"
  # 不要预先 mkdir ~/.config：若该目录已存在，后续 cp 会把「源 .config」拷进目标里，变成 ~/.config/.config

  # 收集 dotfiles 所有顶层项（不含 .git）到数组，避免 while read 占用 stdin
  local items=()
  while IFS= read -r -d '' item; do
    items+=("$item")
  done < <(find "$src_dir" -maxdepth 1 -mindepth 1 ! -name '.git' -print0)

  # 检查目标目录是否包含 dotfiles 内容
  local has_dotfiles_content=0
  for item in "${items[@]}"; do
    if [ -e "$target_home/$(basename "$item")" ]; then
      has_dotfiles_content=1
      break
    fi
  done

  _DEPLOY_OVERWRITE_ALL=0
  _DEPLOY_HAS_SKIP=0
  _DEPLOY_BACKUP=0
  _DEPLOY_BACKUP_DIR=""
  _DEPLOY_TARGET_HOME="$target_home"

  local q_src
  q_src="$(printf '%q' "$src_dir")"

  if [ "$has_dotfiles_content" -eq 0 ]; then
    # 目标目录无 dotfiles 内容，逐项全量复制（含 .git）
    log "No existing dotfiles content; full copy"
    for item in "${items[@]}"; do
      _run_with_executor "cp -a $(printf '%q' "$item") $(printf '%q' "$target_home/$(basename "$item")")" "$executor"
    done
    _run_with_executor "cp -a ${q_src}/.git ${q_home}/.git" "$executor"
  else
    # 有冲突：先询问是否在覆盖前备份，统一放入一个时间戳目录（误覆盖可手动回滚）
    local resp
    _DEPLOY_BACKUP_DIR="$target_home/.dotfiles-backup-$(date +%Y%m%d-%H%M%S)"
    printf '[%s] Back up files that will be overwritten into %s ? [Y/n] ' "$(date +'%F %T')" "$_DEPLOY_BACKUP_DIR" >&2
    read -r resp || resp=''
    if [[ ! "$resp" =~ ^[nN] ]]; then
      _DEPLOY_BACKUP=1
      log "Backups will be saved under: $_DEPLOY_BACKUP_DIR"
    else
      log "Skipping backups"
    fi

    # 遍历所有顶层项，逐项询问覆盖（for 不占用 stdin，read 可正常读终端）
    local base sub
    for item in "${items[@]}"; do
      base="$(basename "$item")"
      if [ "$base" = '.config' ] && [ -d "$item" ] && [ -d "$target_home/.config" ]; then
        # .config 是容器目录：逐个子项分别询问覆盖，而非整体一次（避免「全有或全无」）
        # 必须先把子项收集进数组、再 plain for 遍历：若用 while < <(find) 直接喂循环，
        # _deploy_item 内部的交互 read 会从 find 管道（而非终端）读取，导致子项被静默跳过
        log ".config exists; prompting per sub-item under ~/.config"
        local config_subs=()
        while IFS= read -r -d '' sub; do
          config_subs+=("$sub")
        done < <(find "$item" -maxdepth 1 -mindepth 1 -print0)
        for sub in "${config_subs[@]}"; do
          _deploy_item "$sub" "$target_home/.config/$(basename "$sub")" "$executor"
        done
      else
        _deploy_item "$item" "$target_home/$(basename "$item")" "$executor"
      fi
    done

    # 没有任何跳过（全选 a 或逐个 y），复制 .git
    if [ "$_DEPLOY_HAS_SKIP" -eq 0 ]; then
      log "All items deployed; syncing .git"
      _run_with_executor "cp -a ${q_src}/.git ${q_home}/.git" "$executor"
    fi

    if [ "$_DEPLOY_BACKUP" -eq 1 ] && [ -d "$_DEPLOY_BACKUP_DIR" ]; then
      log_ok "Overwritten files were backed up at: $_DEPLOY_BACKUP_DIR"
    fi
  fi

  [ "$need_cleanup" -eq 1 ] && rm -rf "$src_dir"
  log_ok "dotfiles deploy complete: $target_home"
}

fix_permissions() {
  # 统一设置共享目录的组与权限（可多次执行，幂等）
  local root_dir="$1"
  local group="$2"

  log "Setting group to $group on: $root_dir"
  chgrp -R "$group" "$root_dir"

  log "Applying g+rwX on: $root_dir"
  chmod -R g+rwX "$root_dir"

  log "Setting setgid on directories (inherit group): $root_dir"
  find "$root_dir" -type d -exec chmod g+s {} \;
}
