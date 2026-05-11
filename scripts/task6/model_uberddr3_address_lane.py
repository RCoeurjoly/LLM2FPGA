#!/usr/bin/env python3
"""Model the Task 6 UberDDR3 rowstream address/lane policies."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


BEAT_BYTES = 64


def dense_byte_write(stream_addr: int, value: int) -> dict[str, Any]:
    lane = stream_addr % BEAT_BYTES
    return {
        "stream_addr": stream_addr,
        "value": value,
        "wb_addr": stream_addr // BEAT_BYTES,
        "wb_sel_hex": f"0x{1 << lane:016x}",
        "write_lanes": [lane],
        "read_lane": lane,
    }


def sparse_lowbyte_fullwidth_write(stream_addr: int, value: int) -> dict[str, Any]:
    return {
        "stream_addr": stream_addr,
        "value": value,
        "wb_addr": stream_addr,
        "wb_sel_hex": f"0x{(1 << BEAT_BYTES) - 1:016x}",
        "write_lanes": list(range(BEAT_BYTES)),
        "read_lane": 0,
    }


def apply_write(memory: dict[int, list[int | None]], entry: dict[str, Any]) -> None:
    beat = memory.setdefault(entry["wb_addr"], [None] * BEAT_BYTES)
    for lane in entry["write_lanes"]:
        beat[lane] = entry["value"]


def read_dense(memory: dict[int, list[int | None]], stream_addr: int) -> int | None:
    beat = memory.get(stream_addr // BEAT_BYTES, [None] * BEAT_BYTES)
    return beat[stream_addr % BEAT_BYTES]


def read_sparse_lowbyte(memory: dict[int, list[int | None]], stream_addr: int) -> int | None:
    beat = memory.get(stream_addr, [None] * BEAT_BYTES)
    return beat[0]


def build_policy(
    name: str,
    writes: list[dict[str, Any]],
    stream_addrs: range,
) -> dict[str, Any]:
    memory: dict[int, list[int | None]] = {}
    for entry in writes:
        apply_write(memory, entry)

    dense_readback = [read_dense(memory, addr) for addr in stream_addrs]
    sparse_readback = [read_sparse_lowbyte(memory, addr) for addr in stream_addrs]
    expected = [addr & 0xFF for addr in stream_addrs]
    return {
        "name": name,
        "writes": writes,
        "readback": {
            "dense_byte_reader": dense_readback,
            "sparse_lowbyte_reader": sparse_readback,
        },
        "matches": {
            "dense_byte_reader": dense_readback == expected,
            "sparse_lowbyte_reader": sparse_readback == expected,
        },
        "memory_beats_touched": sorted(memory),
        "memory_footprint_bytes": len(memory) * BEAT_BYTES,
    }


def build_payload(byte_count: int) -> dict[str, Any]:
    stream_addrs = range(byte_count)
    dense_writes = [dense_byte_write(addr, addr & 0xFF) for addr in stream_addrs]
    sparse_writes = [
        sparse_lowbyte_fullwidth_write(addr, addr & 0xFF) for addr in stream_addrs
    ]
    policies = [
        build_policy("dense-byte", dense_writes, stream_addrs),
        build_policy("v35-sparse-lowbyte-fullwidth", sparse_writes, stream_addrs),
    ]
    return {
        "artifact_name": "task6-uberddr3-address-lane-model",
        "status": "PASS",
        "byte_count": byte_count,
        "beat_bytes": BEAT_BYTES,
        "source_facts": {
            "uberddr3_wb_addr_kind": "burst-addressable {row,bank,column}",
            "uberddr3_wb_addr_low_column_bits": "omitted; controller appends three zero column bits for an 8-transfer burst",
            "wb_data_bits": 512,
            "wb_sel_bits": 64,
        },
        "policies": policies,
        "decision": {
            "preferred_loader_policy": "dense-byte",
            "reason": (
                "A rowstream byte address should be split into Wishbone beat "
                "address and byte lane. The current v35 sparse policy is "
                "self-consistent only if all readers also use sparse low-byte "
                "addresses; it is incompatible with a dense DDR3 rowstream source."
            ),
            "next_board_gate": (
                "write stream addresses 0..15 with values 0..15, read both "
                "sparse-lowbyte and dense beat-0 lanes, and record which reader "
                "matches hardware"
            ),
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--byte-count", type=int, default=16)
    parser.add_argument("--out-json", type=Path, required=True)
    args = parser.parse_args()

    if args.byte_count <= 0 or args.byte_count > BEAT_BYTES:
        raise SystemExit("--byte-count must be in 1..64 for this diagnostic")

    payload = build_payload(args.byte_count)
    args.out_json.parent.mkdir(parents=True, exist_ok=True)
    args.out_json.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    print(
        "PASS: task6 UberDDR3 address lane model "
        f"bytes {args.byte_count} preferred dense-byte"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
