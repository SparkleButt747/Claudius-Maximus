#!/bin/bash
# Local test harness — validates the optimization setup works
# before running against a real benchmark.
#
# Creates a mock task, runs Claude Code with the optimized CLAUDE.md,
# and checks if the agent follows the expected workflow.
#
# Usage: ./scripts/local_test.sh [--task simple|medium|hard]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_DIR="$(dirname "$SCRIPT_DIR")"
TASK_LEVEL="${1:---task}"
TASK_TYPE="${2:-simple}"

# Create a temp directory to simulate a container
MOCK_DIR=$(mktemp -d)
trap "rm -rf $MOCK_DIR" EXIT

echo "=== Local Test Harness ==="
echo "Mock task dir: $MOCK_DIR"
echo "Task type: $TASK_TYPE"
echo ""

# Copy CLAUDE.md
cp "$HARNESS_DIR/CLAUDE.md" "$MOCK_DIR/CLAUDE.md"
mkdir -p "$MOCK_DIR/.claude"
cp "$HARNESS_DIR/.claude/settings.json" "$MOCK_DIR/.claude/settings.json"

# Create mock task based on difficulty
case "$TASK_TYPE" in
    simple)
        cat > "$MOCK_DIR/instruction.md" << 'EOF'
# Task: Create a Python Calculator

Create a Python script at `/app/calculator.py` that implements a basic calculator with the following functions:
- `add(a, b)` — returns a + b
- `subtract(a, b)` — returns a - b
- `multiply(a, b)` — returns a * b
- `divide(a, b)` — returns a / b (raise ValueError for division by zero)

The script should also be runnable from the command line:
```
python3 calculator.py add 2 3
# Output: 5.0
```
EOF
        mkdir -p "$MOCK_DIR/tests"
        cat > "$MOCK_DIR/tests/test.sh" << 'TESTEOF'
#!/bin/bash
set -e

# Check file exists
test -f /app/calculator.py || { echo "FAIL: calculator.py not found"; exit 1; }

# Run pytest
cd /app
python3 -c "
from calculator import add, subtract, multiply, divide
assert add(2, 3) == 5
assert subtract(5, 3) == 2
assert multiply(3, 4) == 12
assert divide(10, 2) == 5.0
try:
    divide(1, 0)
    assert False, 'Should have raised ValueError'
except ValueError:
    pass
print('All tests passed')
"

# Check CLI
result=$(python3 calculator.py add 2 3)
test "$result" = "5.0" || { echo "FAIL: CLI output wrong: $result"; exit 1; }

echo "PASS"
TESTEOF
        chmod +x "$MOCK_DIR/tests/test.sh"
        ;;

    medium)
        cat > "$MOCK_DIR/instruction.md" << 'EOF'
# Task: Build a REST API

Create a Flask REST API at `/app/api.py` with these endpoints:
- GET /health — returns {"status": "ok"}
- POST /echo — returns the JSON body it receives
- GET /fibonacci/<n> — returns {"result": <nth fibonacci number>}

The API should run on port 5000.
Start the server with: `python3 api.py`
EOF
        mkdir -p "$MOCK_DIR/tests"
        cat > "$MOCK_DIR/tests/test.sh" << 'TESTEOF'
#!/bin/bash
set -e

test -f /app/api.py || { echo "FAIL: api.py not found"; exit 1; }

# Start server in background
cd /app
python3 api.py &
SERVER_PID=$!
sleep 2

# Test health
HEALTH=$(curl -s http://localhost:5000/health)
echo "$HEALTH" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d['status']=='ok'" || { kill $SERVER_PID; echo "FAIL: health check"; exit 1; }

# Test echo
ECHO=$(curl -s -X POST -H "Content-Type: application/json" -d '{"msg":"hello"}' http://localhost:5000/echo)
echo "$ECHO" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d['msg']=='hello'" || { kill $SERVER_PID; echo "FAIL: echo"; exit 1; }

# Test fibonacci
FIB=$(curl -s http://localhost:5000/fibonacci/10)
echo "$FIB" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d['result']==55" || { kill $SERVER_PID; echo "FAIL: fibonacci"; exit 1; }

kill $SERVER_PID
echo "PASS"
TESTEOF
        chmod +x "$MOCK_DIR/tests/test.sh"
        ;;

    hard)
        cat > "$MOCK_DIR/instruction.md" << 'EOF'
# Task: Implement a Mini Compiler

Create a compiler at `/app/compiler.py` that compiles a simple language to Python bytecode.

The language supports:
- Integer literals: `42`
- Variables: `x = 5`
- Arithmetic: `+`, `-`, `*`, `/`
- Print: `print(expr)`
- If/else: `if expr { ... } else { ... }`
- While loops: `while expr { ... }`

Example program:
```
x = 10
while x {
    print(x)
    x = x - 1
}
```

Usage: `python3 compiler.py program.txt` should execute the program and print output to stdout.
EOF
        mkdir -p "$MOCK_DIR/tests"
        cat > "$MOCK_DIR/tests/test.sh" << 'TESTEOF'
#!/bin/bash
set -e

test -f /app/compiler.py || { echo "FAIL: compiler.py not found"; exit 1; }

# Test 1: Simple print
echo 'print(42)' > /tmp/test1.txt
RESULT=$(python3 /app/compiler.py /tmp/test1.txt)
test "$RESULT" = "42" || { echo "FAIL: test1 expected '42', got '$RESULT'"; exit 1; }

# Test 2: Variable + arithmetic
cat > /tmp/test2.txt << 'PROG'
x = 5
y = 3
print(x + y)
PROG
RESULT=$(python3 /app/compiler.py /tmp/test2.txt)
test "$RESULT" = "8" || { echo "FAIL: test2 expected '8', got '$RESULT'"; exit 1; }

# Test 3: While loop
cat > /tmp/test3.txt << 'PROG'
x = 3
while x {
    print(x)
    x = x - 1
}
PROG
RESULT=$(python3 /app/compiler.py /tmp/test3.txt)
EXPECTED=$'3\n2\n1'
test "$RESULT" = "$EXPECTED" || { echo "FAIL: test3 expected countdown, got '$RESULT'"; exit 1; }

echo "PASS"
TESTEOF
        chmod +x "$MOCK_DIR/tests/test.sh"
        ;;

    *)
        echo "Unknown task type: $TASK_TYPE (use simple, medium, or hard)"
        exit 1
        ;;
esac

echo "[*] Mock task created at $MOCK_DIR"
echo "[*] Instruction:"
cat "$MOCK_DIR/instruction.md"
echo ""
echo "[*] Test script:"
cat "$MOCK_DIR/tests/test.sh"
echo ""
echo "---"
echo ""
echo "To test with Claude Code (agentic mode):"
echo "  cd $MOCK_DIR && claude --dangerously-skip-permissions --max-turns 200 --prompt 'Read CLAUDE.md and instruction.md, then solve the task following the CLAUDE.md workflow. BEGIN.'"
echo ""
echo "Quick test (just validate harness injection):"
echo "  bash $HARNESS_DIR/scripts/inject_harness.sh $MOCK_DIR && cat $MOCK_DIR/.claude/settings.json"
