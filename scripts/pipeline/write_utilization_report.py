#!/usr/bin/env python3
"""Estimate FPGA resource usage from a mapped Yosys JSON design."""

from __future__ import annotations

import argparse
from collections import Counter
import json
import math
from pathlib import Path
import re
from typing import Any


LUT_RE = re.compile(r"^(LUT[1-6]|LUT6_2|CFGLUT5)$")
FF_TYPES = {"FDCE", "FDPE", "FDRE", "FDSE", "LDCE", "LDPE"}
DSP_TYPES = {"DSP48E1"}
BRAM36_TYPES = {"FIFO36E1", "RAMB36E1"}
BRAM18_TYPES = {"FIFO18E1", "RAMB18E1"}

SUMMARY_ORDER = ["slices_lower_bound", "clb_luts", "clb_ffs", "dsp", "bram36", "bram36_equiv", "bram_kb"]
CAPACITY = {
    "slices_lower_bound": "capacity_slices",
    "clb_luts": "capacity_clb_luts",
    "clb_ffs": "capacity_clb_ffs",
    "dsp": "capacity_dsp",
    "bram36": "capacity_bram36",
    "bram36_equiv": "capacity_bram36",
    "bram_kb": "capacity_bram_kb",
}


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser()
    for name in ["design-json", "top", "summary-json", "summary-txt", "stat-json"]:
        p.add_argument(f"--{name}", required=True)
    for name in ["slices", "clb-luts", "clb-ffs", "dsp", "bram36", "bram-kb"]:
        p.add_argument(f"--capacity-{name}", type=int, required=True)
    return p.parse_args()


def write_json(path: str, payload: dict[str, Any]) -> None:
    Path(path).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def cell_counts(module: dict[str, Any]) -> Counter[str]:
    counts: Counter[str] = Counter()
    for cell in (module.get("cells") or {}).values():
        if isinstance(cell.get("type"), str):
            counts[cell["type"]] += 1
    return counts


def attr_is_true(value: Any) -> bool:
    if value is None:
        return False
    if isinstance(value, str):
        stripped = value.strip()
        if not stripped:
            return False
        if stripped in {"0", "false", "False"}:
            return False
        return any(char != "0" for char in stripped)
    return bool(value)


def is_blackbox_module(module: dict[str, Any]) -> bool:
    attrs = module.get("attributes") or {}
    if not isinstance(attrs, dict):
        return False
    return attr_is_true(attrs.get("blackbox"))


def leaf_counts(
    modules: dict[str, dict[str, Any]],
    name: str,
    memo: dict[str, Counter[str]],
    stack: set[str],
) -> Counter[str]:
    if name in memo:
        return memo[name]
    if name in stack:
        raise SystemExit(f"module hierarchy cycle at {name}")
    if name not in modules:
        raise SystemExit(f"module {name!r} not found in design JSON")

    if is_blackbox_module(modules[name]):
        counts = Counter({name: 1})
        memo[name] = counts
        return counts

    stack.add(name)
    counts: Counter[str] = Counter()
    for cell_type, instances in cell_counts(modules[name]).items():
        if cell_type not in modules:
            counts[cell_type] += instances
            continue
        for leaf_type, leaves_per_instance in leaf_counts(modules, cell_type, memo, stack).items():
            counts[leaf_type] += instances * leaves_per_instance
    stack.remove(name)

    memo[name] = counts
    return counts


def as_dict(counts: Counter[str]) -> dict[str, int]:
    return dict(sorted(counts.items()))


def summarize(counts: Counter[str], args: argparse.Namespace) -> dict[str, Any]:
    def count(types: set[str]) -> int:
        return sum(n for cell_type, n in counts.items() if cell_type in types)

    def row(key: str, used: float) -> dict[str, float | int]:
        capacity = getattr(args, CAPACITY[key])
        return {
            "used": used,
            "capacity": capacity,
            "pct": 0.0 if capacity <= 0 else round(100.0 * used / capacity, 2),
        }

    luts = sum(n for cell_type, n in counts.items() if LUT_RE.match(cell_type))
    ffs = count(FF_TYPES)
    bram36 = count(BRAM36_TYPES)
    bram18 = count(BRAM18_TYPES)
    used = {
        "slices_lower_bound": max(math.ceil(luts / 8), math.ceil(ffs / 8)),
        "clb_luts": luts,
        "clb_ffs": ffs,
        "dsp": count(DSP_TYPES),
        "bram36": bram36,
        "bram18": bram18,
        "bram36_equiv": bram36 + bram18 / 2.0,
        "bram_kb": bram36 * 36 + bram18 * 18,
    }
    resources = {"bram18": {"used": bram18}}
    for key in SUMMARY_ORDER:
        resources[key] = row(key, used[key])
    return resources


def top_types(counts: Counter[str]) -> list[dict[str, int]]:
    return [{"type": cell_type, "count": count} for cell_type, count in counts.most_common(12)]


def number(value: float | int) -> str:
    return f"{value:g}" if isinstance(value, float) else str(value)


def summary_text(top: str, resources: dict[str, Any], top_cell_types: list[dict[str, int]]) -> str:
    lines = [f"top: {top}", "estimated mapped resource usage:"]
    for key in SUMMARY_ORDER:
        row = resources[key]
        lines.append(f"- {key}: {number(row['used'])} / {row['capacity']} ({row['pct']:.2f}%)")
    if resources["bram18"]["used"]:
        lines.append(f"- bram18: {resources['bram18']['used']}")
    if top_cell_types:
        lines.append("largest leaf cell types:")
        lines += [f"- {row['type']}: {row['count']}" for row in top_cell_types]
    return "\n".join(lines) + "\n"


def main() -> None:
    args = parse_args()
    design = json.loads(Path(args.design_json).read_text(encoding="utf-8"))
    modules = design.get("modules")
    if not isinstance(modules, dict):
        raise SystemExit(f"{args.design_json} does not contain a modules object")

    memo: dict[str, Counter[str]] = {}
    top_counts = leaf_counts(modules, args.top, memo, set())
    resources = summarize(top_counts, args)
    top_cell_types = top_types(top_counts)

    write_json(args.summary_json, {
        "design_json": args.design_json,
        "top": args.top,
        "resources": resources,
        "top_leaf_cell_types": top_cell_types,
    })
    Path(args.summary_txt).write_text(summary_text(args.top, resources, top_cell_types), encoding="utf-8")
    write_json(args.stat_json, {
        "design_json": args.design_json,
        "top": args.top,
        "top_leaf_cell_counts": as_dict(top_counts),
        "modules": {
            name: {
                "direct_cell_counts": as_dict(cell_counts(module)),
                "leaf_cell_counts": as_dict(leaf_counts(modules, name, memo, set())),
            }
            for name, module in sorted(modules.items())
        },
    })


if __name__ == "__main__":
    main()
