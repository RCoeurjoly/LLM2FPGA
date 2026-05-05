#!/usr/bin/env python3
"""Summarize the v98 DFII byte/phase association matrix probe."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


HYPOTHESIS = (
    "DFII byte/phase writes map to a fixed physical-to-logical byte/phase "
    "association"
)


def as_int(value: Any, default: int = 0) -> int:
    if value is None:
        return default
    if isinstance(value, bool):
        return int(value)
    if isinstance(value, int):
        return value
    if isinstance(value, str):
        text = value.strip().lower()
        if text.startswith("0x"):
            return int(text, 16)
        return int(text, 10)
    return default


def get_first_int(probe: dict[str, Any], keys: list[str], default: int = 0) -> int:
    for key in keys:
        if key in probe:
            return as_int(probe[key], default)
    return default


def get_mask_row(probe: dict[str, Any], base: str, row: int) -> int:
    row_keys = [
        f"{base}_{row}",
        f"{base}s_{row}",
        f"{base}[{row}]",
    ]
    for key in row_keys:
        if key in probe:
            return as_int(probe[key])

    for key in (base, f"{base}s"):
        value = probe.get(key)
        if isinstance(value, list) and row < len(value):
            return as_int(value[row])
        if isinstance(value, dict):
            for row_key in (str(row), f"{row}", f"row_{row}"):
                if row_key in value:
                    return as_int(value[row_key])

    matrix = probe.get("dfii_assoc_matrix")
    if isinstance(matrix, list) and row < len(matrix):
        item = matrix[row]
        if isinstance(item, dict):
            if base.endswith("match_mask"):
                return as_int(item.get("match_mask"))
            if base.endswith("nonzero_mask"):
                return as_int(item.get("nonzero_mask"))
        return as_int(item)

    return 0


def set_bit_positions(mask: int) -> list[int]:
    return [bit for bit in range(16) if mask & (1 << bit)]


def hex16(value: int) -> str:
    return f"0x{value & 0xffff:04x}"


def summarize(
    raw_probe: dict[str, Any],
    bitstream: str | None,
    sha256: str | None,
) -> dict[str, Any]:
    probe = raw_probe.get("fields", raw_probe)
    decoded = raw_probe.get("decoded", {})
    probe_version = get_first_int(
        probe,
        ["probe_version", "version", "jtag_debug_version", "debug_version"],
        0,
    )
    source_phase = get_first_int(
        probe,
        [
            "dfii_source_order_source_phase",
            "dfii_matrix_source_phase",
            "source_phase",
        ],
        0,
    )
    write_command_phase = get_first_int(
        probe,
        ["dfii_write_command_phase", "write_command_phase"],
        0,
    )
    read_phase = get_first_int(
        probe,
        ["dfii_read_command_phase", "read_command_phase"],
        2,
    )

    match_masks = [
        get_mask_row(probe, "dfii_assoc_match_mask", row)
        for row in range(16)
    ]
    nonzero_masks = [
        get_mask_row(probe, "dfii_assoc_nonzero_mask", row)
        for row in range(16)
    ]

    physical_to_logical_byte: list[int | None] = []
    write_cases: list[dict[str, Any]] = []
    one_hot = True

    for slot in range(16):
        matches = set_bit_positions(match_masks[slot])
        nonzero = set_bit_positions(nonzero_masks[slot])
        observed_slot = matches[0] if len(matches) == 1 else None
        if observed_slot is None:
            one_hot = False
        physical_to_logical_byte.append(observed_slot)

        write_case = {
            "write_phase": source_phase,
            "write_command_phase": write_command_phase,
            "write_beat": slot >> 2,
            "write_byte": slot & 3,
            "write_slot": slot,
            "pattern": f"0x{0xa0 + slot:02x}",
            "read_phase": read_phase if observed_slot is not None else None,
            "read_beat": (observed_slot >> 2) if observed_slot is not None else None,
            "read_logical_byte": (observed_slot & 3) if observed_slot is not None else None,
            "read_slot": observed_slot,
            "observed": hex16(match_masks[slot]),
            "observed_nonzero_mask": hex16(nonzero_masks[slot]),
            "observed_match_slots": matches,
            "observed_nonzero_slots": nonzero,
        }
        write_cases.append(write_case)

    mapped = [slot for slot in physical_to_logical_byte if slot is not None]
    is_bijective = one_hot and len(mapped) == 16 and len(set(mapped)) == 16
    probe_failed = bool(decoded.get("failed", False))
    probe_complete = bool(decoded.get("complete", False))
    status = "PASS" if is_bijective and not probe_failed else "FAIL"

    return {
        "status": status,
        "probe_version": probe_version,
        "hypothesis": HYPOTHESIS,
        "bitstream": bitstream,
        "bitstream_sha256": sha256,
        "probe_state": decoded.get("state"),
        "probe_complete": probe_complete,
        "probe_failed": probe_failed,
        "init_state": decoded.get("init_state"),
        "status_flags": decoded.get("status"),
        "write_cases": write_cases,
        "mapping_inference": {
            "is_bijective": is_bijective and not probe_failed,
            "physical_to_logical_byte": physical_to_logical_byte,
            "phase_transform": (
                f"source_phase={source_phase}, "
                f"write_command_phase={write_command_phase}, "
                f"read_phase={read_phase}; slot=beat*4+byte"
            ),
            "confidence": "high" if is_bijective else "low",
        },
        "raw_masks": {
            "match_masks": [hex16(mask) for mask in match_masks],
            "nonzero_masks": [hex16(mask) for mask in nonzero_masks],
        },
        "decision": {
            "next_gate": (
                "apply permutation/phase transform and rerun v44-style "
                "byte-enable/native BIST"
                if is_bijective and not probe_failed
                else "do not change DDR logic; inspect DFII byte/source/read "
                "phase association before rerunning native BIST"
            )
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--probe-json", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--bitstream")
    parser.add_argument("--sha256")
    args = parser.parse_args()

    probe = json.loads(Path(args.probe_json).read_text())
    summary = summarize(probe, args.bitstream, args.sha256)

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()
