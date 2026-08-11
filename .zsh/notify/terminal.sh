#!/usr/bin/env bash
# 跨平台终端 BEL；tmux 下写 client TTY，否则写当前控制终端

_notify_terminal_sound() {
  [[ "${NOTIFY_SOUND:-0}" == 1 ]] || return

  local _tty
  if [[ -n "${_tmux_socket:-}" ]] && command -v tmux &>/dev/null; then
    while IFS= read -r _tty; do
      [[ -w "$_tty" ]] && printf '\a' > "$_tty"
    done < <(tmux -S "$_tmux_socket" list-clients -F '#{client_tty}' 2>/dev/null)
    return
  fi

  [[ -n "${TTY:-}" && -w "$TTY" ]] && printf '\a' > "$TTY" && return
  [[ -w /dev/tty ]] && printf '\a' > /dev/tty 2>/dev/null || true
}
