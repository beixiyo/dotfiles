#!/bin/bash
# 在最左侧列时，改为向右收/踢；否则正常向左
focused=$(niri msg -j focused-window 2>/dev/null)
col=$(echo "$focused" | jq -r '.layout.pos_in_scrolling_layout[0] // empty')

if [ -z "$col" ] || [ "$col" = "1" ]; then
  niri msg action consume-window-into-column
else
  niri msg action consume-or-expel-window-left
fi
