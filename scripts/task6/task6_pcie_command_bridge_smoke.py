#!/usr/bin/env python3
"""Task 6 PCIe command BAR smoke.

The upstream pcie_7x AXI-lite BAR presents 32-bit RTL register values in
the byte order observed by the original BAR pattern smoke, so this helper
uses big-endian 32-bit mmap accesses for register words.

Expected BAR layout from task6_pcie_axil_command_bridge.v:
  0x000 magic   = 0x54365043 ("T6PC")
  0x004 version = 1
  0x008 status  = {error, accepted_pulse, pending, rst_n}
  0x00c accepted_count
  0x040..0x058 command payload words 0..6
  0x060 doorbell bit0 accepts current payload
  0x080..0x098 accepted payload words 0..6
"""

from __future__ import annotations

import argparse
import mmap
import os
import struct
import subprocess
import time
from pathlib import Path

MAGIC = 0x54365043
VERSION = 1
ALL_ONES = 0xFFFFFFFF

PAYLOAD = [
    0x54364A43,  # related Task 6 command/debug magic style
    0x00000001,
    0x11223344,
    0x55667788,
    0x99AABBCC,
    0xDDEEFF00,
    0x13579BDF,
]


def run(cmd: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, text=True, capture_output=True, check=check)


def command_value(bdf: str) -> int:
    return int(run(["setpci", "-s", bdf, "COMMAND"]).stdout.strip(), 16)


def ensure_mem_enabled(bdf: str, device: Path) -> int:
    before = command_value(bdf)
    desired = before | 0x0002
    result = run(["setpci", "-s", bdf, f"COMMAND={desired:04x}"], check=False)
    after = command_value(bdf)
    if (after & 0x0002) == 0:
        enable = device / "enable"
        if enable.exists():
            enable.write_text("1\n")
            after = command_value(bdf)
    if (after & 0x0002) == 0:
        stderr = result.stderr.strip()
        raise SystemExit(f"PCI memory space did not enable: before=0x{before:04x} after=0x{after:04x} {stderr}")
    return before


def rd32(mm: mmap.mmap, offset: int) -> int:
    return struct.unpack_from(">I", mm, offset)[0]


def wr32(mm: mmap.mmap, offset: int, value: int) -> None:
    struct.pack_into(">I", mm, offset, value & 0xFFFFFFFF)
    mm.flush(offset & ~0xFFF, 0x1000)


def read_header(mm: mmap.mmap) -> tuple[int, int, int, int]:
    return (rd32(mm, 0x000), rd32(mm, 0x004), rd32(mm, 0x008), rd32(mm, 0x00C))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bdf", help="PCI BDF, for example 0000:42:00.0")
    parser.add_argument("--payload", nargs=7, type=lambda x: int(x, 0), default=PAYLOAD)
    args = parser.parse_args()

    device = Path("/sys/bus/pci/devices") / args.bdf
    resource0 = device / "resource0"
    if not resource0.exists():
        raise SystemExit(f"missing BAR0 sysfs resource: {resource0}")

    lspci = run(["lspci", "-s", args.bdf]).stdout.strip()
    print(lspci)
    before = ensure_mem_enabled(args.bdf, device)
    after = command_value(args.bdf)
    print(f"COMMAND before: 0x{before:04x}")
    print(f"COMMAND after:  0x{after:04x}")

    fd = os.open(resource0, os.O_RDWR | os.O_SYNC)
    try:
        with mmap.mmap(fd, 4096, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE) as mm:
            magic, version, status0, count0 = read_header(mm)
            for _ in range(10):
                if (magic, version, status0, count0) != (ALL_ONES, ALL_ONES, ALL_ONES, ALL_ONES):
                    break
                time.sleep(0.05)
                magic, version, status0, count0 = read_header(mm)
            print(f"magic: 0x{magic:08x}")
            print(f"version: {version}")
            print(f"status before: 0x{status0:08x}")
            print(f"accepted_count before: {count0}")
            if (magic, version, status0, count0) == (ALL_ONES, ALL_ONES, ALL_ONES, ALL_ONES):
                raise SystemExit(
                    "BAR0 returned all ones after PCI memory space was enabled; "
                    "the endpoint config header may be stale or BAR transactions are not completing. "
                    "Re-run the rescan gate; if it repeats, reprogram the SRAM bitstream and rescan again."
                )
            if magic != MAGIC:
                raise SystemExit(f"bad magic: expected 0x{MAGIC:08x}, got 0x{magic:08x}")
            if version != VERSION:
                raise SystemExit(f"bad version: expected {VERSION}, got {version}")

            for index, value in enumerate(args.payload):
                wr32(mm, 0x040 + index * 4, value)
            echoed = [rd32(mm, 0x040 + index * 4) for index in range(7)]
            print("payload echo:", " ".join(f"0x{x:08x}" for x in echoed))
            if echoed != args.payload:
                raise SystemExit(f"payload echo mismatch: expected {args.payload!r}, got {echoed!r}")

            wr32(mm, 0x060, 0x00000001)
            deadline = time.monotonic() + 1.0
            count1 = rd32(mm, 0x00C)
            while count1 == count0 and time.monotonic() < deadline:
                time.sleep(0.001)
                count1 = rd32(mm, 0x00C)
            status1 = rd32(mm, 0x008)
            accepted = [rd32(mm, 0x080 + index * 4) for index in range(7)]
            print(f"status after: 0x{status1:08x}")
            print(f"accepted_count after: {count1}")
            print("accepted payload:", " ".join(f"0x{x:08x}" for x in accepted))

            if count1 != ((count0 + 1) & 0xFFFFFFFF):
                raise SystemExit(f"accepted_count did not increment by one: before={count0} after={count1}")
            if accepted != args.payload:
                raise SystemExit(f"accepted payload mismatch: expected {args.payload!r}, got {accepted!r}")
    finally:
        os.close(fd)

    print("PASS: Task 6 PCIe command bridge BAR smoke matched")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
