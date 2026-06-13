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
DEFAULT_BOARD = "ypcb003381p1"
DEFAULT_CABLE = "digilent_hs3"
DEFAULT_SERIAL = "210299BF3824"
DEFAULT_FPGA_PART = "xc7k480t"
DEFAULT_BDF = "0000:42:00.0"
EXPECTED_VENDOR = "10ee"
EXPECTED_DEVICE = "0480"
EXPECTED_SUBSYSTEM_DEVICE = "abcd"


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


def setpci_words(bdf: str) -> dict[str, object]:
    cmd = [
        "setpci",
        "-s",
        bdf,
        "COMMAND",
        "VENDOR_ID",
        "DEVICE_ID",
        "HEADER_TYPE",
        "2e.w",
        "10.l",
    ]
    try:
        proc = subprocess.run(
            cmd,
            cwd=ROOT,
            text=True,
            capture_output=True,
            timeout=3.0,
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        return {
            "argv": cmd,
            "returncode": None,
            "stdout": exc.stdout or "",
            "stderr": exc.stderr or "",
            "timeout": True,
            "words": [],
        }
    words = proc.stdout.split()
    return {
        "argv": cmd,
        "returncode": proc.returncode,
        "stdout": proc.stdout,
        "stderr": proc.stderr,
        "timeout": False,
        "words": [word.lower() for word in words],
    }


def classify_config_words(words: list[str]) -> str:
    if len(words) < 4:
        return "config_unreadable"
    command, vendor, device, header_type = [word.lower() for word in words[:4]]
    subsystem_device = words[4].lower() if len(words) > 4 else ""
    bar0 = words[5].lower() if len(words) > 5 else ""
    if command == "ffff":
        return "corrupt_command"
    if vendor == "ffff":
        return "corrupt_vendor_id"
    if vendor != EXPECTED_VENDOR:
        return "wrong_vendor"
    if device != EXPECTED_DEVICE:
        return "corrupt_device_id"
    if header_type not in ("00", "0000"):
        return "corrupt_header_type"
    if subsystem_device and subsystem_device != EXPECTED_SUBSYSTEM_DEVICE:
        return "corrupt_subsystem_device"
    if bar0 in ("00000000", "ffffffff"):
        return "missing_resource0"
    if (int(command, 16) & 0x0002) == 0:
        return "mem_disabled"
    return "pcie_ready"


def classify_config_reads(first_words: list[str], second_words: list[str]) -> str:
    first_normalized = [word.lower() for word in first_words]
    second_normalized = [word.lower() for word in second_words]
    if first_normalized != second_normalized:
        return "unstable_config"
    return classify_config_words(first_normalized)


def flash_write_allowed(classification: str, allow_corrupt_pcie_config: bool) -> bool:
    return classification == "pcie_ready" or allow_corrupt_pcie_config


def record_refusal(args: argparse.Namespace, probe: dict[str, object], classification: str) -> int:
    out_dir = run_dir(f"{args.label}-refused")
    payload = {
        "finished_at": datetime.now().astimezone().isoformat(),
        "returncode": 2,
        "run_dir": str(out_dir.relative_to(ROOT)),
        "mode": "write",
        "bitstream": str(args.bitstream),
        "bdf": args.bdf,
        "classification": classification,
        "config_probe": probe,
        "reason": (
            "refusing flash write while PCIe lifecycle is not pcie_ready; "
            "rerun with --allow-corrupt-pcie-config only for a deliberate "
            "board programming recovery experiment"
        ),
    }
    (out_dir / "flash-result.json").write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(f"refusing flash write: PCIe classification is {classification}", file=sys.stderr)
    print(f"artifact: {out_dir / 'flash-result.json'}", file=sys.stderr)
    return 2


def base_cmd(args: argparse.Namespace) -> list[str]:
    cmd = [str(args.openfpgaloader)]
    if args.board:
        cmd += ["-b", args.board]
        if args.cable:
            cmd += ["-c", args.cable]
        cmd += ["--ftdi-serial", args.ftdi_serial]
    else:
        cmd += [
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
    parser.add_argument(
        "--board",
        default=DEFAULT_BOARD,
        help='openFPGALoader board name; pass "" to use --cable/--fpga-part mode',
    )
    parser.add_argument("--cable", default=DEFAULT_CABLE)
    parser.add_argument("--ftdi-serial", default=DEFAULT_SERIAL)
    parser.add_argument("--fpga-part", default=DEFAULT_FPGA_PART)
    parser.add_argument("--bridge", default=None, help="optional openFPGALoader --bridge value or file")
    parser.add_argument("--bdf", default=DEFAULT_BDF, help="PCIe endpoint BDF used for non-BAR flash-write preflight")
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
    write.add_argument(
        "--allow-corrupt-pcie-config",
        action="store_true",
        help=(
            "allow a flash write when the non-BAR PCIe config preflight is not "
            "pcie_ready; use only for deliberate board programming recovery"
        ),
    )
    args = parser.parse_args()

    if args.mode == "probe":
        return run(base_cmd(args) + ["--detect", "-f"], args.label)

    if not args.confirm_write_flash:
        raise SystemExit("refusing flash write without --confirm-write-flash")
    if not args.bitstream.exists():
        raise SystemExit(f"missing bitstream: {args.bitstream}")
    probe = setpci_words(args.bdf)
    repeat_probe = setpci_words(args.bdf)
    probe["repeat_probe"] = repeat_probe
    classification = classify_config_reads(list(probe["words"]), list(repeat_probe["words"]))
    if not flash_write_allowed(classification, args.allow_corrupt_pcie_config):
        return record_refusal(args, probe, classification)
    cmd = base_cmd(args) + ["--write-flash", "--verify"]
    if args.offset is not None:
        cmd += ["--offset", args.offset]
    cmd.append(str(args.bitstream))
    return run(cmd, args.label)


if __name__ == "__main__":
    sys.exit(main())
