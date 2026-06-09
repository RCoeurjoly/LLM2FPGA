#!/usr/bin/env python3
"""Compare Task 6 loader-only seed20 against full seed20 physical artifacts."""

from __future__ import annotations

import argparse
from datetime import datetime
import json
from pathlib import Path
import re
import subprocess
import sys
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
OUT_ROOT = ROOT / "artifacts" / "task6" / "physical-comparisons"
PCIE_FASM_PATTERNS = {
    "pcie": re.compile(r"PCIE|PCIE_2_1", re.I),
    "gt": re.compile(r"GTXE2|GTP|GTX|GTHE|GTPE|CHANNEL|COMMON", re.I),
    "pcie_clock": re.compile(r"PCIE|GTX|GTPE|GTP|BUFH|BUFG|MMCM|PLL|CLK", re.I),
}
TIMING_RE = re.compile(
    r"Max frequency for clock ['\"]?(?P<clock>[^:'\"]+)['\"]?:\s+(?P<mhz>[0-9.]+)\s+MHz",
    re.I,
)


def stamp() -> str:
    return datetime.now().astimezone().strftime("%Y-%m-%dT%H-%M-%S%z")


def run_capture(argv: list[str], out_path: Path, *, check: bool = False) -> dict[str, Any]:
    proc = subprocess.run(
        argv,
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    out_path.write_text(proc.stdout, encoding="utf-8")
    result = {"argv": argv, "returncode": proc.returncode, "log": str(out_path)}
    if check and proc.returncode != 0:
        raise subprocess.CalledProcessError(proc.returncode, argv, output=proc.stdout)
    return result


def run_json(argv: list[str], log_path: Path, *, check: bool = False) -> tuple[dict[str, Any], dict[str, Any] | None]:
    result = run_capture(argv, log_path, check=check)
    text = log_path.read_text(encoding="utf-8")
    try:
        return result, json.loads(text)
    except json.JSONDecodeError:
        return result, None


def parse_fasm(path: Path) -> set[str]:
    features: set[str] = set()
    with path.open("r", encoding="utf-8") as handle:
        for raw in handle:
            line = raw.strip()
            if line and not line.startswith("#"):
                features.add(line)
    return features


def fasm_pcie_delta(loader_only: Path, full: Path, max_examples: int) -> dict[str, Any]:
    base = parse_fasm(loader_only)
    cand = parse_fasm(full)
    added = cand - base
    removed = base - cand
    classes: dict[str, Any] = {}
    for name, pattern in PCIE_FASM_PATTERNS.items():
        class_added = sorted(feature for feature in added if pattern.search(feature))
        class_removed = sorted(feature for feature in removed if pattern.search(feature))
        classes[name] = {
            "added_count": len(class_added),
            "removed_count": len(class_removed),
            "added_examples": class_added[:max_examples],
            "removed_examples": class_removed[:max_examples],
        }
    return {
        "loader_only_fasm": str(loader_only),
        "full_fasm": str(full),
        "total_added_count": len(added),
        "total_removed_count": len(removed),
        "classes": classes,
    }


IGNORED_PRIMITIVE_ATTRS = {"src", "hdlname", "module_not_derived"}


def normalized_primitive_cell(name: object) -> str:
    text = str(name or "")
    if text.startswith("impl."):
        return text[len("impl."):]
    return text


def filtered_attrs(attrs: dict[str, Any]) -> dict[str, Any]:
    return {key: value for key, value in attrs.items() if key not in IGNORED_PRIMITIVE_ATTRS}


def selected_pcie_primitives(report: dict[str, Any] | None) -> dict[str, dict[str, Any]]:
    if not report:
        return {}
    selected: dict[str, dict[str, Any]] = {}
    for primitive in report.get("primitives", []):
        cell = normalized_primitive_cell(primitive.get("cell"))
        key = f"{primitive.get('type')}::{cell}"
        selected[key] = {
            "type": primitive.get("type"),
            "parameters": primitive.get("parameters") or {},
            "attributes": filtered_attrs(primitive.get("attributes") or {}),
        }
    return selected


def dict_delta(before: dict[str, Any], after: dict[str, Any]) -> dict[str, Any]:
    delta: dict[str, Any] = {}
    for key in sorted(set(before) | set(after)):
        if before.get(key) != after.get(key):
            delta[key] = {"loader_only": before.get(key), "full": after.get(key)}
    return delta


def primitive_delta(loader_report: dict[str, Any] | None, full_report: dict[str, Any] | None) -> dict[str, Any]:
    loader = selected_pcie_primitives(loader_report)
    full = selected_pcie_primitives(full_report)
    cells: dict[str, Any] = {}
    for cell in sorted(set(loader) | set(full)):
        before = loader.get(cell, {})
        after = full.get(cell, {})
        params = dict_delta(before.get("parameters", {}), after.get("parameters", {}))
        attrs = dict_delta(before.get("attributes", {}), after.get("attributes", {}))
        if params or attrs or cell not in loader or cell not in full:
            cells[cell] = {
                "present_loader_only": cell in loader,
                "present_full": cell in full,
                "parameter_delta": params,
                "attribute_delta": attrs,
            }
    return {
        "loader_only_primitive_count": len(loader),
        "full_primitive_count": len(full),
        "changed_cell_count": len(cells),
        "changed_cells": cells,
    }


def timing_summary(paths: list[Path]) -> dict[str, Any]:
    clocks: dict[str, list[dict[str, Any]]] = {}
    for path in paths:
        if not path.exists():
            clocks[str(path)] = [{"error": "missing timing log"}]
            continue
        entries: list[dict[str, Any]] = []
        for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
            match = TIMING_RE.search(line)
            if match:
                entries.append({"clock": match.group("clock"), "mhz": float(match.group("mhz")), "line": line.strip()})
        clocks[str(path)] = entries
    return {"logs": clocks, "note": "Pass --loader-only-timing-log/--full-timing-log with nextpnr logs to populate this section."}


def classify(placement: dict[str, Any] | None, ddr_fasm: dict[str, Any] | None, pcie_delta: dict[str, Any], pcie_fasm: dict[str, Any]) -> str:
    if pcie_delta.get("changed_cell_count", 0):
        return "pcie_primitive_delta"
    pcie_counts = pcie_fasm.get("classes", {})
    if any(item.get("added_count", 0) or item.get("removed_count", 0) for item in pcie_counts.values()):
        return "pcie_physical_delta"
    if placement and placement.get("status") == "FAIL":
        return "ddr3_phy_delta"
    if ddr_fasm and ddr_fasm.get("status") in {"FAIL", "WARN"}:
        return "clock_delta"
    return "no_obvious_physical_delta"


def write_markdown(path: Path, summary: dict[str, Any]) -> None:
    lines = [
        "# Task 6 Seed20 Physical Comparison",
        "",
        f"Final classification: `{summary['classification']}`",
        "",
        "## Inputs",
        "",
        f"- loader-only Yosys JSON: `{summary['inputs']['loader_only_yosys_json']}`",
        f"- full Yosys JSON: `{summary['inputs']['full_yosys_json']}`",
        f"- loader-only placed JSON: `{summary['inputs']['loader_only_placed_json']}`",
        f"- full placed JSON: `{summary['inputs']['full_placed_json']}`",
        f"- loader-only FASM: `{summary['inputs']['loader_only_fasm']}`",
        f"- full FASM: `{summary['inputs']['full_fasm']}`",
        "",
        "## Key Counts",
        "",
        f"- PCIe primitive changed cells: `{summary['pcie_primitive_delta']['changed_cell_count']}`",
        f"- PCIe/GT FASM total added/removed: `{summary['pcie_fasm_delta']['total_added_count']}` / `{summary['pcie_fasm_delta']['total_removed_count']}`",
        f"- DDR3 placement status: `{(summary.get('ddr3_placement') or {}).get('status', 'unavailable')}`",
        f"- DDR3 FASM status: `{(summary.get('ddr3_fasm') or {}).get('status', 'unavailable')}`",
        "",
        "## Hardware Discipline",
        "",
        "Run `scripts/task6/task6_pcie_user_gate.sh lifecycle <BDF>` before any BAR access. If the classification is not `pcie_ready`, stop and keep the artifact as the result.",
        "",
    ]
    path.write_text("\n".join(lines), encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--loader-only-yosys-json", required=True, type=Path)
    parser.add_argument("--full-yosys-json", required=True, type=Path)
    parser.add_argument("--loader-only-placed-json", required=True, type=Path)
    parser.add_argument("--full-placed-json", required=True, type=Path)
    parser.add_argument("--loader-only-fasm", required=True, type=Path)
    parser.add_argument("--full-fasm", required=True, type=Path)
    parser.add_argument("--loader-only-timing-log", action="append", default=[], type=Path)
    parser.add_argument("--full-timing-log", action="append", default=[], type=Path)
    parser.add_argument("--label", default="loader-only-seed20-vs-full-seed20")
    parser.add_argument("--out-dir", type=Path)
    parser.add_argument("--max-examples", type=int, default=16)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    out_dir = args.out_dir or OUT_ROOT / f"{stamp()}-{args.label}"
    out_dir.mkdir(parents=True, exist_ok=False)

    loader_primitive_result, loader_primitive = run_json(
        [sys.executable, str(ROOT / "scripts/task6/task6_pcie_openxc7_primitive_report.py"), str(args.loader_only_yosys_json), "--pretty"],
        out_dir / "loader-only-pcie-primitives.json",
    )
    full_primitive_result, full_primitive = run_json(
        [sys.executable, str(ROOT / "scripts/task6/task6_pcie_openxc7_primitive_report.py"), str(args.full_yosys_json), "--pretty"],
        out_dir / "full-pcie-primitives.json",
    )
    run_capture(
        [sys.executable, str(ROOT / "scripts/task6/extract_nextpnr_ddr3_bel_locks.py"), "--placed-json", str(args.loader_only_placed_json), "--out-json", str(out_dir / "loader-only-ddr3-bel-locks.json")],
        out_dir / "extract-loader-only-ddr3-bel-locks.log",
        check=True,
    )
    placement_result, placement = run_json(
        [sys.executable, str(ROOT / "scripts/task6/compare_nextpnr_placement_stability.py"), "--baseline-bel-locks", str(out_dir / "loader-only-ddr3-bel-locks.json"), "--candidate-placed-json", str(args.full_placed_json), "--label", args.label, "--out-json", str(out_dir / "ddr3-placement-compare.json"), "--no-fail-on-change"],
        out_dir / "ddr3-placement-compare.stdout.json",
    )
    ddr_fasm_result, ddr_fasm = run_json(
        [sys.executable, str(ROOT / "scripts/task6/compare_nextpnr_fasm_physical_stability.py"), "--baseline-fasm", str(args.loader_only_fasm), "--candidate-fasm", str(args.full_fasm), "--label", args.label, "--out-json", str(out_dir / "ddr3-fasm-compare.json"), "--no-fail-on-change"],
        out_dir / "ddr3-fasm-compare.stdout.json",
    )

    pcie_primitives = primitive_delta(loader_primitive, full_primitive)
    pcie_fasm = fasm_pcie_delta(args.loader_only_fasm, args.full_fasm, args.max_examples)
    timing = {
        "loader_only": timing_summary(args.loader_only_timing_log),
        "full": timing_summary(args.full_timing_log),
    }
    summary = {
        "schema": "task6-seed20-physical-comparison-v1",
        "created_at": datetime.now().astimezone().isoformat(),
        "label": args.label,
        "inputs": {
            "loader_only_yosys_json": str(args.loader_only_yosys_json),
            "full_yosys_json": str(args.full_yosys_json),
            "loader_only_placed_json": str(args.loader_only_placed_json),
            "full_placed_json": str(args.full_placed_json),
            "loader_only_fasm": str(args.loader_only_fasm),
            "full_fasm": str(args.full_fasm),
        },
        "commands": {
            "loader_primitive_report": loader_primitive_result,
            "full_primitive_report": full_primitive_result,
            "placement_compare": placement_result,
            "ddr_fasm_compare": ddr_fasm_result,
        },
        "pcie_primitive_delta": pcie_primitives,
        "pcie_fasm_delta": pcie_fasm,
        "ddr3_placement": placement,
        "ddr3_fasm": ddr_fasm,
        "timing": timing,
    }
    summary["classification"] = classify(placement, ddr_fasm, pcie_primitives, pcie_fasm)

    (out_dir / "summary.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    write_markdown(out_dir / "README.md", summary)
    print(out_dir)
    print(f"classification: {summary['classification']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
