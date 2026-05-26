#!/usr/bin/env python3
"""Dump the Task 6 PCIe BAR debug aperture without sudo.

The debug block starts at BAR0 offset 0x200 and is intended for first-stage
board bring-up when PCIe enumeration works but DDR3/rowstream boot does not.
"""

from __future__ import annotations

import argparse
import mmap
import os
from pathlib import Path
import struct
import subprocess
import time

BAR_SIZE = 4096
TASK6_MAGIC = 0x54365043
TASK6_VERSION = 3
DEBUG_MAGIC = 0x54364442
DEBUG_VERSION = 1
ALL_ONES = 0xFFFFFFFF

REG_MAGIC = 0x000
REG_VERSION = 0x004
REG_STATUS = 0x008
REG_ACCEPTED = 0x00C
REG_LOADER = 0x034
REG_LAST_OPCODE = 0x038
REG_LAST_ADDR = 0x03C
REG_WAIT_CYCLES = 0x040
REG_DDR_DEBUG1 = 0x054
REG_TOP1_STATUS = 0x060
REG_DEBUG_MAGIC = 0x200
REG_DEBUG_VERSION = 0x204
REG_DEBUG_HEARTBEAT_COUNT = 0x208
REG_DEBUG_ROWSTREAM_STATUS = 0x20C
REG_DEBUG_ROWSTREAM_SEEN = 0x210
REG_DEBUG_DDR_DEBUG1 = 0x214
REG_DEBUG_LOADER_WAIT = 0x218


def run(cmd: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, text=True, capture_output=True, check=check)


def rd32(mm: mmap.mmap, offset: int) -> int:
    return struct.unpack(">I", bytes(mm[offset : offset + 4]))[0]


def decode_bits(value: int, fields: tuple[tuple[int, str], ...]) -> str:
    names = [name for bit, name in fields if value & (1 << bit)]
    return ",".join(names) or "0"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bdf", help="PCI BDF, for example 0000:42:00.0")
    parser.add_argument("--samples", type=int, default=2, help="number of heartbeat samples to read")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    device = Path("/sys/bus/pci/devices") / args.bdf
    resource0 = device / "resource0"
    if not resource0.exists():
        raise SystemExit(f"missing BAR0 sysfs resource: {resource0}")

    endpoint = run(["lspci", "-s", args.bdf]).stdout.strip()
    command = run(["setpci", "-s", args.bdf, "COMMAND"]).stdout.strip()
    print(endpoint)
    print(f"COMMAND: 0x{int(command, 16):04x}")

    fd = os.open(resource0, os.O_RDWR | os.O_SYNC)
    try:
        with mmap.mmap(fd, BAR_SIZE, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE) as mm:
            regs = {
                "magic": rd32(mm, REG_MAGIC),
                "version": rd32(mm, REG_VERSION),
                "status": rd32(mm, REG_STATUS),
                "accepted": rd32(mm, REG_ACCEPTED),
                "loader": rd32(mm, REG_LOADER),
                "last_opcode": rd32(mm, REG_LAST_OPCODE),
                "last_addr": rd32(mm, REG_LAST_ADDR),
                "wait_cycles": rd32(mm, REG_WAIT_CYCLES),
                "ddr_debug1": rd32(mm, REG_DDR_DEBUG1),
                "top1_status": rd32(mm, REG_TOP1_STATUS),
                "debug_magic": rd32(mm, REG_DEBUG_MAGIC),
                "debug_version": rd32(mm, REG_DEBUG_VERSION),
                "debug_status": rd32(mm, REG_DEBUG_ROWSTREAM_STATUS),
                "debug_seen": rd32(mm, REG_DEBUG_ROWSTREAM_SEEN),
                "debug_ddr_debug1": rd32(mm, REG_DEBUG_DDR_DEBUG1),
                "debug_loader_wait": rd32(mm, REG_DEBUG_LOADER_WAIT),
            }
            heartbeat_samples = []
            for sample in range(max(args.samples, 1)):
                heartbeat_samples.append(rd32(mm, REG_DEBUG_HEARTBEAT_COUNT))
                if sample + 1 < max(args.samples, 1):
                    time.sleep(0.1)

            for name in (
                "magic",
                "version",
                "status",
                "accepted",
                "loader",
                "last_opcode",
                "last_addr",
                "wait_cycles",
                "ddr_debug1",
                "top1_status",
                "debug_magic",
                "debug_version",
                "debug_status",
                "debug_seen",
                "debug_ddr_debug1",
                "debug_loader_wait",
            ):
                print(f"{name:18s}: 0x{regs[name]:08x}")
            print("heartbeat_samples : " + " ".join(f"0x{x:08x}" for x in heartbeat_samples))

            print("status bits        : " + decode_bits(regs["status"], (
                (0, "pcie_rst_n"),
                (1, "event_active"),
                (2, "loader_done"),
                (3, "loader_error"),
                (4, "doorbell_error"),
                (5, "calib_complete"),
                (6, "boot_done"),
            )))
            print("loader bits        : " + decode_bits(regs["loader"], (
                (0, "calib_complete"),
                (1, "boot_done"),
                (2, "done"),
                (3, "error"),
                (4, "magic_ok"),
                (5, "accepted"),
            )))
            print("debug status bits  : " + decode_bits(regs["debug_status"], (
                (0, "pcie_rst_n"),
                (1, "rowstream_rst_n"),
                (2, "calib_complete"),
                (3, "boot_done"),
                (4, "rowstream_heartbeat"),
                (5, "loader_done"),
                (6, "loader_error"),
                (7, "top1_busy"),
            )))
            print("debug seen bits    : " + decode_bits(regs["debug_seen"], (
                (0, "rowstream_heartbeat_seen"),
                (1, "rowstream_rst_n_seen"),
                (2, "calib_complete_seen"),
                (3, "boot_done_seen"),
                (4, "ddr_debug1_nonzero_seen"),
            )))

            if regs["magic"] == ALL_ONES or regs["debug_magic"] == ALL_ONES:
                raise SystemExit("BAR returned all ones; endpoint may be stale")
            if regs["magic"] != TASK6_MAGIC or regs["version"] != TASK6_VERSION:
                raise SystemExit("main Task 6 BAR header did not match")
            if regs["debug_magic"] != DEBUG_MAGIC or regs["debug_version"] != DEBUG_VERSION:
                raise SystemExit("debug aperture is not present in this bitstream")
    finally:
        os.close(fd)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
