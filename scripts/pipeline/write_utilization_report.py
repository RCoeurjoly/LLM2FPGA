#!/usr/bin/env python3
"""Summarize mapped Yosys JSON into utilization report artifacts."""

from __future__ import annotations

import argparse
from collections import Counter
import json
import math
from pathlib import Path
import re
from typing import Any


LUT_RE = re.compile(r"^(?:LUT[1-6]|LUT6_2|CFGLUT5)$")
FF_TYPES = {
    "FDCE",
    "FDPE",
    "FDRE",
    "FDSE",
    "LDCE",
    "LDPE",
}
DSP_TYPES = {"DSP48E1"}
BRAM36_TYPES = {"FIFO36E1", "RAMB36E1"}
BRAM18_TYPES = {"FIFO18E1", "RAMB18E1"}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--design-json", required=True)
    parser.add_argument("--top", required=True)
    parser.add_argument("--summary-json", required=True)
    parser.add_argument("--summary-txt", required=True)
    parser.add_argument("--stat-json", required=True)
    parser.add_argument("--capacity-slices", type=int, required=True)
    parser.add_argument("--capacity-clb-luts", type=int, required=True)
    parser.add_argument("--capacity-clb-ffs", type=int, required=True)
    parser.add_argument("--capacity-dsp", type=int, required=True)
    parser.add_argument("--capacity-bram36", type=int, required=True)
    parser.add_argument("--capacity-bram-kb", type=int, required=True)
    return parser.parse_args()


def counter_to_dict(counter: Counter[str]) -> dict[str, int]:
    return dict(sorted(counter.items()))


def pct(used: float | int, capacity: int) -> float:
    if capacity <= 0:
        return 0.0
    return round((float(used) * 100.0) / float(capacity), 2)


def module_direct_cell_counts(module: dict[str, Any]) -> Counter[str]:
    counts: Counter[str] = Counter()
    for cell in (module.get("cells") or {}).values():
        cell_type = cell.get("type")
        if isinstance(cell_type, str):
            counts[cell_type] += 1
    return counts


def leaf_cell_counts(
    modules: dict[str, dict[str, Any]], mod_name: str, memo: dict[str, Counter[str]], stack: set[str]
) -> Counter[str]:
    if mod_name in memo:
        return memo[mod_name]
    if mod_name in stack:
        raise RuntimeError(f"cycle detected while expanding module hierarchy at {mod_name}")

    stack.add(mod_name)
    module = modules.get(mod_name)
    if module is None:
        raise RuntimeError(f"top module {mod_name!r} not found in design JSON")

    counts: Counter[str] = Counter()
    for cell in (module.get("cells") or {}).values():
        cell_type = cell.get("type")
        if not isinstance(cell_type, str):
            continue
        if cell_type in modules:
            counts.update(leaf_cell_counts(modules, cell_type, memo, stack))
        else:
            counts[cell_type] += 1

    stack.remove(mod_name)
    memo[mod_name] = counts
    return counts


def summarize_resources(
    top_counts: Counter[str],
    capacity_slices: int,
    capacity_clb_luts: int,
    capacity_clb_ffs: int,
    capacity_dsp: int,
    capacity_bram36: int,
    capacity_bram_kb: int,
) -> dict[str, Any]:
    used_luts = sum(count for cell_type, count in top_counts.items() if LUT_RE.match(cell_type))
    used_ffs = sum(count for cell_type, count in top_counts.items() if cell_type in FF_TYPES)
    used_dsps = sum(count for cell_type, count in top_counts.items() if cell_type in DSP_TYPES)
    used_bram36 = sum(count for cell_type, count in top_counts.items() if cell_type in BRAM36_TYPES)
    used_bram18 = sum(count for cell_type, count in top_counts.items() if cell_type in BRAM18_TYPES)
    used_bram36_equiv = used_bram36 + (used_bram18 / 2.0)
    used_bram_kb = (used_bram36 * 36) + (used_bram18 * 18)
    slice_lower_bound = max(math.ceil(used_luts / 8), math.ceil(used_ffs / 8))

    return {
        "slices_lower_bound": {
            "used": slice_lower_bound,
            "capacity": capacity_slices,
            "pct": pct(slice_lower_bound, capacity_slices),
        },
        "clb_luts": {
            "used": used_luts,
            "capacity": capacity_clb_luts,
            "pct": pct(used_luts, capacity_clb_luts),
        },
        "clb_ffs": {
            "used": used_ffs,
            "capacity": capacity_clb_ffs,
            "pct": pct(used_ffs, capacity_clb_ffs),
        },
        "dsp": {
            "used": used_dsps,
            "capacity": capacity_dsp,
            "pct": pct(used_dsps, capacity_dsp),
        },
        "bram36": {
            "used": used_bram36,
            "capacity": capacity_bram36,
            "pct": pct(used_bram36, capacity_bram36),
        },
        "bram18": {
            "used": used_bram18,
        },
        "bram36_equiv": {
            "used": used_bram36_equiv,
            "capacity": capacity_bram36,
            "pct": pct(used_bram36_equiv, capacity_bram36),
        },
        "bram_kb": {
            "used": used_bram_kb,
            "capacity": capacity_bram_kb,
            "pct": pct(used_bram_kb, capacity_bram_kb),
        },
    }


