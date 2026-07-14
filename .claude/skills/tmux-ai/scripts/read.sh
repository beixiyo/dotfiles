#!/usr/bin/env bash
# Usage: ./ai-tools/read.sh <pane_id> [scrollback_lines]
# Captures the output of the specified tmux pane.

PANE_ID=$1
LINES=${2:-100}

if [ -z "$PANE_ID" ]; then
    echo "Usage: $0 <pane_id> [scrollback_lines]" >&2
    exit 1
fi

# -p: print to stdout
# -S -N: start capturing from N lines up in history (scrollback buffer)
# -e: include escape sequences (we omit this so we get plain text)
tmux capture-pane -t "$PANE_ID" -p -S -"$LINES" | sed -e 's/[[:space:]]*$//' | cat -s
