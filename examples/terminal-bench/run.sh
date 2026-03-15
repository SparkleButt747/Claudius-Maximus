#!/bin/bash
# Terminal-Bench 2.0 — Example run configuration
#
# Prerequisites:
#   pip install harbor    # or: uv tool install harbor
#   export ANTHROPIC_API_KEY=sk-ant-...
#
# Usage:
#   cd Claudius-Maximus/
#   bash examples/terminal-bench/run.sh

export DATASET="terminal-bench@2.0"
export MODEL="claude-opus-4-6"
export PARALLEL=4
export MAX_TURNS=200
export ENV=docker
export AGENT_CLASS=CMClaudeCode

exec bash "$(dirname "$0")/../../harness/run.sh" "$@"
