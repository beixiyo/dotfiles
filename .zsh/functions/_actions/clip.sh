#!/usr/bin/env bash
# clip.sh — 剪贴板统一入口：每次执行时现场选择后端，不在 shell 启动时冻结
# 用法: ... | clip.sh copy      复制 stdin
#       clip.sh paste           输出剪贴板内容
#       clip.sh backend         打印本次会选用的后端名（osc52 / pbcopy / clip.exe / wl-copy / xclip / xsel），无可用后端时退出码 1
#       clip.sh available       有可用后端时退出码 0
#
# 调用方：zsh 的 _CLIP_COPY / _CLIP_PASTE（functions/index.zsh）、Bun 工具（bun/src/fzf-shared.ts 的 CLIP_SCRIPT / CLIP_COPY_CMD）
#
# 选择顺序：
#   1. OSC52：被 ssh 登录且无 GUI 的远程机，或本地 tmux 被 ssh / mosh attach（判据见 ~/.local/bin/remote-session tmux-any）
#      OSC52 会被 tmux 广播给所有 attach 的客户端，本地终端与 ssh 对端各写各的剪贴板
#   2. pbcopy → WSL clip.exe → wl-copy → xclip → xsel
#   3. 以上都没有时退回 OSC52

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_is_wsl() {
  [[ -n "${WSL_DISTRO_NAME:-}" || -n "${WSLENV:-}" ]] && return 0
  [[ -r /proc/version ]] && grep -qi microsoft /proc/version
}

# _backend: 打印后端名；无可用后端返回 1
_backend() {
  if [[ -x "$_dir/osc52.sh" ]] && {
       [[ -n "${SSH_TTY:-}" && -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]] \
       || { [[ -n "${TMUX:-}" ]] && "$HOME/.local/bin/remote-session" tmux-any; }
     }; then
    echo osc52
  elif command -v pbcopy >/dev/null 2>&1; then
    echo pbcopy
  elif _is_wsl; then
    echo clip.exe
  elif command -v wl-copy >/dev/null 2>&1; then
    echo wl-copy
  elif command -v xclip >/dev/null 2>&1; then
    echo xclip
  elif command -v xsel >/dev/null 2>&1; then
    echo xsel
  elif [[ -x "$_dir/osc52.sh" ]]; then
    # 本地无任何剪贴板工具：OSC52 在支持它的本地终端里同样可用
    echo osc52
  else
    return 1
  fi
}

_copy() {
  case "$1" in
    osc52) "$_dir/osc52.sh" copy ;;
    pbcopy) pbcopy ;;
    clip.exe) clip.exe ;;
    wl-copy) wl-copy ;;
    xclip) xclip -selection clipboard ;;
    xsel) xsel --clipboard --input ;;
  esac
}

_paste() {
  case "$1" in
    osc52) "$_dir/osc52.sh" paste ;;
    pbcopy) pbpaste ;;
    clip.exe) powershell.exe -NoProfile -Command Get-Clipboard ;;
    wl-copy) wl-paste ;;
    xclip) xclip -selection clipboard -o ;;
    xsel) xsel --clipboard --output ;;
  esac
}

case "${1:-}" in
  copy)
    backend=$(_backend) || { cat >/dev/null; exit 1; }
    _copy "$backend"
    ;;
  paste)
    backend=$(_backend) || exit 1
    _paste "$backend"
    ;;
  backend) _backend ;;
  # 只问“有没有任何后端”，不做 SSH 判定（shell 启动时调用，避免多跑 tmux / ps）
  available)
    [[ -x "$_dir/osc52.sh" ]] && exit 0
    _backend >/dev/null
    ;;
  *)
    echo "usage: clip.sh copy|paste|backend|available" >&2
    exit 2
    ;;
esac
