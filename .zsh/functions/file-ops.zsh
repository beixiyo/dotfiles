#!/usr/bin/env zsh

# Directory / file operations and bulk delete
# Complex logic (rmr / rme) delegated to bun/src/file-ops.ts

() {
  local dir="${${(%):-%x}:A:h}"
  FILE_OPS_BUN_SCRIPT="$dir/bun/src/file-ops.ts"
}

mkcd() { mkdir -p "$@" && cd "$@"; }

## Tree listing (default depth 2). Usage: lt [depth] [path...]
lt() {
  require lsd || return 1
  local level=2
  [[ "$1" == <-> ]] && { level=$1; shift }
  lsd -l -a --icon always --group-directories-first -h --git \
    --ignore-glob "node_modules|.git|.next|dist|.turbo" --tree --depth "$level" --total-size "$@"
}

## Recursively find and delete by pattern. Usage: rmr <root> <pattern1> [pattern2] ...
rmr() {
  require bun || return 1
  bun run "$FILE_OPS_BUN_SCRIPT" rmr "$@"
}

## Delete everything except specified names. Usage: rme <keep1> [keep2] ...
rme() {
  require bun || return 1
  bun run "$FILE_OPS_BUN_SCRIPT" rme "$@"
}

## Open directory in system file manager. Usage: open [path]
open() {
  local target="${1:-.}"
  if is_wsl; then
    require explorer.exe || return 1
    explorer.exe "$target"
  elif is_mac; then
    command open "$target"
  else
    require xdg-open || return 1
    xdg-open "$target"
  fi
}
