#!/usr/bin/env bash
# Usage: ./spawn.sh <main_pane_id> [tmux split-window args...]
# Spawns a new tmux pane (default: right split -h), creates a session
# directory, writes session.env, and auto-starts watch.sh.
#
# Prints two lines to stdout:
#   Line 1: PANE_ID     (e.g. %3)
#   Line 2: SESSION_DIR (e.g. /tmp/ai-collab/20260423-143022-1234)
#
# Also writes $SESSION_DIR/session.env with all session info,
# so subsequent scripts can just: source $SESSION_DIR/session.env

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MAIN_PANE=$1
shift

if [ -z "$MAIN_PANE" ]; then
    echo "Usage: $0 <main_pane_id> [tmux split-window args...]" >&2
    exit 1
fi

SESSION_DIR="/tmp/ai-collab/$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$SESSION_DIR"

PANE_ID=$(tmux split-window -h -d -P -F "#{pane_id}" "$@")

cat > "$SESSION_DIR/session.env" <<EOF
MAIN_PANE=$MAIN_PANE
SUB_PANE=$PANE_ID
SESSION_DIR=$SESSION_DIR
SCRIPTS=$SCRIPT_DIR
EOF

# Auto-start watcher in background
"$SCRIPT_DIR/watch.sh" "$MAIN_PANE" "$SESSION_DIR" >/dev/null 2>&1 &

echo "$PANE_ID"
echo "$SESSION_DIR"
