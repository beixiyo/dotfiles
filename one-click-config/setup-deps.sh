#!/usr/bin/env bash
# 安装 zsh 配置所需的全部依赖
#
# 用法：
#   ./setup-deps.sh
# 说明：
#   - 自动检测包管理器（pacman/apt/dnf/zypper/brew）
#   - 已安装的工具自动跳过
#   - 部分工具在 apt 下需手动安装或用官方脚本

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
for lib_file in common packages download; do
  # shellcheck disable=SC1090 # 路径由固定的 lib_file 列表组成
  source "$LIB_DIR/${lib_file}.sh"
done

# ── 包名映射（按包管理器） ────────────────────────────────────
# 格式：命令名|arch包名|brew包名|apt包名|dnf包名
# 空 = 同命令名，- = 该包管理器不可用（需手动安装）
PACKAGES=(
  'git|git|git|git|git'
  'curl|curl|curl|curl|curl'
  'zsh|zsh|zsh|zsh|zsh'
  'fzf|fzf|fzf|fzf|fzf'
  'fd|fd|fd|fd-find|fd-find'
  'rg|ripgrep|ripgrep|ripgrep|ripgrep'
  'tree|tree|tree|tree|tree'
  'lsd|lsd|lsd|lsd|-'
  'zoxide|zoxide|zoxide|-|-'
  'btop|btop|btop|btop|btop'
  'delta|git-delta|git-delta|-|-'
  'wget|wget|wget|wget|wget'
  'aria2c|aria2|aria2|aria2|aria2'
  'bat|bat|bat|bat|bat'
  'jq|jq|jq|jq|jq'
  'starship|starship|starship|-|-'
  'nvim|neovim|neovim|neovim|neovim'
  'tmux|tmux|tmux|tmux|tmux'
  'safe-rm|safe-rm|safe-rm|safe-rm|-'
  'mise|mise|mise|-|-'
  'unzip|unzip|unzip|unzip|unzip'
  '7z|p7zip|p7zip|p7zip-full|p7zip'
  'unrar|unrar|unrar|unrar|unrar'
  'wl-copy|wl-clipboard|-|wl-clipboard|wl-clipboard'
)

# apt 下需要特殊处理的工具（官方脚本安装）
APT_MANUAL_SCRIPTS=(
  'zoxide|https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh'
  'starship|https://starship.rs/install.sh'
  'mise|https://mise.jdx.dev/install.sh'
)

# ── 辅助函数 ────────────────────────────────────

get_pm_index() {
  case "$1" in
    paru|yay|pacman) echo 1 ;;
    brew)            echo 2 ;;
    apt|apt-get)     echo 3 ;;
    dnf|yum|zypper)  echo 4 ;;
    *)               echo 1 ;;
  esac
}

get_field() {
  echo "$1" | cut -d'|' -f"$2"
}

# 包安装统一复用 lib/packages.sh 的 install_package（含 pacman --needed、brew 分支、按需同步），
# 避免与 lib 各维护一份 PM 分发表

try_script_install() {
  local cmd_name="$1"
  local url=""

  for entry in "${APT_MANUAL_SCRIPTS[@]}"; do
    local name
    name="$(get_field "$entry" 1)"
    if [ "$name" = "$cmd_name" ]; then
      url="$(get_field "$entry" 2)"
      break
    fi
  done

  if [ -z "$url" ]; then
    return 1
  fi

  log "Installing $cmd_name via upstream script ..."
  run_remote_script "$url"
}

# ── 主流程 ────────────────────────────────────

main() {
  init_colors

  PKG_MANAGER="$(detect_package_manager)"
  if [ -z "$PKG_MANAGER" ]; then
    log_err 'No supported package manager found'
    exit 1
  fi

  log "Package manager: $PKG_MANAGER"

  local pm_idx
  pm_idx="$(get_pm_index "$PKG_MANAGER")"
  # 包名字段 = pm_idx + 1（第 1 列是命令名）
  local field_idx=$((pm_idx + 1))

  local installed=0
  local skipped=0
  local failed=0
  local failed_names=()

  for entry in "${PACKAGES[@]}"; do
    local cmd_name pkg_name
    cmd_name="$(get_field "$entry" 1)"
    pkg_name="$(get_field "$entry" "$field_idx")"

    if command -v "$cmd_name" >/dev/null 2>&1; then
      log_ok "[skip] $cmd_name ($(command -v "$cmd_name"))"
      skipped=$((skipped + 1))
      continue
    fi

    if [ "$pkg_name" = '-' ]; then
      log_warn "[manual] $cmd_name not available via $PKG_MANAGER"

      if try_script_install "$cmd_name"; then
        if command -v "$cmd_name" >/dev/null 2>&1; then
          log_ok "[installed] $cmd_name (script)"
          installed=$((installed + 1))
          continue
        fi
      fi

      failed=$((failed + 1))
      failed_names+=("$cmd_name")
      continue
    fi

    if install_package "$pkg_name"; then
      log_ok "[installed] $cmd_name"
      installed=$((installed + 1))
    else
      log_warn "[failed] $cmd_name via $PKG_MANAGER"

      if try_script_install "$cmd_name"; then
        if command -v "$cmd_name" >/dev/null 2>&1; then
          log_ok "[installed] $cmd_name (script fallback)"
          installed=$((installed + 1))
          continue
        fi
      fi

      failed=$((failed + 1))
      failed_names+=("$cmd_name")
    fi
  done

  # apt: fd/bat 需要符号链接
  if [[ "$PKG_MANAGER" == apt* ]]; then
    if command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then
      run_privileged ln -sf "$(command -v fdfind)" /usr/local/bin/fd
      log_ok "Symlinked fd -> fdfind"
    fi
    if command -v batcat >/dev/null 2>&1 && ! command -v bat >/dev/null 2>&1; then
      run_privileged ln -sf "$(command -v batcat)" /usr/local/bin/bat
      log_ok "Symlinked bat -> batcat"
    fi
  fi

  echo ''
  log "=== Summary: $installed installed, $skipped skipped, $failed failed ==="
  if [ "${#failed_names[@]}" -gt 0 ]; then
    log_warn "Install manually: ${failed_names[*]}"
  fi
}

main "$@"
