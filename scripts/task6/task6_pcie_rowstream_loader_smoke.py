#!/usr/bin/env python3
"""Task 6 PCIe BAR smoke for the real DDR3 rowstream loader ingress.

BAR layout from task6_pcie_axil_rowstream_loader_ingress.v:
  0x000 magic       = 0x54365043 ("T6PC")
  0x004 version     = 3
  0x008 control/status; write bit0 clears sticky status
  0x010 loader command magic = 0x33445244
  0x014 opcode/chunk
  0x018 address
  0x020..0x02c command data words
  0x030 doorbell; write bit0 issues command
  0x034 loader sticky status
  0x038 last opcode/chunk
  0x03c last command address
  0x040 wait cycles
  0x044..0x050 read data low words
"""

from __future__ import annotations

import argparse
import mmap
import os
from pathlib import Path
import struct
import subprocess
import time

TASK6_MAGIC = 0x54365043
TASK6_VERSION = 3
COMMAND_MAGIC = 0x33445244
BAR_SIZE = 4096
ALL_ONES = 0xFFFFFFFF

OP_WRITE_DENSE_BYTE = 0x05
OP_READ_DENSE_BEAT = 0x06
OP_WRITE_DENSE_FILL = 0x08
OP_RUN_FULLBEAT = 0x09

STATUS_RST_N = 1 << 0
STATUS_EVENT_ACTIVE = 1 << 1
STATUS_DONE = 1 << 2
STATUS_ERROR = 1 << 3
STATUS_DOORBELL_ERROR = 1 << 4
STATUS_BOOT_DONE = 1 << 5

LOADER_CALIB_COMPLETE = 1 << 0
LOADER_BOOT_DONE = 1 << 1
LOADER_DONE = 1 << 2
LOADER_ERROR = 1 << 3
LOADER_MAGIC_OK = 1 << 4
LOADER_ACCEPTED = 1 << 5


def run(cmd: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, text=True, capture_output=True, check=check)


def command_value(bdf: str) -> int:
    return int(run(["setpci", "-s", bdf, "COMMAND"]).stdout.strip(), 16)


def ensure_mem_enabled(bdf: str, device: Path) -> tuple[int, int]:
    before = command_value(bdf)
    if before & 0x0002:
        return before, before
    if os.geteuid() != 0:
        raise SystemExit(
            f"PCI memory space is disabled for {bdf}. Install/trigger the "
            "Task 6 YPCB PCIe udev rule so it can enable the endpoint and "
            "grant plugdev access to resource0."
        )
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
    return before, after


def rd32(mm: mmap.mmap, offset: int) -> int:
    return struct.unpack(">I", bytes(mm[offset : offset + 4]))[0]


def wr32(mm: mmap.mmap, offset: int, value: int) -> None:
    mm[offset : offset + 4] = struct.pack(">I", value & 0xFFFFFFFF)
    _ = mm[0:4]


def decode_status(value: int) -> str:
    names = []
    for bit, name in (
        (STATUS_RST_N, "rst_n"),
        (STATUS_EVENT_ACTIVE, "event_active"),
        (STATUS_DONE, "done"),
        (STATUS_ERROR, "error"),
        (STATUS_DOORBELL_ERROR, "doorbell_error"),
        (STATUS_BOOT_DONE, "boot_done"),
    ):
        if value & bit:
            names.append(name)
    return ",".join(names) or "0"


def decode_loader(value: int) -> str:
    names = []
    for bit, name in (
        (LOADER_CALIB_COMPLETE, "calib_complete"),
        (LOADER_BOOT_DONE, "boot_done"),
        (LOADER_DONE, "done"),
        (LOADER_ERROR, "error"),
        (LOADER_MAGIC_OK, "magic_ok"),
        (LOADER_ACCEPTED, "accepted"),
    ):
        if value & bit:
            names.append(name)
    return ",".join(names) or "0"


def wait_for(mm: mmap.mmap, offset: int, mask: int, timeout: float, label: str) -> int:
    deadline = time.monotonic() + timeout
    value = rd32(mm, offset)
    while (value & mask) != mask and time.monotonic() < deadline:
        time.sleep(0.001)
        value = rd32(mm, offset)
    if (value & mask) != mask:
        raise SystemExit(f"timeout waiting for {label}: offset=0x{offset:03x} value=0x{value:08x}")
    return value


