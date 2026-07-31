#!/bin/sh

set -eu

tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
state_dir=$(mktemp -d)
trap 'rm -rf "$state_dir"' EXIT

output_file="$state_dir/output"

if XDG_STATE_HOME="$state_dir" nvim --headless -u NONE -l "$tests_dir/test_scratch.lua" >"$output_file" 2>&1; then
  status=0
else
  status=$?
fi

if [ -z "${NO_COLOR:-}" ]; then
  if [ "$status" -eq 0 ]; then
    color='\033[32m'
  else
    color='\033[31m'
  fi
  reset='\033[0m'
else
  color=''
  reset=''
fi

printf '%b' "$color"
cat "$output_file"
printf '%b' "$reset"

exit "$status"
