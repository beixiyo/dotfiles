#!/usr/bin/env zsh

# HTTP/HTTPS & git proxy toggle (bun version)
# bun script generates shell statements; we eval them in current shell

() {
  local dir="${${(%):-%x}:A:h}"
  PROXY_BUN_SCRIPT="$dir/bun/src/proxy.ts"
}

setProxy() {
  require bun || return 1
  eval "$(bun run "$PROXY_BUN_SCRIPT" set "$@")"
}

unsetProxy() {
  require bun || return 1
  eval "$(bun run "$PROXY_BUN_SCRIPT" unset "$@")"
}
