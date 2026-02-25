#!/bin/bash
# snakerail.sh — Run Snakemake with auto-healing via Claude Code
#
# Runs Snakemake directly, catches errors, invokes Claude Code to self-heal,
# commits each fix, and retries until the pipeline succeeds or max retries hit.
#
# Usage:
#   ./snakerail.sh                               # run with defaults
#   ./snakerail.sh --cmd "snakemake --cores 4"   # custom snakemake command
#   ./snakerail.sh --max-retries 5               # limit fix attempts
#   ./snakerail.sh --branch myfix                # custom branch name
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="$SCRIPT_DIR/.snakerail.log"
RUN_LOG="$SCRIPT_DIR/.snakerail_run.log"

# Defaults
SNAKEMAKE_CMD="snakemake --cores all --rerun-incomplete"
MAX_RETRIES=10
BRANCH="snakerail/$(date '+%Y%m%d-%H%M%S')"
EXTRA_ARGS=()

# Parse CLI arguments; unknown flags/args are forwarded to snakemake
while [ $# -gt 0 ]; do
    case "$1" in
        --cmd)         SNAKEMAKE_CMD="$2"; shift 2 ;;
        --max-retries) MAX_RETRIES="$2";   shift 2 ;;
        --branch)      BRANCH="$2";        shift 2 ;;
        *)             EXTRA_ARGS+=("$1"); shift ;;
    esac
done

# Append any extra args to the snakemake command
if [ ${#EXTRA_ARGS[@]} -gt 0 ]; then
    SNAKEMAKE_CMD="$SNAKEMAKE_CMD ${EXTRA_ARGS[*]}"
fi

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }

cd "$SCRIPT_DIR"

# ── 1. Create git branch ──────────────────────────────────────────────────────
log "========================================"
log "START: snakerail"
log "CMD: $SNAKEMAKE_CMD"
log "MAX_RETRIES: $MAX_RETRIES"
log "========================================"

IN_GIT=false
if git rev-parse --git-dir > /dev/null 2>&1; then
    IN_GIT=true
    git checkout -b "$BRANCH" 2>/dev/null || git checkout "$BRANCH"
    log "BRANCH: Switched to branch '$BRANCH'"
else
    log "WARN: Not a git repository; skipping branch operations."
fi

# ── 2. Self-healing loop ──────────────────────────────────────────────────────
RETRIES=0

while true; do
    log "RUN ($RETRIES/$MAX_RETRIES): $SNAKEMAKE_CMD"

    # Unlock stale lock if present, then run snakemake
    snakemake --unlock 2>/dev/null || true
    eval "$SNAKEMAKE_CMD" 2>&1 | tee "$RUN_LOG"
    EXIT_CODE=${PIPESTATUS[0]}

    # ── Success ───────────────────────────────────────────────────────────────
    if [ "$EXIT_CODE" -eq 0 ]; then
        log "DONE: Pipeline completed successfully!"
        if $IN_GIT; then
            log "GIT LOG (changes made during healing):"
            git log --oneline "$BRANCH" 2>/dev/null | head -20 | tee -a "$LOG" || true
        fi
        exit 0
    fi

    log "ERROR: Snakemake exited with code $EXIT_CODE."

    # ── Max retries guard ─────────────────────────────────────────────────────
    if [ "$RETRIES" -ge "$MAX_RETRIES" ]; then
        log "ABORT: Reached max retries ($MAX_RETRIES). Manual intervention required."
        exit 1
    fi

    RETRIES=$((RETRIES + 1))
    log "FIX: Attempt $RETRIES/$MAX_RETRIES — invoking Claude Code..."

    # ── Extract error context ─────────────────────────────────────────────────
    ERROR_CONTEXT=$(grep -E "Error in rule|Traceback|ModuleNotFoundError|FileNotFoundError|CalledProcessError|RuleException" \
        "$RUN_LOG" -B5 -A15 2>/dev/null | tail -80)
    if [ -z "$ERROR_CONTEXT" ]; then
        ERROR_CONTEXT=$(tail -80 "$RUN_LOG")
    fi

    # ── Invoke Claude Code ────────────────────────────────────────────────────
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
- Project root: $SCRIPT_DIR
- Use the project's CLAUDE.md (if present) to understand the project structure.
- Look at Snakefile and workflow/ directory for pipeline rules and scripts.
- If the error is about missing data files (not code), just report it — don't fix missing data."

    claude -p "$PROMPT" \
        --allowedTools "Bash,Read,Edit,Write,Grep,Glob" \
        --dangerously-skip-permissions \
        >> "$LOG" 2>&1
    CLAUDE_EXIT=$?

    if [ "$CLAUDE_EXIT" -ne 0 ]; then
        log "WARN: Claude Code exited with non-zero status ($CLAUDE_EXIT)."
    fi

    # ── Commit any changes Claude made ────────────────────────────────────────
    if $IN_GIT; then
        if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
            git add -A
            git commit -m "snakerail: auto-fix attempt $RETRIES

$(git diff HEAD --stat 2>/dev/null || true)"
            log "GIT: Changes committed."
            git log --oneline -5 | tee -a "$LOG"
        else
            log "GIT: No file changes from Claude (attempt $RETRIES)."
        fi
    fi
done
