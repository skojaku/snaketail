# snakerail

Auto-fix your Snakemake pipeline errors with Claude Code.

**snakerail** runs your Snakemake pipeline and, when an error occurs, automatically invokes [Claude Code](https://claude.ai/code) to diagnose and fix the issue, then retries — looping until the pipeline succeeds or the retry limit is hit.

## How It Works

```
./snakerail.sh
    │
    ├─ create git branch  snakerail/20240101-120000
    │
    └─ loop:
         ├─ run snakemake
         ├─ success → print git log of healing commits, exit
         └─ error   → invoke claude to fix → commit changes → retry
```

1. Creates a **git branch** before the first run so all auto-fixes are isolated and reviewable.
2. Runs Snakemake directly (blocking).
3. On success, prints a `git log` of every fix committed during healing.
4. On error, extracts the error context, calls `claude -p` to fix the code, commits the changes, and retries.
5. Gives up after `--max-retries` attempts.

## Prerequisites

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) (`claude` on PATH)
- [Snakemake](https://snakemake.readthedocs.io/)

## Installation

```bash
git clone https://github.com/skojaku/snakerail.git

# Copy the script into your Snakemake project root (next to your Snakefile)
cp snakerail/snakerail.sh /path/to/your/project/
chmod +x /path/to/your/project/snakerail.sh
```

## Usage

```bash
# Run with defaults (snakemake --cores all --rerun-incomplete)
./snakerail.sh

# Pass any snakemake flags directly
./snakerail.sh --cores 4 -p
./snakerail.sh --config key=val target_rule

# Limit fix attempts
./snakerail.sh --max-retries 5

# Custom branch name
./snakerail.sh --branch my-experiment
```

### snakerail flags

| Flag | Default | Description |
|------|---------|-------------|
| `--max-retries` | `10` | Max auto-fix attempts before giving up |
| `--branch` | `snakerail/YYYYMMDD-HHMMSS` | Git branch created before the first run |

All other flags are forwarded to Snakemake.

## Log Files

| File | Description |
|------|-------------|
| `.snakerail.log` | Full log (timestamps, status, Claude Code output) |
| `.snakerail_run.log` | Snakemake stdout/stderr from the last run |

## Tips

- Add a `CLAUDE.md` to your project root so Claude Code understands your project structure and conventions. This significantly improves fix quality.
- snakerail uses `claude -p` with `--dangerously-skip-permissions` so fixes run unattended. Review `.snakerail.log` and the git log to see what was changed.
- Each auto-fix is committed on the healing branch, so you can `git diff main` to review all changes or `git rebase` them onto your main branch.

## License

MIT
