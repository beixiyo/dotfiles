#!/usr/bin/env bash
set -euo pipefail

dir="$(cd "$(dirname "$0")" && pwd)"
owner="beixiyo"

repos=(
  vv-dashboard.nvim
  vv-expand.nvim
  vv-explorer.nvim
  vv-flow.nvim
  vv-git.nvim
  vv-hover.nvim
  vv-icons.nvim
  vv-indent.nvim
  vv-log-hl.nvim
  vv-markdown.nvim
  vv-replace.nvim
  vv-scrollbar.nvim
  vv-statuscol.nvim
  vv-task-panel.nvim
  vv-utils.nvim
  vv-bufferline.nvim
  vv-i18n.nvim
  vv-mcp.nvim
)

for name in "${repos[@]}"; do
  target="$dir/$name"
  if [ -d "$target" ]; then
    printf '\033[33m=> %s (already exists, skip)\033[0m\n' "$name"
    continue
  fi
  printf '\033[36m=> %s\033[0m\n' "$name"
  git clone "git@github.com:$owner/$name.git" "$target" \
    || printf '\033[31m   ✗ %s failed\033[0m\n' "$name"
done
