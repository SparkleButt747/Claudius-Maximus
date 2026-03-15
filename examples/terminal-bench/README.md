# Terminal-Bench 2.0 Example

This example shows how to run the Claudius-Maximus harness against [Terminal-Bench 2.0](https://github.com/terminal-bench/terminal-bench), a benchmark of 89 real-world terminal tasks spanning SWE, debugging, data science, ML, security, sysadmin, and more.

## Quick Start

```bash
# Install Harbor
pip install harbor  # or: uv tool install harbor

# Set your API key
export ANTHROPIC_API_KEY=sk-ant-...

# Run the full benchmark
bash examples/terminal-bench/run.sh

# Run a subset (5 tasks)
bash examples/terminal-bench/run.sh -l 5

# Run specific tasks
bash examples/terminal-bench/run.sh -t "python-*"
```

## Configuration

Edit `run.sh` or override via environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `MODEL` | `claude-opus-4-6` | Claude model to use |
| `PARALLEL` | `4` | Concurrent tasks |
| `MAX_TURNS` | `200` | Max tool calls per task |
| `ENV` | `docker` | `docker` or `daytona` |

## Results

After a run completes:

```bash
# Summary
python harness/analyze.py harness/jobs/<job-name>/

# Detailed with failures
python harness/analyze.py harness/jobs/<job-name>/ --verbose --failures

# Best-of across multiple runs
python harness/analyze.py harness/jobs/ --aggregate
```

## What We Achieved

Using the Claudius-Maximus harness with Claude Opus 4.6, we achieved **100% (89/89)** on Terminal-Bench 2.0. The `archive/` directory contains the run configurations that got us there.
