#!/usr/bin/env python3
"""Write a YPCB DDR3 DQ/DQS lane grouping report from open metadata."""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import json
import re
from collections import Counter
from pathlib import Path
from typing import Any


UCF_RE = re.compile(
    r'NET\s+"(?P<net>[^"]+)"\s+LOC\s+=\s+"(?P<loc>[^"]+)"'
)
INDEXED_NET_RE = re.compile(r"(?P<base>[^\[]+)\[(?P<index>[0-9]+)\]$")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--memory-ch0-ucf", required=True, type=Path)
    parser.add_argument("--memory-ch0-ucf-artifact-label")
    parser.add_argument("--package-pins-csv", required=True, type=Path)
    parser.add_argument("--package-pins-csv-artifact-label")
    parser.add_argument("--out-dir", required=True, type=Path)
    parser.add_argument("--date", default=dt.date.today().isoformat())
    parser.add_argument("--artifact-name", default="h2-ypcb-ddr3-lane-report")
    return parser.parse_args()


def parse_ucf(path: Path) -> tuple[dict[str, dict[int, str]], dict[str, str]]:
    indexed: dict[str, dict[int, str]] = {}
    scalars: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        match = UCF_RE.search(line)
        if match is None:
            continue
        net = match.group("net")
        loc = match.group("loc")
        indexed_match = INDEXED_NET_RE.fullmatch(net)
        if indexed_match is None:
            scalars[net] = loc
            continue
        indexed.setdefault(indexed_match.group("base"), {})[
            int(indexed_match.group("index"))
        ] = loc
    return indexed, scalars


def parse_package_pins(path: Path) -> dict[str, dict[str, str]]:
    with path.open(newline="", encoding="utf-8") as handle:
        return {row["pin"]: row for row in csv.DictReader(handle)}


def require_indices(indices: dict[int, str], count: int, name: str) -> list[str]:
    missing = [index for index in range(count) if index not in indices]
    if missing:
        raise ValueError(f"{name} missing indices: {missing}")
    return [indices[index] for index in range(count)]


def pin_info(pin: str, package_pins: dict[str, dict[str, str]]) -> dict[str, str | None]:
    row = package_pins.get(pin)
    if row is None:
        return {
            "pin": pin,
            "bank": None,
            "site": None,
            "tile": None,
            "pin_function": None,
        }
    return {
        "pin": pin,
        "bank": row.get("bank"),
        "site": row.get("site"),
        "tile": row.get("tile"),
        "pin_function": row.get("pin_function"),
    }


def render_lane_summary(lanes: list[dict[str, Any]]) -> str:
    lines = [
        "artifact: h2-ypcb-ddr3-lane-report",
        "controller path: LiteDRAM/LiteX only",
        "Vivado MIG lane: rejected",
        "",
        "DQ/DQS lane grouping from MEMORY_CH0.ucf and openXC7 package pins:",
    ]
    for lane in lanes:
        dq_desc = ", ".join(
            f"dq{dq['index']}={dq['pin']}:{dq['bank']}:{dq['pin_function']}"
            for dq in lane["dq"]
        )
        lines.extend(
            [
                f"- lane {lane['lane']}: DQS {lane['dqs_p']['pin']}/"
                f"{lane['dqs_n']['pin']} bank {lane['dqs_bank']} "
                f"({lane['dqs_p']['pin_function']})",
                f"  DQ banks: {lane['dq_bank_counts']}; "
                f"same bank as DQS: {lane['all_dq_same_bank_as_dqs']}",
                f"  {dq_desc}",
            ]
        )
    return "\n".join(lines) + "\n"


