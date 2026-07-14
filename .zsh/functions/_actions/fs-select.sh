#!/usr/bin/env bash
raw=$1
bun_path=$2
rel=$(echo "$raw" | cut -d: -f1,2)
abs=$(bun run "$bun_path" abs "$rel" 2>/dev/null)
printf '%s\n%s\n' "$rel" "$abs"
