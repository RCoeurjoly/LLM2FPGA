#!/usr/bin/env python3
"""Compare two stage-stat bundles stage by stage."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


METRICS = [
    ("rtlil.bytes", "rtlil bytes"),
    ("rtlil.lines", "rtlil lines"),
    ("design.module_count", "module defs"),
    ("design.num_cells", "top cells"),
    ("design.num_submodules", "submodule instances"),
    ("design.num_wires", "wires"),
    ("design.num_wire_bits", "wire bits"),
    ("design.num_memories", "memories"),
    ("design.num_memory_bits", "memory bits"),
    ("design.num_processes", "processes"),
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline-dir", required=True)
    parser.add_argument("--candidate-dir", required=True)
    parser.add_argument("--baseline-label", required=True)
    parser.add_argument("--candidate-label", required=True)
    parser.add_argument("--stage-map-json")
    parser.add_argument("--summary-json", required=True)
    parser.add_argument("--summary-txt", required=True)
    return parser.parse_args()


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def get_stage_order(bundle_dir: Path) -> list[str]:
    index_path = bundle_dir / "index.json"
    if index_path.exists():
        payload = load_json(index_path)
        stages = payload.get("stageOrder")
        if not isinstance(stages, list):
            stages = payload.get("stages")
        if isinstance(stages, list):
            return [stage for stage in stages if isinstance(stage, str)]
    return sorted(
        child.name for child in bundle_dir.iterdir() if (child / "summary.json").exists()
    )


def load_stage_summaries(bundle_dir: Path, stage_order: list[str]) -> dict[str, dict[str, Any]]:
    summaries: dict[str, dict[str, Any]] = {}
    for stage in stage_order:
        summary_path = bundle_dir / stage / "summary.json"
        if summary_path.exists():
            summaries[stage] = load_json(summary_path)
    return summaries


def nested_get(payload: dict[str, Any], path: str) -> Any:
    value: Any = payload
    for part in path.split("."):
        if not isinstance(value, dict):
            return None
        value = value.get(part)
    return value


def as_int(value: Any) -> int | None:
    if value is None:
        return None
    if isinstance(value, bool):
        return int(value)
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return int(value)
    if isinstance(value, str):
        try:
            return int(value)
        except ValueError:
            return None
    return None


def pct(delta: int | None, baseline: int | None) -> float | None:
    if delta is None or baseline in (None, 0):
        return None
    return round((delta * 100.0) / baseline, 2)


def format_int(value: int | None) -> str:
    if value is None:
        return "unknown"
    return f"{value:,}"


def format_delta(delta: int | None, delta_pct: float | None) -> str:
    if delta is None:
        return "unknown"
    pct_suffix = "" if delta_pct is None else f" ({delta_pct:+.2f}%)"
    return f"{delta:+,}{pct_suffix}"


def compare_stage(
    baseline: dict[str, Any], candidate: dict[str, Any]
) -> dict[str, Any]:
    metrics: dict[str, Any] = {}
    for path, label in METRICS:
        baseline_value = as_int(nested_get(baseline, path))
        candidate_value = as_int(nested_get(candidate, path))
        delta = (
            None
            if baseline_value is None or candidate_value is None
            else candidate_value - baseline_value
        )
        metrics[path] = {
            "label": label,
            "baseline": baseline_value,
            "candidate": candidate_value,
            "delta": delta,
            "delta_pct_of_baseline": pct(delta, baseline_value),
        }
    return metrics


def load_stage_pairs(args: argparse.Namespace) -> list[dict[str, str]]:
    if not args.stage_map_json:
        return []

    payload = load_json(Path(args.stage_map_json))
    if not isinstance(payload, list):
        raise SystemExit("stage map JSON must be a list")

    pairs: list[dict[str, str]] = []
    for idx, item in enumerate(payload):
        if not isinstance(item, dict):
            raise SystemExit(f"stage map entry {idx} must be an object")
        stage_id = item.get("id")
        baseline_stage = item.get("baseline")
        candidate_stage = item.get("candidate")
        if not all(isinstance(value, str) and value for value in [stage_id, baseline_stage, candidate_stage]):
            raise SystemExit(
                f"stage map entry {idx} must contain non-empty string fields "
                "'id', 'baseline', and 'candidate'"
            )
        pair = {
            "id": stage_id,
            "baseline": baseline_stage,
            "candidate": candidate_stage,
        }
        label = item.get("label")
        if isinstance(label, str) and label:
            pair["label"] = label
        pairs.append(pair)
    return pairs


def build_summary_lines(payload: dict[str, Any]) -> list[str]:
    lines = [
        f"baseline: {payload['baseline_label']}",
        f"candidate: {payload['candidate_label']}",
    ]
    comparable = payload.get("comparable_stages") or []
    missing = payload.get("missing_stages") or {}
    lines.append(f"comparable stages: {len(comparable)}")
    if missing.get("baseline_only"):
        lines.append("baseline-only stages: " + ", ".join(missing["baseline_only"]))
    if missing.get("candidate_only"):
        lines.append("candidate-only stages: " + ", ".join(missing["candidate_only"]))

    for stage in comparable:
        stage_payload = payload["stages"][stage]
        metrics = stage_payload["metrics"]
        key_metrics = [
            "rtlil.bytes",
            "design.num_cells",
            "design.num_submodules",
            "design.num_memory_bits",
        ]
        stage_desc = stage
        baseline_stage = stage_payload.get("baseline_stage")
        candidate_stage = stage_payload.get("candidate_stage")
        label = stage_payload.get("label")
        if isinstance(label, str) and label:
            stage_desc = f"{stage_desc} ({label})"
        if baseline_stage != candidate_stage:
            stage_desc = f"{stage_desc} [{baseline_stage} vs {candidate_stage}]"
        lines.append(
            f"{stage_desc}: "
            + "; ".join(
                (
                    f"{metrics[key]['label']} "
                    f"{format_int(as_int(metrics[key].get('baseline')))} -> "
                    f"{format_int(as_int(metrics[key].get('candidate')))} "
                    f"({format_delta(as_int(metrics[key].get('delta')), metrics[key].get('delta_pct_of_baseline'))})"
                )
                for key in key_metrics
            )
        )
    return lines


def main() -> None:
    args = parse_args()
    baseline_dir = Path(args.baseline_dir)
    candidate_dir = Path(args.candidate_dir)

    baseline_order = get_stage_order(baseline_dir)
    candidate_order = get_stage_order(candidate_dir)

    baseline_summaries = load_stage_summaries(baseline_dir, baseline_order)
    candidate_summaries = load_stage_summaries(candidate_dir, candidate_order)
    stage_pairs = load_stage_pairs(args)

    if stage_pairs:
        comparable_stages = [
            pair["id"]
            for pair in stage_pairs
            if pair["baseline"] in baseline_summaries and pair["candidate"] in candidate_summaries
        ]
        missing_stages = {
            "baseline_only": [
                pair["baseline"]
                for pair in stage_pairs
                if pair["baseline"] not in baseline_summaries
            ],
            "candidate_only": [
                pair["candidate"]
                for pair in stage_pairs
                if pair["candidate"] not in candidate_summaries
            ],
        }
        stages_payload = {}
        for pair in stage_pairs:
            if pair["id"] not in comparable_stages:
                continue
            stage_entry = {
                "stage_id": pair["id"],
                "baseline_stage": pair["baseline"],
                "candidate_stage": pair["candidate"],
                "metrics": compare_stage(
                    baseline_summaries[pair["baseline"]],
                    candidate_summaries[pair["candidate"]],
                ),
            }
            if "label" in pair:
                stage_entry["label"] = pair["label"]
            stages_payload[pair["id"]] = stage_entry
    else:
        comparable_stages = [stage for stage in baseline_order if stage in candidate_summaries]
        missing_stages = {
            "baseline_only": [stage for stage in baseline_order if stage not in candidate_summaries],
            "candidate_only": [stage for stage in candidate_order if stage not in baseline_summaries],
        }
        stages_payload = {
            stage: {
                "stage_id": stage,
                "baseline_stage": stage,
                "candidate_stage": stage,
                "metrics": compare_stage(
                    baseline_summaries[stage], candidate_summaries[stage]
                ),
            }
            for stage in comparable_stages
        }

    payload = {
        "baseline_label": args.baseline_label,
        "candidate_label": args.candidate_label,
        "comparable_stages": comparable_stages,
        "missing_stages": missing_stages,
        "stages": stages_payload,
    }

    Path(args.summary_json).write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    Path(args.summary_txt).write_text(
        "\n".join(build_summary_lines(payload)) + "\n", encoding="utf-8"
    )


if __name__ == "__main__":
    main()
