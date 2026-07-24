#!/usr/bin/env bash
set -euo pipefail

dir="$(cd "$(dirname "$0")" && pwd)"
max_jobs=6
running_jobs=0

for repo in "$dir"/vv-*/; do
  [ -d "$repo/.git" ] || continue
  name="$(basename "$repo")"

  {
    printf '\033[36m=> %s\033[0m\n' "$name"
    git -C "$repo" pull --ff-only || printf '\033[31m   ✗ %s failed\033[0m\n' "$name"
  } &

  running_jobs=$((running_jobs + 1))
  if (( running_jobs >= max_jobs )); then
    wait -n
    running_jobs=$((running_jobs - 1))
  fi
done
wait
