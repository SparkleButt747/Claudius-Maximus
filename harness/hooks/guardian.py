#!/usr/bin/env python3
"""
Task Guardian — execution quality hooks for autonomous agent sessions.

Handles three hook events via stdin payload:
- PreToolUse: tracks turn count, file edits, verification attempts
- PostToolUse: error/loop detection, turn budget warnings
- Stop: blocks exit if verification hasn't been attempted

Protocol:
  Input: JSON via stdin
  Output: JSON via stdout wrapped in {"hookSpecificOutput": {...}}

State persisted in /tmp/.task_guardian_state.json.

Configuration via environment variables:
  TASK_GUARDIAN_MAX_TURNS          — max turns before forced stop (default: 200)
  TASK_GUARDIAN_EARLY_VERIFY_PCT   — % at which to suggest verification (default: 0.2)
  TASK_GUARDIAN_WARN_PCT           — % at which to warn (default: 0.5)
  TASK_GUARDIAN_CRITICAL_PCT       — % at which to demand verification (default: 0.6)
  TASK_GUARDIAN_LATE_PCT           — % at which to urge wrap-up (default: 0.75)
  TASK_GUARDIAN_MAX_FILE_EDITS     — loop detection threshold per file (default: 4)
  TASK_GUARDIAN_MAX_FAILURES       — consecutive same-error threshold (default: 3)
  TASK_GUARDIAN_MAX_STOP_BLOCKS    — max times to block stop before giving up (default: 3)
"""

from __future__ import annotations

import json
import os
import sys
import time
from pathlib import Path

STATE_FILE = Path("/tmp/.task_guardian_state.json")

# Configurable via environment variables
MAX_TURNS = int(os.environ.get("TASK_GUARDIAN_MAX_TURNS", "200"))
EARLY_VERIFY_PCT = float(os.environ.get("TASK_GUARDIAN_EARLY_VERIFY_PCT", "0.2"))
WARN_PCT = float(os.environ.get("TASK_GUARDIAN_WARN_PCT", "0.5"))
CRITICAL_PCT = float(os.environ.get("TASK_GUARDIAN_CRITICAL_PCT", "0.6"))
LATE_PCT = float(os.environ.get("TASK_GUARDIAN_LATE_PCT", "0.75"))
MAX_FILE_EDITS = int(os.environ.get("TASK_GUARDIAN_MAX_FILE_EDITS", "4"))
MAX_CONSECUTIVE_FAILURES = int(os.environ.get("TASK_GUARDIAN_MAX_FAILURES", "3"))
MAX_STOP_BLOCKS = int(os.environ.get("TASK_GUARDIAN_MAX_STOP_BLOCKS", "3"))

TAG = "[guardian]"

# Patterns indicating verification/test execution
VERIFICATION_PATTERNS = [
    "tests/test.sh",
    "tests/test_",
    "pytest tests/",
    "pytest -v",
    "python -m pytest",
    "python3 -m pytest",
    "make test",
    "cargo test",
    "npm test",
    "go test",
    "bash test",
    "./test.sh",
    "ctest",
    "jest ",
    "mocha ",
    "rspec ",
    "dotnet test",
    "mvn test",
    "gradle test",
]

# Patterns indicating test/build success
SUCCESS_PATTERNS = [
    "passed",
    " ok",
    "0 failed",
    "tests passed",
    "all tests",
    "PASS",
    "OK (",
    "0 errors",
    "Build succeeded",
    "All checks passed",
    "0 failures",
]

# Patterns indicating errors in command output
ERROR_PATTERNS = [
    "error:",
    "Error:",
    "ERROR:",
    "traceback",
    "Traceback",
    "FAILED",
    "not found",
    "No such file",
    "permission denied",
    "Permission denied",
    "command not found",
    "ModuleNotFoundError",
    "ImportError",
    "SyntaxError",
    "NameError",
    "TypeError",
    "ValueError",
    "FileNotFoundError",
    "ConnectionRefusedError",
    "OSError",
    "RuntimeError",
    "segmentation fault",
    "Segmentation fault",
    "core dumped",
    "killed",
    "Killed",
    "AssertionError",
]


def load_state() -> dict:
    if STATE_FILE.exists():
        try:
            return json.loads(STATE_FILE.read_text())
        except (json.JSONDecodeError, OSError):
            pass
    return {
        "start_time": time.time(),
        "turn_count": 0,
        "file_edits": {},
        "verification_attempted": False,
        "verification_passed": False,
        "consecutive_failures": 0,
        "last_error_sig": "",
        "stop_block_count": 0,
    }


def save_state(state: dict) -> None:
    try:
        STATE_FILE.write_text(json.dumps(state))
    except OSError:
        pass


def emit(payload: dict) -> None:
    json.dump(payload, sys.stdout)


def emit_allow(reason: str = "") -> None:
    emit({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "allow",
            "permissionDecisionReason": reason,
        }
    })


def emit_notification(event: str, message: str) -> None:
    emit({
        "hookSpecificOutput": {
            "hookEventName": event,
            "notification": message,
        }
    })


