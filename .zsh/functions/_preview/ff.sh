#!/usr/bin/env bash
target=$1
if [ -d "$target" ]; then
  command -v lsd &>/dev/null \
    && lsd --tree --depth 3 --color always --icon always --group-directories-first -a "$target" \
    || ls -la "$target"
else
  command -v bat &>/dev/null \
    && bat --color=always --style=numbers --line-range=:500 "$target" \
    || cat "$target"
fi
