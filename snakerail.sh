#!/bin/bash
# snakerail — run Snakemake, auto-fix errors with Claude Code, repeat until done
# Usage: ./snakerail.sh [--max-retries N] [--branch NAME] [snakemake args...]
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="$DIR/.snakerail.log"
RUN_LOG="$DIR/.snakerail_run.log"
MAX_RETRIES=10
BRANCH="snakerail/$(date '+%Y%m%d-%H%M%S')"
PASS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --max-retries) MAX_RETRIES="$2"; shift 2 ;;
    --branch)      BRANCH="$2";      shift 2 ;;
    *)             PASS+=("$1");     shift ;;
  esac
done

log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG"; }

cd "$DIR"
git checkout -b "$BRANCH" 2>/dev/null || true
log "Starting on branch $BRANCH"

for attempt in $(seq 1 $((MAX_RETRIES + 1))); do
  snakemake --unlock 2>/dev/null || true
  snakemake --cores all --rerun-incomplete "${PASS[@]}" 2>&1 | tee "$RUN_LOG"
  EXIT=${PIPESTATUS[0]}

  if [ $EXIT -eq 0 ]; then
    log "Pipeline complete."
    git log --oneline "$BRANCH" 2>/dev/null
    exit 0
  fi

  if [ $attempt -gt $MAX_RETRIES ]; then
    log "Giving up after $MAX_RETRIES attempts."
    exit 1
  fi

  log "Error on attempt $attempt — invoking Claude Code to fix..."

  ERROR=$(grep -E "Error|Traceback" "$RUN_LOG" -B3 -A10 2>/dev/null | tail -60)
  [ -z "$ERROR" ] && ERROR=$(tail -60 "$RUN_LOG")

  claude -p "Fix the Snakemake error below. Edit the code so it won't recur. Do not restart Snakemake.
When done, git add and commit your changes with a descriptive message.
Project: $DIR

$ERROR" \
    --allowedTools "Bash,Read,Edit,Write,Grep,Glob,WebFetch,WebSearch" \
    --dangerously-skip-permissions >> "$LOG" 2>&1

  git log --oneline -3 | tee -a "$LOG"
done
