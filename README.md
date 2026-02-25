# snakerail

Auto-fix your Snakemake pipeline errors with Claude Code.

## How It Works

1. Creates a git branch (`snakerail/YYYYMMDD-HHMMSS`)
2. Runs Snakemake; on success prints the healing git log and exits
3. On error, invokes Claude Code to diagnose, fix, and commit the code
4. Repeats until the pipeline succeeds or `--max-retries` is hit

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (`claude` on PATH)
- [Snakemake](https://snakemake.readthedocs.io/)

## Installation

```bash
git clone https://github.com/skojaku/snakerail.git
chmod +x snakerail 
export PATH="$PATH:<the directory filepath>/snakerail"   # add to ~/.bashrc or ~/.zshrc
```

Run the script from your Snakemake project root (where your `Snakefile` lives).

## Usage

```bash
cd /path/to/your/snakemake/project

snakerail                          # run with defaults
snakerail --cores 4 -p             # pass flags to snakemake
snakerail --max-retries 5          # limit fix attempts
snakerail --branch my-experiment   # custom branch name
```

`--max-retries` and `--branch` are snakerail flags; everything else is forwarded to Snakemake.

## Tips

- Add a `CLAUDE.md` to your project root to help Claude understand the codebase — this improves fix quality significantly.
- All fixes are committed on the healing branch; use `git log` or `git diff main` to review what changed.

## License

MIT
