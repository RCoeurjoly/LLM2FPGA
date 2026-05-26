#!/usr/bin/env python3
"""Task 6 FPGA flash probe/write wrapper.

Flash writes are deliberately guarded. Probe mode does not write flash. Write
mode requires --confirm-write-flash so accidental normal board gates do not
modify non-volatile configuration.
"""

from __future__ import annotations

import argparse
from datetime import datetime
import json
from pathlib import Path
import shlex
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[2]
RUNS_ROOT = ROOT / "artifacts" / "task6" / "runs"
DEFAULT_OPENFPGALOADER = Path("/home/roland/openFPGALoader/build/openFPGALoader")
DEFAULT_CABLE = "digilent_hs3"
DEFAULT_SERIAL = "210299BF3824"
DEFAULT_FPGA_PART = "xc7k480t"


def iso_stamp() -> str:
    return datetime.now().astimezone().strftime("%Y-%m-%dT%H-%M-%S%z")


def run_dir(label: str) -> Path:
    path = RUNS_ROOT / f"{iso_stamp()}-{label}"
    path.mkdir(parents=True, exist_ok=False)
    (path / "logs").mkdir()
    return path


def run(cmd: list[str], label: str) -> int:
    out_dir = run_dir(label)
    print("$ " + shlex.join(cmd))
    proc = subprocess.run(cmd, cwd=ROOT, text=True, capture_output=True, check=False)
    print(proc.stdout, end="")
    print(proc.stderr, end="", file=sys.stderr)
    (out_dir / "logs" / "openfpgaloader.stdout").write_text(proc.stdout, encoding="utf-8")
    (out_dir / "logs" / "openfpgaloader.stderr").write_text(proc.stderr, encoding="utf-8")
    payload = {
        "finished_at": datetime.now().astimezone().isoformat(),
        "argv": cmd,
        "returncode": proc.returncode,
        "run_dir": str(out_dir.relative_to(ROOT)),
    }
    (out_dir / "flash-result.json").write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(f"run_dir: {out_dir}")
    return proc.returncode


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

    probe = subparsers.add_parser("probe", help="detect FPGA and attached flash without writing flash")
    probe.add_argument("--label", default="pcie-flash-probe")

    write = subparsers.add_parser("write", help="write and verify a bitstream to flash")
    write.add_argument("bitstream", type=Path)
    write.add_argument(
        "--confirm-write-flash",
        action="store_true",
        help="required guard for non-volatile flash writes",
    )
    write.add_argument("--offset", default=None, help="optional flash byte offset")
    write.add_argument("--label", default="pcie-flash-write")
    args = parser.parse_args()

    if args.mode == "probe":
        return run(base_cmd(args) + ["--detect", "-f"], args.label)

    if not args.confirm_write_flash:
        raise SystemExit("refusing flash write without --confirm-write-flash")
    if not args.bitstream.exists():
        raise SystemExit(f"missing bitstream: {args.bitstream}")
    cmd = base_cmd(args) + ["--write-flash", "--verify"]
    if args.offset is not None:
        cmd += ["--offset", args.offset]
    cmd.append(str(args.bitstream))
    return run(cmd, args.label)


if __name__ == "__main__":
    sys.exit(main())
