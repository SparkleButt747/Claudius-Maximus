# Architecture

## Overview

Claudius-Maximus optimises Claude Code's performance on Harbor benchmarks through three complementary systems:

```
┌─────────────────────────────────────────────────────┐
│                    Harbor                            │
│  (orchestrates tasks, manages containers, scoring)   │
├─────────────────────────────────────────────────────┤
│                                                      │
│  ┌──────────────┐   ┌──────────────┐                │
│  │  agent.py     │──▶│  Container   │                │
│  │  (Harbor      │   │              │                │
│  │   agent class)│   │ ┌──────────┐ │                │
│  └──────────────┘   │ │ CLAUDE.md│ │  ← Prompt      │
│                      │ ├──────────┤ │                │
│                      │ │guardian  │ │  ← Hooks       │
│                      │ │.py       │ │                │
│                      │ ├──────────┤ │                │
│                      │ │settings  │ │  ← Permissions │
│                      │ │.json     │ │                │
│                      │ └──────────┘ │                │
│                      │              │                │
│                      │  Claude Code │                │
│                      │  (runs task) │                │
│                      └──────────────┘                │
└─────────────────────────────────────────────────────┘
```

## System 1: Agent Prompt (CLAUDE.md)

The agent prompt is injected into every container's working directory. Claude Code reads it automatically.

**Responsibilities:**
- Define the workflow phases (Bootstrap → Understand → Plan → Execute → Verify)
- Encode task-solving patterns and anti-patterns
- Set reasoning budget guidance per phase
- Establish the verification protocol

**Impact:** This is the highest-impact component. A well-written CLAUDE.md alone can improve pass rates by 30-40%.

## System 2: Guardian Hooks (hooks/guardian.py)

A Python script that implements the Claude Code hooks protocol. It's registered in `.claude/settings.json` and runs on every tool call.

**Responsibilities:**
- Track execution state (turns, file edits, errors)
- Detect verification attempts and success
- Emit warnings (loop detection, time budget)
- Block premature exit (Stop hook)

**How it works:**
1. Claude Code sends a JSON payload to stdin before/after each tool call
2. The hook reads the payload, updates state in `/tmp/`
3. The hook responds with JSON on stdout (allow, notification, or empty)

## System 3: Harbor Agent Classes (agent.py)

Custom agent classes that extend Harbor's built-in `ClaudeCode` agent. They inject the harness into containers during setup.

**Classes:**
- `CMClaudeCode` — Standard Anthropic API agent
- `CMDroid` — Ollama via Anthropic-compatible API
- `CMOpenAI` — Ollama via OpenAI-compatible API (QwenCode base)

**Injection flow:**
1. Harbor calls `agent.setup(environment)`
2. Agent detects container working directory (`pwd`)
3. Agent uploads `CLAUDE.md`, `guardian.py`, and generates `settings.json`
4. Claude Code starts and reads these files automatically

## Supporting Components

### Middleware Pipeline (middleware.py)

An alternative to hooks for programmatic control. Five composable middleware classes that can be used in custom agent implementations:

- `EnvironmentBootstrapMiddleware` — prompts environment probing
- `PlanEnforcementMiddleware` — detects implementation without planning
- `LoopDetectionMiddleware` — tracks repeated failures
- `TimeBudgetMiddleware` — injects time warnings
- `PreCompletionChecklistMiddleware` — blocks exit without verification

### Runner Scripts

- `run.sh` — Main entry point. Configures and invokes `harbor run`
- `cron-run.sh` — Wraps `run.sh` with logging and macOS notifications
- `scripts/inject_harness.sh` — Standalone injection script (for Dockerfile use)
- `scripts/bootstrap.sh` — Comprehensive environment probe
- `scripts/verify.sh` — Universal test suite runner
- `scripts/local_test.sh` — Local testing with mock tasks

### Analysis Tools

- `analyze.py` — Parse job results, compute pass rates, aggregate across runs
- `monitor.py` — Live monitoring of in-progress jobs

## Data Flow

```
1. User runs: bash harness/run.sh
2. run.sh calls: harbor run -d <dataset> --agent-import-path agent:CMClaudeCode
3. Harbor creates containers, one per task
4. CMClaudeCode.setup() injects CLAUDE.md + hooks + settings
5. Claude Code starts in each container
6. Claude Code reads CLAUDE.md, follows the workflow
7. guardian.py monitors execution quality via hooks
8. Claude Code solves the task, runs verification
9. Harbor runs the verifier, records results
10. User runs: python analyze.py jobs/<job-name>/
```
