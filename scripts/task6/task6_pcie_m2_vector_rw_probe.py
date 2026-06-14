#!/usr/bin/env python3
"""Probe M2 BAR input/residual vector write/readback without starting compute."""

from __future__ import annotations

import argparse
import json
import mmap
import os
from pathlib import Path
import struct
import subprocess
import time
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUT = ROOT / "artifacts" / "task6" / "runs" / "m2-vector-rw-probe.json"
BAR_SIZE = 4096
REG_M2_INPUT = 0x540
REG_M2_RESIDUAL = 0x580


def run(cmd: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, check=check, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def rd32(mm: mmap.mmap, offset: int) -> int:
    return struct.unpack(">I", bytes(mm[offset : offset + 4]))[0]


def wr32(mm: mmap.mmap, offset: int, value: int) -> None:
    mm[offset : offset + 4] = struct.pack(">I", value & 0xFFFFFFFF)
    _ = mm[0:4]


def encode_bar_vector_words(words: list[int]) -> list[int]:
    if len(words) != 16:
        raise SystemExit(f"vector must contain 16 words, got {len(words)}")
    compensated: list[int] = []
    for index in range(0, len(words), 2):
        pair = ((words[index + 1] & 0xFFFFFFFF) << 32) | (words[index] & 0xFFFFFFFF)
        rotated = ((pair << 1) | (pair >> 63)) & 0xFFFFFFFFFFFFFFFF
        compensated.append(rotated & 0xFFFFFFFF)
        compensated.append((rotated >> 32) & 0xFFFFFFFF)
    return compensated


def write_words(mm: mmap.mmap, base: int, words: list[int]) -> None:
    for index, word in enumerate(words):
        wr32(mm, base + index * 4, word)


def read_words(mm: mmap.mmap, base: int) -> list[int]:
    return [rd32(mm, base + index * 4) for index in range(16)]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bdf", help="PCI BDF, for example 0000:42:00.0")
    parser.add_argument("--json-out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--settle", type=float, default=0.05)
    parser.add_argument("--lane-compensate", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    device = Path("/sys/bus/pci/devices") / args.bdf
    resource0 = device / "resource0"
    if not resource0.exists():
        raise SystemExit(f"{resource0} does not exist")

    lspci = run(["lspci", "-s", args.bdf], check=False).stdout.strip()
    input_words = [0x2500_1000 + index for index in range(16)]
    residual_words = [0x5A00_2000 + index for index in range(16)]

    fd = os.open(resource0, os.O_RDWR | os.O_SYNC)
    try:
        with mmap.mmap(fd, BAR_SIZE, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE) as mm:
            before_input = read_words(mm, REG_M2_INPUT)
            before_residual = read_words(mm, REG_M2_RESIDUAL)
            input_write_words = encode_bar_vector_words(input_words) if args.lane_compensate else input_words
            residual_write_words = encode_bar_vector_words(residual_words) if args.lane_compensate else residual_words
            write_words(mm, REG_M2_INPUT, input_write_words)
            write_words(mm, REG_M2_RESIDUAL, residual_write_words)
            time.sleep(args.settle)
            after_input = read_words(mm, REG_M2_INPUT)
            after_residual = read_words(mm, REG_M2_RESIDUAL)
    finally:
        os.close(fd)

    result: dict[str, Any] = {
        "artifact_name": "task6-pcie-m2-vector-rw-probe",
        "bdf": args.bdf,
        "lspci": lspci,
        "status": "PASS" if after_input == input_words and after_residual == residual_words else "FAIL",
        "input_expected": [f"0x{word:08x}" for word in input_words],
        "input_written": [f"0x{word:08x}" for word in input_write_words],
        "input_before": [f"0x{word:08x}" for word in before_input],
        "input_after": [f"0x{word:08x}" for word in after_input],
        "residual_expected": [f"0x{word:08x}" for word in residual_words],
        "residual_written": [f"0x{word:08x}" for word in residual_write_words],
        "residual_before": [f"0x{word:08x}" for word in before_residual],
        "residual_after": [f"0x{word:08x}" for word in after_residual],
        "checks": {
            "input_readback": after_input == input_words,
            "residual_readback": after_residual == residual_words,
        },
    }
    args.json_out.parent.mkdir(parents=True, exist_ok=True)
    args.json_out.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if result["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