def top_types(counter: Counter[str], top_count: int = 12) -> list[dict[str, int]]:
    return [
        {"type": cell_type, "count": count}
        for cell_type, count in counter.most_common(top_count)
    ]


def summary_lines(top: str, resources: dict[str, Any], top_cell_types: list[dict[str, int]]) -> list[str]:
    lines = [f"top: {top}", "estimated mapped resource usage:"]
    for key in ["slices_lower_bound", "clb_luts", "clb_ffs", "dsp", "bram36", "bram36_equiv", "bram_kb"]:
        row = resources[key]
        lines.append(
            f"- {key}: {row['used']} / {row['capacity']} ({row['pct']:.2f}%)"
        )
    if resources["bram18"]["used"]:
        lines.append(f"- bram18: {resources['bram18']['used']}")
    if top_cell_types:
        lines.append("largest leaf cell types:")
        for row in top_cell_types:
            lines.append(f"- {row['type']}: {row['count']}")
    return lines


def main() -> None:
    args = parse_args()
    design_json_path = Path(args.design_json)
    summary_json_path = Path(args.summary_json)
    summary_txt_path = Path(args.summary_txt)
    stat_json_path = Path(args.stat_json)

    design = json.loads(design_json_path.read_text(encoding="utf-8"))
    modules = design.get("modules")
    if not isinstance(modules, dict):
        raise SystemExit(f"{design_json_path} does not contain a modules object")

    memo: dict[str, Counter[str]] = {}
    top_leaf_counts = leaf_cell_counts(modules, args.top, memo, set())

    module_stats = {
        mod_name: {
            "direct_cell_counts": counter_to_dict(module_direct_cell_counts(module)),
            "leaf_cell_counts": counter_to_dict(leaf_cell_counts(modules, mod_name, memo, set())),
        }
        for mod_name, module in sorted(modules.items())
    }

    resources = summarize_resources(
        top_leaf_counts,
        capacity_slices=args.capacity_slices,
        capacity_clb_luts=args.capacity_clb_luts,
        capacity_clb_ffs=args.capacity_clb_ffs,
        capacity_dsp=args.capacity_dsp,
        capacity_bram36=args.capacity_bram36,
        capacity_bram_kb=args.capacity_bram_kb,
    )
    top_cell_types = top_types(top_leaf_counts)

    summary_payload = {
        "design_json": str(design_json_path),
        "top": args.top,
        "resources": resources,
        "top_leaf_cell_types": top_cell_types,
    }
    stat_payload = {
        "design_json": str(design_json_path),
        "top": args.top,
        "top_leaf_cell_counts": counter_to_dict(top_leaf_counts),
        "modules": module_stats,
    }

    summary_json_path.write_text(
        json.dumps(summary_payload, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    summary_txt_path.write_text(
        "\n".join(summary_lines(args.top, resources, top_cell_types)) + "\n",
        encoding="utf-8",
    )
    stat_json_path.write_text(
        json.dumps(stat_payload, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
