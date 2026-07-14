#!/usr/bin/env bash
repo=$1
clip=${GREPO_CLIP_CMD:-cat}
u=$(git -C "$repo" remote get-url origin 2>/dev/null) \
  || u=$(git -C "$repo" remote get-url "$(git -C "$repo" remote | head -n1)" 2>/dev/null) \
  || exit 1
u=${u%.git}
case $u in
  git@*:*)
    tmp=${u#git@}
    host=${tmp%%:*}
    path=${u#*:}
    link="https://${host}/${path}" ;;
  ssh://git@*/*)
    rest=${u#ssh://git@}
    link="https://${rest%%/*}/${rest#*/}" ;;
  http://*|https://*)
    link=$u ;;
  *)
    link=$u ;;
esac
printf '%s\n' "$link" | eval "$clip"
