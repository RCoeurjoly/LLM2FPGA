#!/usr/bin/env python3
"""Summarize an overnight Codex Task 6 run directory."""

from __future__ import annotations

import csv
import json
import sys
from pathlib import Path


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: codex_autonight_report.py <run_dir>")

    run_dir = Path(sys.argv[1])
    driver = run_dir / "driver.csv"
    report = run_dir / "SUMMARY.md"

    rows = []
    if driver.exists():
        with driver.open(newline="", encoding="utf-8") as f:
            rows = list(csv.DictReader(f))

    artifacts = []
    for path in sorted(Path("artifacts/task6/parallel-hypotheses").glob("*.json")):
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except Exception:
            continue
        name = payload.get("artifact_name") or path.stem
        status = payload.get("status")
        decision = payload.get("decision", {})
        if isinstance(decision, dict):
            verdict = decision.get("verdict")
            next_gate = decision.get("next_gate")
        else:
            verdict = None
            next_gate = None
        artifacts.append((path, name, status, verdict, next_gate))

    lines = [
        "# Codex overnight summary",
        "",
        f"- run_dir: `{run_dir}`",
        f"- iterations: {len(rows)}",
        "",
        "## Iterations",
        "",
        "| iter | start | end | rc | reason | log |",
        "| ---: | --- | --- | ---: | --- | --- |",
    ]
    for row in rows:
        lines.append(
            f"| {row.get('iteration')} | {row.get('start_iso')} | {row.get('end_iso')} | "
            f"{row.get('exit_code')} | {row.get('reason')} | `{row.get('log')}` |"
        )

    lines.extend([
        "",
        "## Recent hypothesis artifacts",
        "",
        "| artifact | status | verdict | next gate |",
        "| --- | --- | --- | --- |",
    ])
    for path, name, status, verdict, next_gate in artifacts[-20:]:
        lines.append(
            f"| `{path}` | {status or ''} | {verdict or ''} | {next_gate or ''} |"
        )

    status_file = Path("AUTONIGHT_STATUS.md")
    if status_file.exists():
        lines.extend(["", "## Final AUTONIGHT_STATUS excerpt", ""])
        text = status_file.read_text(encoding="utf-8", errors="replace")
        lines.append("```markdown")
        lines.append(text[-5000:])
        lines.append("```")

    report.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"wrote {report}")


if __name__ == "__main__":
    main()
