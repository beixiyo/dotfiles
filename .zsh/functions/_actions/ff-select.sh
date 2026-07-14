#!/usr/bin/env bash
rel=$1
bun_path=$2
abs=$(bun run "$bun_path" abs "$rel" 2>/dev/null)
printf '%s\n%s\n' "$rel" "$abs"
