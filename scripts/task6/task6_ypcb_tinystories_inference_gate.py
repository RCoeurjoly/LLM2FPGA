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
DEFAULT_BASELINE_DIR = (
    ROOT
    / "artifacts"
    / "task6"
    / "uberddr3-baseline-flow"
    / "seed16-vainilla-2026-05-20"
)
DEFAULT_BITSTREAMS = {
    1: "ypcb-00338-1p1-ddr3-bist-1lane-full-openxc7.bit",
    2: "ypcb-00338-1p1-ddr3-bist-2lanes-full-openxc7.bit",
}
DEFAULT_RUN_ROOT = ROOT / "artifacts" / "task6" / "runs"
LOADER_SCRIPT = ROOT / "scripts" / "task6" / "task6_ddr3_rowstream_loader.py"
DEFAULT_ADAPTER = ROOT / "TinyStories" / "model_adapter_representative_core.py"
DEFAULT_BOUNDARIES = "0,1,31,32,50256"
DEFAULT_PLAN_ID = "plan-unknown"
DEFAULT_HYPOTHESIS_ID = "hypothesis-unknown"


def default_bitstream(byte_lanes: int) -> Path:
    if byte_lanes not in DEFAULT_BITSTREAMS:
        raise ValueError(f"unsupported byte-lanes: {byte_lanes}")
    return DEFAULT_BASELINE_DIR / DEFAULT_BITSTREAMS[byte_lanes]


@dataclass
class StepResult:
    name: str
    run_dir: Path
    return_code: int
    payload: dict[str, Any] | None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--byte-lanes", type=int, choices=(1, 2), default=2)
    parser.add_argument(
        "--bitstream",
        type=Path,
        default=None,
        help="Path to the DDR3 anchor bitstream.",
    )
    parser.add_argument(
        "--model-path",
        type=Path,
        default=None,
        help="TinyStories-1M model snapshot for top1 replay.",
    )
    parser.add_argument(
        "--adapter-path",
        type=Path,
        default=DEFAULT_ADAPTER,
        help="Adapter path used to replay top1.",
    )
    parser.add_argument(
        "--storage-mode",
        choices=("lowbyte", "beat"),
        default="lowbyte",
        help="Storage mode used for rowstream load/replay.",
    )
    parser.add_argument(
        "--run-root",
        type=Path,
        default=None,
        help="Directory that stores all three step sub-runs.",
    )
    parser.add_argument("--plan-id", default=DEFAULT_PLAN_ID, help="Plan identifier used for this run.")
    parser.add_argument(
        "--hypothesis-id",
        default=DEFAULT_HYPOTHESIS_ID,
        help="Hypothesis identifier for this run.",
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
    parser.add_argument(
        "--skip-top1",
        action="store_true",
        help="Skip top1 replay in inference stage.",
    )
    parser.add_argument(
        "--json-only",
        action="store_true",
        help="Only print final gate summary JSON.",
    )
    return parser.parse_args()


# Optional metadata keys used to drive future reporting dashboards.
KNOWN_GATE_KEYS = [
    "boot_gate",
    "fullbeat_gate",
    "boundary_rows_gate",
    "full_readback_gate",
    "top1_gate",
]


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
        "--storage-mode",
        args.storage_mode,
        "--byte-lanes",
        str(args.byte_lanes),
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


def build_gates(steps: list[StepResult]) -> dict[str, str | None]:
    gates = {key: "PENDING" for key in KNOWN_GATE_KEYS}
    for step in steps:
        if step.name == "boot-only":
            gates["boot_gate"] = "PASS" if step_passed(step) else "FAIL"
        elif step.name == "rtl-fullbeat":
            gates["fullbeat_gate"] = "PASS" if step_passed(step) else "FAIL"
            if step.payload:
                gates["boundary_rows_gate"] = step.payload.get("boundary_rows", "PENDING")
                gates["full_readback_gate"] = step.payload.get("full_readback", "PENDING")
                gates["top1_gate"] = step.payload.get("top1", "PENDING")
        elif step.name == "tinystories-inference":
            if step.payload:
                gates["boundary_rows_gate"] = step.payload.get("boundary_rows", gates["boundary_rows_gate"])
                gates["full_readback_gate"] = step.payload.get("full_readback", gates["full_readback_gate"])
                gates["top1_gate"] = step.payload.get("top1", gates["top1_gate"])

    for key, value in list(gates.items()):
        if value == "PENDING":
            continue
        if isinstance(value, str) and value.upper() in {"PASS", "FAIL"}:
            continue
        if isinstance(value, dict):
            gates[key] = "PASS" if value.get("status", "") == "PASS" else "FAIL"
        elif isinstance(value, bool):
            gates[key] = "PASS" if value else "FAIL"

    return gates


def main() -> int:
    args = parse_args()
    args.bitstream = args.bitstream or default_bitstream(args.byte_lanes)
    if not args.bitstream.exists():
        raise SystemExit(f"bitstream does not exist: {args.bitstream}")

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
        if not args.skip_top1 and args.model_path is None:
            raise SystemExit("--model-path is required unless --skip-top1 is set")
        if not args.skip_top1 and args.adapter_path is None:
            raise SystemExit("--adapter-path is required unless --skip-top1 is set")

        inference_args: list[str] = [
            "--run-inference",
            "--boundary-tokens",
            args.boundary_tokens,
            "--sample-count",
            str(args.sample_count),
        ]
        if args.skip_top1:
            inference_args.append("--no-top1-from-model")
        else:
            inference_args.extend(
                [
                    "--top1-from-model",
                    "--model-path",
                    str(args.model_path),
                    "--adapter-path",
                    str(args.adapter_path),
                ]
            )

        inference = run_loader_step(
            "tinystories-inference",
            run_root / "tinystories-inference",
            args,
            extra_args=inference_args,
            program=False,
        )
        steps.append(inference)
        overall_ok = overall_ok and step_passed(inference)

    gates = build_gates(steps)
    summary = {
        "artifact_name": "task6-ypcb-ddr3-inference-gate",
        "plan_id": args.plan_id,
        "hypothesis_id": args.hypothesis_id,
        "status": "PASS" if overall_ok else "FAIL",
        "lane": "ddr3",
        "byte_lanes": args.byte_lanes,
        "storage_mode": args.storage_mode,
        "run_root": str(run_root),
        "bitstream": str(args.bitstream),
        "gates": gates,
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
