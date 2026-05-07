#!/usr/bin/env python3
"""Create Task 6 run directories and serialize board-facing commands."""

from __future__ import annotations

import argparse
from datetime import datetime
import fcntl
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
RUNS_ROOT = ROOT / "artifacts" / "task6" / "runs"
LOCK_PATH = ROOT / "artifacts" / "task6" / "board.lock"


def iso_timestamp() -> str:
    return datetime.now().astimezone().strftime("%Y-%m-%dT%H-%M-%S%z")


def sanitize_label(value: str) -> str:
    cleaned = []
    for char in value.lower():
        if char.isalnum():
            cleaned.append(char)
        elif char in ("-", "_", ".", "+"):
            cleaned.append(char)
        elif char.isspace():
            cleaned.append("-")
    label = "".join(cleaned).strip("-")
    return label or "task6-run"


def allocate_run_dir(label: str) -> Path:
    RUNS_ROOT.mkdir(parents=True, exist_ok=True)
    base = f"{iso_timestamp()}-{sanitize_label(label)}"
    for index in range(100):
        suffix = "" if index == 0 else f"-{index:02d}"
        candidate = RUNS_ROOT / f"{base}{suffix}"
        try:
            candidate.mkdir(exist_ok=False)
            return candidate
        except FileExistsError:
            continue
    raise SystemExit(f"could not allocate run dir for {label!r}")


def yaml_scalar(value: Any) -> str:
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    text = str(value)
    escaped = text.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def write_meta_yaml(path: Path, payload: dict[str, Any]) -> None:
    lines: list[str] = []
    for key, value in payload.items():
        if isinstance(value, list):
            lines.append(f"{key}:")
            for item in value:
                lines.append(f"  - {yaml_scalar(item)}")
        else:
            lines.append(f"{key}: {yaml_scalar(value)}")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def cmd_init(args: argparse.Namespace) -> int:
    run_dir = allocate_run_dir(args.label)
    for name in ("logs", "bitstreams", "readback", "references"):
        (run_dir / name).mkdir()

    created_at = datetime.now().astimezone().isoformat()
    meta = {
        "schema": "task6-board-run-v1",
        "created_at": created_at,
        "label": args.label,
        "experiment": args.experiment,
        "board": args.board,
        "fpga": args.fpga,
        "jtag_cable": args.jtag_cable,
        "ftdi_serial": args.ftdi_serial,
        "bitstream": str(args.bitstream) if args.bitstream else None,
        "reference_artifacts": args.reference_artifact,
        "notes": args.notes,
    }
    write_meta_yaml(run_dir / "meta.yaml", meta)
    write_json(
        run_dir / "verdict.json",
        {
            "schema": "task6-board-verdict-v1",
            "status": "CREATED",
            "created_at": created_at,
            "run_dir": str(run_dir.relative_to(ROOT)),
            "correctness": None,
            "route": None,
            "board": None,
            "bram_margin": None,
            "lut_margin": None,
            "dsp_margin": None,
            "timing_margin": None,
            "runtime": None,
            "notes": [],
        },
    )
    print(run_dir)
    return 0


def update_command_result(
    run_dir: Path,
    log_name: str,
    argv: list[str],
    returncode: int,
) -> None:
    result_path = run_dir / "command-results.jsonl"
    payload = {
        "finished_at": datetime.now().astimezone().isoformat(),
        "log": log_name,
        "argv": argv,
        "returncode": returncode,
    }
    with result_path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(payload, sort_keys=True) + "\n")


def cmd_with_lock(args: argparse.Namespace) -> int:
    run_dir = args.run_dir.resolve()
    if not run_dir.is_dir():
        raise SystemExit(f"run dir does not exist: {run_dir}")
    if not args.command:
        raise SystemExit("missing command after --")

    LOCK_PATH.parent.mkdir(parents=True, exist_ok=True)
    with LOCK_PATH.open("w", encoding="utf-8") as lock_file:
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
        lock_file.seek(0)
        lock_file.truncate()
        lock_file.write(
            json.dumps(
                {
                    "pid": os.getpid(),
                    "run_dir": str(run_dir),
                    "started_at": datetime.now().astimezone().isoformat(),
                    "argv": args.command,
                },
                sort_keys=True,
            )
            + "\n"
        )
        lock_file.flush()

        log_path = run_dir / "logs" / args.log_name
        log_path.parent.mkdir(parents=True, exist_ok=True)
        with log_path.open("w", encoding="utf-8") as log:
            log.write("$ " + shlex.join(args.command) + "\n")
            log.flush()
            proc = subprocess.run(
                args.command,
                cwd=ROOT,
                stdout=log,
                stderr=subprocess.STDOUT,
                text=True,
                check=False,
            )
        update_command_result(run_dir, args.log_name, args.command, proc.returncode)
        lock_file.seek(0)
        lock_file.truncate()
    return proc.returncode


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command_name", required=True)

    init = subparsers.add_parser("init")
    init.add_argument("--label", required=True)
    init.add_argument("--experiment", required=True)
    init.add_argument("--board", default="YPCB-00338-1P1")
    init.add_argument("--fpga", default="xc7k480tffg1156")
    init.add_argument("--jtag-cable", default="digilent_hs3")
    init.add_argument("--ftdi-serial", default="210299BF3824")
    init.add_argument("--bitstream", type=Path)
    init.add_argument("--reference-artifact", action="append", default=[])
    init.add_argument("--notes")
    init.set_defaults(func=cmd_init)

    locked = subparsers.add_parser("with-lock")
    locked.add_argument("--run-dir", required=True, type=Path)
    locked.add_argument("--log-name", default="command.log")
    locked.add_argument("command", nargs=argparse.REMAINDER)
    locked.set_defaults(func=cmd_with_lock)

    args = parser.parse_args()
    if getattr(args, "command", None) and args.command[0] == "--":
        args.command = args.command[1:]
    return args


def main() -> int:
    args = parse_args()
    return int(args.func(args))


if __name__ == "__main__":
    sys.exit(main())
