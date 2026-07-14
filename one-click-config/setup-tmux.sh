#!/usr/bin/env bash
# 一键安装 tmux 插件（tpm + tmux-resurrect / continuum / catppuccin 等）
#
# 用法：
#   ./setup-tmux.sh            # 克隆 tpm（如缺）并安装 conf/plugins.conf 声明的全部插件
#   ./setup-tmux.sh --update   # 更新已安装插件
#
# 前提：
#   - 已安装 git 与 tmux（由 setup-deps.sh 安装）
#   - 已部署 dotfiles（setup-user.sh），即 ~/.config/tmux/tmux.conf 就位
# 说明：
#   - 插件目录被 gitignore：远程 clone / 新机部署后插件为空，必须跑本脚本补齐
#   - 以【普通用户】运行（装进你自己的 ~/.config），勿用 sudo

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
# shellcheck disable=SC1091 # 路径相对于当前脚本固定解析
source "$LIB_DIR/common.sh"

TPM_REPO_URL='https://github.com/tmux-plugins/tpm'
TMUX_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/tmux"
PLUGINS_DIR="$TMUX_DIR/plugins"
TPM_DIR="$PLUGINS_DIR/tpm"

require_cmds() {
  # 必备命令缺失则报错退出（指向 setup-deps）
  local missing=0 c
  for c in "$@"; do
    if ! command -v "$c" >/dev/null 2>&1; then
      log_err "$c not found"
      missing=1
    fi
  done
  [ "$missing" -eq 0 ] || { log_err 'Install missing deps first (./setup-deps.sh), then rerun'; exit 1; }
}

ensure_tpm() {
  # 幂等：已有 tpm 则跳过，否则浅克隆
  if [ -d "$TPM_DIR/.git" ]; then
    log "tpm already present: $TPM_DIR"
    return 0
  fi
  log "Cloning tpm -> $TPM_DIR"
  mkdir -p "$PLUGINS_DIR"
  git clone --depth 1 --single-branch --no-tags "$TPM_REPO_URL" "$TPM_DIR"
}

_run_tpm() {
  # 在【独立 socket】上跑 tpm，绝不碰用户正在使用的 tmux server
  # 关键：tpm 内部用裸 `tmux`，会跟随 $TMUX/默认 socket；故清掉 $TMUX 并指定独立 TMUX_TMPDIR，
  # 把它所有 tmux 调用都导到一次性 server。tpm 从该 server 的全局环境读安装路径（缺失会 FATAL），
  # 这里显式设好它；插件列表则由 tpm 解析 tmux.conf 及其 source 的文件得到（无需 source 配置）
  local bin="$1"; shift
  local tmpdir rc=0
  tmpdir="$(mktemp -d)"
  (
    local tpm_rc=0
    unset TMUX
    export TMUX_TMPDIR="$tmpdir"
    # 用 detached session 拉起隔离 server：无 session 的 start-server 会立即退出、丢失全局环境
    # 全程 TMUX 已 unset 且 TMUX_TMPDIR 指向一次性 socket，下面所有 tmux 调用只作用于隔离 server
    tmux new-session -d -s tpm_setup
    tmux set-environment -g TMUX_PLUGIN_MANAGER_PATH "$PLUGINS_DIR"
    "$bin" "$@" || tpm_rc=$?
    tmux kill-server 2>/dev/null || true
    exit "$tpm_rc"
  ) || rc=$?
  rm -rf "$tmpdir"
  return "$rc"
}

install_plugins() {
  log 'Installing tmux plugins via tpm ...'
  _run_tpm "$TPM_DIR/bin/install_plugins"
}

update_plugins() {
  log 'Updating tmux plugins via tpm ...'
  _run_tpm "$TPM_DIR/bin/update_plugins" all
}

main() {
  init_colors

  if [ "$(id -u)" -eq 0 ]; then
    log_warn 'Running as root installs plugins into /root; run as your normal user instead'
  fi

  require_cmds git tmux

  if [ ! -f "$TMUX_DIR/tmux.conf" ]; then
    log_err "No tmux config at $TMUX_DIR/tmux.conf; deploy dotfiles first (./setup-user.sh)"
    exit 1
  fi

  ensure_tpm

  case "${1:-}" in
    ''|--install) install_plugins ;;
    --update)     update_plugins ;;
    *)            log_err "Unknown arg: $1 (use --install | --update)"; exit 1 ;;
  esac

  log_ok 'tmux plugins ready. Open tmux; reload config anytime with: prefix + r'
}

main "$@"
