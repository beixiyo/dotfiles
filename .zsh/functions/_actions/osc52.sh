#!/usr/bin/env bash
# OSC52 剪贴板桥：SSH 远程环境无本地剪贴板工具时，
# 通过终端转义序列把 stdin 送回本地终端，由其写入系统剪贴板
# 用法: ... | osc52.sh copy   复制 stdin（链路: 远端 tmux -> ssh -> 本地终端）
#       osc52.sh paste        读 tmux 最近 buffer；无 tmux 时无法读取，提示本地粘贴
#
# 注意：必须把序列写到 pane 的 tty 而非 stdout，否则会污染管道输出

set -eu

# 无控制终端的进程（如被 agent 捕获 stdout 的场景）读不到 /dev/tty，
# tmux 环境下以 TMUX_PANE 对应的 tty 为准
_tty() {
  if [[ -n "${TMUX:-}" ]]; then
    tmux display-message -p -t "${TMUX_PANE:-}" '#{pane_tty}'
  else
    echo /dev/tty
  fi
}

_copy() {
  # 命令替换会吃掉尾部换行，追加哨兵字节保真
  local data
  data=$(cat; printf x)
  data=${data%x}

  # Linux base64 默认按 76 列折行，OSC52 序列里不允许出现换行
  local b64
  b64=$(printf '%s' "$data" | base64 | tr -d '\n')

  local tty
  tty=$(_tty)

  if [[ -n "${TMUX:-}" ]]; then
    if [[ "$(tmux show-options -sgv set-clipboard 2>/dev/null || true)" == on ]]; then
      # 裸 OSC52：tmux 拦截后自动写入自身 buffer 并转发给外层终端
      printf '\033]52;c;%s\007' "$b64" > "$tty"
    else
      # 未开转发：先存 buffer 供 paste，再用 DCS passthrough 绕过 tmux 直发外层终端
      printf '%s' "$data" | tmux load-buffer -
      printf '\033Ptmux;\033\033]52;c;%s\007\033\\' "$b64" > "$tty"
    fi
  else
    printf '\033]52;c;%s\007' "$b64" > "$tty"
  fi
}

case "${1:-}" in
  copy) _copy ;;
  paste)
    if [[ -n "${TMUX:-}" ]]; then
      exec tmux show-buffer
    fi
    echo "osc52: reading the remote clipboard needs tmux; paste from your local terminal instead" >&2
    exit 1
    ;;
  *)
    echo "usage: $0 copy (stdin) | paste" >&2
    exit 1
    ;;
esac
