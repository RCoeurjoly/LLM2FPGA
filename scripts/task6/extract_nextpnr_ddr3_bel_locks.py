#!/usr/bin/env python3
"""Extract targeted DDR3 BEL locks from a nextpnr --write JSON artifact."""

from __future__ import annotations

import argparse
import json
from collections import Counter
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


def load_top_cells(path: Path) -> dict[str, Any]:
    data = json.loads(path.read_text(encoding="utf-8"))
    for module in data["modules"].values():
        if module.get("attributes", {}).get("top") == "00000000000000000000000000000001":
            return module["cells"]
    if "top" in data["modules"]:
        return data["modules"]["top"]["cells"]
    if len(data["modules"]) == 1:
        return next(iter(data["modules"].values()))["cells"]
    raise KeyError("could not identify top module")


def extract_locks(placed_json: Path) -> dict[str, Any]:
    cells = load_top_cells(placed_json)
    locks: list[dict[str, str]] = []
    skipped_missing_bel: list[dict[str, str]] = []

    for name, cell in sorted(cells.items()):
        cell_type = cell.get("type", "")
        scope = cell_scope(name, cell_type)
        if scope is None:
            continue
        bel = cell.get("attributes", {}).get("NEXTPNR_BEL")
        if not bel:
            skipped_missing_bel.append(
                {"cell": name, "type": cell_type, "scope": scope}
            )
            continue
        locks.append({"cell": name, "type": cell_type, "scope": scope, "bel": bel})

    type_counts = Counter(lock["type"] for lock in locks)
    scope_counts = Counter(lock["scope"] for lock in locks)
    return {
        "format": "task6.nextpnr-ddr3-bel-locks.v1",
        "source_placed_json": str(placed_json),
        "lock_count": len(locks),
        "type_counts": dict(sorted(type_counts.items())),
        "scope_counts": dict(sorted(scope_counts.items())),
        "skipped_missing_bel_count": len(skipped_missing_bel),
        "skipped_missing_bel": skipped_missing_bel,
        "locks": locks,
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Extract DDR3-related nextpnr BEL locks from placed JSON."
    )
    parser.add_argument("--placed-json", required=True, type=Path)
    parser.add_argument("--out-json", required=True, type=Path)
    args = parser.parse_args()

    report = extract_locks(args.placed_json)
    args.out_json.write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    summary_keys = ("lock_count", "type_counts", "scope_counts")
    print(
        json.dumps(
            {key: report[key] for key in summary_keys},
            indent=2,
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
