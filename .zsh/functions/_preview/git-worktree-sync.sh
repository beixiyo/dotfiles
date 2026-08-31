#!/usr/bin/env bash

# Preview one worktree selected by gwt-sync without modifying its Git state.

set -u

worktree=${1:-}
if [[ -z "$worktree" || ! -d "$worktree" ]]; then
  printf 'worktree is unavailable: %s\n' "$worktree"
  exit 0
fi

printf '\033[1mPath\033[0m  %s\n\n' "$worktree"
git -C "$worktree" --no-pager status --short --branch --untracked-files=all 2>/dev/null

printf '\n\033[1mRecent commits\033[0m\n'
git -C "$worktree" --no-pager log \
  --graph \
  --decorate \
  --color=always \
  --format='%C(auto)%h%d %s %C(black)%C(bold)%cr' \
  -12 \
  2>/dev/null

printf '\n\033[1mChanged paths\033[0m\n'
git -C "$worktree" --no-pager diff --stat --color=always 2>/dev/null
git -C "$worktree" --no-pager diff --cached --stat --color=always 2>/dev/null
