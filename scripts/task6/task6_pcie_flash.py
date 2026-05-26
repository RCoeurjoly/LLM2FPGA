#!/usr/bin/env python3
"""Task 6 FPGA flash probe/write wrapper.

Flash writes are deliberately guarded. Probe mode does not write flash. Write mode
requires --confirm-write-flash so accidental normal board gates do not modify
non-volatile configuration.
"""

from __future__ import annotations

import argparse
from pathlib import Path
import shlex
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OPENFPGALOADER = Path("/home/roland/openFPGALoader/build/openFPGALoader")
DEFAULT_CABLE = "digilent_hs3"
DEFAULT_SERIAL = "210299BF3824"
DEFAULT_FPGA_PART = "xc7k480t"


def run(cmd: list[str]) -> int:
    print("$ " + shlex.join(cmd))
    return subprocess.run(cmd, cwd=ROOT, check=False).returncode


def base_cmd(args: argparse.Namespace) -> list[str]:
    cmd = [
        str(args.openfpgaloader),
        "-c",
        args.cable,
        "--ftdi-serial",
        args.ftdi_serial,
        "--fpga-part",
        args.fpga_part,
    ]
    if args.bridge is not None:
        cmd += ["--bridge", args.bridge]
    return cmd


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--openfpgaloader", type=Path, default=DEFAULT_OPENFPGALOADER)
    parser.add_argument("--cable", default=DEFAULT_CABLE)
    parser.add_argument("--ftdi-serial", default=DEFAULT_SERIAL)
    parser.add_argument("--fpga-part", default=DEFAULT_FPGA_PART)
    parser.add_argument("--bridge", default=None, help="optional openFPGALoader --bridge value or file")
    subparsers = parser.add_subparsers(dest="mode", required=True)

    subparsers.add_parser("probe", help="detect FPGA and attached flash without writing flash")

    write = subparsers.add_parser("write", help="write and verify a bitstream to flash")
    write.add_argument("bitstream", type=Path)
    write.add_argument(
        "--confirm-write-flash",
        action="store_true",
        help="required guard for non-volatile flash writes",
    )
    write.add_argument("--offset", default=None, help="optional flash byte offset")
    args = parser.parse_args()

    if args.mode == "probe":
        return run(base_cmd(args) + ["--detect", "-f"])

    if not args.confirm_write_flash:
        raise SystemExit("refusing flash write without --confirm-write-flash")
    if not args.bitstream.exists():
        raise SystemExit(f"missing bitstream: {args.bitstream}")
    cmd = base_cmd(args) + ["--write-flash", "--verify"]
    if args.offset is not None:
        cmd += ["--offset", args.offset]
    cmd.append(str(args.bitstream))
    return run(cmd)


if __name__ == "__main__":
    sys.exit(main())