def is_verification_command(cmd: str) -> bool:
    return any(pattern in cmd for pattern in VERIFICATION_PATTERNS)


def detect_hook_type(data: dict) -> str:
    if "tool_output" in data:
        return "PostToolUse"
    if "tool_name" in data:
        return "PreToolUse"
    return "Stop"


def handle_pretool(data: dict) -> None:
    state = load_state()
    state["turn_count"] = state.get("turn_count", 0) + 1

    tool_name = data.get("tool_name", "")
    tool_input = data.get("tool_input", {})

    # Track file edits for loop detection
    if tool_name in ("Edit", "Write"):
        filepath = tool_input.get("file_path", "unknown")
        state["file_edits"][filepath] = state["file_edits"].get(filepath, 0) + 1

    # Track verification attempts
    if tool_name == "Bash":
        cmd = tool_input.get("command", "")
        if is_verification_command(cmd):
            if not state.get("verification_attempted"):
                state["stop_block_count"] = 0
            state["verification_attempted"] = True

    save_state(state)
    emit_allow(TAG)


def handle_posttool(data: dict) -> None:
    state = load_state()

    tool_name = data.get("tool_name", "")
    tool_output = str(data.get("tool_output", ""))

    if tool_name == "Bash":
        # Error detection with signature deduplication
        has_error = any(err in tool_output for err in ERROR_PATTERNS)

        if has_error:
            sig = tool_output[:200]
            if sig == state.get("last_error_sig", ""):
                state["consecutive_failures"] = state.get("consecutive_failures", 0) + 1
            else:
                state["consecutive_failures"] = 1
                state["last_error_sig"] = sig
        else:
            state["consecutive_failures"] = 0

        # Detect verification success
        if state.get("verification_attempted"):
            if any(kw in tool_output for kw in SUCCESS_PATTERNS):
                state["verification_passed"] = True

    save_state(state)

    notifications = []

    # Loop detection: file edited too many times
    for filepath, count in state.get("file_edits", {}).items():
        if count >= MAX_FILE_EDITS:
            notifications.append(
                f"{TAG} WARNING: {filepath} edited {count} times. "
                "STOP editing this file. Re-read the requirements and try "
                "a fundamentally different approach."
            )

    # Consecutive failure detection
    if state.get("consecutive_failures", 0) >= MAX_CONSECUTIVE_FAILURES:
        notifications.append(
            f"{TAG} WARNING: {state['consecutive_failures']} consecutive failures "
            "with the same error. Your current approach is wrong. Switch strategy."
        )

    # Turn budget warnings (percentage-based, configurable)
    turn_count = state.get("turn_count", 0)
    verified = state.get("verification_attempted", False)
    passed = state.get("verification_passed", False)

    if turn_count >= int(MAX_TURNS * CRITICAL_PCT) and not verified:
        notifications.append(
            f"{TAG} CRITICAL: Turn {turn_count}/{MAX_TURNS} without verification. "
            "STOP. Run the tests NOW."
        )
    elif turn_count >= int(MAX_TURNS * EARLY_VERIFY_PCT) and not verified:
        notifications.append(
            f"{TAG} Run verification now to check progress. "
            f"Turn {turn_count}/{MAX_TURNS}."
        )
    elif turn_count >= int(MAX_TURNS * LATE_PCT):
        notifications.append(
            f"{TAG} Turn {turn_count}/{MAX_TURNS}. Running low. "
            "Wrap up — ensure tests pass and stop."
        )
    elif turn_count >= int(MAX_TURNS * WARN_PCT) and not passed:
        notifications.append(
            f"{TAG} Turn {turn_count}/{MAX_TURNS}. Tests not yet passing. "
            "Consider simplifying your approach."
        )

    if notifications:
        emit_notification("PostToolUse", " | ".join(notifications))
    else:
        emit({})


def handle_stop(data: dict) -> None:
    state = load_state()

    if not state.get("verification_attempted", False):
        state["stop_block_count"] = state.get("stop_block_count", 0) + 1
        save_state(state)

        if state["stop_block_count"] >= MAX_STOP_BLOCKS:
            emit({})
            return

        emit_notification(
            "Stop",
            f"{TAG} BLOCKED: You have NOT run the test suite. "
            "You MUST verify before stopping. Run the project's tests."
        )
    elif not state.get("verification_passed", False):
        state["stop_block_count"] = state.get("stop_block_count", 0) + 1
        save_state(state)

        if state["stop_block_count"] >= 2:
            emit({})
            return

        emit_notification(
            "Stop",
            f"{TAG} Tests were run but appear to have failed. "
            "Review the output, fix issues, and re-run verification."
        )
    else:
        emit({})


def main() -> None:
    try:
        data = json.load(sys.stdin)
    except (json.JSONDecodeError, EOFError):
        data = {}

    hook_type = detect_hook_type(data)

    if hook_type == "PreToolUse":
        handle_pretool(data)
    elif hook_type == "PostToolUse":
        handle_posttool(data)
    elif hook_type == "Stop":
        handle_stop(data)
    else:
        emit({})


if __name__ == "__main__":
    main()
