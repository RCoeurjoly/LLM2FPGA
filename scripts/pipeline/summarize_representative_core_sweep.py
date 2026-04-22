#!/usr/bin/env python3
"""Summarize representative-core sweep compare bundles."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest-json", required=True)
    parser.add_argument("--summary-json", required=True)
    parser.add_argument("--summary-txt", required=True)
    return parser.parse_args()


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def fmt_int(value: int | float | None) -> str:
    if value is None:
        return "unknown"
    if isinstance(value, float) and not value.is_integer():
        return f"{value:,.2f}"
    return f"{int(value):,}"


def fmt_pct(value: float | None) -> str:
    if value is None:
        return "unknown"
    return f"{value:+.2f}%"


def row_status(stage8_delta: int | None, clb_luts_delta: int | float | None) -> str:
    if stage8_delta is None or clb_luts_delta is None:
        return "incomplete"
    if stage8_delta < 0 and clb_luts_delta < 0:
        return "helpful"
    if stage8_delta < 0 or clb_luts_delta < 0:
        return "mixed"
    return "worse"


def build_row(entry: dict[str, Any]) -> dict[str, Any]:
    compare_dir = Path(entry["compare_dir"])
    stage_stats = load_json(compare_dir / "stage-stats" / "summary.json")
    utilization = load_json(compare_dir / "utilization" / "summary.json")

    stage8_metrics = ((stage_stats.get("stages") or {}).get("stage8") or {}).get("metrics") or {}
    stage8_rtlil = stage8_metrics.get("rtlil.bytes") or {}
    clb_luts = ((utilization.get("resources") or {}).get("clb_luts")) or {}
    slices = ((utilization.get("resources") or {}).get("slices_lower_bound")) or {}

    row = {
        "key": entry["key"],
        "label": entry.get("label"),
        "config": entry["config"],
        "compare_dir": str(compare_dir),
        "stage8_rtlil_bytes_delta": stage8_rtlil.get("delta"),
        "stage8_rtlil_bytes_delta_pct": stage8_rtlil.get("delta_pct_of_baseline"),
        "clb_luts_delta": clb_luts.get("delta_used"),
        "clb_luts_delta_pct": clb_luts.get("delta_pct_of_baseline"),
        "slices_delta": slices.get("delta_used"),
        "slices_delta_pct": slices.get("delta_pct_of_baseline"),
    }
    row["status"] = row_status(
        row["stage8_rtlil_bytes_delta"], row["clb_luts_delta"]
    )
    return row


def build_summary_lines(payload: dict[str, Any]) -> list[str]:
    lines = [
        "Representative-core all-memory vs top4-memory sweep",
        f"variants: {len(payload['variants'])}",
        f"first helpful variant: {payload.get('first_helpful_variant') or 'none'}",
        "",
    ]

    for row in payload["variants"]:
        config = row["config"]
        lines.append(
            (
                f"{row['key']} [{row['status']}]: "
                f"vocab={config['vocab_size']} layers={config['num_layers']} "
                f"hidden={config['hidden_size']} heads={config['num_heads']} "
                f"pos={config['max_position_embeddings']} win={config['window_size']}; "
                f"stage8 rtlil delta={fmt_int(row['stage8_rtlil_bytes_delta'])} "
                f"({fmt_pct(row['stage8_rtlil_bytes_delta_pct'])}); "
                f"clb_luts delta={fmt_int(row['clb_luts_delta'])} "
                f"({fmt_pct(row['clb_luts_delta_pct'])}); "
                f"slices delta={fmt_int(row['slices_delta'])} "
                f"({fmt_pct(row['slices_delta_pct'])})"
            )
        )
    return lines


def main() -> None:
    args = parse_args()
    manifest = load_json(Path(args.manifest_json))
    if not isinstance(manifest, list):
        raise SystemExit("manifest JSON must be a list")

    rows = [build_row(entry) for entry in manifest]
    first_helpful_variant = next(
        (row["key"] for row in rows if row["status"] == "helpful"), None
    )

    payload = {
        "variants": rows,
        "first_helpful_variant": first_helpful_variant,
    }
    Path(args.summary_json).write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    Path(args.summary_txt).write_text(
        "\n".join(build_summary_lines(payload)) + "\n", encoding="utf-8"
    )


if __name__ == "__main__":
    main()
