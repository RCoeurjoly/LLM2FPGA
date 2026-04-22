#!/usr/bin/env python3
"""Wrap raw Yosys RTLIL stat output into a stage-oriented report."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-il", required=True)
    parser.add_argument("--raw-yosys-json", required=True)
    parser.add_argument("--summary-json", required=True)
    parser.add_argument("--summary-txt", required=True)
    parser.add_argument("--stat-json", required=True)
    parser.add_argument("--top", required=True)
    parser.add_argument("--stage-id", required=True)
    return parser.parse_args()


def load_json(path: str) -> dict[str, Any]:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def write_json(path: str, payload: dict[str, Any]) -> None:
    Path(path).write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )


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


def percent(part: int | None, whole: int | None) -> float | None:
    if part is None or whole in (None, 0):
        return None
    return round((part * 100.0) / whole, 2)


def count_lines(text: str) -> int:
    if not text:
        return 0
    return text.count("\n") + (0 if text.endswith("\n") else 1)


def find_top_module(modules: dict[str, Any], top: str) -> str:
    candidates = [top, f"\\{top}"]
    for candidate in candidates:
        if candidate in modules:
            return candidate
    raise SystemExit(
        f"top module {top!r} was not found in Yosys stat modules: {sorted(modules)[:8]}"
    )


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
                "pct_of_top_num_cells": percent(count, total_cells),
            }
        )
    rows.sort(key=lambda row: row["count"], reverse=True)
    return rows[:top_count]


def build_summary(
    input_il: str,
    top: str,
    stage_id: str,
    raw_yosys: dict[str, Any],
) -> dict[str, Any]:
    modules = raw_yosys.get("modules")
    if not isinstance(modules, dict):
        raise SystemExit(f"{input_il} stat JSON does not contain a modules object")

    top_key = find_top_module(modules, top)
    top_module = modules[top_key]
    top_num_cells = as_int(top_module.get("num_cells"))

    rtlil_text = Path(input_il).read_text(encoding="utf-8", errors="replace")
    rtlil_path = Path(input_il)

    design_summary = {
        "module_count": len(modules),
        "top_module_key": top_key,
        "num_wires": as_int(top_module.get("num_wires")),
        "num_wire_bits": as_int(top_module.get("num_wire_bits")),
        "num_pub_wires": as_int(top_module.get("num_pub_wires")),
        "num_pub_wire_bits": as_int(top_module.get("num_pub_wire_bits")),
        "num_ports": as_int(top_module.get("num_ports")),
        "num_port_bits": as_int(top_module.get("num_port_bits")),
        "num_memories": as_int(top_module.get("num_memories")),
        "num_memory_bits": as_int(top_module.get("num_memory_bits")),
        "num_processes": as_int(top_module.get("num_processes")),
        "num_cells": top_num_cells,
        "num_submodules": as_int(top_module.get("num_submodules")),
        "top_cell_types": summarize_top_cell_types(
            top_module.get("num_cells_by_type") or {}, top_num_cells
        ),
    }

    return {
        "stage_id": stage_id,
        "top": top,
        "rtlil": {
            "path": input_il,
            "bytes": rtlil_path.stat().st_size,
            "lines": count_lines(rtlil_text),
        },
        "design": design_summary,
    }


def format_int(value: int | None) -> str:
    if value is None:
        return "unknown"
    return f"{value:,}"


def format_pct(value: float | None) -> str:
    if value is None:
        return "unknown"
    return f"{value:.2f}%"


def build_summary_text(summary: dict[str, Any]) -> str:
    rtlil = summary["rtlil"]
    design = summary["design"]
    lines = [
        f"stage: {summary['stage_id']}",
        f"top: {summary['top']}",
        (
            "rtlil: "
            f"{format_int(as_int(rtlil.get('lines')))} lines, "
            f"{format_int(as_int(rtlil.get('bytes')))} bytes"
        ),
        (
            "design summary: "
            f"{format_int(as_int(design.get('module_count')))} module definitions, "
            f"{format_int(as_int(design.get('num_cells')))} top cells, "
            f"{format_int(as_int(design.get('num_submodules')))} submodule instances"
        ),
        (
            "wires/memory: "
            f"{format_int(as_int(design.get('num_wires')))} wires / "
            f"{format_int(as_int(design.get('num_wire_bits')))} wire bits, "
            f"{format_int(as_int(design.get('num_memories')))} memories / "
            f"{format_int(as_int(design.get('num_memory_bits')))} memory bits"
        ),
        (
            "ports/processes: "
            f"{format_int(as_int(design.get('num_ports')))} ports / "
            f"{format_int(as_int(design.get('num_port_bits')))} port bits, "
            f"{format_int(as_int(design.get('num_processes')))} processes"
        ),
    ]

    top_cell_types = design.get("top_cell_types") or []
    if top_cell_types:
        lines.append(
            "top cell types: "
            + ", ".join(
                f"{row['type']}={format_int(as_int(row.get('count')))}"
                f" ({format_pct(row.get('pct_of_top_num_cells'))})"
                for row in top_cell_types
            )
        )

    return "\n".join(lines) + "\n"


def main() -> None:
    args = parse_args()
    raw_yosys = load_json(args.raw_yosys_json)
    summary = build_summary(args.input_il, args.top, args.stage_id, raw_yosys)

    write_json(args.summary_json, summary)
    Path(args.summary_txt).write_text(
        build_summary_text(summary), encoding="utf-8"
    )

    stat_payload = dict(summary)
    stat_payload["yosys_stat"] = raw_yosys
    write_json(args.stat_json, stat_payload)


if __name__ == "__main__":
    main()
