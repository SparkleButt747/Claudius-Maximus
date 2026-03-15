#!/bin/bash
# Claudius-Maximus Pre-Completion Verification
# Finds and runs the test suite, reporting PASS/FAIL.
# Handles: test.sh, pytest, Makefile, cargo test, go test, npm test

set -euo pipefail

TASK_DIR="${1:-/app}"
PASS=true

echo "=== PRE-COMPLETION VERIFICATION ==="

# Priority 1: test.sh (most common in benchmarks)
if [ -f "$TASK_DIR/tests/test.sh" ]; then
    echo "[*] Running tests/test.sh..."
    cd "$TASK_DIR"
    if bash tests/test.sh; then
        echo "[PASS] test.sh passed"
    else
        echo "[FAIL] test.sh failed (exit $?)"
        PASS=false
    fi

# Priority 2: pytest
elif ls "$TASK_DIR/tests/test_"*.py "$TASK_DIR/tests/"*.py 2>/dev/null | head -1 >/dev/null 2>&1; then
    echo "[*] Running pytest..."
    cd "$TASK_DIR"
    if python3 -m pytest tests/ -v 2>&1; then
        echo "[PASS] pytest passed"
    else
        echo "[FAIL] pytest failed (exit $?)"
        PASS=false
    fi

# Priority 3: Makefile with test target
elif [ -f "$TASK_DIR/Makefile" ] && grep -q "^test:" "$TASK_DIR/Makefile" 2>/dev/null; then
    echo "[*] Running make test..."
    cd "$TASK_DIR"
    if make test; then
        echo "[PASS] make test passed"
    else
        echo "[FAIL] make test failed (exit $?)"
        PASS=false
    fi

# Priority 4: Cargo test (Rust)
elif [ -f "$TASK_DIR/Cargo.toml" ]; then
    echo "[*] Running cargo test..."
    cd "$TASK_DIR"
    if cargo test 2>&1; then
        echo "[PASS] cargo test passed"
    else
        echo "[FAIL] cargo test failed"
        PASS=false
    fi

# Priority 5: Go test
elif ls "$TASK_DIR/"*_test.go 2>/dev/null | head -1 >/dev/null 2>&1; then
    echo "[*] Running go test..."
    cd "$TASK_DIR"
    if go test ./... 2>&1; then
        echo "[PASS] go test passed"
    else
        echo "[FAIL] go test failed"
        PASS=false
    fi

# Priority 6: npm test
elif [ -f "$TASK_DIR/package.json" ] && grep -q '"test"' "$TASK_DIR/package.json" 2>/dev/null; then
    echo "[*] Running npm test..."
    cd "$TASK_DIR"
    if npm test 2>&1; then
        echo "[PASS] npm test passed"
    else
        echo "[FAIL] npm test failed"
        PASS=false
    fi

else
    echo "[WARN] No standard test suite found in $TASK_DIR"
    echo "[*] Listing files for manual verification:"
    ls -la "$TASK_DIR/"
fi

echo ""
if [ "$PASS" = true ]; then
    echo "=== VERIFICATION: PASS ==="
else
    echo "=== VERIFICATION: FAIL ==="
    exit 1
fi
