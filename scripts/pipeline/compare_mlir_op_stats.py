#!/usr/bin/env python3
"""Compare MLIR op-stat reports between a baseline and candidate artifact."""

from __future__ import annotations

import argparse
import json
import re
from collections import Counter
from pathlib import Path
from typing import Any


OP_STAT_RE = re.compile(r"^\s*([^\s,][^,]*)\s*,\s*([0-9]+)\s*$")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline-input", required=True)
    parser.add_argument("--candidate-input", required=True)
    parser.add_argument("--baseline-stats", required=True)
    parser.add_argument("--candidate-stats", required=True)
    parser.add_argument("--baseline-label", required=True)
    parser.add_argument("--candidate-label", required=True)
    parser.add_argument("--summary-json", required=True)
    parser.add_argument("--summary-txt", required=True)
    return parser.parse_args()


def count_lines(text: str) -> int:
    if not text:
        return 0
    return text.count("\n") + (0 if text.endswith("\n") else 1)


def parse_op_stats(path: Path) -> dict[str, int]:
    counts: dict[str, int] = {}
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        match = OP_STAT_RE.match(line)
        if not match:
            continue
        op_name = match.group(1).strip()
        counts[op_name] = int(match.group(2))
    if not counts:
        raise SystemExit(f"{path} did not contain parseable MLIR op stats")
    return counts


def dialect_for_op(op_name: str) -> str:
    if "." not in op_name:
        return op_name
    return op_name.split(".", 1)[0]


def summarize_artifact(input_path: Path, stats_path: Path) -> dict[str, Any]:
    op_counts = parse_op_stats(stats_path)
    text = input_path.read_text(encoding="utf-8", errors="replace")
    dialect_op_counts = Counter(dialect_for_op(op_name) for op_name in op_counts)
    dialect_total_ops = Counter()
    for op_name, count in op_counts.items():
        dialect_total_ops[dialect_for_op(op_name)] += count

    return {
        "input": {
            "path": str(input_path),
            "bytes": input_path.stat().st_size,
            "lines": count_lines(text),
        },
        "stats_path": str(stats_path),
        "total_operations": sum(op_counts.values()),
        "distinct_operations": len(op_counts),
        "operations": dict(sorted(op_counts.items())),
        "dialects": {
            dialect: {
                "distinct_operations": dialect_op_counts[dialect],
                "total_operations": dialect_total_ops[dialect],
            }
            for dialect in sorted(dialect_op_counts)
        },
    }


def format_int(value: int) -> str:
    return f"{value:,}"


def top_count_deltas(
    baseline_ops: dict[str, int], candidate_ops: dict[str, int], limit: int = 12
) -> list[dict[str, Any]]:
    rows = []
    for op_name in sorted(set(baseline_ops) & set(candidate_ops)):
        baseline = baseline_ops[op_name]
        candidate = candidate_ops[op_name]
        delta = candidate - baseline
        rows.append(
            {
                "op": op_name,
                "baseline": baseline,
                "candidate": candidate,
                "delta": delta,
                "abs_delta": abs(delta),
            }
        )
    rows.sort(key=lambda row: (row["abs_delta"], row["op"]), reverse=True)
    return rows[:limit]


def build_summary(payload: dict[str, Any]) -> str:
    baseline = payload["baseline"]
    candidate = payload["candidate"]
    comparison = payload["comparison"]
    lines = [
        f"baseline: {payload['baseline_label']}",
        f"candidate: {payload['candidate_label']}",
        (
            "input size: "
            f"{payload['baseline_label']}={format_int(baseline['input']['bytes'])} bytes / "
            f"{format_int(baseline['input']['lines'])} lines, "
            f"{payload['candidate_label']}={format_int(candidate['input']['bytes'])} bytes / "
            f"{format_int(candidate['input']['lines'])} lines"
        ),
        (
            "operations: "
            f"{payload['baseline_label']}={format_int(baseline['total_operations'])} total / "
            f"{format_int(baseline['distinct_operations'])} distinct, "
            f"{payload['candidate_label']}={format_int(candidate['total_operations'])} total / "
            f"{format_int(candidate['distinct_operations'])} distinct"
        ),
        (
            "coverage: "
            f"ops_complete={comparison['op_coverage_complete']} "
            f"dialects_complete={comparison['dialect_coverage_complete']}"
        ),
    ]

    missing_ops = comparison["missing_operations"]
    if missing_ops:
        lines.append(
            "missing ops: "
            + ", ".join(
                f"{row['op']} (baseline {format_int(row['baseline_count'])})"
                for row in missing_ops
            )
        )
    else:
        lines.append("missing ops: none")

    extra_ops = comparison["extra_operations"]
    if extra_ops:
        lines.append(
            "extra ops: "
            + ", ".join(
                f"{row['op']} (candidate {format_int(row['candidate_count'])})"
                for row in extra_ops[:16]
            )
        )
    else:
        lines.append("extra ops: none")

    missing_dialects = comparison["missing_dialects"]
    if missing_dialects:
        lines.append("missing dialects: " + ", ".join(missing_dialects))
    else:
        lines.append("missing dialects: none")

    top_deltas = comparison["largest_count_deltas"]
    if top_deltas:
        lines.append(
            "largest shared-op deltas: "
            + ", ".join(
                (
                    f"{row['op']} "
                    f"{format_int(row['baseline'])}->{format_int(row['candidate'])} "
                    f"({row['delta']:+,})"
                )
                for row in top_deltas
            )
        )

    return "\n".join(lines) + "\n"


def main() -> None:
    args = parse_args()
    baseline = summarize_artifact(
        Path(args.baseline_input), Path(args.baseline_stats)
    )
    candidate = summarize_artifact(
        Path(args.candidate_input), Path(args.candidate_stats)
    )

    baseline_ops = baseline["operations"]
    candidate_ops = candidate["operations"]
    baseline_dialects = baseline["dialects"]
    candidate_dialects = candidate["dialects"]

    missing_operations = [
        {
            "op": op_name,
            "baseline_count": baseline_ops[op_name],
            "candidate_count": 0,
        }
        for op_name in sorted(set(baseline_ops) - set(candidate_ops))
    ]
    extra_operations = [
        {
            "op": op_name,
            "baseline_count": 0,
            "candidate_count": candidate_ops[op_name],
        }
        for op_name in sorted(set(candidate_ops) - set(baseline_ops))
    ]
    missing_dialects = sorted(set(baseline_dialects) - set(candidate_dialects))
    extra_dialects = sorted(set(candidate_dialects) - set(baseline_dialects))

    payload = {
        "baseline_label": args.baseline_label,
        "candidate_label": args.candidate_label,
        "baseline": baseline,
        "candidate": candidate,
        "comparison": {
            "op_coverage_complete": not missing_operations,
            "dialect_coverage_complete": not missing_dialects,
            "coverage_complete": not missing_operations and not missing_dialects,
            "missing_operations": missing_operations,
            "extra_operations": extra_operations,
            "missing_dialects": missing_dialects,
            "extra_dialects": extra_dialects,
            "largest_count_deltas": top_count_deltas(baseline_ops, candidate_ops),
        },
    }

    Path(args.summary_json).write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    Path(args.summary_txt).write_text(build_summary(payload), encoding="utf-8")


if __name__ == "__main__":
    main()
