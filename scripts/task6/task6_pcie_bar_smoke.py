#!/usr/bin/env python3
"""BAR0 smoke for the pcie_7x Vivado oracle and Task 6 endpoints.

This intentionally uses Linux PCI sysfs instead of the external `pcimem`
utility. It still must run as root because PCI config writes and resource0
MMIO access are root-only on this host.

Offset 0 is a header register for the Task 6 command bridge, not writable
scratch RAM. The default auto mode therefore treats a readable ``T6PC`` header
as a BAR header pass and only runs the legacy write/readback echo when the BAR
looks like the upstream smoke RAM responder.
"""

from __future__ import annotations

import argparse
import mmap
import multiprocessing as mp
import os
import subprocess
import sys
from pathlib import Path

TASK6_MAGIC_BYTES = {b"T6PC", b"CP6T"}


def hexdump(data: bytes, base: int = 0) -> str:
    lines: list[str] = []
    for off in range(0, len(data), 16):
        chunk = data[off : off + 16]
        hex_bytes = " ".join(f"{b:02x}" for b in chunk)
        hex_bytes = f"{hex_bytes:<47}"
        ascii_bytes = "".join(chr(b) if 32 <= b < 127 else "." for b in chunk)
        lines.append(f"{base + off:08x}  {hex_bytes}  |{ascii_bytes}|")
    return "\n".join(lines)


def run(cmd: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, text=True, capture_output=True, check=check)


def command_value(bdf: str) -> int:
    result = run(["setpci", "-s", bdf, "COMMAND"])
    return int(result.stdout.strip(), 16)


def command_write(bdf: str, value: int, *, direct: bool = False) -> bool:
    cmd = ["setpci"]
    if direct:
        cmd.append("-H1")
    cmd += ["-s", bdf, f"COMMAND={value:04x}"]
    result = run(cmd, check=False)
    if result.returncode == 0:
        return True

    label = "direct config" if direct else "sysfs config"
    print(f"{label} write failed:", file=sys.stderr)
    if result.stdout:
        print(result.stdout.rstrip(), file=sys.stderr)
    if result.stderr:
        print(result.stderr.rstrip(), file=sys.stderr)
    return False


def sysfs_enable_device(device: Path) -> bool:
    enable = device / "enable"
    if not enable.exists():
        print(f"missing sysfs enable node: {enable}", file=sys.stderr)
        return False

    try:
        before = enable.read_text().strip()
    except OSError as exc:
        print(f"could not read {enable}: {exc}", file=sys.stderr)
        before = "unknown"

    try:
        enable.write_text("1\n")
    except OSError as exc:
        print(f"sysfs device enable failed: {exc}", file=sys.stderr)
        return False

    try:
        after = enable.read_text().strip()
    except OSError:
        after = "unknown"
    print(f"sysfs enable count: {before} -> {after}")
    return True


def first_word_is_task6_header(data: bytes) -> bool:
    return data[:4] in TASK6_MAGIC_BYTES


def bar0_worker(
    resource_path: str,
    size: int,
    pattern: bytes,
    write_offset: int,
    mode: str,
    conn: mp.connection.Connection,
) -> None:
    fd = os.open(resource_path, os.O_RDWR | os.O_SYNC)
    try:
        try:
            with mmap.mmap(fd, size, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE) as mm:
                initial = mm[:64]
                if mode == "header" or (mode == "auto" and first_word_is_task6_header(initial)):
                    conn.send(("ok", "mmap", "header", initial, initial))
                    return
                if mode == "auto" and write_offset == 0 and not initial.startswith(b"\x12\x34\x56\x78"):
                    conn.send(
                        (
                            "error",
                            "BAR0 offset 0 is not the upstream smoke pattern and not a Task 6 header; "
                            "refusing to write offset 0 in auto mode",
                        )
                    )
                    return
                mm.seek(write_offset)
                mm.write(pattern)
                mm.flush()
                mm.seek(0)
                readback = mm.read(max(64, write_offset + len(pattern)))
                conn.send(("ok", "mmap", "echo", initial, readback))
                return
        except PermissionError as exc:
            conn.send(("mmap-denied", str(exc)))

        initial = os.pread(fd, 64, 0)
        if mode == "header" or (mode == "auto" and first_word_is_task6_header(initial)):
            conn.send(("ok", "pread/pwrite", "header", initial, initial))
            return
        if mode == "auto" and write_offset == 0 and not initial.startswith(b"\x12\x34\x56\x78"):
            conn.send(
                (
                    "error",
                    "BAR0 offset 0 is not the upstream smoke pattern and not a Task 6 header; "
                    "refusing to write offset 0 in auto mode",
                )
            )
            return
        written = os.pwrite(fd, pattern, write_offset)
        if written != len(pattern):
            conn.send(
                ("error", f"short BAR0 write at offset 0x{write_offset:x}: wrote {written} of {len(pattern)} bytes")
            )
            return
        readback = os.pread(fd, max(64, write_offset + len(pattern)), 0)
        conn.send(("ok", "pread/pwrite", "echo", initial, readback))
    except BaseException as exc:
        conn.send(("error", repr(exc)))
    finally:
        os.close(fd)
        conn.close()


def recv_or_timeout(conn: mp.connection.Connection, proc: mp.Process, timeout_s: float, phase: str):
    if conn.poll(timeout_s):
        return conn.recv()
    proc.kill()
    proc.join(1.0)
    raise SystemExit(
        f"BAR0 MMIO {phase} timed out after {timeout_s:g}s. "
        "PCI memory space is enabled, but the endpoint did not complete the BAR0 transaction. "
        "Treat this as a Vivado BAR/TLP completion gate failure unless dmesg shows a host-side AER/reset event."
    )


