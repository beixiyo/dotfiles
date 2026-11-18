#!/usr/bin/env bash
# Usage: ./wait-ready.sh <pane_id> <keyword> [timeout_seconds] [poll_interval] [delay_after]
# Polls pane content until keyword appears, waits delay_after seconds, then exits 0.
# Exits 1 on timeout.
#
# Examples:
#   ./wait-ready.sh %3 "Ask anything"           # opencode, default 30s timeout, 1s poll, 2s delay
#   ./wait-ready.sh %3 ">" 30 1 0               # generic prompt, no delay
#   ./wait-ready.sh %3 "claude" 60 2 3          # claude code, 3s delay

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PANE_ID=$1
KEYWORD=$2
TIMEOUT=${3:-30}
INTERVAL=${4:-1}
DELAY=${5:-3}

if [ -z "$PANE_ID" ] || [ -z "$KEYWORD" ]; then
    echo "Usage: $0 <pane_id> <keyword> [timeout] [poll_interval] [delay_after]" >&2
    exit 1
fi

ELAPSED=0
while [ "$ELAPSED" -lt "$TIMEOUT" ]; do
    if "$SCRIPT_DIR/read.sh" "$PANE_ID" 50 2>/dev/null | grep -q "$KEYWORD"; then
        sleep "$DELAY"
        exit 0
    fi
    sleep "$INTERVAL"
    ELAPSED=$((ELAPSED + INTERVAL))
done

echo "Timeout: '$KEYWORD' not found in pane $PANE_ID after ${TIMEOUT}s" >&2
exit 1
