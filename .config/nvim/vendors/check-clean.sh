#!/usr/bin/env bash
set -euo pipefail

dir="$(cd "$(dirname "$0")" && pwd)"
dirty=0
checked=0

for repo in "$dir"/vv-*/; do
  [ -d "$repo/.git" ] || continue
  name="$(basename "$repo")"
  checked=$((checked + 1))

  if ! status="$(git -C "$repo" status --short --untracked-files=all)"; then
    printf '\033[31m=> %s (cannot read status)\033[0m\n' "$name"
    dirty=1
    continue
  fi

  if [ -z "$status" ]; then
    if ! ahead="$(git -C "$repo" rev-list --count '@{upstream}..HEAD' 2>/dev/null)"; then
      printf '\033[31m=> %s (no upstream branch)\033[0m\n' "$name"
      dirty=1
      continue
    fi

    if (( ahead == 0 )); then
      printf '\033[32m=> %s (clean)\033[0m\n' "$name"
      continue
    fi

    printf '\033[31m=> %s (%d unpushed commit(s))\033[0m\n' "$name" "$ahead"
    dirty=1
    continue
  fi

  printf '\033[31m=> %s (dirty)\033[0m\n%s\n' "$name" "$status"
  dirty=1
done

if (( checked == 0 )); then
  printf '\033[33mNo vv-* Git repositories found\033[0m\n'
  exit 0
fi

if (( dirty )); then
  printf '\033[31mSome vv-* repositories have uncommitted changes\033[0m\n'
  exit 1
fi

printf '\033[32mAll %d vv-* repositories are clean\033[0m\n' "$checked"
