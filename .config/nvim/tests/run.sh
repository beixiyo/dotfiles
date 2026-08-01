#!/bin/sh

set -eu

tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
state_dir=$(mktemp -d)
trap 'rm -rf "$state_dir"' EXIT

scratch_output="$state_dir/scratch-output"
noice_output="$state_dir/noice-output"

status=0
XDG_STATE_HOME="$state_dir" nvim --headless -u NONE -l "$tests_dir/test_scratch.lua" >"$scratch_output" 2>&1 || status=$?
if [ "$status" -eq 0 ]; then
  XDG_STATE_HOME="$state_dir" nvim --headless -l "$tests_dir/test_noice_confirm.lua" >"$noice_output" 2>&1 || status=$?
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
cat "$scratch_output"
if [ -f "$noice_output" ]; then
  cat "$noice_output"
fi
printf '%b' "$reset"

exit "$status"
