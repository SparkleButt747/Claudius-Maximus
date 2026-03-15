# Optimization Guide

The techniques below are ranked by impact. Each was validated across multiple benchmark runs and cross-referenced with top-performing open-source agents (ForgeCode, Droid, LangChain, Letta, OB-1).

## 1. Forced Verification (+15-20%)

**The single most impactful technique.** The #1 failure mode for autonomous agents is claiming completion without running the test suite.

**How it works:**
- The `Stop` hook in `guardian.py` blocks the agent from exiting if it hasn't run verification
- The CLAUDE.md prompt has a mandatory Phase 4 (Verify)
- The middleware pipeline's `PreCompletionChecklistMiddleware` detects completion signals without prior verification

**Configuration:**
```bash
# Max times to block stop before giving up (safety valve)
export TASK_GUARDIAN_MAX_STOP_BLOCKS=3
```

## 2. Mandatory Planning (+28%)

ForgeCode demonstrated a jump from 38% to 66% pass rate just by requiring agents to write a plan before implementing.

**How it works:**
- CLAUDE.md Phase 2 requires a numbered plan (5-15 steps)
- `PlanEnforcementMiddleware` detects implementation activity without a prior plan
- The plan forces the agent to think about deliverables, dependencies, and verification strategy

## 3. Environment Bootstrapping (+5-8%)

24.1% of all command failures in benchmarks are "tool not found" errors. A single bootstrap command eliminates most of these.

**How it works:**
- CLAUDE.md Phase 0 runs a compound command that probes OS, languages, tools, and packages
- `scripts/bootstrap.sh` provides a comprehensive version
- `EnvironmentBootstrapMiddleware` prompts bootstrapping on the first turn

## 4. Test-First Strategy (+5-10%)

Reading test files before implementing eliminates the second most common failure mode: building the wrong thing.

**How it works:**
- CLAUDE.md Phase 0 reads test files in the same command as bootstrapping
- Phase 1 explicitly requires extracting deliverables from test assertions
- "Tests are ground truth" is hammered throughout the prompt

## 5. Loop Detection (+3-5%)

Agents get stuck in loops: editing the same file repeatedly, running the same failing command, or oscillating between approaches.

**How it works:**
- `guardian.py` tracks file edit counts and consecutive error signatures
- After N edits to the same file (default: 4), it warns the agent to try a different approach
- After N consecutive same-error failures (default: 3), it demands a strategy change
- `LoopDetectionMiddleware` provides the same detection in the middleware pipeline

**Configuration:**
```bash
export TASK_GUARDIAN_MAX_FILE_EDITS=4
export TASK_GUARDIAN_MAX_FAILURES=3
```

## 6. Reasoning Sandwich (+3-5%)

Allocate reasoning effort dynamically: maximum for understanding and verification, medium for execution.

**How it works:**
- `config.yaml` documents the recommended thinking budget per phase
- The agent prompt structures work into phases with explicit reasoning guidance
- High reasoning on Phase 0-1 prevents misunderstanding (the #1 cause of failure)
- Medium reasoning on Phase 3 keeps execution efficient

## 7. Time Budget Awareness (+2-3%)

Agents that don't track time budget waste turns on optimisation after passing, or run out of time before verifying.

**How it works:**
- `guardian.py` emits warnings at configurable turn-count thresholds
- `TimeBudgetMiddleware` injects warnings at 50%, 75%, and 90% time elapsed
- Early verification (~30% through budget) catches issues before it's too late

**Configuration:**
```bash
export TASK_GUARDIAN_EARLY_VERIFY_PCT=0.2   # Suggest verification
export TASK_GUARDIAN_WARN_PCT=0.5           # Warn about time
export TASK_GUARDIAN_CRITICAL_PCT=0.6       # Demand verification
export TASK_GUARDIAN_LATE_PCT=0.75          # Urge wrap-up
```

## Stacking Effects

These techniques compound. Our progression on Terminal-Bench 2.0:

| Run | Techniques | Score |
|-----|-----------|-------|
| Baseline | Claude Code default | ~60% |
| +Planning | CLAUDE.md with mandatory plan | ~75% |
| +Verification | Stop hook + forced testing | ~85% |
| +Bootstrap | Environment probe + test-first | ~90% |
| +Loop detection | Guardian hooks | ~95% |
| +Tuning | Full pipeline, optimised prompt | 100% |

## Customisation for Your Benchmark

1. **Start with CLAUDE.md** — this has the biggest impact and is easiest to customise
2. **Add the guardian hook** — forced verification is nearly free and universally beneficial
3. **Tune thresholds** — adjust `MAX_TURNS`, verification percentages, and loop detection limits for your benchmark's difficulty
4. **Add task patterns** — extend `task_patterns.md` with patterns specific to your benchmark's task categories
5. **Build a custom Dockerfile** — pre-install packages your benchmark commonly needs
