"""
Claudius-Maximus Optimized Agents for Harbor.

Extends Harbor's built-in ClaudeCode agent to inject the optimization harness
(CLAUDE.md, hooks, settings.json) into containers before task execution.

Provides three agent variants:
- CMClaudeCode: Uses Anthropic Claude models (Opus, Sonnet) via Anthropic API
- CMDroid: Uses Ollama/local models via Anthropic-compatible API (Ollama v0.14.0+)
- CMOpenAI: Uses Ollama/local models via OpenAI-compatible API (QwenCode base)

Usage with Claude:
    harbor run -d <dataset>@<version> \
        --agent-import-path agent:CMClaudeCode \
        -m anthropic/claude-opus-4-6 \
        -n 4 --ak max_turns=200

Usage with Ollama (Anthropic-compat):
    ANTHROPIC_BASE_URL=http://host.docker.internal:11434 \
    harbor run -d <dataset> --agent-import-path agent:CMDroid -m minimax-m2.5:cloud

Usage with Ollama (OpenAI-compat):
    MODEL=minimax-m2.5:cloud harbor run -d <dataset> --agent-import-path agent:CMOpenAI
"""

from __future__ import annotations

import json
import os
import shlex
from pathlib import Path

from harbor.agents.installed.claude_code import ClaudeCode
from harbor.agents.installed.qwen_code import QwenCode
from harbor.agents.installed.base import ExecInput
from harbor.environments.base import BaseEnvironment
from harbor.models.trial.paths import EnvironmentPaths

# Harness files (relative to this script)
HARNESS_DIR = Path(__file__).parent
CLAUDE_MD = HARNESS_DIR / "CLAUDE.md"
HOOKS_PY = HARNESS_DIR / "hooks" / "guardian.py"
SETTINGS_JSON = HARNESS_DIR / ".claude" / "settings.json"


async def _detect_workdir(environment: BaseEnvironment) -> str:
    """Detect the container's working directory."""
    result = await environment.exec(command="pwd")
    workdir = result.stdout.strip() if result.stdout else "/app"
    return workdir if workdir.startswith("/") else "/app"


def _build_settings(hook_cmd: str) -> dict:
    """Build the Claude Code settings.json with hook registration."""
    return {
        "permissions": {
            "allow": [
                "Bash(*)", "Read(*)", "Write(*)", "Edit(*)", "Glob(*)", "Grep(*)"
            ]
        },
        "hooks": {
            "PreToolUse": [
                {"matcher": "", "hooks": [
                    {"type": "command", "command": hook_cmd, "timeout": 5}
                ]}
            ],
            "PostToolUse": [
                {"matcher": "Bash", "hooks": [
                    {"type": "command", "command": hook_cmd, "timeout": 5}
                ]}
            ],
            "Stop": [
                {"matcher": "", "hooks": [
                    {"type": "command", "command": hook_cmd, "timeout": 5}
                ]}
            ],
        },
    }


async def _inject_harness(
    environment: BaseEnvironment, workdir: str, logger, *, tag: str = "harness"
) -> None:
    """Inject CLAUDE.md, hooks, and settings into the container."""
    # Inject CLAUDE.md into workdir (Claude Code reads this automatically)
    if CLAUDE_MD.exists():
        await environment.upload_file(
            source_path=CLAUDE_MD,
            target_path=f"{workdir}/CLAUDE.md",
        )

    # Inject hooks
    await environment.exec(
        command=f"mkdir -p {workdir}/.claude-harness/hooks {workdir}/.claude"
    )

    if HOOKS_PY.exists():
        await environment.upload_file(
            source_path=HOOKS_PY,
            target_path=f"{workdir}/.claude-harness/hooks/guardian.py",
        )
        await environment.exec(
            command=f"chmod +x {workdir}/.claude-harness/hooks/guardian.py"
        )

    # Build and inject settings.json with correct hook paths
    hook_cmd = f"python3 {workdir}/.claude-harness/hooks/guardian.py"
    settings = _build_settings(hook_cmd)
    settings_json = json.dumps(settings, indent=2)
    escaped = shlex.quote(settings_json)
    await environment.exec(
        command=f"echo {escaped} > {workdir}/.claude/settings.json"
    )

    logger.info(f"[{tag}] Harness injected into {workdir}")


class CMClaudeCode(ClaudeCode):
    """ClaudeCode with Claudius-Maximus harness injection."""

    @staticmethod
    def name() -> str:
        return "cm-claude-code"

    async def setup(self, environment: BaseEnvironment) -> None:
        await super().setup(environment)
        workdir = await _detect_workdir(environment)
        await _inject_harness(environment, workdir, self.logger)


