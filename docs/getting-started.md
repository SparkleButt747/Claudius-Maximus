# Getting Started

## Prerequisites

- **Python 3.10+**
- **Node.js 18+** (for Claude Code CLI)
- **Docker** (for running benchmark containers)
- **Harbor** (`pip install harbor` or `uv tool install harbor`)
- An **Anthropic API key** or Claude Code OAuth token

## Installation

```bash
git clone https://github.com/SparkleButt747/Claudius-Maximus.git
cd Claudius-Maximus
```

No additional installation needed — the harness is pure bash + Python with no dependencies beyond Harbor.

## Your First Run

### 1. Set up authentication

```bash
# Option A: API key
export ANTHROPIC_API_KEY=sk-ant-...

# Option B: Claude Code OAuth (macOS — auto-detected from keychain)
claude login
```

### 2. Run a quick test

```bash
# Run 3 tasks from Terminal-Bench to verify setup
DATASET=terminal-bench@2.0 bash harness/run.sh -l 3
```

### 3. Check results

```bash
python harness/analyze.py harness/jobs/<job-name>/ --verbose
```

## Running Against Other Benchmarks

The harness is benchmark-agnostic. To run against a different Harbor dataset:

```bash
# SWE-bench
DATASET=swe-bench-verified@1.0 bash harness/run.sh

# Any Harbor-compatible dataset
DATASET=your-dataset@version bash harness/run.sh
```

## Using Different Models

```bash
# Sonnet (cheaper, faster)
MODEL=claude-sonnet-4-6 bash harness/run.sh

# Via Ollama (local models)
MODEL=minimax-m2.5:cloud AGENT_CLASS=CMDroid bash harness/run.sh
```

## Project Structure

```
Claudius-Maximus/
├── harness/                  # Core harness files
│   ├── CLAUDE.md             # Agent prompt (injected into containers)
│   ├── agent.py              # Harbor agent classes
│   ├── hooks/guardian.py     # Execution quality hooks
│   ├── middleware.py         # Middleware pipeline
│   ├── run.sh                # Main runner script
│   ├── cron-run.sh           # Automated/scheduled runs
│   ├── analyze.py            # Result analysis
│   ├── monitor.py            # Live run monitoring
│   ├── config.yaml           # Configuration reference
│   ├── Dockerfile            # Pre-built container image
│   ├── prompt_template.j2    # Harbor prompt template
│   ├── task_patterns.md      # Task category reference
│   ├── .claude/settings.json # Claude Code settings for containers
│   └── scripts/
│       ├── bootstrap.sh      # Environment probe script
│       ├── inject_harness.sh # Container injection script
│       ├── local_test.sh     # Local testing with mock tasks
│       └── verify.sh         # Universal test runner
├── examples/
│   └── terminal-bench/       # TB 2.0 example config
├── archive/                  # Historical run configs & results
└── docs/                     # Documentation
```

## Next Steps

- Read the [Optimization Guide](optimization-guide.md) to understand each technique
- Read the [Hooks Reference](hooks-reference.md) to customise the guardian hooks
- Read [Writing Rules](writing-rules.md) to create your own CLAUDE.md
- Check `examples/` for benchmark-specific configurations