def run_bar0_smoke(
    resource0: Path,
    size: int,
    pattern: bytes,
    write_offset: int,
    mode: str,
    timeout_s: float,
) -> tuple[str, str, bytes, bytes, list[str]]:
    parent_conn, child_conn = mp.Pipe(duplex=False)
    proc = mp.Process(target=bar0_worker, args=(str(resource0), size, pattern, write_offset, mode, child_conn))
    proc.start()
    child_conn.close()

    messages: list[str] = []
    try:
        msg = recv_or_timeout(parent_conn, proc, timeout_s, "mmap probe")
        if msg[0] == "mmap-denied":
            messages.append(f"BAR0 mmap denied: {msg[1]}; trying pread/pwrite fallback")
            msg = recv_or_timeout(parent_conn, proc, timeout_s, "pread/pwrite fallback")

        if msg[0] == "ok":
            _, method, result_mode, initial, readback = msg
            return method, result_mode, initial, readback, messages

        if msg[0] == "error":
            raise SystemExit(
                f"BAR0 resource access failed after PCI memory space was enabled: {msg[1]}. "
                "The host allows PCI device enable, but userspace MMIO is still blocked or the endpoint rejects BAR access."
            )

        raise SystemExit(f"unexpected BAR0 worker result: {msg!r}")
    finally:
        parent_conn.close()
        proc.join(1.0)
        if proc.is_alive():
            proc.kill()
            proc.join(1.0)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("bdf", help="PCI BDF, for example 0000:42:00.0")
    parser.add_argument("--size", type=int, default=4096, help="BAR0 mmap size")
    parser.add_argument(
        "--pattern",
        default="abcdefgh",
        help="ASCII bytes for the legacy BAR echo write",
    )
    parser.add_argument(
        "--mode",
        choices=("auto", "header", "echo"),
        default="auto",
        help=(
            "BAR probe mode. auto treats T6PC at offset 0 as a header pass and "
            "otherwise runs the legacy upstream echo smoke."
        ),
    )
    parser.add_argument(
        "--write-offset",
        type=lambda value: int(value, 0),
        default=0,
        help="BAR0 offset for echo writes; auto mode refuses offset 0 unless the upstream smoke pattern is present",
    )
    parser.add_argument(
        "--no-direct-config",
        action="store_true",
        help="Do not try setpci -H1 if the default sysfs config write fails",
    )
    parser.add_argument(
        "--no-sysfs-enable",
        action="store_true",
        help="Do not write 1 to the device sysfs enable node if config writes fail",
    )
    parser.add_argument(
        "--bar-timeout",
        type=float,
        default=3.0,
        help="Seconds to wait for each BAR0 MMIO probe before declaring a timeout",
    )
    args = parser.parse_args()
    if args.write_offset < 0:
        raise SystemExit("--write-offset must be nonnegative")

    device = Path("/sys/bus/pci/devices") / args.bdf
    resource0 = device / "resource0"
    if not resource0.exists():
        raise SystemExit(f"missing BAR0 sysfs resource: {resource0}")

    print(run(["lspci", "-s", args.bdf]).stdout.strip())
    before = command_value(args.bdf)
    print(f"COMMAND before: 0x{before:04x}")

    desired_command = before | 0x0002
    command_write(args.bdf, desired_command)
    after = command_value(args.bdf)

    if (after & 0x0002) == 0 and not args.no_sysfs_enable:
        print("COMMAND memory-enable bit is still clear; trying sysfs device enable")
        sysfs_enable_device(device)
        after = command_value(args.bdf)

    if (after & 0x0002) == 0 and not args.no_direct_config:
        print("COMMAND memory-enable bit is still clear; trying setpci -H1")
        command_write(args.bdf, desired_command, direct=True)
        after = command_value(args.bdf)

    print(f"COMMAND after:  0x{after:04x}")
    if (after & 0x0002) == 0:
        raise SystemExit(
            "PCI memory space is still disabled, so BAR0 cannot be mmapped. "
            "The host rejected normal config access, sysfs device enable, and any enabled fallback. "
            "Check kernel lockdown/Secure Boot policy or use a root environment that permits PCI config writes."
        )

    pattern = args.pattern.encode("ascii")
    if args.write_offset + len(pattern) > args.size:
        raise SystemExit(
            f"echo write exceeds mapped BAR window: offset=0x{args.write_offset:x} "
            f"pattern_len={len(pattern)} size=0x{args.size:x}"
        )
    method, result_mode, initial, readback, messages = run_bar0_smoke(
        resource0, args.size, pattern, args.write_offset, args.mode, args.bar_timeout
    )
    for message in messages:
        print(message)
    print(f"BAR0 first word via {method}:")
    print(hexdump(initial[:4]))
    if result_mode == "header":
        print("BAR0 header snapshot:")
        print(hexdump(initial[:64]))
        if not first_word_is_task6_header(initial):
            raise SystemExit(
                f"BAR0 header mismatch: expected T6PC magic at offset 0, got {initial[:4]!r}"
            )
        print("PASS: BAR0 Task 6 header magic matched; offset 0 was not written")
        return 0

    print(f"BAR0 write/readback smoke at offset 0x{args.write_offset:x}:")
    print(hexdump(readback[:64]))
    observed = readback[args.write_offset : args.write_offset + len(pattern)]
    if observed != pattern:
        raise SystemExit(
            f"BAR0 readback mismatch at offset 0x{args.write_offset:x}: expected {pattern!r}, got {observed!r}"
        )

    print("PASS: BAR0 write/readback matched")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
