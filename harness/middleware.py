"""
Claudius-Maximus Middleware Layer

Implements key middleware patterns from top-performing benchmark agents:
1. PreCompletionChecklistMiddleware — prevents exit without verification
2. LoopDetectionMiddleware — breaks repetitive failure patterns
3. TimeBudgetMiddleware — injects time warnings
4. EnvironmentBootstrapMiddleware — maps container at start
5. PlanEnforcementMiddleware — forces planning before execution

These can be used standalone or composed into a pipeline.
"""

from __future__ import annotations

import json
import re
import time
from dataclasses import dataclass, field
from typing import Any


@dataclass
class ExecutionContext:
    """Shared state across all middleware."""

    start_time: float = field(default_factory=time.time)
    timeout_seconds: int = 900
    turn_count: int = 0
    file_edits: dict[str, int] = field(default_factory=dict)
    command_history: list[str] = field(default_factory=list)
    error_history: list[str] = field(default_factory=list)
    consecutive_same_error: int = 0
    last_error_signature: str = ""
    plan_written: bool = False
    bootstrap_done: bool = False
    verification_attempted: bool = False
    verification_passed: bool = False
    test_files_found: list[str] = field(default_factory=list)

    @property
    def elapsed(self) -> float:
        return time.time() - self.start_time

    @property
    def remaining(self) -> float:
        return max(0, self.timeout_seconds - self.elapsed)

    @property
    def pct_elapsed(self) -> float:
        return min(100, (self.elapsed / self.timeout_seconds) * 100)


class MiddlewareBase:
    """Base class for middleware components."""

    def process_turn(self, ctx: ExecutionContext, agent_output: str) -> str | None:
        """
        Process a turn. Returns an injection string to prepend to the
        next prompt, or None if no intervention is needed.
        """
        return None

    def should_block_exit(self, ctx: ExecutionContext) -> str | None:
        """
        Check if the agent should be prevented from exiting.
        Returns a message explaining why, or None to allow exit.
        """
        return None


class PreCompletionChecklistMiddleware(MiddlewareBase):
    """
    Prevents the agent from claiming completion without running verification.
    This is the #1 most impactful middleware — eliminates the most common
    failure mode where agents write code then stop without testing.
    """

    COMPLETION_SIGNALS = [
        r"task.*(?:complete|done|finished)",
        r"(?:all|everything).*(?:pass|work|correct)",
        r"successfully.*(?:implement|complet|finish)",
        r"solution.*(?:ready|complete)",
        r"i'?m?\s+done",
    ]

    def process_turn(self, ctx: ExecutionContext, agent_output: str) -> str | None:
        output_lower = agent_output.lower()

        for pattern in self.COMPLETION_SIGNALS:
            if re.search(pattern, output_lower):
                if not ctx.verification_attempted:
                    return (
                        "\n\n**STOP. You indicated completion but have NOT run verification.**\n"
                        "You MUST run the test suite before finishing.\n"
                        "Run verification NOW.\n"
                    )
        return None

    def should_block_exit(self, ctx: ExecutionContext) -> str | None:
        if not ctx.verification_attempted:
            return "BLOCKED: Cannot exit without running verification."
        if ctx.verification_attempted and not ctx.verification_passed:
            return (
                "BLOCKED: Verification failed. Fix the issues and re-verify "
                "before exiting."
            )
        return None


