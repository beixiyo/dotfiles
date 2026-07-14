#!/usr/bin/env bash
file=$1
diff=$(git diff --color=always HEAD -- "$file" 2>/dev/null)
if [[ -n "$diff" ]]; then
  if command -v delta &>/dev/null; then
    echo "$diff" | delta --side-by-side --width=${FZF_PREVIEW_COLUMNS:-80}
  else
    echo "$diff"
  fi
else
  if command -v bat &>/dev/null; then
    bat --color=always --style=numbers "$file" 2>/dev/null
  else
    cat "$file" 2>/dev/null || echo "No diff available for $file"
  fi
fi
