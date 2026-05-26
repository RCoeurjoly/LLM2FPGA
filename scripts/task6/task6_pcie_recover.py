#!/usr/bin/env python3
"""Recover the Task 6 FPGA PCIe endpoint after JTAG reprogramming.

This helper intentionally uses only the narrow sysfs nodes delegated by the
Task 6 udev rule: the matched endpoint's remove/reset/rescan files and its
immediate upstream bridge rescan file.
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import subprocess
import time

EXPECTED_VENDOR = "0x10ee"
EXPECTED_DEVICE = "0x0480"
EXPECTED_SUBSYSTEM_VENDOR = "0x10ee"
EXPECTED_SUBSYSTEM_DEVICE = "0xabcd"


def run(cmd: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, text=True, capture_output=True, check=check)


def read_text(path: Path) -> str:
    return path.read_text(encoding="ascii").strip()


def write_one(path: Path, label: str) -> None:
    if not path.exists():
        raise SystemExit(f"missing {label}: {path}")
    if not os.access(path, os.W_OK):
        raise SystemExit(
            f"{label} is not writable by this user: {path}\n"
            "Install/trigger the updated Task 6 PCIe udev rule from ~/FutureProofDotfiles."
        )
    path.write_text("1\n", encoding="ascii")


def command_value(bdf: str) -> int | None:
    result = run(["setpci", "-s", bdf, "COMMAND"], check=False)
    if result.returncode != 0:
        return None
    text = result.stdout.strip()
    if not text:
        return None
    return int(text, 16)


def verify_identity(device: Path) -> None:
    fields = {
        "vendor": EXPECTED_VENDOR,
        "device": EXPECTED_DEVICE,
        "subsystem_vendor": EXPECTED_SUBSYSTEM_VENDOR,
        "subsystem_device": EXPECTED_SUBSYSTEM_DEVICE,
    }
    for name, expected in fields.items():
        path = device / name
        if not path.exists():
            raise SystemExit(f"missing PCI identity attribute: {path}")
        observed = read_text(path)
        if observed != expected:
            raise SystemExit(f"unexpected {name}: expected {expected}, got {observed}")


def wait_for_endpoint(bdf: str, timeout_s: float) -> Path:
    deadline = time.monotonic() + timeout_s
    device = Path("/sys/bus/pci/devices") / bdf
    while time.monotonic() < deadline:
        if device.exists() and (device / "resource0").exists():
            return device
        time.sleep(0.1)
    raise SystemExit(f"timeout waiting for PCI endpoint to reappear: {bdf}")


def wait_for_config(bdf: str, timeout_s: float) -> int:
    deadline = time.monotonic() + timeout_s
    last: int | None = None
    while time.monotonic() < deadline:
        value = command_value(bdf)
        last = value
        if value is not None and value != 0xFFFF:
            return value
        time.sleep(0.1)
    last_text = "none" if last is None else f"0x{last:04x}"
    raise SystemExit(f"timeout waiting for live PCI config space: last COMMAND={last_text}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bdf", help="PCI BDF, for example 0000:42:00.0")
    parser.add_argument("--timeout", type=float, default=10.0)
    parser.add_argument(
        "--reset-first",
        action="store_true",
        help="Write the endpoint reset node before remove/rescan when available",
    )
    args = parser.parse_args()

    device = Path("/sys/bus/pci/devices") / args.bdf
    if not device.exists():
        raise SystemExit(f"missing PCI endpoint: {device}")
    verify_identity(device)

    real_device = device.resolve()
    bridge_rescan = real_device.parent / "rescan"

    endpoint = run(["lspci", "-Dnn", "-s", args.bdf], check=False).stdout.strip()
    command_before = command_value(args.bdf)
    print(endpoint or f"{args.bdf} not shown by lspci")
    print("COMMAND before: " + ("none" if command_before is None else f"0x{command_before:04x}"))

    if args.reset_first and (real_device / "reset").exists():
        write_one(real_device / "reset", "endpoint reset")
        time.sleep(0.25)

    write_one(real_device / "remove", "endpoint remove")
    for _ in range(20):
        if not device.exists():
            break
        time.sleep(0.05)

    write_one(bridge_rescan, "upstream bridge rescan")

    recovered = wait_for_endpoint(args.bdf, args.timeout)
    command_after = wait_for_config(args.bdf, args.timeout)
    verify_identity(recovered)

    resource0 = recovered / "resource0"
    stat = resource0.stat()
    print(f"COMMAND after:  0x{command_after:04x}")
    print(f"resource0:      {resource0}")
    print(f"resource0 mode: {oct(stat.st_mode & 0o777)} uid={stat.st_uid} gid={stat.st_gid}")
    print("PASS: Task 6 PCIe endpoint recovered through delegated sysfs nodes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
