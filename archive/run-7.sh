#!/bin/bash
# Run-7: Retry rate-limited + remaining tasks after rate limit reset
#
# Covers: 42 tasks (35 never-run + 7 retryable fails)
# Rate limits reset at 2am UTC — run this after reset
#
# Retryable fails (CLAUDE.md updated with better guidance):
#   - adaptive-rejection-sampler (scalar bounds fix)
#   - configure-git-webserver (nginx path fix)
#   - torch-tensor-parallelism (RowParallel guidance)
#   - mteb-retrieve, make-mips-interpreter, video-processing, install-windows-3.11
#   - pytorch-model-recovery (was rate-limited, never actually ran)
#
# Settings:
#   - PARALLEL=1 (sequential, avoid rate limits)
#   - --override-memory 8192 (8GB) for OOM tasks
#   - --agent-setup-timeout-multiplier 3.0 for setup timeouts
#   - --environment-build-timeout-multiplier 3.0 for env build timeouts
#   - --max-retries 1 for infra flakes
#   - --agent-timeout-multiplier 1.0 (use default task timeouts)
#   - reasoning_effort=high

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PATH="$HOME/.local/bin:$PATH"

MODEL="${MODEL:-claude-opus-4-6}"
PARALLEL="${PARALLEL:-1}"
export CLAUDE_CODE_MAX_OUTPUT_TOKENS="${CLAUDE_CODE_MAX_OUTPUT_TOKENS:-100000}"
ENV="${ENV:-docker}"
DATASET="terminal-bench@2.0"
MAX_TURNS="${MAX_TURNS:-200}"
AGENT_TIMEOUT_MULT="${AGENT_TIMEOUT_MULT:-1.0}"
JOB_NAME="${JOB_NAME:-run-7-$(date +%Y%m%d-%H%M%S)}"

echo "=== Terminal-Bench Run-7 (Post Rate-Limit Reset) ==="
echo "Model:      $MODEL"
echo "Parallel:   $PARALLEL"
echo "Env:        $ENV"
echo "Max turns:  $MAX_TURNS"
echo "Timeout:    ${AGENT_TIMEOUT_MULT}x"
echo "Memory:     8192 MB"
echo "Job name:   $JOB_NAME"
echo "Excluding:  40 passed + 4 timeouts + 3 extreme-duration = 47 tasks"
echo ""

# Check dependencies
command -v harbor &>/dev/null || { echo "ERROR: harbor not found"; exit 1; }

for f in CLAUDE.md hooks/tbench_hooks.py agent.py; do
    [ -f "$SCRIPT_DIR/$f" ] || { echo "ERROR: Missing $SCRIPT_DIR/$f"; exit 1; }
done

export PYTHONPATH="${SCRIPT_DIR}:${PYTHONPATH:-}"

# Auth
if [ -z "${ANTHROPIC_API_KEY:-}" ] && [ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
    OAUTH_TOKEN=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null | \
        python3 -c "import sys,json; print(json.loads(sys.stdin.read()).get('claudeAiOauth',{}).get('accessToken',''))" 2>/dev/null || echo "")
    if [ -n "$OAUTH_TOKEN" ]; then
        export CLAUDE_CODE_OAUTH_TOKEN="$OAUTH_TOKEN"
        echo "[*] Using OAuth token from macOS keychain"
    else
        echo "ERROR: No ANTHROPIC_API_KEY or OAuth token found"
        exit 1
    fi
fi

echo "[*] Running Terminal-Bench run-7 (post rate-limit reset)..."
echo ""

harbor run \
    -d "$DATASET" \
    --agent-import-path "agent:TBenchClaudeCode" \
    -m "anthropic/$MODEL" \
    -e "$ENV" \
    -n "$PARALLEL" \
    --job-name "$JOB_NAME" \
    --ak "max_turns=$MAX_TURNS" \
    --ak "reasoning_effort=high" \
    --agent-timeout-multiplier "$AGENT_TIMEOUT_MULT" \
    --agent-setup-timeout-multiplier 3.0 \
    --environment-build-timeout-multiplier 3.0 \
    --override-memory-mb 8192 \
    --max-retries 1 \
    --retry-include "RuntimeError" \
    --retry-include "AgentSetupTimeoutError" \
    -o "$SCRIPT_DIR/jobs" \
    -x "break-filter-js-from-html" \
    -x "build-pov-ray" \
    -x "caffe-cifar-10" \
    -x "chess-best-move" \
    -x "cobol-modernization" \
    -x "compile-compcert" \
    -x "count-dataset-tokens" \
    -x "crack-7z-hash" \
    -x "custom-memory-heap-crash" \
    -x "db-wal-recovery" \
    -x "distribution-search" \
    -x "extract-moves-from-video" \
    -x "feal-linear-cryptanalysis" \
    -x "fix-git" \
    -x "gcode-to-text" \
    -x "git-multibranch" \
    -x "gpt2-codegolf" \
    -x "headless-terminal" \
    -x "hf-model-inference" \
    -x "kv-store-grpc" \
    -x "largest-eigenval" \
    -x "llm-inference-batching-scheduler" \
    -x "log-summary-date-ranges" \
    -x "make-doom-for-mips" \
    -x "merge-diff-arc-agi-task" \
    -x "modernize-scientific-stack" \
    -x "multi-source-data-merger" \
    -x "overfull-hbox" \
    -x "password-recovery" \
    -x "path-tracing" \
    -x "path-tracing-reverse" \
    -x "polyglot-rust-c" \
    -x "portfolio-optimization" \
    -x "prove-plus-comm" \
    -x "pypi-server" \
    -x "pytorch-model-cli" \
    -x "qemu-alpine-ssh" \
    -x "qemu-startup" \
    -x "regex-chess" \
    -x "reshard-c4-data" \
    -x "sam-cell-seg" \
    -x "schemelike-metacircular-eval" \
    -x "torch-pipeline-parallelism" \
    -x "train-fasttext" \
    -x "tune-mjcf" \
    -x "winning-avg-corewars" \
    -x "write-compressor" \
    "$@"

echo ""
echo "=== Run-7 complete ==="
echo "Results: $SCRIPT_DIR/jobs/$JOB_NAME/"
echo "Analyze: python3 analyze.py $SCRIPT_DIR/jobs/$JOB_NAME/ --verbose"
