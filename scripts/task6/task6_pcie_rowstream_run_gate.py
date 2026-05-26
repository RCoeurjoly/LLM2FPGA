#!/usr/bin/env python3
"""Validate the DDR3-resident Task 6 rowstream image through the PCIe BAR ingress."""

from __future__ import annotations

import argparse
import hashlib
import json
import mmap
import os
from pathlib import Path
import struct
import subprocess
import time
from typing import Any

TASK6_MAGIC = 0x54365043
TASK6_VERSION = 3
COMMAND_MAGIC = 0x33445244
BAR_SIZE = 4096
ALL_ONES = 0xFFFFFFFF

OP_READ_DENSE_BEAT = 0x06

STATUS_RST_N = 1 << 0
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
        raise SystemExit(
            f"PCI memory space did not enable: before=0x{before:04x} "
            f"after=0x{after:04x} {stderr}"
        )
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
        raise TimeoutError(
            f"timeout waiting for {label}: offset=0x{offset:03x} "
            f"value=0x{value:08x}"
        )
    return value


def read_low_16(mm: mmap.mmap) -> bytes:
    return b"".join(rd32(mm, 0x044 + index * 4).to_bytes(4, "little") for index in range(4))


def issue_read_beat(mm: mmap.mmap, beat_addr: int, timeout: float) -> bytes:
    wr32(mm, 0x008, 0x1)
    wr32(mm, 0x010, COMMAND_MAGIC)
    wr32(mm, 0x014, OP_READ_DENSE_BEAT)
    wr32(mm, 0x018, beat_addr)
    for index in range(4):
        wr32(mm, 0x020 + index * 4, 0)
    accepted_before = rd32(mm, 0x00C)
    wr32(mm, 0x030, 0x1)
    wait_for(mm, 0x008, STATUS_DONE, timeout, "ingress done")
    loader = wait_for(
        mm,
        0x034,
        LOADER_ACCEPTED | LOADER_MAGIC_OK | LOADER_DONE,
        timeout,
        "loader accepted/done",
    )
    status = rd32(mm, 0x008)
    accepted_after = rd32(mm, 0x00C)
    if status & (STATUS_ERROR | STATUS_DOORBELL_ERROR):
        raise RuntimeError(
            f"ingress error after read beat {beat_addr}: "
            f"status=0x{status:08x} {decode_status(status)}"
        )
    if loader & LOADER_ERROR:
        raise RuntimeError(
            f"loader error after read beat {beat_addr}: "
            f"loader=0x{loader:08x} {decode_loader(loader)}"
        )
    if accepted_after != ((accepted_before + 1) & 0xFFFFFFFF):
        raise RuntimeError(
            f"accepted_count did not increment: before={accepted_before} "
            f"after={accepted_after}"
        )
    return read_low_16(mm)


def sample_indices(total_beats: int, requested: list[int], count: int) -> list[int]:
    if requested:
        return sorted({index for index in requested if 0 <= index < total_beats})
    if total_beats <= 0 or count <= 0:
        return []
    if count >= total_beats:
        return list(range(total_beats))
    points = {0, total_beats - 1}
    if count > 2:
        for index in range(count):
            points.add(round(index * (total_beats - 1) / (count - 1)))
    return sorted(points)[:count]


