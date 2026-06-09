#!/usr/bin/env python3
"""Task 6 PCIe-visible int8 MLP/residual boundary gate."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import mmap
import os
import struct
import subprocess
import time
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUT = ROOT / "artifacts" / "task6" / "runs" / "mlp-boundary-board-summary.json"
BAR_SIZE = 4096
ALL_ONES = 0xFFFFFFFF
TASK6_MAGIC = 0x54365043
TASK6_VERSION = 3
MLP_MAGIC = 0x54364D4C
MLP_VERSION = 1

CONTRACT_VERSION = "task6-transformer-boundary-mlp-v1"
CONTRACT_STAGE = "M1-transformer-boundary-mlp"
CONTRACT_RESP_HOST = [
    "transformer checkpoint/replay context setup",
    "PCIe lifecycle and run orchestration",
    "artifact logging and comparison",
]
CONTRACT_RESP_FPGA = [
    "MLP boundary selftest execution (`c_fc -> GELU -> c_proj -> residual add -> int8 output`)",
    "first-sample/result register exposure and status reporting",
]
REG_MAGIC = 0x000
REG_VERSION = 0x004
REG_STATUS = 0x008
REG_DEBUG_MAGIC = 0x200
REG_DEBUG_STATUS = 0x204
REG_MLP_MAGIC = 0x300
REG_MLP_VERSION = 0x304
REG_MLP_PRESENT = 0x308
REG_MLP_STATUS = 0x30C
REG_MLP_CYCLE_COUNT = 0x310
REG_MLP_FAIL_DETAIL = 0x314
REG_MLP_FAIL_VALUES = 0x318
REG_MLP_FIRST_ADD_SAMPLE = 0x31C
REG_MLP_FIRST_REQUANT_SAMPLE = 0x320
MLP_STATE_PASS = 0xB
EXPECTED_FIRST_ADD_SAMPLE = 0x0A0A0201
EXPECTED_FIRST_REQUANT_SAMPLE = 0x0A0A0001


def run(cmd: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, check=check, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def rd32(mm: mmap.mmap, offset: int) -> int:
    return struct.unpack(">I", bytes(mm[offset : offset + 4]))[0]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bdf", help="PCI BDF, for example 0000:42:00.0")
    parser.add_argument("--json-out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--expect-first-add", type=lambda text: int(text, 0), default=EXPECTED_FIRST_ADD_SAMPLE)
    parser.add_argument("--expect-first-requant", type=lambda text: int(text, 0), default=EXPECTED_FIRST_REQUANT_SAMPLE)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    device = Path("/sys/bus/pci/devices") / args.bdf
    resource0 = device / "resource0"
    if not resource0.exists():
        raise SystemExit(f"missing BAR0 sysfs resource: {resource0}")

    lspci = run(["lspci", "-s", args.bdf]).stdout.strip()
    command = run(["setpci", "-s", args.bdf, "COMMAND"]).stdout.strip()
    started = time.monotonic()

    fd = os.open(resource0, os.O_RDWR | os.O_SYNC)
    try:
        with mmap.mmap(fd, BAR_SIZE, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE) as mm:
            regs = {
                "magic": rd32(mm, REG_MAGIC),
                "version": rd32(mm, REG_VERSION),
                "status": rd32(mm, REG_STATUS),
                "debug_magic": rd32(mm, REG_DEBUG_MAGIC),
                "debug_status": rd32(mm, REG_DEBUG_STATUS),
                "mlp_magic": rd32(mm, REG_MLP_MAGIC),
                "mlp_version": rd32(mm, REG_MLP_VERSION),
                "mlp_present": rd32(mm, REG_MLP_PRESENT),
                "mlp_status": rd32(mm, REG_MLP_STATUS),
                "mlp_cycle_count": rd32(mm, REG_MLP_CYCLE_COUNT),
                "mlp_fail_detail": rd32(mm, REG_MLP_FAIL_DETAIL),
                "mlp_fail_values": rd32(mm, REG_MLP_FAIL_VALUES),
                "mlp_first_add_sample": rd32(mm, REG_MLP_FIRST_ADD_SAMPLE),
                "mlp_first_requant_sample": rd32(mm, REG_MLP_FIRST_REQUANT_SAMPLE),
            }
    finally:
        os.close(fd)

    mlp_state = regs["mlp_status"] & 0x0F
    mlp_fail_reason = (regs["mlp_fail_detail"] >> 8) & 0x03
    mlp_fail_index = regs["mlp_fail_detail"] & 0xFF
    checks = {
        "task6_magic": regs["magic"] == TASK6_MAGIC,
        "task6_version": regs["version"] == TASK6_VERSION,
        "not_all_ones": all(value != ALL_ONES for value in regs.values()),
        "mlp_magic": regs["mlp_magic"] == MLP_MAGIC,
        "mlp_version": regs["mlp_version"] == MLP_VERSION,
        "mlp_present": regs["mlp_present"] == 1,
        "mlp_state_pass": mlp_state == MLP_STATE_PASS,
        "mlp_fail_clear": mlp_fail_reason == 0 and mlp_fail_index == 0 and regs["mlp_fail_values"] == 0,
        "first_add_sample": regs["mlp_first_add_sample"] == args.expect_first_add,
        "first_requant_sample": regs["mlp_first_requant_sample"] == args.expect_first_requant,
    }
    status = "PASS" if all(checks.values()) else "FAIL"
    result: dict[str, Any] = {
        "artifact_name": "task6-pcie-mlp-boundary-board-gate",
        "status": status,
        "date": dt.date.today().isoformat(),
        "contract": {
            "version": CONTRACT_VERSION,
            "stage": CONTRACT_STAGE,
            "responsibilities": {
                "host": CONTRACT_RESP_HOST,
                "fpga": CONTRACT_RESP_FPGA,
            },
            "notes": "Boundary-stage selftest proof; not yet a full transformer on-board forward pass.",
        },
        "bdf": args.bdf,
        "lspci": lspci,
        "command": command,
        "elapsed_seconds": time.monotonic() - started,
        "boundary": "c_fc -> fixed-point GELU -> c_proj -> residual add -> int8 block output",
        "expected": {
            "mlp_magic": f"0x{MLP_MAGIC:08x}",
            "mlp_version": MLP_VERSION,
            "mlp_state": MLP_STATE_PASS,
            "mlp_state_name": "PASS",
            "first_add_sample": f"0x{args.expect_first_add:08x}",
            "first_requant_sample": f"0x{args.expect_first_requant:08x}",
        },
        "decoded": {
            "mlp_state": mlp_state,
            "mlp_state_name": "PASS" if mlp_state == MLP_STATE_PASS else "OTHER",
            "mlp_fail_reason": mlp_fail_reason,
            "mlp_fail_index": mlp_fail_index,
            "first_add_seen": bool(regs["mlp_status"] & (1 << 10)),
            "first_requant_seen": bool(regs["mlp_status"] & (1 << 11)),
        },
        "checks": checks,
        "registers": {name: f"0x{value:08x}" for name, value in regs.items()},
    }
    args.json_out.parent.mkdir(parents=True, exist_ok=True)
    args.json_out.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if status == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
