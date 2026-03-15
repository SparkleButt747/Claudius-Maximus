#!/bin/bash
# Run-9: Retry 17 OAuth-expired tasks + 8 real failures from run-8
#
# OAuth failures (17): never ran due to token expiration mid-run-8
#   git-leak-recovery, build-cython-ext, pytorch-model-recovery,
#   model-extraction-relu-logits, nginx-request-logging, sparql-university,
#   large-scale-text-editing, sqlite-db-truncate, sanitize-git-repo,
#   build-pmars, rstan-to-pystan, sqlite-with-gcov, openssl-selfsigned-cert,
#   constraints-scheduling, dna-insert, vulnerable-secret, dna-assembly
#
# Real failures retried with updated CLAUDE.md (8):
#   adaptive-rejection-sampler (Rule 17 updated)
#   configure-git-webserver (Rule 2 strengthened)
#   polyglot-c-py (Rule 4 strengthened)
#   raman-fitting, extract-elf, financial-document-processor,
#   filter-js-from-html, cancel-async-tasks
#
# Settings: same as run-8 (PARALLEL=1, 8GB, reasoning_effort=high)

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
JOB_NAME="${JOB_NAME:-run-9-$(date +%Y%m%d-%H%M%S)}"

echo "=== Terminal-Bench Run-9 (OAuth Retry + Real Failures) ==="
echo "Model:      $MODEL"
echo "Parallel:   $PARALLEL"
echo "Env:        $ENV"
echo "Max turns:  $MAX_TURNS"
echo "Timeout:    ${AGENT_TIMEOUT_MULT}x"
echo "Memory:     8192 MB"
echo "Job name:   $JOB_NAME"
echo "Running:    25 tasks (17 OAuth retry + 8 real failure retry)"
echo ""

# Check dependencies
command -v harbor &>/dev/null || { echo "ERROR: harbor not found"; exit 1; }

for f in CLAUDE.md hooks/tbench_hooks.py agent.py; do
    [ -f "$SCRIPT_DIR/$f" ] || { echo "ERROR: Missing $SCRIPT_DIR/$f"; exit 1; }
done

export PYTHONPATH="${SCRIPT_DIR}:${PYTHONPATH:-}"

# Auth — always fetch fresh token
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

echo "[*] Running Terminal-Bench run-9 (OAuth retry + real failures)..."
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
    -x "bn-fit-modify" \
    -x "break-filter-js-from-html" \
    -x "build-pov-ray" \
    -x "caffe-cifar-10" \
    -x "chess-best-move" \
    -x "circuit-fibsqrt" \
    -x "cobol-modernization" \
    -x "code-from-image" \
    -x "compile-compcert" \
    -x "count-dataset-tokens" \
    -x "crack-7z-hash" \
    -x "custom-memory-heap-crash" \
    -x "db-wal-recovery" \
    -x "distribution-search" \
    -x "extract-moves-from-video" \
    -x "feal-differential-cryptanalysis" \
    -x "feal-linear-cryptanalysis" \
    -x "fix-code-vulnerability" \
    -x "fix-git" \
    -x "fix-ocaml-gc" \
    -x "gcode-to-text" \
    -x "git-multibranch" \
    -x "gpt2-codegolf" \
    -x "headless-terminal" \
    -x "hf-model-inference" \
    -x "install-windows-3.11" \
    -x "kv-store-grpc" \
    -x "largest-eigenval" \
    -x "llm-inference-batching-scheduler" \
    -x "log-summary-date-ranges" \
    -x "mailman" \
    -x "make-doom-for-mips" \
    -x "make-mips-interpreter" \
    -x "mcmc-sampling-stan" \
    -x "merge-diff-arc-agi-task" \
    -x "modernize-scientific-stack" \
    -x "mteb-leaderboard" \
    -x "mteb-retrieve" \
    -x "multi-source-data-merger" \
    -x "overfull-hbox" \
    -x "password-recovery" \
    -x "path-tracing" \
    -x "path-tracing-reverse" \
    -x "polyglot-rust-c" \
    -x "portfolio-optimization" \
    -x "protein-assembly" \
    -x "prove-plus-comm" \
    -x "pypi-server" \
    -x "pytorch-model-cli" \
    -x "qemu-alpine-ssh" \
    -x "qemu-startup" \
    -x "query-optimize" \
    -x "regex-chess" \
    -x "regex-log" \
    -x "reshard-c4-data" \
    -x "sam-cell-seg" \
    -x "schemelike-metacircular-eval" \
    -x "torch-pipeline-parallelism" \
    -x "torch-tensor-parallelism" \
    -x "train-fasttext" \
    -x "tune-mjcf" \
    -x "video-processing" \
    -x "winning-avg-corewars" \
    -x "write-compressor" \
    "$@"

echo ""
echo "=== Run-9 complete ==="
echo "Results: $SCRIPT_DIR/jobs/$JOB_NAME/"
echo "Analyze: python3 analyze.py $SCRIPT_DIR/jobs/$JOB_NAME/ --verbose"
