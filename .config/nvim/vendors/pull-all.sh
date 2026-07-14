#!/usr/bin/env bash
set -euo pipefail

dir="$(cd "$(dirname "$0")" && pwd)"

for repo in "$dir"/vv-*/; do
  [ -d "$repo/.git" ] || continue
  name="$(basename "$repo")"
  printf '\033[36m=> %s\033[0m\n' "$name"
  git -C "$repo" pull --ff-only || printf '\033[31m   ✗ %s failed\033[0m\n' "$name"
done
