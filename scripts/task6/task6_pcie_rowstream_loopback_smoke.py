#!/usr/bin/env python3
"""Task 6 PCIe BAR rowstream loopback smoke.

Expected BAR layout from task6_pcie_axil_rowstream_loopback.v:
  0x000 magic   = 0x54365043 ("T6PC")
  0x004 version = 2
  0x008 status  = {error, done, busy, rst_n}
  0x00c accepted_count
  0x010 payload byte count
  0x014 expected byte-sum checksum
  0x018 doorbell bit0 validates current payload
  0x020 observed byte-sum checksum
  0x024 observed xor32 checksum
  0x028 first payload word
  0x02c last payload word
  0x030 mismatch summary
  0x034 written byte count
  0x100..0xfff payload aperture
"""

from __future__ import annotations

import argparse
import mmap
import os
from pathlib import Path
import struct
import subprocess
import time

MAGIC = 0x54365043
VERSION = 2
BAR_SIZE = 4096
PAYLOAD_OFFSET = 0x100
MAX_PAYLOAD_BYTES = BAR_SIZE - PAYLOAD_OFFSET
ALL_ONES = 0xFFFFFFFF

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_ROWSTREAM = (
    ROOT
    / "artifacts"
    / "task6"
    / "parallel-hypotheses"
    / "h2-ddr3-row-stream-pack-replay"
    / "rowstream.bin"
)


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


def flush_page(mm: mmap.mmap) -> None:
    mm.flush(0, BAR_SIZE)


def deterministic_payload(size: int) -> bytes:
    return bytes(((index * 17 + 23) & 0xFF) for index in range(size))


def rowstream_payload(path: Path, size: int) -> bytes:
    data = path.read_bytes()
    if len(data) < size:
        raise SystemExit(f"rowstream payload too small: {path} has {len(data)} bytes, need {size}")
    return data[:size]


def be_words(payload: bytes) -> list[int]:
    words: list[int] = []
    for offset in range(0, len(payload), 4):
        chunk = payload[offset : offset + 4].ljust(4, b"\x00")
        words.append(struct.unpack(">I", chunk)[0])
    return words


def xor32(words: list[int]) -> int:
    value = 0
    for word in words:
        value ^= word
    return value & 0xFFFFFFFF


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bdf", help="PCI BDF, for example 0000:42:00.0")
    parser.add_argument("--bytes", type=int, default=MAX_PAYLOAD_BYTES, help="payload bytes to write; max 3840")
    parser.add_argument("--pattern", choices=("deterministic", "rowstream"), default="deterministic")
    parser.add_argument("--rowstream-bin", type=Path, default=DEFAULT_ROWSTREAM)
    parser.add_argument("--poll-timeout", type=float, default=1.0)
    parser.add_argument("--verify-readback", action=argparse.BooleanOptionalAction, default=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.bytes <= 0 or args.bytes > MAX_PAYLOAD_BYTES:
        raise SystemExit(f"--bytes must be in 1..{MAX_PAYLOAD_BYTES}, got {args.bytes}")

    payload = (
        deterministic_payload(args.bytes)
        if args.pattern == "deterministic"
        else rowstream_payload(args.rowstream_bin, args.bytes)
    )
    words = be_words(payload)
    expected_sum = sum(payload) & 0xFFFFFFFF
    expected_xor = xor32(words)
    expected_first = words[0]
    expected_last = words[-1]

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
        with mmap.mmap(fd, BAR_SIZE, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE) as mm:
            magic = rd32(mm, 0x000)
            version = rd32(mm, 0x004)
            status0 = rd32(mm, 0x008)
            count0 = rd32(mm, 0x00C)
            print(f"magic: 0x{magic:08x}")
            print(f"version: {version}")
            print(f"status before: 0x{status0:08x}")
            print(f"accepted_count before: {count0}")
            if magic == ALL_ONES and version == ALL_ONES:
                raise SystemExit("BAR0 returned all ones; endpoint may be stale or BAR transactions are not completing")
            if magic != MAGIC:
                raise SystemExit(f"bad magic: expected 0x{MAGIC:08x}, got 0x{magic:08x}")
            if version != VERSION:
                raise SystemExit(f"bad version: expected {VERSION}, got {version}")

            wr32(mm, 0x008, 0x1)  # clear done/error
            wr32(mm, 0x010, args.bytes)
            wr32(mm, 0x014, expected_sum)
            flush_page(mm)

            start = time.monotonic()
            for index, word in enumerate(words):
                wr32(mm, PAYLOAD_OFFSET + index * 4, word)
            flush_page(mm)
            elapsed = max(time.monotonic() - start, 1e-9)

            wr32(mm, 0x018, 0x1)
            flush_page(mm)
            deadline = time.monotonic() + args.poll_timeout
            status1 = rd32(mm, 0x008)
            while (status1 & 0x4) == 0 and time.monotonic() < deadline:
                time.sleep(0.001)
                status1 = rd32(mm, 0x008)

            count1 = rd32(mm, 0x00C)
            observed_count = rd32(mm, 0x034)
            observed_sum = rd32(mm, 0x020)
            observed_xor = rd32(mm, 0x024)
            first_word = rd32(mm, 0x028)
            last_word = rd32(mm, 0x02C)
            mismatch = rd32(mm, 0x030)

            print(f"status after: 0x{status1:08x}")
            print(f"accepted_count after: {count1}")
            print(f"written bytes: {observed_count}")
            print(f"checksum sum: expected=0x{expected_sum:08x} observed=0x{observed_sum:08x}")
            print(f"checksum xor: expected=0x{expected_xor:08x} observed=0x{observed_xor:08x}")
            print(f"first word: expected=0x{expected_first:08x} observed=0x{first_word:08x}")
            print(f"last word: expected=0x{expected_last:08x} observed=0x{last_word:08x}")
            print(f"mismatch: 0x{mismatch:08x}")
            print(f"payload write throughput: {(args.bytes / elapsed) / (1024 * 1024):.2f} MiB/s")

            if (status1 & 0x4) == 0:
                raise SystemExit("loopback doorbell did not complete before timeout")
            if status1 & 0x8:
                raise SystemExit("loopback status error bit set")
            if count1 != ((count0 + 1) & 0xFFFFFFFF):
                raise SystemExit(f"accepted_count did not increment: before={count0} after={count1}")
            if observed_count != args.bytes:
                raise SystemExit(f"written byte count mismatch: expected={args.bytes} observed={observed_count}")
            if observed_sum != expected_sum:
                raise SystemExit("byte-sum checksum mismatch")
            if observed_xor != expected_xor:
                raise SystemExit("xor32 checksum mismatch")
            if first_word != expected_first or last_word != expected_last:
                raise SystemExit("first/last word mismatch")
            if mismatch != 0:
                raise SystemExit(f"mismatch summary nonzero: 0x{mismatch:08x}")
            if args.verify_readback:
                readback = bytes(mm[PAYLOAD_OFFSET : PAYLOAD_OFFSET + args.bytes])
                if readback != payload:
                    raise SystemExit("payload aperture readback mismatch")
    finally:
        os.close(fd)

    print("PASS: Task 6 PCIe rowstream loopback matched")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
