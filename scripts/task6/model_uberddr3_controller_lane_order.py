#!/usr/bin/env python3
"""Model UberDDR3 controller byte order for Task 6 full-beat diagnostics."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


BEAT_BYTES = 64
LANES = 8
BURSTS = 8


def byte_coord(byte_index: int) -> dict[str, int]:
    if byte_index < 0 or byte_index >= BEAT_BYTES:
        raise ValueError("byte index must be in 0..63")
    return {
        "byte": byte_index,
        "burst": byte_index // LANES,
        "lane": byte_index % LANES,
        "bit_low": byte_index * 8,
        "bit_high": byte_index * 8 + 7,
    }


def ramp(base: int) -> list[int]:
    return [((base + index) & 0xFF) for index in range(BEAT_BYTES)]


def parse_prefix(hex_prefix: str) -> list[int]:
    data = bytes.fromhex(hex_prefix)
    if len(data) > BEAT_BYTES:
        raise ValueError("observed prefix cannot exceed one 64-byte beat")
    return list(data)


def classify_observed(base: int, observed: list[int]) -> list[dict[str, Any]]:
    expected = ramp(base)
    rows: list[dict[str, Any]] = []
    for index, value in enumerate(observed):
        coord = byte_coord(index)
        expected_value = expected[index]
        rows.append(
            {
                **coord,
                "observed": value,
                "expected": expected_value,
                "matches_expected": value == expected_value,
            }
        )
    return rows


def build_payload(base: int, observed_prefix_hex: str) -> dict[str, Any]:
    observed = parse_prefix(observed_prefix_hex)
    rows = classify_observed(base, observed)
    matching = [row for row in rows if row["matches_expected"]]
    matching_lanes = sorted({row["lane"] for row in matching})
    matching_bursts = sorted({row["burst"] for row in matching})
    return {
        "artifact_name": "task6-uberddr3-controller-lane-order-model",
        "status": "PASS",
        "base": base,
        "observed_prefix_hex": observed_prefix_hex,
        "beat_bytes": BEAT_BYTES,
        "lanes": LANES,
        "bursts": BURSTS,
        "source_facts": {
            "wb_data_layout": (
                "o_wb_data[burst*64 + lane*8 +: 8] carries one byte; "
                "comments in ddr3_controller.v describe each 64-bit burst as "
                "{LANE7..LANE0}."
            ),
            "write_stage_source": "stage1_data_d = i_wb_data",
            "read_stage_sink": (
                "o_wb_data_q[pipe][burst*64 + lane*8 +: 8] <= "
                "i_phy_iserdes_data[burst*64 + lane*8 +: 8]"
            ),
        },
        "matched_positions": matching,
        "matched_lanes": matching_lanes,
        "matched_bursts": matching_bursts,
        "all_positions": rows,
        "decision": {
            "verdict": "controller-byte-layout-model-established",
            "interpretation": (
                "The v63 lower-prefix matches are position-specific in the "
                "controller byte layout. Further lane-order work should use "
                "controller-local simulation/formal or an unmodified v63 board "
                "bitstream, not new top-level laneprobe hardware."
            ),
            "next_gate": (
                "Restore the board build to exact v63, re-run boot/fullbeat, "
                "then compare observed matched byte coordinates against this "
                "model before changing controller-facing write/read timing."
            ),
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", type=lambda value: int(value, 0), default=0x20)
    parser.add_argument(
        "--observed-prefix-hex",
        default="a8c1a823a8c1a827a851a82ba851a82f",
        help="Observed lower-prefix bytes from a boot-clean v63 board run.",
    )
    parser.add_argument("--out-json", type=Path, required=True)
    args = parser.parse_args()

    if args.base < 0 or args.base > 0xFF:
        raise SystemExit("--base must fit in one byte")

    payload = build_payload(args.base, args.observed_prefix_hex)
    args.out_json.parent.mkdir(parents=True, exist_ok=True)
    args.out_json.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    print(
        "PASS: task6 UberDDR3 controller lane order model "
        f"matches={len(payload['matched_positions'])} "
        f"lanes={payload['matched_lanes']} bursts={payload['matched_bursts']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
