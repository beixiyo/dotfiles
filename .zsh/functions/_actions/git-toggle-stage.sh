#!/usr/bin/env bash
file=$1
staged=$(git diff --cached --name-only -- "$file" 2>/dev/null)
if [[ -n "$staged" ]]; then
  git reset -- "$file"
else
  git add -- "$file"
fi
