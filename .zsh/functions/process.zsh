#!/usr/bin/env zsh

# Process management: fp (fzf kill), killByName, killByPort
# Core logic in bun/src/process.ts

() {
  local dir="${${(%):-%x}:A:h}"
  PROCESS_BUN_SCRIPT="$dir/bun/src/process.ts"
  _FP_BUN="$dir/bun/src"
}

killByName() {
  require bun || return 1
  bun run "$PROCESS_BUN_SCRIPT" kill-by-name "$@"
}

killByPort() {
  require lsof || return 1
  require bun || return 1
  bun run "$PROCESS_BUN_SCRIPT" kill-by-port "$@"
}

fp() { bun run "$_FP_BUN/fp-cmd.ts" "$@"; }