def parse_index_list(text: str) -> list[int]:
    if not text:
        return []
    return [int(part, 0) for part in text.split(",") if part.strip()]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bdf", help="PCI BDF, for example 0000:42:00.0")
    parser.add_argument("--image", required=True, type=Path, help="expected packed rowstream image")
    parser.add_argument("--start-beat", type=lambda text: int(text, 0), default=0)
    parser.add_argument("--max-bytes", type=lambda text: int(text, 0), default=None)
    parser.add_argument("--full-readback", action=argparse.BooleanOptionalAction, default=True)
    parser.add_argument("--verify-samples", type=int, default=16)
    parser.add_argument("--verify-beats", default="")
    parser.add_argument("--poll-timeout", type=float, default=2.0)
    parser.add_argument("--boot-timeout", type=float, default=5.0)
    parser.add_argument("--progress-every", type=int, default=16384)
    parser.add_argument("--json-out", type=Path)
    parser.add_argument("--readback-out", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    image = args.image.read_bytes()
    if args.max_bytes is not None:
        image = image[: args.max_bytes]
    if not image:
        raise SystemExit("empty rowstream image")
    if len(image) % 16:
        image += bytes(16 - (len(image) % 16))
    total_beats = len(image) // 16
    expected_sha = hashlib.sha256(image).hexdigest()

    device = Path("/sys/bus/pci/devices") / args.bdf
    resource0 = device / "resource0"
    if not resource0.exists():
        raise SystemExit(f"missing BAR0 sysfs resource: {resource0}")

    print(run(["lspci", "-s", args.bdf]).stdout.strip())
    before, after = ensure_mem_enabled(args.bdf, device)
    print(f"COMMAND before: 0x{before:04x}")
    print(f"COMMAND after:  0x{after:04x}")

    started = time.monotonic()
    samples: list[dict[str, Any]] = []
    readback = bytearray() if args.full_readback else None
    sample_set = set(sample_indices(total_beats, parse_index_list(args.verify_beats), args.verify_samples))
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
                raise SystemExit("BAR0 returned all ones; endpoint may be stale")
            if magic != TASK6_MAGIC:
                raise SystemExit(f"bad magic: expected 0x{TASK6_MAGIC:08x}, got 0x{magic:08x}")
            if version != TASK6_VERSION:
                raise SystemExit(f"bad version: expected {TASK6_VERSION}, got {version}")
            wait_for(mm, 0x008, STATUS_RST_N | STATUS_BOOT_DONE, args.boot_timeout, "DDR boot_done")

            read_count = total_beats if args.full_readback else len(sample_set)
            for ordinal, beat_index in enumerate(range(total_beats) if args.full_readback else sorted(sample_set), start=1):
                observed = issue_read_beat(mm, args.start_beat + beat_index, args.poll_timeout)
                expected = image[beat_index * 16 : (beat_index + 1) * 16]
                if readback is not None:
                    readback.extend(observed)
                if beat_index in sample_set:
                    match = observed == expected
                    samples.append(
                        {
                            "beat": args.start_beat + beat_index,
                            "image_beat": beat_index,
                            "expected_hex": expected.hex(),
                            "observed_hex": observed.hex(),
                            "match": match,
                        }
                    )
                    if not match:
                        raise SystemExit(
                            f"verify mismatch at beat {beat_index}: "
                            f"expected={expected.hex()} observed={observed.hex()}"
                        )
                if args.progress_every and (
                    ordinal == 1 or ordinal == read_count or ordinal % args.progress_every == 0
                ):
                    print(f"read beats: {ordinal}/{read_count}")
    finally:
        os.close(fd)

    elapsed = time.monotonic() - started
    readback_bytes = bytes(readback) if readback is not None else None
    readback_sha = hashlib.sha256(readback_bytes).hexdigest() if readback_bytes is not None else None
    full_match = readback_bytes == image if readback_bytes is not None else None
    if readback_bytes is not None and args.readback_out is not None:
        args.readback_out.write_bytes(readback_bytes)
    if full_match is False:
        raise SystemExit(f"full readback SHA mismatch: expected={expected_sha} observed={readback_sha}")

    result = {
        "status": "PASS",
        "bdf": args.bdf,
        "image": str(args.image),
        "bytes_checked": len(image),
        "beats_checked": total_beats if args.full_readback else len(sample_set),
        "start_beat": args.start_beat,
        "expected_sha256": expected_sha,
        "readback_sha256": readback_sha,
        "full_readback": args.full_readback,
        "full_match": full_match,
        "elapsed_seconds": elapsed,
        "bytes_per_second": len(image) / elapsed if args.full_readback and elapsed > 0 else None,
        "verify_samples": samples,
    }
    print(json.dumps(result, indent=2, sort_keys=True))
    if args.json_out is not None:
        args.json_out.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
