#!/usr/bin/env python3
"""Analyze Harbor benchmark job results.

Usage:
    python analyze.py jobs/<job-name>/
    python analyze.py jobs/<job-name>/ --verbose
    python analyze.py jobs/<job-name>/ --failures
    python analyze.py jobs/ --aggregate          # cross-run best-of
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

RATE_LIMIT_MARKERS = ["out of extra usage", "OverloadedError", "rate limit"]


def _parse_task_dir(task_dir: Path) -> dict:
    """Parse a single task directory into a result dict."""
    task_name = task_dir.name.rsplit("__", 1)[0]

    result_file = task_dir / "result.json"
    agent_log = task_dir / "agent" / "claude-code.txt"

    status = "unknown"
    score = None
    turns = 0
    cost = 0.0
    duration_ms = 0
    error = None
    rate_limited = False

    if result_file.exists():
        try:
            result = json.loads(result_file.read_text())
            verifier = result.get("verifier_result", {})
            if verifier:
                reward = verifier.get("rewards", {}).get("reward", None)
                if reward is not None:
                    score = reward
                    status = "pass" if reward > 0 else "fail"

            agent_result = result.get("agent_result") or {}
            cost = agent_result.get("cost_usd", 0.0) or 0.0

            agent_exec = result.get("agent_execution") or {}
            if agent_exec.get("started_at") and agent_exec.get("finished_at"):
                from datetime import datetime

                start = datetime.fromisoformat(agent_exec["started_at"].rstrip("Z"))
                end = datetime.fromisoformat(agent_exec["finished_at"].rstrip("Z"))
                duration_ms = (end - start).total_seconds() * 1000

            exc_info = result.get("exception_info")
            if exc_info:
                exc_type = exc_info.get("exception_type", "")
                error = f"{exc_type}: {exc_info.get('exception_message', '')}"[:100]
                # Only override status if verifier didn't already determine pass/fail
                if status not in ("pass", "fail"):
                    if "AgentTimeout" in exc_type:
                        status = "timeout"
                    else:
                        status = "infra-error"
        except (json.JSONDecodeError, KeyError):
            status = "eval-error"

    if agent_log.exists():
        try:
            for line in agent_log.read_text().strip().splitlines():
                data = json.loads(line)
                if data.get("type") == "result":
                    turns = data.get("num_turns", 0)
                    if not cost:
                        cost = data.get("total_cost_usd", 0.0) or 0.0
                    if not duration_ms:
                        duration_ms = data.get("duration_ms", 0)
                    result_text = str(data.get("result", ""))
                    if data.get("is_error"):
                        error = error or result_text[:100]
                        if any(m in result_text for m in RATE_LIMIT_MARKERS):
                            rate_limited = True
                        elif turns <= 2 and cost < 0.01:
                            rate_limited = True
                        elif status == "unknown":
                            status = "agent-error"
        except (json.JSONDecodeError, KeyError):
            pass

    if rate_limited and status in ("fail", "unknown", "agent-error"):
        status = "rate-limited"

    return {
        "task": task_name,
        "status": status,
        "score": score,
        "turns": turns,
        "cost": cost,
        "duration_s": duration_ms / 1000,
        "error": error,
    }


def _print_summary(results: list[dict], label: str) -> None:
    passed = sum(1 for r in results if r["status"] == "pass")
    failed = sum(1 for r in results if r["status"] == "fail")
    rate_ltd = sum(1 for r in results if r["status"] == "rate-limited")
    timeouts = sum(1 for r in results if r["status"] == "timeout")
    errors = sum(
        1 for r in results if r["status"] in ("agent-error", "eval-error", "infra-error", "unknown")
    )
    total = len(results)
    fair = passed + failed
    total_cost = sum(r["cost"] for r in results)
    total_time = sum(r["duration_s"] for r in results)

    print(f"{'=' * 60}")
    print(f"Job: {label}")
    print(f"{'=' * 60}")
    if fair:
        print(f"Fair rate: {passed}/{fair} ({100 * passed / fair:.1f}%)")
    print(f"Passed:   {passed}")
    print(f"Failed:   {failed}")
    print(f"Timeout:  {timeouts}")
    print(f"Rate ltd: {rate_ltd}")
    print(f"Errors:   {errors}")
    print(f"Cost:     ${total_cost:.2f}")
    print(f"Time:     {total_time / 60:.1f} min")
    print(f"{'=' * 60}")


def _print_details(results: list[dict], *, failures_only: bool = False) -> None:
    print(f"\n{'Task':<45} {'Status':<14} {'Turns':>5} {'Cost':>8} {'Time':>8}")
    print("-" * 82)
    for r in sorted(results, key=lambda x: x["status"]):
        if failures_only and r["status"] == "pass":
            continue
        time_str = f"{r['duration_s']:.0f}s" if r["duration_s"] else "?"
        cost_str = f"${r['cost']:.3f}" if r["cost"] else "?"
        print(
            f"{r['task']:<45} {r['status']:<14} {r['turns']:>5} {cost_str:>8} {time_str:>8}"
        )
        if r.get("error") and not failures_only:
            print(f"  └─ {r['error']}")


def analyze_job(
    job_dir: Path, *, verbose: bool = False, failures_only: bool = False
) -> None:
    results: list[dict] = []
    for task_dir in sorted(job_dir.iterdir()):
        if not task_dir.is_dir():
            continue
        results.append(_parse_task_dir(task_dir))

    if not results:
        print(f"No results found in {job_dir}")
        return

    _print_summary(results, job_dir.name)
    if verbose or failures_only:
        _print_details(results, failures_only=failures_only)


def aggregate(jobs_dir: Path, *, verbose: bool = False) -> None:
    """Best-of across all runs, with proper rate-limit detection."""
    STATUS_PRIORITY = {
        "pass": 0,
        "fail": 1,
        "timeout": 2,
        "infra-error": 3,
        "agent-error": 4,
        "rate-limited": 5,
        "eval-error": 6,
        "unknown": 7,
    }
    best: dict[str, dict] = {}

    for job_dir in sorted(jobs_dir.iterdir()):
        if not job_dir.is_dir():
            continue
        for task_dir in job_dir.iterdir():
            if not task_dir.is_dir():
                continue
            r = _parse_task_dir(task_dir)
            r["source"] = job_dir.name
            cur_p = STATUS_PRIORITY.get(r["status"], 7)
            existing = best.get(r["task"])
            if existing is None or cur_p < STATUS_PRIORITY.get(existing["status"], 7):
                best[r["task"]] = r

    results = sorted(best.values(), key=lambda x: x["task"])
    _print_summary(results, f"AGGREGATE ({jobs_dir.name})")
    if verbose:
        _print_details(results)


def main() -> None:
    if len(sys.argv) < 2:
        print(
            "Usage: python analyze.py <job-dir> [--verbose] [--failures] [--aggregate]"
        )
        sys.exit(1)

    job_dir = Path(sys.argv[1])
    verbose = "--verbose" in sys.argv or "-v" in sys.argv
    failures_only = "--failures" in sys.argv or "-f" in sys.argv
    agg = "--aggregate" in sys.argv or "--agg" in sys.argv

    if not job_dir.exists():
        print(f"ERROR: {job_dir} does not exist")
        sys.exit(1)

    if agg:
        aggregate(job_dir, verbose=verbose)
    else:
        analyze_job(job_dir, verbose=verbose, failures_only=failures_only)


if __name__ == "__main__":
    main()
