#!/usr/bin/env bash

FLAG="/tmp/clipboard-paste-flag"
rm -f "$FLAG"

# 后台监听剪贴板数据源变更（即使内容相同也会触发）
wl-paste --watch sh -c "touch '$FLAG'" &
WATCH_PID=$!

clipse-gui

kill "$WATCH_PID" 2>/dev/null
wait "$WATCH_PID" 2>/dev/null

if [ -f "$FLAG" ]; then
  rm -f "$FLAG"
  sleep 0.1
  wtype -M ctrl -P v -p v -m ctrl
fi