def main() -> None:
    args = parse_args()
    indexed, scalars = parse_ucf(args.memory_ch0_ucf)
    package_pins = parse_package_pins(args.package_pins_csv)

    dq = require_indices(indexed.get("ddr3_dq", {}), 72, "ddr3_dq")
    dqs_p = require_indices(indexed.get("ddr3_dqs_p", {}), 9, "ddr3_dqs_p")
    dqs_n = require_indices(indexed.get("ddr3_dqs_n", {}), 9, "ddr3_dqs_n")

    lanes: list[dict[str, Any]] = []
    mismatched_lanes: list[int] = []
    for lane in range(9):
        dqs_p_info = pin_info(dqs_p[lane], package_pins)
        dqs_n_info = pin_info(dqs_n[lane], package_pins)
        dq_infos = []
        for bit in range(8):
            index = lane * 8 + bit
            info = pin_info(dq[index], package_pins)
            dq_infos.append({"index": index, **info})
        dq_bank_counts = Counter(str(info["bank"]) for info in dq_infos)
        dqs_bank = str(dqs_p_info["bank"])
        all_dq_same_bank_as_dqs = (
            len(dq_bank_counts) == 1 and next(iter(dq_bank_counts)) == dqs_bank
        )
        if not all_dq_same_bank_as_dqs:
            mismatched_lanes.append(lane)
        lanes.append(
            {
                "lane": lane,
                "expected_dq_indices": list(range(lane * 8, lane * 8 + 8)),
                "dqs_p": dqs_p_info,
                "dqs_n": dqs_n_info,
                "dqs_bank": dqs_bank,
                "dq_bank_counts": dict(sorted(dq_bank_counts.items())),
                "all_dq_same_bank_as_dqs": all_dq_same_bank_as_dqs,
                "dq": dq_infos,
            }
        )

    control_pins = {
        name: pin_info(pin, package_pins)
        for name, pin in sorted(scalars.items())
        if name.startswith("ddr3_")
    }
    indexed_controls = {
        name: [pin_info(pin, package_pins) for pin in require_indices(indices, len(indices), name)]
        for name, indices in sorted(indexed.items())
        if name
        in {
            "ddr3_addr",
            "ddr3_ba",
            "ddr3_ck_p",
            "ddr3_ck_n",
            "ddr3_cke",
            "ddr3_cs_n",
            "ddr3_odt",
        }
    }

    payload = {
        "artifact_name": args.artifact_name,
        "status": "PASS" if not mismatched_lanes else "PARTIAL",
        "date": args.date,
        "policy": {
            "vivado_mig_lane": "rejected",
            "controller_path": "LiteDRAM/LiteX only",
        },
        "source_artifacts": {
            "memory_ch0_ucf": (
                args.memory_ch0_ucf_artifact_label or str(args.memory_ch0_ucf)
            ),
            "package_pins_csv": (
                args.package_pins_csv_artifact_label or str(args.package_pins_csv)
            ),
        },
        "lane_model": (
            "LiteDRAM receives pads.dq in UCF index order. For an x8 module lane, "
            "DQ indices lane*8..lane*8+7 are expected to share the matching "
            "DQS index and package bank."
        ),
        "lanes": lanes,
        "control_pins": control_pins,
        "indexed_controls": indexed_controls,
        "validation": {
            "dq_count": len(dq),
            "dqs_p_count": len(dqs_p),
            "dqs_n_count": len(dqs_n),
            "all_lanes_same_bank_as_dqs": not mismatched_lanes,
            "mismatched_lanes": mismatched_lanes,
        },
        "decision": {
            "verdict": (
                "ucf-lane-groups-are-bank-consistent"
                if not mismatched_lanes
                else "inspect-ucf-lane-bank-mismatches"
            ),
            "next_gate": (
                "Use the bank-consistent UCF byte-lane groups as the reference "
                "when building the DFII byte/phase/address association probe."
            ),
        },
    }

    args.out_dir.mkdir(parents=True, exist_ok=True)
    (args.out_dir / "summary.json").write_text(
        json.dumps(payload, indent=2) + "\n",
        encoding="utf-8",
    )
    (args.out_dir / "summary.txt").write_text(
        render_lane_summary(lanes),
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
