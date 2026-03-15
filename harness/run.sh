#!/bin/bash
# Claudius-Maximus Harness Runner
#
# Usage:
#   ./run.sh                          # Run all tasks
#   ./run.sh -l 5                     # Run 5 tasks
#   ./run.sh -t "python-*"            # Run tasks matching glob
#   ./run.sh -l 1 --debug             # Debug with 1 task
#
# Environment variables:
#   MODEL    — Claude model (default: claude-opus-4-6)
#   PARALLEL — Concurrent tasks (default: 4)
#   ENV      — docker or daytona (default: docker)
#   DATASET  — Harbor dataset (default: terminal-bench@2.0)
#   MAX_TURNS — Max tool calls per task (default: 200)
#   AGENT_CLASS — Agent class to use (default: CMClaudeCode)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PATH="$HOME/.local/bin:$PATH"

MODEL="${MODEL:-claude-opus-4-6}"
PARALLEL="${PARALLEL:-4}"
export CLAUDE_CODE_MAX_OUTPUT_TOKENS="${CLAUDE_CODE_MAX_OUTPUT_TOKENS:-100000}"
ENV="${ENV:-docker}"
DATASET="${DATASET:-terminal-bench@2.0}"
MAX_TURNS="${MAX_TURNS:-200}"
AGENT_TIMEOUT_MULT="${AGENT_TIMEOUT_MULT:-3.0}"
AGENT_CLASS="${AGENT_CLASS:-CMClaudeCode}"
JOB_NAME="${JOB_NAME:-cm-$(date +%Y%m%d-%H%M%S)}"

echo "=== Claudius-Maximus Harness ==="
echo "Dataset:    $DATASET"
echo "Model:      $MODEL"
echo "Agent:      $AGENT_CLASS"
echo "Parallel:   $PARALLEL"
echo "Env:        $ENV"
echo "Max turns:  $MAX_TURNS"
echo "Timeout:    ${AGENT_TIMEOUT_MULT}x"
echo "Job name:   $JOB_NAME"
echo ""

# Check dependencies
command -v harbor &>/dev/null || { echo "ERROR: harbor not found. Run: uv tool install harbor"; exit 1; }

# Verify harness files
for f in CLAUDE.md hooks/guardian.py agent.py; do
    [ -f "$SCRIPT_DIR/$f" ] || { echo "ERROR: Missing $SCRIPT_DIR/$f"; exit 1; }
done

# Add harness directory to Python path so Harbor can import agent.py
export PYTHONPATH="${SCRIPT_DIR}:${PYTHONPATH:-}"

# Auth: prefer ANTHROPIC_API_KEY, fall back to OAuth token from macOS keychain
if [ -z "${ANTHROPIC_API_KEY:-}" ] && [ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
    OAUTH_TOKEN=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null | \
        python3 -c "import sys,json; print(json.loads(sys.stdin.read()).get('claudeAiOauth',{}).get('accessToken',''))" 2>/dev/null || echo "")
    if [ -n "$OAUTH_TOKEN" ]; then
        export CLAUDE_CODE_OAUTH_TOKEN="$OAUTH_TOKEN"
        echo "[*] Using OAuth token from macOS keychain"
    else
        echo "ERROR: No ANTHROPIC_API_KEY or OAuth token found"
        echo "  Set ANTHROPIC_API_KEY=sk-ant-... or log in with 'claude login'"
        exit 1
    fi
fi

echo "[*] Running benchmark..."
echo ""

harbor run \
    -d "$DATASET" \
    --agent-import-path "agent:$AGENT_CLASS" \
    -m "anthropic/$MODEL" \
    -e "$ENV" \
    -n "$PARALLEL" \
    --job-name "$JOB_NAME" \
    --ak "max_turns=$MAX_TURNS" \
    --ak "reasoning_effort=high" \
    --agent-timeout-multiplier "$AGENT_TIMEOUT_MULT" \
    -o "$SCRIPT_DIR/jobs" \
    "$@"

echo ""
echo "=== Run complete ==="
echo "Results: $SCRIPT_DIR/jobs/$JOB_NAME/"