class LoopDetectionMiddleware(MiddlewareBase):
    """
    Detects when the agent is stuck in a loop and forces strategy change.
    Tracks file edits, command repetition, and error patterns.
    """

    MAX_SAME_FILE_EDITS = 4
    MAX_CONSECUTIVE_ERRORS = 3
    MAX_COMMAND_REPEATS = 3

    def process_turn(self, ctx: ExecutionContext, agent_output: str) -> str | None:
        warnings = []

        for filepath, count in ctx.file_edits.items():
            if count >= self.MAX_SAME_FILE_EDITS:
                warnings.append(
                    f"LOOP: `{filepath}` edited {count} times. "
                    "The approach is wrong. Try a completely different solution."
                )

        if ctx.consecutive_same_error >= self.MAX_CONSECUTIVE_ERRORS:
            warnings.append(
                f"LOOP: Same error {ctx.consecutive_same_error} times in a row. "
                f"Error: {ctx.last_error_signature[:150]}. "
                "STOP retrying. Change your approach fundamentally."
            )

        if len(ctx.command_history) >= self.MAX_COMMAND_REPEATS:
            recent = ctx.command_history[-self.MAX_COMMAND_REPEATS:]
            if len(set(recent)) == 1:
                warnings.append(
                    f"LOOP: Same command run {self.MAX_COMMAND_REPEATS} times. "
                    "This is not working. Try something different."
                )

        if warnings:
            return "\n\n**" + "\n".join(warnings) + "**\n"
        return None


class TimeBudgetMiddleware(MiddlewareBase):
    """
    Injects time budget warnings at critical thresholds.
    Prevents timeout failures by encouraging the agent to
    wrap up and verify before time runs out.
    """

    def process_turn(self, ctx: ExecutionContext, agent_output: str) -> str | None:
        pct = ctx.pct_elapsed
        remaining = ctx.remaining

        if pct > 90:
            return (
                f"\n\n**CRITICAL: Only {remaining:.0f}s remaining! "
                "Run verification NOW. Do not start new work.**\n"
            )
        elif pct > 75:
            return (
                f"\n\n**WARNING: {remaining:.0f}s remaining ({pct:.0f}% elapsed). "
                "Finish current work and run verification soon.**\n"
            )
        elif pct > 50 and not ctx.verification_attempted:
            return (
                f"\n\nTime: {remaining:.0f}s remaining. "
                "Consider running a quick verification to check progress.\n"
            )
        return None


class PlanEnforcementMiddleware(MiddlewareBase):
    """
    Enforces that the agent writes a plan before starting implementation.
    This alone can jump pass rate from 38% to 66% (ForgeCode data).
    """

    PLAN_INDICATORS = [
        r"(?:step|phase)\s+\d",
        r"\d+\.\s+\w",
        r"plan:",
        r"approach:",
        r"strategy:",
    ]

    IMPLEMENTATION_INDICATORS = [
        r"(?:cat|echo|printf)\s+>",
        r"(?:pip|npm|apt)\s+install",
        r"(?:python|node|gcc|make|cargo)\s+",
        r"(?:mkdir|touch|cp|mv)\s+",
    ]

    def process_turn(self, ctx: ExecutionContext, agent_output: str) -> str | None:
        output_lower = agent_output.lower()
        for pattern in self.PLAN_INDICATORS:
            if re.search(pattern, output_lower):
                ctx.plan_written = True
                break

        if not ctx.plan_written and ctx.turn_count >= 2:
            for pattern in self.IMPLEMENTATION_INDICATORS:
                if re.search(pattern, output_lower):
                    return (
                        "\n\n**STOP. You're implementing without a plan.**\n"
                        "Write a numbered plan (5-15 steps) first. This is mandatory.\n"
                        "Include: deliverables, dependencies, commands, verification.\n"
                    )
        return None


class EnvironmentBootstrapMiddleware(MiddlewareBase):
    """
    Ensures environment is probed at the start of execution.
    Missing tools account for 24.1% of all command failures.
    """

    def process_turn(self, ctx: ExecutionContext, agent_output: str) -> str | None:
        if ctx.turn_count == 0 and not ctx.bootstrap_done:
            return (
                "\n\n**FIRST: Run the environment bootstrap to discover available tools.**\n"
                "```bash\n"
                "echo '--- OS ---' && cat /etc/os-release 2>/dev/null | head -3 && "
                "echo '--- Languages ---' && which python3 node gcc rustc go 2>/dev/null && "
                "echo '--- Tools ---' && which make cmake git curl 2>/dev/null && "
                "echo '--- Files ---' && ls -la\n"
                "```\n"
            )
        return None


