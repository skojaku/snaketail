#!/bin/bash
# doctorsnake_launch.sh — Launches a tmux session with two panes:
#   Left pane:  Doctor monitor (doctorsnake_monitor.sh)
#   Right pane: Snakemake pipeline
#
# Usage:
#   ./doctorsnake_launch.sh                              # launch with defaults
#   ./doctorsnake_launch.sh --cmd "snakemake --cores 4"  # custom snakemake command
#   ./doctorsnake_launch.sh --interval 1800              # check every 30 min
#   ./doctorsnake_launch.sh --session myname             # custom tmux session name
#   ./doctorsnake_launch.sh --attach                     # re-attach to existing session
#   ./doctorsnake_launch.sh --kill                       # kill existing session
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONF="$SCRIPT_DIR/.doctorsnake.conf"
SESSION_NAME="doctorsnake"

# Defaults
SNAKEMAKE_CMD="snakemake --cores all --rerun-incomplete"
INTERVAL=300
MAX_RETRIES=10

# Load persisted config if it exists
[ -f "$CONF" ] && source "$CONF"

# Parse CLI arguments
MODE="launch"
while [ $# -gt 0 ]; do
    case "$1" in
        --cmd)         SNAKEMAKE_CMD="$2"; shift 2 ;;
        --interval)    INTERVAL="$2";      shift 2 ;;
        --max-retries) MAX_RETRIES="$2";   shift 2 ;;
        --session)     SESSION_NAME="$2";  shift 2 ;;
        --attach)      MODE="attach";      shift ;;
        --kill)        MODE="kill";        shift ;;
        *) echo "Unknown flag: $1"; exit 1 ;;
    esac
done

# ═══════════════════════════════════════════════════════════════════════════════
# --attach: reconnect to an existing session
# ═══════════════════════════════════════════════════════════════════════════════
if [ "$MODE" = "attach" ]; then
    if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
        exec tmux attach-session -t "$SESSION_NAME"
    else
        echo "No active session '$SESSION_NAME'. Run without --attach to start."
        exit 1
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════════
# --kill: tear down an existing session
# ═══════════════════════════════════════════════════════════════════════════════
if [ "$MODE" = "kill" ]; then
    if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
        tmux kill-session -t "$SESSION_NAME"
        echo "Session '$SESSION_NAME' killed."
    else
        echo "No active session '$SESSION_NAME'."
    fi
    exit 0
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Launch mode: create tmux session with two panes
# ═══════════════════════════════════════════════════════════════════════════════
if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    echo "Session '$SESSION_NAME' already exists."
    echo "  --attach   to reconnect"
    echo "  --kill     to tear down and re-launch"
    exit 1
fi

# Persist current settings so the monitor script picks them up
cat > "$CONF" <<CONFEOF
SESSION_NAME="$SESSION_NAME"
SNAKEMAKE_CMD="$SNAKEMAKE_CMD"
INTERVAL=$INTERVAL
MAX_RETRIES=$MAX_RETRIES
CONFEOF

echo "Creating tmux session '$SESSION_NAME'..."
echo "  Left pane:  Doctor monitor (checks every ${INTERVAL}s, max $MAX_RETRIES retries)"
echo "  Right pane: $SNAKEMAKE_CMD"

# Create session (first pane becomes the doctor / left pane)
tmux new-session -d -s "$SESSION_NAME" -c "$SCRIPT_DIR" -x 220 -y 50

# Split horizontally — new pane (right) for snakemake
tmux split-window -h -t "$SESSION_NAME" -c "$SCRIPT_DIR"

# Right pane: launch Snakemake
tmux send-keys -t "${SESSION_NAME}.2" \
    "cd '$SCRIPT_DIR' && snakemake --unlock 2>/dev/null; $SNAKEMAKE_CMD 2>&1 | tee '$SCRIPT_DIR/.doctorsnake_run.log'" Enter

# Left pane: launch the doctor monitoring loop
tmux send-keys -t "${SESSION_NAME}.1" \
    "'$SCRIPT_DIR/doctorsnake_monitor.sh' --session '$SESSION_NAME'" Enter

# Select the right pane so the user sees pipeline output first
tmux select-pane -t "${SESSION_NAME}.2"

# Attach
exec tmux attach-session -t "$SESSION_NAME"
