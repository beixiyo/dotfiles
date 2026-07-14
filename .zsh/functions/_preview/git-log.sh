#!/usr/bin/env bash
commit=$(echo "$1" | grep -o "[a-f0-9]\{7,40\}" | head -1)
[[ -z "$commit" ]] && exit 0
out=$(git show --color=always "$commit" 2>/dev/null)
if command -v delta &>/dev/null; then
  echo "$out" | delta --width=${FZF_PREVIEW_COLUMNS:-80}
else
  echo "$out"
fi
