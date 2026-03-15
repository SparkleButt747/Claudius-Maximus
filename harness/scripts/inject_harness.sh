#!/bin/bash
# Inject the Claudius-Maximus harness into a container's working directory.
# Run as a setup command in Harbor agent config.
#
# Usage: bash inject_harness.sh [task_dir]

set -euo pipefail

TASK_DIR="${1:-/app}"
HARNESS_DIR="$TASK_DIR/.claude-harness"

echo "[harness] Injecting Claudius-Maximus optimization harness..."

# Create directories
mkdir -p "$HARNESS_DIR/hooks"
mkdir -p "$TASK_DIR/.claude"

# === CLAUDE.md (primary optimization lever) ===
if [ -f "/harness/CLAUDE.md" ]; then
    cp /harness/CLAUDE.md "$TASK_DIR/CLAUDE.md"
else
    cat > "$TASK_DIR/CLAUDE.md" << 'CLAUDEMD'
# Autonomous Agent Instructions

You are an autonomous terminal agent. Follow this MANDATORY workflow:

## Phase 0: Bootstrap
Run first: `uname -a && which python3 node gcc rustc go make 2>/dev/null && ls -la /app/`

## Phase 1: Understand
1. `cat /app/instruction.md`
2. `cat /app/tests/test.sh 2>/dev/null; cat /app/tests/test_*.py 2>/dev/null`
3. Tests define success. READ THEM.

## Phase 2: Plan
Write a numbered plan (5-15 steps) BEFORE implementing.

## Phase 3: Execute
- Non-interactive installs: `DEBIAN_FRONTEND=noninteractive apt-get install -y`
- After 2 failures on same approach, switch approach entirely
- Use `timeout 120 <cmd>` for potentially hanging commands

## Phase 4: Verify (MANDATORY)
```bash
cd /app && bash tests/test.sh
```
NEVER stop without running verification. Fix failures and re-verify.

## Rules
- NEVER ask questions
- NEVER stop without verification
- Working 80% > failed 100%
- Read test files first
CLAUDEMD
fi

# === Hooks ===
if [ -f "/harness/hooks/guardian.py" ]; then
    cp /harness/hooks/guardian.py "$HARNESS_DIR/hooks/"
else
    # Inline fallback hook — protocol-compatible
    cat > "$HARNESS_DIR/hooks/guardian.py" << 'HOOKPY'
#!/usr/bin/env python3
import json, sys, time
from pathlib import Path

STATE = Path("/tmp/.guardian_state.json")

VERIFY_PATTERNS = ["tests/test.sh", "pytest", "test_", "make test", "cargo test", "npm test"]
SUCCESS_PATTERNS = ["passed", " ok", "0 failed", "tests passed", "PASS", "OK ("]

def load():
    try: return json.loads(STATE.read_text())
    except: return {"verification_attempted": False, "verification_passed": False, "turn_count": 0, "file_edits": {}, "consecutive_failures": 0, "last_error_sig": "", "stop_block_count": 0}

def save(s):
    try: STATE.write_text(json.dumps(s))
    except: pass

def detect_type(d):
    if "tool_output" in d: return "PostToolUse"
    if "tool_name" in d: return "PreToolUse"
    return "Stop"

def main():
    try: inp = json.load(sys.stdin)
    except: inp = {}
    state = load()
    hook_type = detect_type(inp)

    if hook_type == "PreToolUse":
        state["turn_count"] = state.get("turn_count", 0) + 1
        tool = inp.get("tool_name", "")
        ti = inp.get("tool_input", {})
        if tool in ("Edit", "Write"):
            fp = ti.get("file_path", "?")
            state["file_edits"][fp] = state["file_edits"].get(fp, 0) + 1
        if tool == "Bash":
            cmd = ti.get("command", "")
            if any(p in cmd for p in VERIFY_PATTERNS):
                if not state.get("verification_attempted"):
                    state["stop_block_count"] = 0
                state["verification_attempted"] = True
        save(state)
        json.dump({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow", "permissionDecisionReason": "[guardian]"}}, sys.stdout)

    elif hook_type == "PostToolUse":
        tool_output = str(inp.get("tool_output", ""))
        if state.get("verification_attempted") and any(k in tool_output for k in SUCCESS_PATTERNS):
            state["verification_passed"] = True
        save(state)
        # Loop warnings
        warnings = []
        for fp, cnt in state.get("file_edits", {}).items():
            if cnt >= 4:
                warnings.append(f"[guardian] {fp} edited {cnt}x — try different approach")
        if state.get("consecutive_failures", 0) >= 3:
            warnings.append("[guardian] 3+ consecutive failures — switch strategy")
        if warnings:
            json.dump({"hookSpecificOutput": {"hookEventName": "PostToolUse", "notification": " | ".join(warnings)}}, sys.stdout)
        else:
            json.dump({}, sys.stdout)

    elif hook_type == "Stop":
        if not state.get("verification_attempted"):
            state["stop_block_count"] = state.get("stop_block_count", 0) + 1
            save(state)
            if state["stop_block_count"] >= 3:
                json.dump({}, sys.stdout)
            else:
                json.dump({"hookSpecificOutput": {"hookEventName": "Stop", "notification": "[guardian] BLOCKED: Run tests first: cd /app && bash tests/test.sh"}}, sys.stdout)
        elif not state.get("verification_passed"):
            state["stop_block_count"] = state.get("stop_block_count", 0) + 1
            save(state)
            if state["stop_block_count"] >= 2:
                json.dump({}, sys.stdout)
            else:
                json.dump({"hookSpecificOutput": {"hookEventName": "Stop", "notification": "[guardian] Tests may have failed. Fix and re-run."}}, sys.stdout)
        else:
            json.dump({}, sys.stdout)
    else:
        json.dump({}, sys.stdout)

if __name__ == "__main__":
    main()
HOOKPY
    chmod +x "$HARNESS_DIR/hooks/guardian.py"
fi

# === Claude Code settings (hooks + permissions) ===
cat > "$TASK_DIR/.claude/settings.json" << 'SETTINGS'
{
  "permissions": {
    "allow": ["Bash(*)", "Read(*)", "Write(*)", "Edit(*)", "Glob(*)", "Grep(*)"]
  },
  "hooks": {
    "PreToolUse": [
      {"matcher": "", "hooks": [{"type": "command", "command": "python3 /app/.claude-harness/hooks/guardian.py", "timeout": 5}]}
    ],
    "PostToolUse": [
      {"matcher": "Bash", "hooks": [{"type": "command", "command": "python3 /app/.claude-harness/hooks/guardian.py", "timeout": 5}]}
    ],
    "Stop": [
      {"matcher": "", "hooks": [{"type": "command", "command": "python3 /app/.claude-harness/hooks/guardian.py", "timeout": 5}]}
    ]
  }
}
SETTINGS

echo "[harness] Injection complete. Files:"
ls -la "$TASK_DIR/CLAUDE.md" "$TASK_DIR/.claude/settings.json" "$HARNESS_DIR/hooks/" 2>/dev/null
echo "[harness] Ready for benchmark execution."
