#!/usr/bin/env bash
# 跨平台 URL 打开器：macOS / WSL2 / Linux (X11 or Wayland)

url=$1
[ -z "$url" ] && exit 0

case "$OSTYPE" in
  darwin*)
    open "$url"
    ;;
  linux*)
    if grep -qi microsoft /proc/version 2>/dev/null; then
      # WSL2：优先 wslview，回退 powershell Start-Process
      command -v wslview >/dev/null \
        && wslview "$url" \
        || powershell.exe -NoProfile -Command "Start-Process '$url'" 2>/dev/null
    else
      xdg-open "$url" >/dev/null 2>&1
    fi
    ;;
esac
