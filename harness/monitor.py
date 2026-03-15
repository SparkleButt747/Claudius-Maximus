#!/usr/bin/env python3
"""Monitor a running Harbor benchmark job. Usage: python monitor.py jobs/<job-name>/"""

from __future__ import annotations

import json
import sys
from datetime import datetime
from pathlib import Path


def monitor(job_dir: Path) -> None:
    done, passed, failed, running = 0, 0, 0, 0
    pass_list, fail_list = [], []

    for d in sorted(job_dir.iterdir()):
        if not d.is_dir():
            continue
        task_name = d.name.rsplit("__", 1)[0]
        result_file = d / "result.json"
        if result_file.exists():
            try:
                r = json.loads(result_file.read_text())
                vr = r.get("verifier_result", {})
                reward = vr.get("rewards", {}).get("reward", 0) if vr else 0
                done += 1
                if reward > 0:
                    passed += 1
                    pass_list.append(task_name)
                else:
                    failed += 1
                    exc = r.get("exception_info")
                    reason = exc.get("exception_type", "") if exc else ""
                    fail_list.append(f"{task_name} ({reason})" if reason else task_name)
            except Exception:
                done += 1
                failed += 1
                fail_list.append(f"{task_name} (parse-error)")
        else:
            running += 1

    total = done + running
    print(f"[{datetime.now().strftime('%H:%M:%S')}] {done}/{total} done | "
          f"{passed} pass | {failed} fail | {running} running")
    if done > 0:
        print(f"  Pass rate: {100 * passed / done:.1f}% "
              f"(projected {100 * passed / total:.1f}% if current rate holds)")
    if fail_list:
        print(f"  Failures: {', '.join(fail_list)}")


if __name__ == "__main__":
    job_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("jobs/latest")
    if not job_dir.exists():
        print(f"ERROR: {job_dir} does not exist")
        sys.exit(1)
    monitor(job_dir)
