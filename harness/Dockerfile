# Claudius-Maximus Optimized Claude Code Container
# Pre-installs harness + common dependencies for benchmark tasks.
#
# Build: docker build -t cm-claude-optimized .
# Test:  docker run -it -e ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY cm-claude-optimized

FROM node:22-bookworm

# System dependencies commonly needed by benchmark tasks
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    build-essential cmake ninja-build \
    python3 python3-pip python3-venv python3-dev \
    git curl wget jq \
    openssl libssl-dev \
    ffmpeg \
    gdb binutils strace ltrace \
    zip unzip \
    netcat-openbsd socat \
    sqlite3 \
    xxd \
    && rm -rf /var/lib/apt/lists/*

# Claude Code CLI
RUN npm install -g @anthropic-ai/claude-code@latest

# Common Python packages (pre-warmed so agent doesn't waste time installing)
RUN pip3 install --break-system-packages \
    numpy pandas scipy scikit-learn matplotlib \
    requests flask fastapi uvicorn \
    pytest pycryptodome sympy z3-solver \
    pillow beautifulsoup4 lxml \
    2>/dev/null || true

# Harness directory structure
RUN mkdir -p /harness/hooks /harness/scripts /app/.claude /app/.claude-harness/hooks

# Copy harness files
COPY CLAUDE.md /harness/CLAUDE.md
COPY hooks/guardian.py /harness/hooks/guardian.py
COPY .claude/settings.json /harness/settings.json
COPY scripts/inject_harness.sh /harness/scripts/inject_harness.sh

# Inject harness into /app (Claude Code reads CLAUDE.md and .claude/ from cwd)
RUN bash /harness/scripts/inject_harness.sh /app

WORKDIR /app

# Agentic mode with prompt injection
ENTRYPOINT ["claude", "--dangerously-skip-permissions", "--max-turns", "200"]
