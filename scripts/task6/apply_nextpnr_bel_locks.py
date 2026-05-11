#!/usr/bin/env python3
"""Apply extracted nextpnr BEL locks to a Yosys JSON netlist."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def find_top_module(netlist: dict[str, Any]) -> dict[str, Any]:
    for module in netlist["modules"].values():
        if module.get("attributes", {}).get("top") == "00000000000000000000000000000001":
            return module
    if "top" in netlist["modules"]:
        return netlist["modules"]["top"]
    if len(netlist["modules"]) == 1:
        return next(iter(netlist["modules"].values()))
    raise KeyError("could not identify top module")


def module_for_cell(
    netlist: dict[str, Any], parent: dict[str, Any], cell_name: str
) -> dict[str, Any]:
    cell = parent["cells"][cell_name]
    return netlist["modules"][cell["type"]]


def find_lock_target(
    netlist: dict[str, Any], top_module: dict[str, Any], hierarchical_name: str
) -> dict[str, Any] | None:
    if hierarchical_name in top_module["cells"]:
        return top_module["cells"][hierarchical_name]

    phy_prefix = "uberddr3.ddr3_phy_inst."
    if hierarchical_name.startswith(phy_prefix):
        if "uberddr3" not in top_module["cells"]:
            return None
        ddr3_top = module_for_cell(netlist, top_module, "uberddr3")
        if "ddr3_phy_inst" not in ddr3_top["cells"]:
            return None
        ddr3_phy = module_for_cell(netlist, ddr3_top, "ddr3_phy_inst")
        local_name = hierarchical_name[len(phy_prefix) :]
        return ddr3_phy["cells"].get(local_name)

    return None


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Patch a Yosys JSON netlist with nextpnr BEL attributes."
    )
    parser.add_argument("--yosys-json", required=True, type=Path)
    parser.add_argument("--locks-json", required=True, type=Path)
    parser.add_argument("--out-json", required=True, type=Path)
    parser.add_argument(
        "--allow-missing",
        action="store_true",
        help="Do not fail when a lock cell is absent from the target netlist.",
    )
    args = parser.parse_args()

    netlist = load_json(args.yosys_json)
    locks_doc = load_json(args.locks_json)
    top_module = find_top_module(netlist)

    applied: list[dict[str, str]] = []
    missing: list[dict[str, str]] = []
    conflicts: list[dict[str, str]] = []

    for lock in locks_doc["locks"]:
        name = lock["cell"]
        cell = find_lock_target(netlist, top_module, name)
        if cell is None:
            missing.append(lock)
            continue
        attrs = cell.setdefault("attributes", {})
        old_bel = attrs.get("BEL")
        if old_bel and old_bel != lock["bel"]:
            conflicts.append(
                {
                    "cell": name,
                    "type": lock["type"],
                    "old_bel": old_bel,
                    "new_bel": lock["bel"],
                }
            )
        attrs["BEL"] = lock["bel"]
        applied.append(lock)

    if conflicts:
        print(json.dumps({"conflicts": conflicts}, indent=2, sort_keys=True))
        return 1
    if missing and not args.allow_missing:
        print(json.dumps({"missing": missing}, indent=2, sort_keys=True))
        return 1

    netlist.setdefault("task6_bel_lock_report", {})
    netlist["task6_bel_lock_report"] = {
        "format": "task6.nextpnr-ddr3-bel-lock-application.v1",
        "source_yosys_json": str(args.yosys_json),
        "source_locks_json": str(args.locks_json),
        "applied_count": len(applied),
        "missing_count": len(missing),
        "missing": missing,
    }

    args.out_json.write_text(
        json.dumps(netlist, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(
        json.dumps(
            {"applied_count": len(applied), "missing_count": len(missing)},
            indent=2,
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
