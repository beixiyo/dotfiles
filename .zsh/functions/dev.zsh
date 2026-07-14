#!/usr/bin/env zsh

# Dev helpers: d / b / i / t — thin wrappers around bun/src/dev.ts

() {
  local dir="${${(%):-%x}:A:h}"
  DEV_BUN_SCRIPT="$dir/bun/src/dev.ts"
}

d() { require bun || return 1; bun run "$DEV_BUN_SCRIPT" d "$@"; }
b() { require bun || return 1; bun run "$DEV_BUN_SCRIPT" b "$@"; }
i() { require bun || return 1; bun run "$DEV_BUN_SCRIPT" i "$@"; }
t() { require bun || return 1; bun run "$DEV_BUN_SCRIPT" t "$@"; }
