#!/bin/bash
# snakerail — run Snakemake, auto-fix errors with Claude Code, repeat until done
# Usage: ./snakerail.sh [--max-retries N] [--branch NAME] [snakemake args...]
set -uo pipefail

DIR="$PWD"
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

run_snakemake() {
  snakemake --unlock 2>/dev/null; snakemake "${PASS[@]}" 2>&1 | tee "$DIR/.snakerail_run.log"
  return ${PIPESTATUS[0]}
}

heal() {
  local error
  error=$(grep -E "Error|Traceback" "$DIR/.snakerail_run.log" -B3 -A10 2>/dev/null | tail -60)
  [ -z "$error" ] && error=$(tail -60 "$DIR/.snakerail_run.log")
  claude -p "Fix the Snakemake error below. Edit the code, then git add and commit. Do not restart Snakemake.
Project: $DIR

$error" \
    --allowedTools "Bash,Read,Edit,Write,Grep,Glob,WebFetch,WebSearch" \
    --dangerously-skip-permissions
}

# ── main ──────────────────────────────────────────────────────────────────────
cd "$DIR"
git checkout -b "$BRANCH" 2>/dev/null || true
echo "Starting on branch $BRANCH"

for attempt in $(seq 1 $MAX_RETRIES); do
  run_snakemake && { echo "Pipeline complete."; git log --oneline "$BRANCH"; exit 0; }
  echo "Attempt $attempt/$MAX_RETRIES failed — healing..."
  heal
done

echo "Giving up after $MAX_RETRIES attempts."
exit 1
