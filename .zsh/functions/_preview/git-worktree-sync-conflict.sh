#!/usr/bin/env bash

# Render one immutable gwt-sync preflight report inside the confirmation UI.

set -u

report=${1:-}
if [[ -z "$report" || ! -f "$report" ]]; then
  printf 'Conflict preview is unavailable\n'
  exit 0
fi

if command -v delta &>/dev/null; then
  exec delta \
    --paging=never \
    --side-by-side \
    --width="${FZF_PREVIEW_COLUMNS:-80}" \
    < "$report"
fi

cat "$report"
