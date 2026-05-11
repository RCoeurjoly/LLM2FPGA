#!/usr/bin/env python3
"""Validate the Task 6 DDR3 JTAG loader command bit packing."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


COMMAND_BITS = 192
COMMAND_MAGIC = 0x33445244
OP_WRITE_LOWBYTE = 0x03
OP_WRITE_DENSE_BYTE = 0x05
BEAT_BYTES = 64

MAGIC_LSB = 0
MAGIC_WIDTH = 32
OPCODE_LSB = 32
OPCODE_WIDTH = 8
CHUNK_LSB = 40
CHUNK_WIDTH = 2
ADDR_LSB = 48
ADDR_WIDTH = 32
CURRENT_DATA_BYTE_LSB = 64
DENSE_EFFECTIVE_ADDR_WIDTH = 16
DATA_BYTE_WIDTH = 8


def bit_range(lsb: int, width: int) -> set[int]:
    return set(range(lsb, lsb + width))


def pack_command(
    opcode: int,
    chunk: int,
    addr: int,
    data_byte: int,
    *,
    data_lsb: int,
) -> int:
    payload = COMMAND_MAGIC
    payload |= (opcode & 0xFF) << OPCODE_LSB
    payload |= (chunk & 0x3) << CHUNK_LSB
    payload |= (addr & 0xFFFF_FFFF) << ADDR_LSB
    payload |= (data_byte & 0xFF) << data_lsb
    return payload


def decode_current(payload: int) -> dict[str, int]:
    command_addr = (payload >> ADDR_LSB) & 0xFFFF_FFFF
    dense_stream_addr = command_addr & ((1 << DENSE_EFFECTIVE_ADDR_WIDTH) - 1)
    data_byte = (payload >> CURRENT_DATA_BYTE_LSB) & 0xFF
    lane = dense_stream_addr % BEAT_BYTES
    return {
        "magic": payload & 0xFFFF_FFFF,
        "opcode": (payload >> OPCODE_LSB) & 0xFF,
        "chunk": (payload >> CHUNK_LSB) & 0x3,
        "command_addr_raw": command_addr,
        "dense_stream_addr": dense_stream_addr,
        "data_byte": data_byte,
        "dense_wb_addr": dense_stream_addr // BEAT_BYTES,
        "dense_lane": lane,
        "dense_sel_low16": (1 << lane) & 0xFFFF,
    }


def dense_case(stream_addr: int, value: int) -> dict[str, Any]:
    payload = pack_command(
        OP_WRITE_DENSE_BYTE,
        0,
        stream_addr,
        value,
        data_lsb=CURRENT_DATA_BYTE_LSB,
    )
    decoded = decode_current(payload)
    expected = {
        "dense_stream_addr": stream_addr,
        "data_byte": value & 0xFF,
        "dense_wb_addr": stream_addr // BEAT_BYTES,
        "dense_lane": stream_addr % BEAT_BYTES,
        "dense_sel_low16": (1 << (stream_addr % BEAT_BYTES)) & 0xFFFF,
    }
    return {
        "stream_addr": stream_addr,
        "value": value & 0xFF,
        "payload_hex": f"0x{payload:0{COMMAND_BITS // 4}x}",
        "decoded": decoded,
        "expected": expected,
        "match": all(decoded[key] == expected[key] for key in expected),
    }


def overlap_negative_case(stream_addr: int, value: int) -> dict[str, Any]:
    payload = pack_command(
        OP_WRITE_DENSE_BYTE,
        0,
        stream_addr,
        value,
        data_lsb=CURRENT_DATA_BYTE_LSB,
    )
    decoded = decode_current(payload)
    return {
        "stream_addr": stream_addr,
        "value": value & 0xFF,
        "data_lsb": CURRENT_DATA_BYTE_LSB,
        "payload_hex": f"0x{payload:0{COMMAND_BITS // 4}x}",
        "decoded_by_current_rtl": decoded,
        "raw_command_addr_corrupted": decoded["command_addr_raw"] != stream_addr,
        "dense_effective_addr_preserved": decoded["dense_stream_addr"] == stream_addr,
        "data_preserved": decoded["data_byte"] == (value & 0xFF),
    }


def build_payload(byte_count: int) -> dict[str, Any]:
    fields = {
        "magic": [MAGIC_LSB, MAGIC_LSB + MAGIC_WIDTH - 1],
        "opcode": [OPCODE_LSB, OPCODE_LSB + OPCODE_WIDTH - 1],
        "chunk": [CHUNK_LSB, CHUNK_LSB + CHUNK_WIDTH - 1],
        "addr": [ADDR_LSB, ADDR_LSB + ADDR_WIDTH - 1],
        "data_byte": [
            CURRENT_DATA_BYTE_LSB,
            CURRENT_DATA_BYTE_LSB + DATA_BYTE_WIDTH - 1,
        ],
        "dense_effective_addr": [ADDR_LSB, ADDR_LSB + DENSE_EFFECTIVE_ADDR_WIDTH - 1],
    }
    overlaps = {
        "raw_addr_vs_data": sorted(
            bit_range(ADDR_LSB, ADDR_WIDTH)
            & bit_range(CURRENT_DATA_BYTE_LSB, DATA_BYTE_WIDTH)
        ),
        "dense_effective_addr_vs_data": sorted(
            bit_range(ADDR_LSB, DENSE_EFFECTIVE_ADDR_WIDTH)
            & bit_range(CURRENT_DATA_BYTE_LSB, DATA_BYTE_WIDTH)
        ),
    }
    dense_cases = [dense_case(addr, addr & 0xFF) for addr in range(byte_count)]
    overlap_negative = overlap_negative_case(0, 15)
    pass_current = (
        not overlaps["dense_effective_addr_vs_data"]
        and all(case["match"] for case in dense_cases)
        and overlap_negative["raw_command_addr_corrupted"]
        and overlap_negative["dense_effective_addr_preserved"]
        and overlap_negative["data_preserved"]
    )
    return {
        "artifact_name": "task6-uberddr3-jtag-command-packing-model",
        "status": "PASS" if pass_current else "FAIL",
        "command_bits": COMMAND_BITS,
        "fields": fields,
        "overlaps": overlaps,
        "dense_write_cases": dense_cases,
        "overlap_negative_control": overlap_negative,
        "decision": {
            "verdict": (
                "command-packing-dense-effective-layout-passes"
                if pass_current
                else "command-packing-dense-effective-layout-fails"
            ),
            "next_gate": (
                "Use the calibration-preserving byte-at-bit-64 command layout "
                "only with dense commands that derive their stream address from "
                "the low 16 address bits. Do not interpret the overlapped raw "
                "32-bit command address for dense byte writes."
            ),
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--byte-count", type=int, default=16)
    parser.add_argument("--out-json", type=Path, required=True)
    args = parser.parse_args()
    if args.byte_count <= 0 or args.byte_count > BEAT_BYTES:
        raise SystemExit("--byte-count must be in 1..64")
    payload = build_payload(args.byte_count)
    args.out_json.parent.mkdir(parents=True, exist_ok=True)
    args.out_json.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    print(
        f"{payload['status']}: task6 JTAG command packing "
        f"{payload['decision']['verdict']}"
    )
    return 0 if payload["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