def issue_command(mm: mmap.mmap, opcode: int, chunk: int, addr: int, data0: int, timeout: float) -> tuple[int, int, int]:
    wr32(mm, 0x008, 0x1)
    wr32(mm, 0x010, COMMAND_MAGIC)
    wr32(mm, 0x014, ((chunk & 0x3) << 8) | (opcode & 0xFF))
    wr32(mm, 0x018, addr)
    wr32(mm, 0x020, data0)
    wr32(mm, 0x024, 0)
    wr32(mm, 0x028, 0)
    wr32(mm, 0x02C, 0)
    accepted_before = rd32(mm, 0x00C)
    wr32(mm, 0x030, 0x1)
    wait_for(mm, 0x008, STATUS_DONE, timeout, "ingress done")
    loader = wait_for(mm, 0x034, LOADER_ACCEPTED | LOADER_MAGIC_OK | LOADER_DONE, timeout, "loader accepted/done")
    status = rd32(mm, 0x008)
    accepted_after = rd32(mm, 0x00C)
    if status & (STATUS_ERROR | STATUS_DOORBELL_ERROR):
        raise SystemExit(f"ingress error after opcode 0x{opcode:02x}: status=0x{status:08x} {decode_status(status)}")
    if loader & LOADER_ERROR:
        raise SystemExit(f"loader error after opcode 0x{opcode:02x}: loader=0x{loader:08x} {decode_loader(loader)}")
    if accepted_after != ((accepted_before + 1) & 0xFFFFFFFF):
        raise SystemExit(f"accepted_count did not increment: before={accepted_before} after={accepted_after}")
    return status, loader, accepted_after


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bdf", help="PCI BDF, for example 0000:42:00.0")
    parser.add_argument("--byte-addr", type=lambda text: int(text, 0), default=70)
    parser.add_argument("--value", type=lambda text: int(text, 0), default=0x5A)
    parser.add_argument("--poll-timeout", type=float, default=2.0)
    parser.add_argument("--boot-timeout", type=float, default=5.0)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    byte_addr = args.byte_addr
    value = args.value & 0xFF
    beat_addr = byte_addr // 64
    lane = byte_addr % 64
    read_word_offset = 0x044 + (lane // 4) * 4
    lane_shift = (lane % 4) * 8

    device = Path("/sys/bus/pci/devices") / args.bdf
    resource0 = device / "resource0"
    if not resource0.exists():
        raise SystemExit(f"missing BAR0 sysfs resource: {resource0}")

    print(run(["lspci", "-s", args.bdf]).stdout.strip())
    before, after = ensure_mem_enabled(args.bdf, device)
    print(f"COMMAND before: 0x{before:04x}")
    print(f"COMMAND after:  0x{after:04x}")

    fd = os.open(resource0, os.O_RDWR | os.O_SYNC)
    try:
        with mmap.mmap(fd, BAR_SIZE, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE) as mm:
            magic = rd32(mm, 0x000)
            version = rd32(mm, 0x004)
            status = rd32(mm, 0x008)
            loader = rd32(mm, 0x034)
            print(f"magic:   0x{magic:08x}")
            print(f"version: {version}")
            print(f"status:  0x{status:08x} {decode_status(status)}")
            print(f"loader:  0x{loader:08x} {decode_loader(loader)}")
            if magic == ALL_ONES and version == ALL_ONES:
                raise SystemExit("BAR0 returned all ones; endpoint may be stale or BAR transactions are not completing")
            if magic != TASK6_MAGIC:
                raise SystemExit(f"bad magic: expected 0x{TASK6_MAGIC:08x}, got 0x{magic:08x}")
            if version != TASK6_VERSION:
                raise SystemExit(f"bad version: expected {TASK6_VERSION}, got {version}")
            status = wait_for(mm, 0x008, STATUS_RST_N | STATUS_BOOT_DONE, args.boot_timeout, "DDR boot_done")
            print(f"boot status: 0x{status:08x} {decode_status(status)}")

            print(f"write dense byte: byte_addr={byte_addr} value=0x{value:02x}")
            status, loader, count = issue_command(mm, OP_WRITE_DENSE_BYTE, 0, byte_addr, value, args.poll_timeout)
            print(f"after write: status=0x{status:08x} {decode_status(status)} loader=0x{loader:08x} {decode_loader(loader)} count={count}")

            print(f"read dense beat: beat_addr={beat_addr}")
            status, loader, count = issue_command(mm, OP_READ_DENSE_BEAT, 0, beat_addr, 0, args.poll_timeout)
            read_word = rd32(mm, read_word_offset)
            observed = (read_word >> lane_shift) & 0xFF
            last_opcode_chunk = rd32(mm, 0x038)
            last_addr = rd32(mm, 0x03C)
            wait_cycles = rd32(mm, 0x040)
            print(f"after read:  status=0x{status:08x} {decode_status(status)} loader=0x{loader:08x} {decode_loader(loader)} count={count}")
            print(f"last opcode/chunk: 0x{last_opcode_chunk:08x}")
            print(f"last addr: 0x{last_addr:08x}")
            print(f"wait cycles: {wait_cycles}")
            print(f"read word offset 0x{read_word_offset:03x}: 0x{read_word:08x}")
            print(f"observed lane byte: 0x{observed:02x}")
            if observed != value:
                raise SystemExit(f"readback mismatch: expected 0x{value:02x}, observed 0x{observed:02x}")
    finally:
        os.close(fd)

    print("PASS: Task 6 PCIe rowstream loader DDR3 write/read smoke matched")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
