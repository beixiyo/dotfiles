#!/usr/bin/env zsh

# Git tools: grepo / gdiff / glog
# fzf command building in bun/src/*.ts, zsh is thin glue

() {
  local dir="${${(%):-%x}:A:h}"
  _GIT_BUN="$dir/bun/src"
}

grepo() {
  require bun || return 1
  local d
  d=$(bun run "$_GIT_BUN/grepo.ts" "$@") && [[ -d "$d" ]] && cd "$d"
}

gdiff() { require bun || return 1; bun run "$_GIT_BUN/gdiff.ts" "$@"; }

glog() { require bun || return 1; bun run "$_GIT_BUN/glog.ts" "$@"; }
