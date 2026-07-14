#!/usr/bin/env bash
repo=$1
clip=${GREPO_CLIP_CMD:-cat}
u=$(git -C "$repo" remote get-url origin 2>/dev/null) \
  || u=$(git -C "$repo" remote get-url "$(git -C "$repo" remote | head -n1)" 2>/dev/null) \
  || exit 1
printf '%s\n' "$u" | eval "$clip"
