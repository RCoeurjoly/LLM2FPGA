#!/usr/bin/env python3
"""Compare two utilization-report bundles."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


RESOURCE_ORDER = [
    "slices_lower_bound",
    "clb_luts",
    "clb_ffs",
    "dsp",
    "bram36",
    "bram36_equiv",
    "bram_kb",
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline-dir", required=True)
    parser.add_argument("--candidate-dir", required=True)
    parser.add_argument("--baseline-label", required=True)
    parser.add_argument("--candidate-label", required=True)
    parser.add_argument("--summary-json", required=True)
    parser.add_argument("--summary-txt", required=True)
    return parser.parse_args()


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def as_number(value: Any) -> int | float | None:
    if value is None:
        return None
    if isinstance(value, bool):
        return int(value)
    if isinstance(value, (int, float)):
        return value
    if isinstance(value, str):
        try:
            return int(value)
        except ValueError:
            try:
                return float(value)
            except ValueError:
                return None
    return None


def fmt_number(value: int | float | None) -> str:
    if value is None:
        return "unknown"
    if isinstance(value, float) and not value.is_integer():
        return f"{value:,.2f}"
    return f"{int(value):,}"


def pct(delta: int | float | None, baseline: int | float | None) -> float | None:
    if delta is None or baseline in (None, 0):
        return None
    return round((float(delta) * 100.0) / float(baseline), 2)


def compare_resource(
    baseline_row: dict[str, Any] | None, candidate_row: dict[str, Any] | None
) -> dict[str, Any]:
    baseline_used = as_number((baseline_row or {}).get("used"))
    candidate_used = as_number((candidate_row or {}).get("used"))
    baseline_capacity = as_number((baseline_row or {}).get("capacity"))
    candidate_capacity = as_number((candidate_row or {}).get("capacity"))
    delta = (
        None
        if baseline_used is None or candidate_used is None
        else candidate_used - baseline_used
    )
    return {
        "baseline_used": baseline_used,
        "candidate_used": candidate_used,
        "delta_used": delta,
        "delta_pct_of_baseline": pct(delta, baseline_used),
        "baseline_capacity": baseline_capacity,
        "candidate_capacity": candidate_capacity,
    }


def compare_top_leaf_types(
    baseline_counts: dict[str, int], candidate_counts: dict[str, int]
) -> list[dict[str, Any]]:
    common_types = sorted(set(baseline_counts) | set(candidate_counts))
    deltas: list[dict[str, Any]] = []
    for cell_type in common_types:
        baseline_value = baseline_counts.get(cell_type, 0)
        candidate_value = candidate_counts.get(cell_type, 0)
        delta = candidate_value - baseline_value
        if delta == 0:
            continue
        deltas.append(
            {
                "type": cell_type,
                "baseline": baseline_value,
                "candidate": candidate_value,
                "delta": delta,
                "delta_pct_of_baseline": pct(delta, baseline_value),
            }
        )
    deltas.sort(key=lambda row: abs(row["delta"]), reverse=True)
    return deltas[:12]


def build_summary_lines(payload: dict[str, Any]) -> list[str]:
    lines = [
        f"baseline: {payload['baseline_label']}",
        f"candidate: {payload['candidate_label']}",
        "resource deltas:",
    ]
    for key in RESOURCE_ORDER:
        row = payload["resources"][key]
        pct_suffix = (
            ""
            if row["delta_pct_of_baseline"] is None
            else f" ({row['delta_pct_of_baseline']:+.2f}%)"
        )
        lines.append(
            f"- {key}: {fmt_number(row['baseline_used'])} -> "
            f"{fmt_number(row['candidate_used'])} "
            f"({fmt_number(row['delta_used'])}{pct_suffix})"
        )

    top_leaf_deltas = payload.get("top_leaf_type_deltas") or []
    if top_leaf_deltas:
        lines.append("largest leaf-cell deltas:")
        for row in top_leaf_deltas:
            pct_suffix = (
                ""
                if row["delta_pct_of_baseline"] is None
                else f" ({row['delta_pct_of_baseline']:+.2f}%)"
            )
            lines.append(
                f"- {row['type']}: {fmt_number(row['baseline'])} -> "
                f"{fmt_number(row['candidate'])} "
                f"({fmt_number(row['delta'])}{pct_suffix})"
            )
    return lines


def main() -> None:
    args = parse_args()
    baseline_dir = Path(args.baseline_dir)
    candidate_dir = Path(args.candidate_dir)

    baseline_summary = load_json(baseline_dir / "summary.json")
    candidate_summary = load_json(candidate_dir / "summary.json")
    baseline_stat = load_json(baseline_dir / "stat.json")
    candidate_stat = load_json(candidate_dir / "stat.json")

    baseline_resources = baseline_summary.get("resources") or {}
    candidate_resources = candidate_summary.get("resources") or {}

    payload = {
        "baseline_label": args.baseline_label,
        "candidate_label": args.candidate_label,
        "resources": {
            key: compare_resource(
                baseline_resources.get(key), candidate_resources.get(key)
            )
            for key in RESOURCE_ORDER
        },
        "top_leaf_type_deltas": compare_top_leaf_types(
            baseline_stat.get("top_leaf_cell_counts") or {},
            candidate_stat.get("top_leaf_cell_counts") or {},
        ),
    }

    Path(args.summary_json).write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    Path(args.summary_txt).write_text(
        "\n".join(build_summary_lines(payload)) + "\n", encoding="utf-8"
    )


if __name__ == "__main__":
    main()
