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
STALE_SUBSYSTEM_DEVICE = "0xffff"


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


def config_words(bdf: str) -> list[str]:
    result = run(
        ["setpci", "-s", bdf, "COMMAND", "VENDOR_ID", "DEVICE_ID", "HEADER_TYPE"],
        check=False,
    )
    if result.returncode != 0:
        return []
    return result.stdout.split()


def verify_identity(device: Path, *, allow_stale_subsystem: bool = False) -> None:
    fields = {
        "vendor": EXPECTED_VENDOR,
        "device": EXPECTED_DEVICE,
        "subsystem_vendor": EXPECTED_SUBSYSTEM_VENDOR,
    }
    for name, expected in fields.items():
        path = device / name
        if not path.exists():
            raise SystemExit(f"missing PCI identity attribute: {path}")
        observed = read_text(path)
        if observed != expected:
            raise SystemExit(f"unexpected {name}: expected {expected}, got {observed}")

    subsystem_path = device / "subsystem_device"
    if not subsystem_path.exists():
        raise SystemExit(f"missing PCI identity attribute: {subsystem_path}")
    subsystem_device = read_text(subsystem_path)
    if subsystem_device == EXPECTED_SUBSYSTEM_DEVICE:
        return
    if allow_stale_subsystem and subsystem_device == STALE_SUBSYSTEM_DEVICE:
        print(
            "stale subsystem_device 0xffff; attempting delegated remove/rescan recovery"
        )
        return
    raise SystemExit(
        "unexpected subsystem_device: "
        f"expected {EXPECTED_SUBSYSTEM_DEVICE}, got {subsystem_device}"
    )


def wait_for_endpoint_resource(
    bdf: str,
    bridge_rescan: Path,
    timeout_s: float,
    rescan_interval_s: float,
) -> Path:
    deadline = time.monotonic() + timeout_s
    next_rescan = 0.0
    device = Path("/sys/bus/pci/devices") / bdf
    last_state = "missing"
    while time.monotonic() < deadline:
        now = time.monotonic()
        if device.exists():
            if (device / "resource0").exists():
                return device
            last_state = "present without resource0"
        else:
            last_state = "missing"

        if now >= next_rescan:
            write_one(bridge_rescan, "upstream bridge rescan")
            next_rescan = now + rescan_interval_s
        time.sleep(0.1)
    raise SystemExit(f"timeout waiting for PCI endpoint resource0: {bdf} ({last_state})")


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
    parser.add_argument(
        "--rescan-interval",
        type=float,
        default=1.0,
        help="seconds between repeated upstream bridge rescans while waiting for BAR0",
    )
    parser.add_argument(
        "--force-dead-config",
        action="store_true",
        help=(
            "attempt remove/rescan even when live PCI config reads as all 0xffff; "
            "normally this is treated as a stale Thunderbolt function that needs "
            "chassis or host re-enumeration"
        ),
    )
    args = parser.parse_args()

    device = Path("/sys/bus/pci/devices") / args.bdf
    if not device.exists():
        raise SystemExit(f"missing PCI endpoint: {device}")
    verify_identity(device, allow_stale_subsystem=True)

    real_device = device.resolve()
    bridge_rescan = real_device.parent / "rescan"

    endpoint = run(["lspci", "-Dnn", "-s", args.bdf], check=False).stdout.strip()
    command_before = command_value(args.bdf)
    print(endpoint or f"{args.bdf} not shown by lspci")
    print("COMMAND before: " + ("none" if command_before is None else f"0x{command_before:04x}"))
    words_before = [word.lower() for word in config_words(args.bdf)]
    if (
        not args.force_dead_config
        and command_before == 0xFFFF
        and not (device / "resource0").exists()
    ):
        observed = " ".join(words_before) if words_before else "unreadable"
        raise SystemExit(
            "live PCI config COMMAND reads as 0xffff and BAR0 is absent; "
            f"refusing delegated remove/rescan by default (config={observed}) "
            "because this stale Thunderbolt function state has correlated with "
            "host freezes. Re-enumerate the chassis or reboot with the FPGA "
            "already configured, then run lifecycle again. Use "
            "--force-dead-config only for a deliberate recovery experiment."
        )

    if args.reset_first and (real_device / "reset").exists():
        write_one(real_device / "reset", "endpoint reset")
        time.sleep(0.25)

    write_one(real_device / "remove", "endpoint remove")
    for _ in range(20):
        if not device.exists():
            break
        time.sleep(0.05)

    write_one(bridge_rescan, "upstream bridge rescan")

    recovered = wait_for_endpoint_resource(
        args.bdf,
        bridge_rescan,
        args.timeout,
        args.rescan_interval,
    )
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