class MiddlewarePipeline:
    """Composes multiple middleware into a processing pipeline."""

    def __init__(self, middlewares: list[MiddlewareBase] | None = None):
        self.middlewares = middlewares or [
            EnvironmentBootstrapMiddleware(),
            PlanEnforcementMiddleware(),
            LoopDetectionMiddleware(),
            TimeBudgetMiddleware(),
            PreCompletionChecklistMiddleware(),
        ]
        self.ctx = ExecutionContext()

    def process_turn(self, agent_output: str) -> list[str]:
        """Process a turn through all middleware. Returns list of injections."""
        self.ctx.turn_count += 1
        injections = []

        for mw in self.middlewares:
            result = mw.process_turn(self.ctx, agent_output)
            if result:
                injections.append(result)

        return injections

    def can_exit(self) -> tuple[bool, str]:
        """Check if the agent should be allowed to exit."""
        for mw in self.middlewares:
            block_reason = mw.should_block_exit(self.ctx)
            if block_reason:
                return False, block_reason
        return True, ""

    def update_from_tool_call(self, tool_name: str, args: dict[str, Any]) -> None:
        """Update context from a tool call."""
        if tool_name in ("Edit", "Write"):
            filepath = args.get("file_path", "unknown")
            self.ctx.file_edits[filepath] = self.ctx.file_edits.get(filepath, 0) + 1

        if tool_name == "Bash":
            cmd = args.get("command", "")
            self.ctx.command_history.append(cmd)

            if any(kw in cmd for kw in ["pytest", "test.sh", "test_", "make test"]):
                self.ctx.verification_attempted = True

    def update_from_tool_result(
        self, tool_name: str, result: str, exit_code: int = 0
    ) -> None:
        """Update context from a tool result."""
        if exit_code != 0:
            error_sig = result.strip().split("\n")[0][:200] if result else "unknown error"
            if error_sig == self.ctx.last_error_signature:
                self.ctx.consecutive_same_error += 1
            else:
                self.ctx.consecutive_same_error = 1
                self.ctx.last_error_signature = error_sig
        else:
            self.ctx.consecutive_same_error = 0

            if self.ctx.verification_attempted:
                result_lower = result.lower() if result else ""
                if any(kw in result_lower for kw in ["passed", "ok", "success", "0 failed"]):
                    self.ctx.verification_passed = True

    def get_status(self) -> dict[str, Any]:
        """Get current pipeline status."""
        return {
            "turn_count": self.ctx.turn_count,
            "elapsed_seconds": round(self.ctx.elapsed, 1),
            "remaining_seconds": round(self.ctx.remaining, 1),
            "pct_elapsed": round(self.ctx.pct_elapsed, 1),
            "plan_written": self.ctx.plan_written,
            "bootstrap_done": self.ctx.bootstrap_done,
            "verification_attempted": self.ctx.verification_attempted,
            "verification_passed": self.ctx.verification_passed,
            "files_edited": dict(self.ctx.file_edits),
            "consecutive_errors": self.ctx.consecutive_same_error,
        }


if __name__ == "__main__":
    pipeline = MiddlewarePipeline()
    pipeline.ctx.timeout_seconds = 900

    print("Turn 1 - agent starts implementing without plan:")
    injections = pipeline.process_turn("Let me install python packages: pip install numpy")
    for inj in injections:
        print(inj)

    print("\nTurn 2 - agent writes plan:")
    injections = pipeline.process_turn(
        "Step 1: Read instruction\nStep 2: Install deps\nStep 3: Implement"
    )
    for inj in injections:
        print(inj)

    print(f"\nPlan written: {pipeline.ctx.plan_written}")

    print("\nTurn 3 - agent claims done without testing:")
    injections = pipeline.process_turn("The task is complete. Everything works correctly.")
    for inj in injections:
        print(inj)

    print("\nCan exit?", pipeline.can_exit())
    print("\nStatus:", json.dumps(pipeline.get_status(), indent=2))
