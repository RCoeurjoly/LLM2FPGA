#!/usr/bin/env python3
"""Compare nextpnr DDR3 placement between a baseline lock set and a placed JSON.

This gate is a more direct complement to FASM diffing: it checks whether the same
DDR3-critical cells land on the same BELs, and reports movement by scope.
"""

from __future__ import annotations

import argparse
import csv
import json
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


DDR3_PHY_TYPES = {
    "IDELAYE2_IDELAYE2",
    "IDELAYCTRL_IDELAYCTRL",
    "ISERDESE2_ISERDESE2",
    "OSERDESE2_OSERDESE2",
    "IOB33_INBUF_EN",
    "IOB33_OUTBUF",
    "IOB33M_INBUF_EN",
    "IOB33M_OUTBUF",
    "IOB33S_OUTBUF",
    "INVERTER",
}

DDR3_BOARD_PIN_PREFIXES = (
    "ddram_a[",
    "ddram_ba[",
    "ddram_cas_n",
    "ddram_cke",
    "ddram_clk_n",
    "ddram_clk_p",
    "ddram_cs_n",
    "ddram_odt",
    "ddram_ras_n",
    "ddram_reset_n",
    "ddram_we_n",
)

DDR3_CLOCK_TYPES = {
    "BUFGCTRL",
    "PLLE2_ADV_PLLE2_ADV",
}


def load_top_cells(path: Path) -> dict[str, dict[str, Any]]:
    data = json.loads(path.read_text(encoding="utf-8"))
    for module in data["modules"].values():
        if module.get("attributes", {}).get("top") == "00000000000000000000000000000001":
            return module["cells"]
    if "top" in data["modules"]:
        return data["modules"]["top"]["cells"]
    if len(data["modules"]) == 1:
        return next(iter(data["modules"].values()))["cells"]
    raise KeyError("could not identify top module")


def cell_scope(name: str, cell_type: str) -> str | None:
    if cell_type in DDR3_PHY_TYPES:
        if name.startswith("uberddr3.ddr3_phy_inst."):
            return "uberddr3_phy"
    if cell_type in DDR3_PHY_TYPES:
        if name.startswith(DDR3_BOARD_PIN_PREFIXES):
            return "ddr3_board_pins"
    if cell_type in DDR3_CLOCK_TYPES:
        if name.startswith("clk") or name.startswith("clock_"):
            return "ddr3_clocks"
    return None


def extract_placement_cells(path: Path) -> dict[str, dict[str, Any]]:
    cells = load_top_cells(path)
    placement: dict[str, dict[str, Any]] = {}
    for name, cell in sorted(cells.items()):
        cell_type = cell.get("type", "")
        scope = cell_scope(name, cell_type)
        if scope is None:
            continue
        bel = cell.get("attributes", {}).get("NEXTPNR_BEL")
        placement[name] = {"type": cell_type, "scope": scope, "bel": bel}
    return placement


def read_baseline_locks(path: Path) -> dict[str, dict[str, Any]]:
    doc = json.loads(path.read_text(encoding="utf-8"))
    locks = doc.get("locks")
    if not isinstance(locks, list):
        raise ValueError("baseline locks JSON missing locks array")
    baseline: dict[str, dict[str, Any]] = {}
    for entry in locks:
        if not isinstance(entry, dict):
            continue
        name = str(entry.get("cell", ""))
        if not name:
            continue
        bel = str(entry.get("bel", "")) if entry.get("bel") is not None else None
        scope = str(entry.get("scope", "")) if entry.get("scope") else None
        cell_type = str(entry.get("type", "")) if entry.get("type") else ""
        if scope is None:
            continue
        baseline[name] = {
            "type": cell_type,
            "scope": scope,
            "bel": bel,
        }
    return baseline


