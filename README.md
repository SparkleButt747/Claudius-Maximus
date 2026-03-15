# Claudius-Maximus

A benchmark optimization harness for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) on [Harbor](https://github.com/harbor-ai/harbor) benchmarks.

Claudius-Maximus injects an optimized prompt, guardian hooks, and permission settings into Harbor containers — turning Claude Code from a baseline agent into a structured, self-monitoring solver. It's benchmark-agnostic: swap the dataset and go.

## Results

On Terminal-Bench 2.0, the full harness achieves **100% pass rate** (up from ~60% baseline):

| Technique | Cumulative Score |
|-----------|-----------------|
| Claude Code default | ~60% |
| + Mandatory planning | ~75% |
| + Forced verification | ~85% |
| + Environment bootstrap | ~90% |
| + Loop detection | ~95% |
| + Full pipeline tuned | 100% |

> **A note on overfitting:** The 100% score on Terminal-Bench includes domain-specific task patterns and hints in `CLAUDE.md` and `task_patterns.md` that were iteratively tuned against this specific benchmark. Some of this guidance is close to "teaching to the test" — e.g. telling the agent how git-history tasks typically hide secrets, or how scientific tasks structure their output. The general-purpose techniques (forced verification, mandatory planning, loop detection, environment bootstrapping) transfer well to other benchmarks. The task-specific patterns will not. When adapting this harness for a new benchmark, expect the structural techniques to carry over but plan to develop your own task patterns through iteration. See [docs/optimization-guide.md](docs/optimization-guide.md#a-note-on-overfitting) for more detail.

## How It Works

Three systems work together:

1. **Agent Prompt** (`harness/CLAUDE.md`) — Injected into every container. Defines a mandatory 5-phase workflow: Bootstrap → Understand → Plan → Execute → Verify. This alone accounts for +30-40% improvement.

2. **Guardian Hooks** (`harness/hooks/guardian.py`) — Monitors execution quality via Claude Code's hook protocol. Tracks turns, detects loops, forces verification before exit. Runs inside the container.

3. **Harbor Agent Classes** (`harness/agent.py`) — Custom agent classes that inject the harness into containers during setup. Supports Anthropic API, Ollama (Anthropic-compat), and Ollama (OpenAI-compat) backends.

```
Harbor creates container → Agent.setup() injects harness → Claude Code reads CLAUDE.md
                                                         → Guardian monitors via hooks
                                                         → Agent solves task with structure
```

## Quick Start

### Prerequisites

- Python 3.10+
- Node.js 18+ (for Claude Code CLI)
- Docker
- [Harbor](https://github.com/harbor-ai/harbor) (`pip install harbor`)
- Anthropic API key or Claude Code OAuth

### Run

```bash
git clone https://github.com/SparkleButt747/Claudius-Maximus.git
cd Claudius-Maximus

# Set your API key
export ANTHROPIC_API_KEY=sk-ant-...

# Run 3 tasks from Terminal-Bench to verify setup
DATASET=terminal-bench@2.0 bash harness/run.sh -l 3

# Check results
python harness/analyze.py harness/jobs/<job-name>/ --verbose
```

### Other Benchmarks

```bash
DATASET=swe-bench-verified@1.0 bash harness/run.sh
DATASET=your-dataset@version bash harness/run.sh
```

### Other Models

```bash
MODEL=claude-sonnet-4-6 bash harness/run.sh
MODEL=minimax-m2.5:cloud AGENT_CLASS=CMDroid bash harness/run.sh
```

## Project Structure

```
Claudius-Maximus/
├── harness/                  # Core harness files
│   ├── CLAUDE.md             # Agent prompt (injected into containers)
│   ├── agent.py              # Harbor agent classes
│   ├── hooks/guardian.py     # Execution quality hooks
│   ├── middleware.py         # Middleware pipeline (5 classes)
│   ├── run.sh                # Main runner script
│   ├── cron-run.sh           # Scheduled/automated runs
│   ├── analyze.py            # Result analysis
│   ├── monitor.py            # Live run monitoring
│   ├── config.yaml           # Configuration reference
│   ├── Dockerfile            # Pre-built container image
│   ├── prompt_template.j2    # Harbor prompt template
│   ├── task_patterns.md      # Task category reference
│   ├── .claude/settings.json # Claude Code container settings
│   └── scripts/
│       ├── bootstrap.sh      # Environment probe
│       ├── inject_harness.sh # Container injection
│       ├── local_test.sh     # Local testing with mock tasks
│       └── verify.sh         # Universal test runner
├── examples/
│   └── terminal-bench/       # Terminal-Bench 2.0 config
├── archive/                  # Historical run configs & results
└── docs/                     # Documentation
```

## Optimization Techniques

Each technique was validated across multiple runs and cross-referenced with top-performing open-source agents:

| # | Technique | Impact | How |
|---|-----------|--------|-----|
| 1 | Forced verification | +15-20% | Stop hook blocks exit without running tests |
| 2 | Mandatory planning | +28% | Agent must write numbered plan before implementing |
| 3 | Environment bootstrap | +5-8% | Probe OS, tools, packages on first turn |
| 4 | Test-first strategy | +5-10% | Read test files before implementing |
| 5 | Loop detection | +3-5% | Track file edits and consecutive errors |
| 6 | Reasoning sandwich | +3-5% | High reasoning for understanding, medium for execution |
| 7 | Time budget awareness | +2-3% | Warn agent at configurable turn thresholds |

See [docs/optimization-guide.md](docs/optimization-guide.md) for full details.

## Customising for Your Benchmark

1. **Start with `harness/CLAUDE.md`** — highest impact, easiest to customise
2. **Add the guardian hook** — forced verification is nearly free and universally beneficial
3. **Tune thresholds** — adjust via environment variables (see [docs/hooks-reference.md](docs/hooks-reference.md))
4. **Add task patterns** — extend `task_patterns.md` for your benchmark's categories
5. **Create an example config** — see `examples/terminal-bench/` as a template

## Documentation

- [Getting Started](docs/getting-started.md) — Installation, first run, configuration
- [Architecture](docs/architecture.md) — System design, data flow, component overview
- [Optimization Guide](docs/optimization-guide.md) — Techniques ranked by impact
- [Hooks Reference](docs/hooks-reference.md) — Guardian hook events, configuration, protocol
- [Writing Rules](docs/writing-rules.md) — How to write effective CLAUDE.md prompts

## Configuration

All guardian thresholds are configurable via environment variables:

```bash
export TASK_GUARDIAN_MAX_TURNS=200          # Max turns before forced stop
export TASK_GUARDIAN_MAX_FILE_EDITS=4       # Loop detection: edits per file
export TASK_GUARDIAN_MAX_FAILURES=3         # Loop detection: consecutive errors
export TASK_GUARDIAN_MAX_STOP_BLOCKS=3      # Max stop blocks before safety valve
export TASK_GUARDIAN_EARLY_VERIFY_PCT=0.2   # Suggest verification
export TASK_GUARDIAN_WARN_PCT=0.5           # Warn about time
export TASK_GUARDIAN_CRITICAL_PCT=0.6       # Demand verification
export TASK_GUARDIAN_LATE_PCT=0.75          # Urge wrap-up
```

## Contributing

Contributions are welcome via pull requests. By submitting a PR, you agree to license your contribution under the same CC BY-NC-SA 4.0 terms. Valuable areas:

- **New benchmark examples** — add an `examples/<benchmark>/` directory with config and README
- **Task patterns** — extend `task_patterns.md` with category-specific guidance
- **Guardian improvements** — better detection patterns, smarter loop detection
- **Analysis tooling** — cross-benchmark comparison, visualisation

## License

CC BY-NC-SA 4.0 — see [LICENSE](LICENSE).

You may share and adapt this work with attribution. Commercial use is not permitted. Derivative works must use the same license.
