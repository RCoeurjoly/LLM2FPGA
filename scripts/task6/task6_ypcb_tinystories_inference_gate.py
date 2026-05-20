#!/usr/bin/env python3
"""Run the YPCB TinyStories-1M DDR3 gate end-to-end."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_BITSTREAM = (
    ROOT
    / "artifacts"
    / "task6"
    / "uberddr3-baseline-flow"
    / "seed16-vainilla-2026-05-20"
    / "ypcb-00338-1p1-ddr3-bist-1lane-full-openxc7.bit"
)
DEFAULT_RUN_ROOT = ROOT / "artifacts" / "task6" / "runs"
LOADER_SCRIPT = ROOT / "scripts" / "task6" / "task6_ddr3_rowstream_loader.py"
DEFAULT_ADAPTER = ROOT / "TinyStories" / "model_adapter_representative_core.py"
DEFAULT_BOUNDARIES = "0,1,31,32,50256"


@dataclass
class StepResult:
    name: str
    run_dir: Path
    return_code: int
    payload: dict[str, Any] | None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--bitstream",
        type=Path,
        default=DEFAULT_BITSTREAM,
        help="Path to the DDR3 anchor bitstream.",
    )
    parser.add_argument(
        "--model-path",
        required=True,
        type=Path,
        help="TinyStories-1M model snapshot for top1 replay.",
    )
    parser.add_argument(
        "--adapter-path",
        type=Path,
        default=DEFAULT_ADAPTER,
        help="Adapter path used to replay top1.",
    )
    parser.add_argument(
        "--run-root",
        type=Path,
        default=None,
        help="Directory that stores all three step sub-runs.",
    )
    parser.add_argument("--calib-timeout", type=float, default=120.0)
    parser.add_argument("--fullbeat-base", type=lambda value: int(value, 0), default=0x20)
    parser.add_argument("--fullbeat-addr", type=lambda value: int(value, 0), default=0)
    parser.add_argument("--sample-count", type=int, default=8)
    parser.add_argument("--boundary-tokens", default=DEFAULT_BOUNDARIES)
    parser.add_argument("--serial", default="210299BF3824")
    parser.add_argument("--jtag-cable", default="digilent_hs3")
    parser.add_argument("--freq-hz", type=int, default=1_000_000)
    parser.add_argument("--tdo-bit", type=int, choices=(0, 7), default=7)
    parser.add_argument("--command-delay", type=float, default=0.001)
    parser.add_argument("--command-repeats", type=int, default=2)
    parser.add_argument("--skip-boot", action="store_true", help="Skip boot-only stage.")
    parser.add_argument(
        "--skip-fullbeat",
        action="store_true",
        help="Skip RTL fullbeat diagnostic stage.",
    )
    parser.add_argument(
        "--skip-inference",
        action="store_true",
        help="Skip inference load/readback/top1 stage.",
    )
    parser.add_argument("--json-only", action="store_true", help="Only print final gate summary JSON.")
    return parser.parse_args()


def run_loader_step(
    name: str,
    run_dir: Path,
    args: argparse.Namespace,
    *,
    extra_args: list[str],
    program: bool,
) -> StepResult:
    command = [
        sys.executable,
        str(LOADER_SCRIPT),
        "--bitstream",
        str(args.bitstream),
        "--run-dir",
        str(run_dir),
        "--json-only",
        "--serial",
        args.serial,
        "--jtag-cable",
        args.jtag_cable,
        "--freq-hz",
        str(args.freq_hz),
        "--tdo-bit",
        str(args.tdo_bit),
        "--command-delay",
        str(args.command_delay),
        "--command-repeats",
        str(args.command_repeats),
        "--calib-timeout",
        str(args.calib_timeout),
        "--no-program" if not program else "--program",
    ]
    command.extend(extra_args)

    completed = subprocess.run(
        command,
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    raw_output = completed.stdout.strip()
    payload = None
    if raw_output:
        try:
            payload = json.loads(raw_output)
        except json.JSONDecodeError:
            payload = {"status": "FAIL", "raw_output": raw_output}

    return StepResult(
        name=name,
        run_dir=run_dir,
        return_code=completed.returncode,
        payload=payload,
    )


def step_passed(step: StepResult) -> bool:
    if step.return_code != 0:
        return False
    if step.payload is None:
        return False
    return str(step.payload.get("status", "")).upper() == "PASS"


def main() -> int:
    args = parse_args()

    run_root = args.run_root
    if run_root is None:
        stamp = datetime.now().astimezone().strftime("%Y-%m-%dT%H-%M-%S%z")
        run_root = DEFAULT_RUN_ROOT / f"{stamp}-task6-ypcb-ddr3-inference-gate"
    run_root.mkdir(parents=True, exist_ok=True)

    steps: list[StepResult] = []
    overall_ok = True

    if not args.skip_boot:
        boot = run_loader_step(
            "boot-only",
            run_root / "boot-only",
            args,
            extra_args=["--boot-only"],
            program=True,
        )
        steps.append(boot)
        overall_ok = overall_ok and step_passed(boot)

    if overall_ok and not args.skip_fullbeat:
        fullbeat = run_loader_step(
            "rtl-fullbeat",
            run_root / "rtl-fullbeat",
            args,
            extra_args=[
                "--diagnostic-rtl-fullbeat-base",
                str(args.fullbeat_base),
                "--diagnostic-rtl-fullbeat-addr",
                str(args.fullbeat_addr),
            ],
            program=False,
        )
        steps.append(fullbeat)
        overall_ok = overall_ok and step_passed(fullbeat)

    if overall_ok and not args.skip_inference:
        inference = run_loader_step(
            "tinystories-inference",
            run_root / "tinystories-inference",
            args,
            extra_args=[
                "--storage-mode",
                "lowbyte",
                "--run-inference",
                "--top1-from-model",
                "--model-path",
                str(args.model_path),
                "--adapter-path",
                str(args.adapter_path),
                "--sample-count",
                str(args.sample_count),
                "--boundary-tokens",
                args.boundary_tokens,
            ],
            program=False,
        )
        steps.append(inference)
        overall_ok = overall_ok and step_passed(inference)

    summary = {
        "artifact_name": "task6-ypcb-ddr3-inference-gate",
        "status": "PASS" if overall_ok else "FAIL",
        "run_root": str(run_root),
        "bitstream": str(args.bitstream),
        "steps": [
            {
                "name": step.name,
                "run_dir": str(step.run_dir),
                "return_code": step.return_code,
                "payload": step.payload,
            }
            for step in steps
        ],
    }

    (run_root / "gate-summary.json").write_text(
        json.dumps(summary, sort_keys=True, indent=2) + "\n",
        encoding="utf-8",
    )

    if args.json_only:
        print(json.dumps(summary, sort_keys=True, indent=2))
    else:
        print(summary["status"])
        for step in summary["steps"]:
            status = step["payload"].get("status") if step["payload"] else None
            print(f"{step['name']}: rc={step['return_code']} status={status}")
    return 0 if overall_ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
