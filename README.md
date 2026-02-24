# doctorsnake

Auto-fix your Snakemake pipeline errors with Claude Code.

**doctorsnake** launches a tmux session with two panes: one runs your Snakemake pipeline, the other monitors it. When an error is detected, it automatically invokes [Claude Code](https://claude.ai/code) to diagnose and fix the issue, then restarts the pipeline.

## How It Works

```
┌─────────────────────────────┬─────────────────────────────┐
│  doctorsnake monitor        │  snakemake --cores all      │
│                             │                             │
│  Checking every 300s...     │  Building DAG of jobs...    │
│  OK: Snakemake is running.  │  rule compute_stats:        │
│  FIX: Error detected!       │    input: data/raw.csv      │
│  Invoking Claude Code...    │    output: data/stats.csv   │
│  RESTART: Pipeline resumed. │  Error in rule compute_stats│
│                             │  ...                        │
└─────────────────────────────┴─────────────────────────────┘
         Left pane                     Right pane
```

1. The **right pane** runs your Snakemake command.
2. The **left pane** polls at a configurable interval.
3. If Snakemake is still running, it logs `OK` and sleeps.
4. If the pipeline finished (`100% done` / `Nothing to be done`), it exits.
5. If an error is detected, it extracts the error context, calls `claude -p` to fix the code, then restarts Snakemake.
6. Retries up to `--max-retries` times before giving up.

## Prerequisites

- [tmux](https://github.com/tmux/tmux)
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) (`claude` command available on PATH)
- [Snakemake](https://snakemake.readthedocs.io/)

## Installation

```bash
# Clone the repo
git clone https://github.com/skojaku/doctorsnake.git

# Copy scripts into your Snakemake project
cp doctorsnake/doctorsnake_launch.sh doctorsnake/doctorsnake_monitor.sh /path/to/your/project/
chmod +x /path/to/your/project/doctorsnake_launch.sh /path/to/your/project/doctorsnake_monitor.sh
```

Both scripts must live in the **root of your Snakemake project** (next to your `Snakefile`).

## Usage

```bash
# Launch with defaults (snakemake --cores all --rerun-incomplete)
./doctorsnake_launch.sh

# Custom Snakemake command
./doctorsnake_launch.sh --cmd "snakemake --cores 4 -p"

# Check every 10 minutes, max 5 retries
./doctorsnake_launch.sh --interval 600 --max-retries 5

# Custom tmux session name
./doctorsnake_launch.sh --session my_pipeline

# Re-attach to a running session
./doctorsnake_launch.sh --attach

# Kill a running session
./doctorsnake_launch.sh --kill
```

### CLI Flags

| Flag | Default | Description |
|------|---------|-------------|
| `--cmd` | `snakemake --cores all --rerun-incomplete` | Snakemake command to run |
| `--interval` | `300` (5 min) | Seconds between checks |
| `--max-retries` | `10` | Max auto-fix attempts before giving up |
| `--session` | `doctorsnake` | tmux session name |
| `--attach` | — | Re-attach to existing session |
| `--kill` | — | Kill existing session |

## Configuration

Settings are persisted to `.doctorsnake.conf` when you launch, so the monitor script picks up the same parameters. You can also create this file manually:

```bash
SESSION_NAME="doctorsnake"
SNAKEMAKE_CMD="snakemake --cores all --rerun-incomplete"
INTERVAL=300
MAX_RETRIES=10
```

## Log Files

| File | Description |
|------|-------------|
| `.doctorsnake.log` | Monitor log (timestamps, status, Claude Code output) |
| `.doctorsnake_run.log` | Snakemake stdout/stderr |
| `.doctorsnake_last_output.txt` | Last captured tmux pane content |
| `.doctorsnake_retry_count` | Current retry counter (auto-deleted on success) |
| `.doctorsnake.conf` | Persisted launch settings |

## Tips

- Add a `CLAUDE.md` to your project root so Claude Code understands your project structure, conventions, and file layout. This dramatically improves fix quality.
- The monitor uses `claude -p` with `--dangerously-skip-permissions` so fixes run unattended. Review the log to see what was changed.
- If the same error keeps recurring, the retry limit will stop the loop. Check `.doctorsnake.log` for details.

## License

MIT
