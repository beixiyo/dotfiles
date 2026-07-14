#!/usr/bin/env bash
# 跨平台剪贴板读取：macOS / WSL2 / Linux (X11 or Wayland)

case "$OSTYPE" in
  darwin*)
    pbpaste
    ;;
  linux*)
    if grep -qi microsoft /proc/version 2>/dev/null; then
      # WSL2：通过 Windows interop 读剪贴板，去掉 Windows 换行符 \r
      powershell.exe -command 'Get-Clipboard' 2>/dev/null | sed 's/\r$//'
    elif [[ -n "$WAYLAND_DISPLAY" ]]; then
      wl-paste --no-newline 2>/dev/null
    else
      xclip -o -selection clipboard 2>/dev/null \
        || xsel --clipboard --output 2>/dev/null
    fi
    ;;
esac
