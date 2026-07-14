#!/usr/bin/env bash
raw=$1
p=${raw%%:*}
tmp=${raw#*:}
l=${tmp%%:*}
[[ "$l" =~ ^[0-9]+$ ]] || l=1
s=$(( l > 12 ? l - 12 : 1 ))
e=$(( l + 40 ))
if command -v bat &>/dev/null; then
  bat --color=always --style=numbers --theme=base16 \
    --line-range "$s:$e" --highlight-line "$l" "$p"
else
  sed -n "${s},${e}p" "$p"
fi
