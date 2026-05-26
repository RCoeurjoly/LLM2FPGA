#!/usr/bin/env python3
"""Rescan the fixed Task 6 upstream PCIe bridge without sudo."""

from __future__ import annotations

import argparse
from pathlib import Path


DEFAULT_BRIDGE = "0000:41:00.0"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bridge_bdf", nargs="?", default=DEFAULT_BRIDGE)
    args = parser.parse_args()

    bridge = Path("/sys/bus/pci/devices") / args.bridge_bdf
    rescan = bridge / "rescan"
    if not bridge.exists():
        raise SystemExit(f"missing PCI bridge: {bridge}")
    if not rescan.exists():
        raise SystemExit(f"missing bridge rescan node: {rescan}")
    if not rescan.is_file():
        raise SystemExit(f"bridge rescan is not a file: {rescan}")
    try:
        rescan.write_text("1\n", encoding="ascii")
    except PermissionError as exc:
        raise SystemExit(
            f"bridge rescan is not writable by this user: {rescan}\n"
            "Install/trigger the Task 6 PCIe udev rules."
        ) from exc
    print(f"PASS: rescanned Task 6 upstream bridge {args.bridge_bdf}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
