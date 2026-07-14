#!/bin/bash
# 多窗口列：踢出底部窗口到右侧（与 Win+[ 吸入底部对称）
# 单窗口列：边缘判断，最右侧时改为向左收/踢
focused=$(niri msg -j focused-window 2>/dev/null)
col=$(echo "$focused" | jq -r '.layout.pos_in_scrolling_layout[0] // empty')

if [ -z "$col" ]; then
  niri msg action consume-or-expel-window-left
  exit 0
fi

ws_id=$(echo "$focused" | jq '.workspace_id')
win_count=$(niri msg -j windows | jq "[.[] | select(.workspace_id == $ws_id and .is_floating == false and .layout.pos_in_scrolling_layout[0] == $col)] | length")

if [ "$win_count" -gt 1 ]; then
  niri msg action expel-window-from-column
  exit 0
fi

max_col=$(niri msg -j windows | jq "[.[] | select(.workspace_id == $ws_id and .is_floating == false) | .layout.pos_in_scrolling_layout[0]] | max")

if [ "$col" = "$max_col" ]; then
  niri msg action consume-or-expel-window-left
else
  niri msg action consume-or-expel-window-right
fi