def compare_placements(
    baseline: dict[str, dict[str, Any]],
    candidate: dict[str, dict[str, Any]],
    label: str,
    ignore_scopes: set[str],
    max_examples: int,
) -> dict[str, Any]:
    baseline_scopes = Counter(entry["scope"] for entry in baseline.values())
    candidate_scopes = Counter(entry["scope"] for entry in candidate.values())

    moved = []
    missing = []
    missing_bel = []
    candidate_only = []
    unchanged = []
    for cell, base in sorted(baseline.items()):
        scope = base["scope"]
        if scope in ignore_scopes:
            continue
        candidate_entry = candidate.get(cell)
        if candidate_entry is None:
            missing.append(
                {
                    "cell": cell,
                    "type": base["type"],
                    "scope": scope,
                    "baseline_bel": base["bel"],
                }
            )
            continue
        candidate_bel = candidate_entry.get("bel")
        if candidate_bel is None:
            missing_bel.append(
                {
                    "cell": cell,
                    "type": base["type"],
                    "scope": scope,
                    "baseline_bel": base["bel"],
                }
            )
            continue
        if candidate_bel != base["bel"]:
            moved.append(
                {
                    "cell": cell,
                    "type": base["type"],
                    "scope": scope,
                    "baseline_bel": base["bel"],
                    "candidate_bel": candidate_bel,
                }
            )
            continue
        unchanged.append(cell)

    for cell, entry in sorted(candidate.items()):
        scope = entry["scope"]
        if scope in ignore_scopes:
            continue
        if cell not in baseline:
            candidate_only.append(
                {
                    "cell": cell,
                    "type": entry["type"],
                    "scope": scope,
                    "candidate_bel": entry.get("bel"),
                }
            )

    fail_scopes = {"uberddr3_phy", "ddr3_clocks"}
    fail_reasons: list[str] = []
    warn_reasons: list[str] = []
    fail_count = 0
    warn_count = 0
    for item in moved + missing + missing_bel:
        if item["scope"] in fail_scopes:
            fail_count += 1
        else:
            warn_count += 1
    if fail_count:
        fail_reasons.append(
            "DDR3 PHY/clock BEL placement changed relative to known-good baseline"
        )
    if candidate_only:
        warn_count += len(
            [item for item in candidate_only if item["scope"] in fail_scopes]
        )
        if warn_count:
            warn_reasons.append(
                "Candidate includes extra DDR3-scoped placed cells not in the baseline lock set"
            )

    status = "PASS"
    if fail_count:
        status = "FAIL"
    elif warn_count:
        status = "WARN"
    else:
        status = "PASS"

    summary = {
        "baseline_cell_count": len(baseline),
        "candidate_cell_count": len(candidate),
        "unchecked_baseline_cell_count": len(
            [entry for entry in baseline.values() if entry["scope"] in ignore_scopes]
        ),
        "unchanged_count": len(unchanged),
        "moved_count": len(moved),
        "missing_count": len(missing),
        "missing_bel_count": len(missing_bel),
        "candidate_only_count": len(candidate_only),
        "critical_fail_count": fail_count,
        "warning_count": warn_count,
        "baseline_scope_counts": dict(sorted(baseline_scopes.items())),
        "candidate_scope_counts": dict(sorted(candidate_scopes.items())),
        "ignore_scopes": sorted(ignore_scopes),
    }

    return {
        "label": label,
        "status": status,
        "reasons": (fail_reasons + warn_reasons) or ["No DDR3 placement movement detected"],
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "summary": summary,
        "details": {
            "moved": moved[:max_examples],
            "moved_count_total": len(moved),
            "missing": missing[:max_examples],
            "missing_count_total": len(missing),
            "missing_bel": missing_bel[:max_examples],
            "missing_bel_count_total": len(missing_bel),
            "candidate_only": candidate_only[:max_examples],
            "candidate_only_count_total": len(candidate_only),
            "unchanged_cells_sample": unchanged[:max_examples],
            "unchanged_count_total": len(unchanged),
        },
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Compare DDR3 critical placement between baseline locks and candidate placed JSON."
    )
    parser.add_argument("--baseline-bel-locks", required=True, type=Path)
    parser.add_argument("--candidate-placed-json", required=True, type=Path)
    parser.add_argument("--label", default="task6-ddr3-placement-stability")
    parser.add_argument("--out-json", type=Path)
    parser.add_argument(
        "--out-csv",
        type=Path,
        help="Optional CSV summary including moved/missing/missing_bel/candidate-only counts.",
    )
    parser.add_argument("--max-examples", type=int, default=24)
    parser.add_argument(
        "--ignore-scope",
        action="append",
        default=[],
        help="Ignore one DDR3 scope.  Repeatable.",
    )
    parser.add_argument(
        "--fail-on-change",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Return non-zero when DDR3 placement-critical cells changed.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    baseline = read_baseline_locks(args.baseline_bel_locks)
    candidate = extract_placement_cells(args.candidate_placed_json)
    report = compare_placements(
        baseline=baseline,
        candidate=candidate,
        label=args.label,
        ignore_scopes=set(args.ignore_scope),
        max_examples=args.max_examples,
    )
    report["baseline_bel_locks"] = str(args.baseline_bel_locks)
    report["candidate_placed_json"] = str(args.candidate_placed_json)

    report_text = json.dumps(report, indent=2, sort_keys=True)
    if args.out_json is not None:
        args.out_json.parent.mkdir(parents=True, exist_ok=True)
        args.out_json.write_text(report_text + "\n", encoding="utf-8")

    if args.out_csv is not None:
        args.out_csv.parent.mkdir(parents=True, exist_ok=True)
        with args.out_csv.open("w", encoding="utf-8", newline="") as handle:
            writer = csv.writer(handle)
            writer.writerow(
                [
                    "label",
                    "status",
                    "moved_count",
                    "missing_count",
                    "missing_bel_count",
                    "candidate_only_count",
                    "critical_fail_count",
                    "warning_count",
                ]
            )
            writer.writerow(
                [
                    report["label"],
                    report["status"],
                    report["summary"]["moved_count"],
                    report["summary"]["missing_count"],
                    report["summary"]["missing_bel_count"],
                    report["summary"]["candidate_only_count"],
                    report["summary"]["critical_fail_count"],
                    report["summary"]["warning_count"],
                ]
            )

    print(report_text)
    if args.fail_on_change and report["status"] != "PASS":
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
