#!/usr/bin/env python3
"""Wrap raw Yosys stat output or an explicit bottleneck into one JSON report."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    parser.add_argument("--status", required=True, choices=["ok", "oom-bottleneck"])
    parser.add_argument("--input-filelist", required=True)
    parser.add_argument("--memory-inventory", required=True)
    parser.add_argument("--raw-yosys-json")
    parser.add_argument("--exit-code", type=int)
    parser.add_argument("--top", default="main")
    return parser.parse_args()


def load_json(path: str | None) -> dict | None:
    if path is None:
        return None
    return json.loads(Path(path).read_text(encoding="utf-8"))


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


def pct(part: int | None, whole: int | None) -> float | None:
    if part is None or whole in (None, 0):
        return None
    return round((part * 100.0) / whole, 2)


def summarize_top_cell_types(
    cell_counts: dict[str, Any], total_cells: int | None, top_count: int = 8
) -> list[dict[str, Any]]:
    rows = []
    for cell_type, raw_count in cell_counts.items():
        count = as_int(raw_count)
        if count is None:
            continue
        rows.append(
            {
                "type": cell_type,
                "count": count,
                "pct_of_design_cells": pct(count, total_cells),
            }
        )
    rows.sort(key=lambda row: row["count"], reverse=True)
    return rows[:top_count]


def summarize_largest_memories(
    top_modules: list[dict[str, Any]], total_bits: int | None, top_count: int = 4
) -> list[dict[str, Any]]:
    rows = []
    for module in top_modules[:top_count]:
        bits = as_int(module.get("memory_bits"))
        rows.append(
            {
                "module": module.get("module"),
                "file": module.get("file"),
                "width_bits": as_int(module.get("width_bits")),
                "depth": as_int(module.get("depth")),
                "memory_bits": bits,
                "pct_of_total_memory_bits": pct(bits, total_bits),
            }
        )
    return rows


def build_reviewer_summary(
    status: str, inventory: dict | None, raw_yosys: dict | None, top: str
) -> dict[str, Any]:
    inventory = inventory or {}
    bundle_metrics = inventory.get("bundle_metrics") or {}
    memory_inventory = inventory.get("memory_inventory") or {}
    main_sv = bundle_metrics.get("main_sv") or {}

    total_memory_bits = as_int(memory_inventory.get("total_memory_bits"))
    largest_four_bits = as_int(memory_inventory.get("largest_four_memory_bits"))
    top_modules = memory_inventory.get("top_modules") or []

    summary: dict[str, Any] = {
        "overall_finding": (
            "Yosys completed and emitted a stat report for the emitted SystemVerilog bundle."
            if status == "ok"
            else "Yosys did not complete; the emitted SystemVerilog bundle provides explicit size evidence for the bottleneck."
        ),
        "sv_bundle": {
            "file_count": as_int(bundle_metrics.get("file_count")),
            "total_bytes": as_int(bundle_metrics.get("total_bytes")),
            "main_sv_path": main_sv.get("path"),
            "main_sv_bytes": as_int(main_sv.get("bytes")),
            "main_sv_lines": as_int(main_sv.get("lines")),
        },
        "memory_modules": {
            "module_count": as_int(memory_inventory.get("module_count")),
            "total_memory_bits": total_memory_bits,
            "largest_four_memory_bits": largest_four_bits,
            "largest_four_pct_of_total_memory_bits": pct(
                largest_four_bits, total_memory_bits
            ),
            "largest_modules": summarize_largest_memories(top_modules, total_memory_bits),
        },
    }

    if status == "ok" and raw_yosys is not None:
        design = raw_yosys.get("design") or {}
        total_cells = as_int(design.get("num_cells"))
        summary["design"] = {
            "top": top,
            "num_cells": total_cells,
            "top_cell_types": summarize_top_cell_types(
                design.get("num_cells_by_type") or {}, total_cells
            ),
        }

    return summary


def format_int(value: int | None) -> str:
    if value is None:
        return "unknown"
    return f"{value:,}"


def format_pct(value: float | None) -> str:
    if value is None:
        return "unknown"
    return f"{value:.2f}%"


def build_reviewer_summary_lines(
    status: str, reviewer_summary: dict[str, Any], diagnostic: dict[str, Any] | None = None
) -> list[str]:
    lines = [f"status: {status}", reviewer_summary["overall_finding"]]

    sv_bundle = reviewer_summary.get("sv_bundle") or {}
    lines.append(
        "sv bundle: "
        f"{format_int(as_int(sv_bundle.get('file_count')))} files, "
        f"{format_int(as_int(sv_bundle.get('total_bytes')))} bytes total, "
        f"main.sv {format_int(as_int(sv_bundle.get('main_sv_lines')))} lines / "
        f"{format_int(as_int(sv_bundle.get('main_sv_bytes')))} bytes"
    )

    memory_modules = reviewer_summary.get("memory_modules") or {}
    lines.append(
        "memory modules: "
        f"{format_int(as_int(memory_modules.get('module_count')))}, "
        f"{format_int(as_int(memory_modules.get('total_memory_bits')))} bits total, "
        f"largest four {format_int(as_int(memory_modules.get('largest_four_memory_bits')))} bits "
        f"({format_pct(memory_modules.get('largest_four_pct_of_total_memory_bits'))})"
    )

    largest_modules = memory_modules.get("largest_modules") or []
    if largest_modules:
        lines.append(
            "largest memories: "
            + ", ".join(
                f"{row.get('module')}={format_int(as_int(row.get('memory_bits')))} bits"
                for row in largest_modules
            )
        )

    design = reviewer_summary.get("design")
    if design is not None:
        lines.append(f"design cells: {format_int(as_int(design.get('num_cells')))}")
        top_cell_types = design.get("top_cell_types") or []
        if top_cell_types:
            lines.append(
                "top cell types: "
                + ", ".join(
                    f"{row.get('type')}={format_int(as_int(row.get('count')))}"
                    for row in top_cell_types[:5]
                )
            )

    if diagnostic is not None:
        lines.append(
            "diagnostic: "
            f"exit_code={diagnostic.get('exit_code')}, "
            f"reason={diagnostic.get('reason')}, "
            f"likely_cause={diagnostic.get('likely_cause')}"
        )

    return lines


def main() -> None:
    args = parse_args()
    inventory = load_json(args.memory_inventory)
    raw_yosys = load_json(args.raw_yosys_json)
    reviewer_summary = build_reviewer_summary(
        args.status, inventory, raw_yosys, args.top
    )

    payload = {
        "status": args.status,
        "tool": "yosys-slang",
        "top": args.top,
        "input_filelist": args.input_filelist,
        "memory_inventory": inventory,
        "reviewer_summary": reviewer_summary,
    }

    if args.status == "ok":
        payload["report_kind"] = "yosys-stat"
        payload["yosys_stat"] = raw_yosys
        payload["reviewer_summary_lines"] = build_reviewer_summary_lines(
            args.status, reviewer_summary
        )
    else:
        payload["report_kind"] = "explicit-bottleneck-report"
        payload["diagnostic"] = {
            "exit_code": args.exit_code,
            "reason": "Yosys was killed while processing the emitted SystemVerilog bundle.",
            "likely_cause": "out-of-memory during SystemVerilog frontend or elaboration",
        }
        payload["reviewer_summary_lines"] = build_reviewer_summary_lines(
            args.status, reviewer_summary, payload["diagnostic"]
        )

    Path(args.output).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()
