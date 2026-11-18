#!/usr/bin/env bash
# Usage: ./ai-tools/watch.sh <main_pane_id> <session_dir> [poll_interval_seconds]
# Runs in the background. Polls for $SESSION_DIR/done, then notifies the main agent via tmux.
#
# On completion, injects into main pane:
#   [AI_DONE] <session_dir>

MAIN_PANE=$1
SESSION_DIR=$2
INTERVAL=${3:-5}

if [ -z "$MAIN_PANE" ] || [ -z "$SESSION_DIR" ]; then
    echo "Usage: $0 <main_pane_id> <session_dir> [poll_interval]" >&2
    exit 1
fi

while true; do
    if [ -f "$SESSION_DIR/done" ]; then
        tmux send-keys -t "$MAIN_PANE" -l "[AI_DONE] $SESSION_DIR"
        tmux send-keys -t "$MAIN_PANE" Enter
        exit 0
    fi
    sleep "$INTERVAL"
done
