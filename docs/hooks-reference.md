# Hooks Reference

The guardian hook system (`harness/hooks/guardian.py`) monitors agent execution quality using Claude Code's hook protocol.

## Hook Events

### PreToolUse

Fires before every tool call. The guardian uses this to:

- **Count turns** — tracks total tool calls for budget warnings
- **Track file edits** — records edit counts per file for loop detection
- **Detect verification** — marks when the agent runs test commands

Always returns `permissionDecision: "allow"` — it monitors, never blocks tool use.

### PostToolUse

Fires after `Bash` tool calls. The guardian uses this to:

- **Detect errors** — matches output against error patterns, tracks consecutive failures
- **Detect verification success** — checks for success patterns after test runs
- **Emit warnings** — loop detection and turn budget notifications

### Stop

Fires when the agent tries to exit. The guardian uses this to:

- **Block premature exit** — if verification hasn't been attempted, blocks with a notification
- **Block on failure** — if tests were run but didn't pass, blocks once
- **Safety valve** — after N blocks (default: 3), allows exit to prevent infinite loops

## Configuration

All thresholds are configurable via environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `TASK_GUARDIAN_MAX_TURNS` | `200` | Max turns before forced stop |
| `TASK_GUARDIAN_EARLY_VERIFY_PCT` | `0.2` | % at which to suggest verification |
| `TASK_GUARDIAN_WARN_PCT` | `0.5` | % at which to warn about time |
| `TASK_GUARDIAN_CRITICAL_PCT` | `0.6` | % at which to demand verification |
| `TASK_GUARDIAN_LATE_PCT` | `0.75` | % at which to urge wrap-up |
| `TASK_GUARDIAN_MAX_FILE_EDITS` | `4` | Loop detection: max edits per file |
| `TASK_GUARDIAN_MAX_FAILURES` | `3` | Loop detection: consecutive same-error threshold |
| `TASK_GUARDIAN_MAX_STOP_BLOCKS` | `3` | Max times to block stop before giving up |

## State Persistence

State is stored in `/tmp/.task_guardian_state.json` with this schema:

```json
{
  "start_time": 1710000000.0,
  "turn_count": 42,
  "file_edits": {"/app/main.py": 3},
  "verification_attempted": true,
  "verification_passed": false,
  "consecutive_failures": 0,
  "last_error_sig": "",
  "stop_block_count": 1
}
```

## Protocol

The hook communicates via JSON on stdin/stdout:

**Input** (from Claude Code):
```json
{"tool_name": "Bash", "tool_input": {"command": "pytest tests/"}}
```

**Output** (to Claude Code):
```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "permissionDecisionReason": "[guardian]"
  }
}
```

**Notification output:**
```json
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "notification": "[guardian] WARNING: 3 consecutive failures. Switch strategy."
  }
}
```

## Customising

To add custom detection patterns, edit the lists at the top of `guardian.py`:

- `VERIFICATION_PATTERNS` — commands that count as running tests
- `SUCCESS_PATTERNS` — output strings that indicate tests passed
- `ERROR_PATTERNS` — output strings that indicate errors

## Middleware vs Hooks

The project includes two complementary systems:

| Feature | `hooks/guardian.py` | `middleware.py` |
|---------|-------------------|-----------------|
| Where it runs | Inside the container (Claude Code hook) | Outside, in the Harbor agent |
| How it's invoked | Automatically by Claude Code | Called by agent code |
| State | File-based (`/tmp/`) | In-memory |
| Best for | Production benchmark runs | Custom agent implementations |

For most use cases, the hook is sufficient. The middleware pipeline is useful if you're building a custom Harbor agent that needs programmatic control over the intervention logic.