class CMDroid(ClaudeCode):
    """Droid agent using Ollama's Anthropic-compatible API.

    Ollama v0.14.0+ supports Anthropic Messages API natively.
    Set ANTHROPIC_BASE_URL=http://host.docker.internal:11434 (NOT /v1)
    Works with: minimax-m2.5:cloud, glm-5:cloud, kimi-k2.5:cloud, qwen3.5

    See: https://ollama.com/blog/claude
    """

    @staticmethod
    def name() -> str:
        return "cm-droid"

    async def setup(self, environment: BaseEnvironment) -> None:
        await super().setup(environment)
        workdir = await _detect_workdir(environment)
        await _inject_harness(environment, workdir, self.logger, tag="droid")

    def create_run_agent_commands(self, instruction: str) -> list[ExecInput]:
        """Configure Claude Code to use Ollama's Anthropic-compatible API."""
        escaped_instruction = shlex.quote(instruction)

        model_name = self.model_name or os.environ.get("MODEL", "minimax-m2.5:cloud")
        if "/" in model_name:
            model_name = model_name.split("/")[-1]

        env = {
            "ANTHROPIC_AUTH_TOKEN": "ollama",
            "ANTHROPIC_API_KEY": "",
            "ANTHROPIC_BASE_URL": "http://host.docker.internal:11434",
            "ANTHROPIC_MODEL": model_name,
            "CLAUDE_CONFIG_DIR": "/logs/agent/sessions",
            "FORCE_AUTO_BACKGROUND_TASKS": "1",
            "ENABLE_BACKGROUND_TASKS": "1",
            "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
            "IS_SANDBOX": "1",
        }

        setup_command = (
            "mkdir -p $CLAUDE_CONFIG_DIR/debug $CLAUDE_CONFIG_DIR/projects/-app "
            "$CLAUDE_CONFIG_DIR/sessions $CLAUDE_CONFIG_DIR/shell-snapshots "
            "$CLAUDE_CONFIG_DIR/statsig $CLAUDE_CONFIG_DIR/todos"
        )

        max_turns = getattr(self, "_max_turns", None) or os.environ.get(
            "CLAUDE_CODE_MAX_TURNS", ""
        )
        max_turns_flag = f"--max-turns {max_turns}" if max_turns else ""

        run_command = (
            'export PATH="$HOME/.local/bin:$PATH"; '
            f"claude --verbose --output-format=stream-json "
            f"--permission-mode=bypassPermissions "
            f"--model {model_name} "
            f"{max_turns_flag} "
            f"--print -- {escaped_instruction} 2>&1 </dev/null | tee /logs/agent/claude-code.txt"
        )

        return [
            ExecInput(command=setup_command, env=env),
            ExecInput(command=run_command, env=env),
        ]


class CMOpenAI(QwenCode):
    """OpenAI-compatible agent using Ollama or similar APIs.

    Uses QwenCode as base which natively supports OpenAI-compatible APIs.
    Works with models like minimax-m2.5:cloud via Ollama, vLLM, etc.
    """

    @staticmethod
    def name() -> str:
        return "cm-openai"

    async def setup(self, environment: BaseEnvironment) -> None:
        await super().setup(environment)
        await environment.exec(command="mkdir -p /app/.claude-harness/hooks /app/.claude")

        if CLAUDE_MD.exists():
            await environment.upload_file(
                source_path=CLAUDE_MD, target_path="/app/CLAUDE.md"
            )

        if HOOKS_PY.exists():
            await environment.upload_file(
                source_path=HOOKS_PY,
                target_path="/app/.claude-harness/hooks/guardian.py",
            )
            await environment.exec(
                command="chmod +x /app/.claude-harness/hooks/guardian.py"
            )

        self.logger.info("[openai] Harness injected into /app")

    def create_run_agent_commands(self, instruction: str) -> list[ExecInput]:
        """Configure Qwen CLI to use Ollama's OpenAI-compatible API."""
        escaped_instruction = shlex.quote(instruction)

        ollama_base_url = os.environ.get(
            "OLLAMA_BASE_URL", "http://host.docker.internal:11434/v1"
        )
        model_name = self.model_name or os.environ.get("MODEL", "minimax-m2.5:cloud")
        if "/" in model_name:
            model_name = model_name.split("/")[-1]

        env = {
            "OPENAI_API_KEY": os.environ.get("OLLAMA_API_KEY", "ollama"),
            "OPENAI_BASE_URL": ollama_base_url,
            "OPENAI_MODEL": model_name,
        }
        env = {k: v for k, v in env.items() if v}

        setup_command = (
            "mkdir -p /logs/agent && "
            "which qwen || (npm install -g @anthropic-ai/qwen-cli 2>/dev/null || true)"
        )

        run_command = (
            f"qwen --yolo --prompt={escaped_instruction} "
            f"2>&1 | tee /logs/agent/qwen-code.txt"
        )

        return [
            ExecInput(command=setup_command, env=env),
            ExecInput(command=run_command, env=env),
        ]
