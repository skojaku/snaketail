#!/bin/bash
# snakerail — run Snakemake, auto-fix errors with Claude Code, repeat until done
# Usage: ./snakerail.sh [--max-retries N] [--branch NAME] [snakemake args...]
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="$DIR/.snakerail.log"
MAX_RETRIES=10
BRANCH="snakerail/$(date '+%Y%m%d-%H%M%S')"
EXTRA=()

while [ $# -gt 0 ]; do
  case "$1" in
    --max-retries) MAX_RETRIES="$2"; shift 2 ;;
    --branch)      BRANCH="$2";      shift 2 ;;
    *)             EXTRA+=("$1");    shift ;;
  esac
done

log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG"; }

cd "$DIR"
git checkout -b "$BRANCH" 2>/dev/null || true
log "branch: $BRANCH"

RETRIES=0
while true; do
  snakemake --unlock 2>/dev/null || true
  snakemake --cores all --rerun-incomplete "${EXTRA[@]}" 2>&1 | tee "$DIR/.snakerail_run.log"
  [ ${PIPESTATUS[0]} -eq 0 ] && { log "done"; git log --oneline "$BRANCH" 2>/dev/null; exit 0; }

  log "error (attempt $RETRIES/$MAX_RETRIES)"
  [ "$RETRIES" -ge "$MAX_RETRIES" ] && { log "abort: max retries reached"; exit 1; }
  RETRIES=$((RETRIES + 1))

  ERROR=$(grep -E "Error in rule|Traceback|Error" "$DIR/.snakerail_run.log" -B3 -A10 2>/dev/null | tail -60)
  [ -z "$ERROR" ] && ERROR=$(tail -60 "$DIR/.snakerail_run.log")

  claude -p "Snakemake pipeline failed. Fix the code so it won't recur. Do not restart Snakemake.
Project: $DIR

Error output:
$ERROR" \
    --allowedTools "Bash,Read,Edit,Write,Grep,Glob" \
    --dangerously-skip-permissions >> "$LOG" 2>&1

  if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
    git add -A && git commit -m "snakerail: fix attempt $RETRIES" >> "$LOG"
    git log --oneline -3 | tee -a "$LOG"
  fi
done
