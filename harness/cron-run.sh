#!/bin/bash
# Claudius-Maximus Cron Runner
#
# Runs the full benchmark and logs results.
# Designed to be called from cron or launchd.
#
# Usage (manual):
#   ./cron-run.sh
#
# Cron example (nightly at 2am):
#   0 2 * * * /path/to/Claudius-Maximus/harness/cron-run.sh >> /path/to/logs/cron.log 2>&1

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
JOB_NAME="cron-${TIMESTAMP}"
LOG_FILE="$LOG_DIR/${JOB_NAME}.log"

echo "[$TIMESTAMP] Starting cron run: $JOB_NAME" | tee "$LOG_FILE"

# Run the benchmark
JOB_NAME="$JOB_NAME" "$SCRIPT_DIR/run.sh" 2>&1 | tee -a "$LOG_FILE"

# Analyze results
echo "" | tee -a "$LOG_FILE"
echo "[$TIMESTAMP] Analyzing results..." | tee -a "$LOG_FILE"
python3 "$SCRIPT_DIR/analyze.py" "$SCRIPT_DIR/jobs/$JOB_NAME" --verbose 2>&1 | tee -a "$LOG_FILE"

# Optional: send notification (macOS)
SCORE=$(python3 "$SCRIPT_DIR/analyze.py" "$SCRIPT_DIR/jobs/$JOB_NAME" 2>/dev/null | grep "^Score:" | head -1 || echo "Score: ?")
osascript -e "display notification \"$SCORE\" with title \"Benchmark Complete\" subtitle \"$JOB_NAME\"" 2>/dev/null || true

echo "[$TIMESTAMP] Done." | tee -a "$LOG_FILE"
