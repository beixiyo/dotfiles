#!/usr/bin/env bash
# Usage: ./send.sh <pane_id> <command_string>
# Sends text to a specific tmux pane and presses Enter.
# Long messages are chunked to avoid TUI input buffer drops.

PANE_ID=$1
shift
COMMAND="$*"

if [ -z "$PANE_ID" ] || [ -z "$COMMAND" ]; then
    echo "Usage: $0 <pane_id> <command_string>" >&2
    exit 1
fi

CHUNK_SIZE=40
LEN=${#COMMAND}

if [ "$LEN" -le "$CHUNK_SIZE" ]; then
    tmux send-keys -t "$PANE_ID" -l "$COMMAND"
else
    OFFSET=0
    while [ "$OFFSET" -lt "$LEN" ]; do
        CHUNK="${COMMAND:OFFSET:CHUNK_SIZE}"
        tmux send-keys -t "$PANE_ID" -l "$CHUNK"
        OFFSET=$((OFFSET + CHUNK_SIZE))
        [ "$OFFSET" -lt "$LEN" ] && sleep 0.05
    done
fi

tmux send-keys -t "$PANE_ID" Enter
