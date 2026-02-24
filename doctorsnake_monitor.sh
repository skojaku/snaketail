#!/bin/bash
# doctorsnake_monitor.sh — Monitor loop that watches a Snakemake pane,
# detects errors, invokes Claude Code to fix them, and restarts the pipeline.
#
# This script is launched by doctorsnake_launch.sh in the left tmux pane.
# It can also be run standalone (without tmux) for debugging.
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONF="$SCRIPT_DIR/.doctorsnake.conf"
LOG="$SCRIPT_DIR/.doctorsnake.log"
RETRY_FILE="$SCRIPT_DIR/.doctorsnake_retry_count"
SESSION_NAME="doctorsnake"

# ═══════════════════════════════════════════════════════════════════════════════
# Defaults (overridden by .conf, then by CLI flags)
# ═══════════════════════════════════════════════════════════════════════════════
SNAKEMAKE_CMD="snakemake --cores all --rerun-incomplete"
INTERVAL=300
MAX_RETRIES=10

# Load persisted config if it exists
[ -f "$CONF" ] && source "$CONF"

# Parse CLI arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --cmd)         SNAKEMAKE_CMD="$2"; shift 2 ;;
        --interval)    INTERVAL="$2";      shift 2 ;;
        --max-retries) MAX_RETRIES="$2";   shift 2 ;;
        --session)     SESSION_NAME="$2";  shift 2 ;;
        *) echo "Unknown flag: $1"; exit 1 ;;
    esac
done

# ═══════════════════════════════════════════════════════════════════════════════
# Monitor loop: watches the Snakemake pane and fixes errors
# ═══════════════════════════════════════════════════════════════════════════════
SNAKE_PANE="${SESSION_NAME}.2"
PROJECT="$SCRIPT_DIR"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }

log "========================================"
log "START: Doctor monitoring loop started."
log "START: Watching pane $SNAKE_PANE"
log "START: Interval=${INTERVAL}s, max_retries=$MAX_RETRIES"
log "START: Command: $SNAKEMAKE_CMD"
log "========================================"
echo ""
echo "Doctor is watching the Snakemake pane (right)."
echo "Checking every ${INTERVAL}s. Press Ctrl-C to stop monitoring."
echo ""

while true; do
    sleep "$INTERVAL"

    # ── 1. Check if Snakemake is still running ────────────────────────────
    if pgrep -af "snakemake.*--cores" 2>/dev/null | grep -q "$PROJECT"; then
        log "OK: Snakemake is still running."
        continue
    fi

    # ── 2. Capture tmux output from the Snakemake pane ───────────────────
    OUTPUT=$(tmux capture-pane -t "$SNAKE_PANE" -p -S -500 2>&1)
    echo "$OUTPUT" > "$PROJECT/.doctorsnake_last_output.txt"

    # ── 3. Check for completion ──────────────────────────────────────────
    if echo "$OUTPUT" | grep -q "Nothing to be done\|steps (100%) done"; then
        log "DONE: Pipeline completed successfully!"
        rm -f "$RETRY_FILE"
        break
    fi

    # ── 4. Check for errors ──────────────────────────────────────────────
    if ! echo "$OUTPUT" | grep -qE "Error in rule|Traceback|ModuleNotFoundError|FileNotFoundError|CalledProcessError|RuleException"; then
        log "IDLE: No Snakemake process and no errors detected. Restarting pipeline."
        tmux send-keys -t "$SNAKE_PANE" \
            "cd '$PROJECT' && snakemake --unlock 2>/dev/null; $SNAKEMAKE_CMD 2>&1 | tee '$PROJECT/.doctorsnake_run.log'" Enter
        continue
    fi

    # ── 5. Error detected — check retry count ───────────────────────────
    RETRIES=0
    [ -f "$RETRY_FILE" ] && RETRIES=$(cat "$RETRY_FILE")

    if [ "$RETRIES" -ge "$MAX_RETRIES" ]; then
        log "ABORT: Reached max retries ($MAX_RETRIES). Manual intervention required."
        break
    fi

    RETRIES=$((RETRIES + 1))
    echo "$RETRIES" > "$RETRY_FILE"
    log "FIX: Error detected (attempt $RETRIES/$MAX_RETRIES). Invoking Claude Code..."

    # ── 6. Extract error context ─────────────────────────────────────────
    ERROR_CONTEXT=$(echo "$OUTPUT" | grep -B5 -A15 "Error in rule\|Traceback\|ModuleNotFoundError\|FileNotFoundError" | tail -60)

    # ── 7. Invoke Claude Code to diagnose and fix ────────────────────────
    cd "$PROJECT"

    PROMPT="You are monitoring a Snakemake pipeline in this project.

The pipeline has stopped with an error. Here is the recent output:

---
$ERROR_CONTEXT
---

Your job:
1. Diagnose the error from the output above.
2. Read the failing script or Snakefile rule to understand the issue.
3. Fix the code (edit the file) so the error won't recur.
4. Do NOT restart Snakemake — just fix the code. The caller will restart it.
5. Be concise. Output only what you changed and why.

Important:
- Project root: $PROJECT
- Use the project's CLAUDE.md (if present) to understand the project structure.
- Look at Snakefile and workflow/ directory for pipeline rules and scripts.
- If the error is about missing data files (not code), just report it — don't try to fix missing data."

    claude -p "$PROMPT" \
        --allowedTools "Bash,Read,Edit,Write,Grep,Glob" \
        --dangerously-skip-permissions \
        >> "$LOG" 2>&1

    if [ $? -ne 0 ]; then
        log "WARN: Claude Code exited with non-zero status."
    fi

    # ── 8. Restart Snakemake in the right pane ───────────────────────────
    log "RESTART: Unlocking and restarting Snakemake."
    tmux send-keys -t "$SNAKE_PANE" \
        "cd '$PROJECT' && snakemake --unlock 2>/dev/null; $SNAKEMAKE_CMD 2>&1 | tee '$PROJECT/.doctorsnake_run.log'" Enter
    log "RESTART: Snakemake restarted."
done

log "STOP: Doctor loop exited."
