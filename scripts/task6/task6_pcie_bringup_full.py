#!/usr/bin/env python3
"""Autonomous Task 6 PCIe cold bring-up and board acceptance gate."""

from __future__ import annotations

import argparse
from datetime import datetime
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
RUNS_ROOT = ROOT / "artifacts" / "task6" / "runs"
DEFAULT_BDF = "0000:42:00.0"
DEFAULT_BRIDGE_BDF = "0000:41:00.0"
DEFAULT_POWER_URL = "192.168.1.136"
DEFAULT_SECRET_FILE = Path.home() / ".config" / "task6-pcie" / "tapo.env"
DEFAULT_PROMPT_REFERENCE = (
    ROOT
    / "artifacts"
    / "task6"
    / "parallel-hypotheses"
    / "h2-tinystories-1m-prompt-output-head-q024-reference.json"
)


def iso_stamp() -> str:
    return datetime.now().astimezone().strftime("%Y-%m-%dT%H-%M-%S%z")


def make_run_dir(label: str) -> Path:
    path = RUNS_ROOT / f"{iso_stamp()}-{label}"
    path.mkdir(parents=True, exist_ok=False)
    return path


def redacted_argv(cmd: list[str]) -> list[str]:
    result: list[str] = []
    redact_next = False
    for arg in cmd:
        if redact_next:
            result.append("<redacted>")
            redact_next = False
            continue
        result.append(arg)
        if arg in {"--password", "--tapo-password"}:
            redact_next = True
    return result


def run(cmd: list[str], *, run_dir: Path, name: str, timeout: float, dry_run: bool) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "name": name,
        "argv": redacted_argv(cmd),
        "dry_run": dry_run,
    }
    if dry_run:
        payload.update({"returncode": 0, "stdout": "", "stderr": "", "timeout": False})
    else:
        try:
            proc = subprocess.run(
                cmd,
                cwd=ROOT,
                text=True,
                capture_output=True,
                timeout=timeout,
                check=False,
            )
            payload.update(
                {
                    "returncode": proc.returncode,
                    "stdout": proc.stdout,
                    "stderr": proc.stderr,
                    "timeout": False,
                }
            )
        except subprocess.TimeoutExpired as exc:
            payload.update(
                {
                    "returncode": None,
                    "stdout": exc.stdout or "",
                    "stderr": exc.stderr or "",
                    "timeout": True,
                }
            )
    (run_dir / f"{name}.json").write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    return payload


def command_failed(result: dict[str, Any]) -> bool:
    return bool(result.get("timeout")) or result.get("returncode") != 0


def parse_orchestrator_run_dir(stdout: str) -> str | None:
    try:
        payload = json.loads(stdout)
    except json.JSONDecodeError:
        return None
    return payload.get("run_dir") if isinstance(payload, dict) else None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bdf", nargs="?", default=DEFAULT_BDF)
    parser.add_argument("--bridge-bdf", default=DEFAULT_BRIDGE_BDF)
    parser.add_argument("--label", default="task6-autonomous-bringup")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--bitstream", type=Path, help="optional BPI bitstream to flash before cold bring-up")
    parser.add_argument("--confirm-write-flash", action="store_true")
    parser.add_argument("--power-provider", choices=["tapo-p115"], default="tapo-p115")
    parser.add_argument("--power-url", default=DEFAULT_POWER_URL)
    parser.add_argument("--secret-file", type=Path, default=DEFAULT_SECRET_FILE)
    parser.add_argument("--power-off-wait", type=float, default=10.0)
    parser.add_argument("--power-on-wait", type=float, default=45.0)
    parser.add_argument("--max-power-cycles", type=int, default=3)
    parser.add_argument("--command-timeout", type=float, default=900.0)
    parser.add_argument("--model-path", type=Path)
    parser.add_argument(
        "--reference-json",
        type=Path,
        help="prompt reference JSON; defaults to the checked-in TinyStories prompt reference when present",
    )
    parser.add_argument("--sample-count", type=int, default=8)
    parser.add_argument("--prompt", default="Once upon a time there was")
    parser.add_argument("--skip-initial-power-cycle", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    run_dir = make_run_dir(args.label)
    steps: list[dict[str, Any]] = []

    if args.bitstream is not None:
        if not args.confirm_write_flash:
            raise SystemExit("--bitstream requires --confirm-write-flash")
        flash_cmd = [
            "scripts/task6/task6_pcie_user_gate.sh",
            "flash",
            args.bdf,
            "write",
            str(args.bitstream),
            "--confirm-write-flash",
            "--label",
            f"{args.label}-flash-write",
        ]
        result = run(flash_cmd, run_dir=run_dir, name="flash-write", timeout=args.command_timeout, dry_run=args.dry_run)
        steps.append(result)
        if command_failed(result):
            return finish(args, run_dir, steps, "FAIL", "flash-write failed")

    if not args.skip_initial_power_cycle:
        cycle_cmd = [
            "nix",
            "shell",
            "nixpkgs#uv",
            "-c",
            "uv",
            "run",
            "--with",
            "tapo",
            "python3",
            "scripts/task6/task6_tapo_p115_power.py",
            "--backend",
            "tapo",
            "--host",
            args.power_url,
            "--state",
            "off",
        ]
        env = os.environ.copy()
        if args.secret_file.exists():
            for line in args.secret_file.read_text(encoding="utf-8").splitlines():
                if "=" in line and not line.lstrip().startswith("#"):
                    key, value = line.split("=", 1)
                    env.setdefault(key.strip(), value.strip().strip('"').strip("'"))
        if "TAPO_USERNAME" in env:
            cycle_cmd.extend(["--username", env["TAPO_USERNAME"]])
        if "TAPO_PASSWORD" in env:
            cycle_cmd.extend(["--password", env["TAPO_PASSWORD"]])
        off = run(cycle_cmd, run_dir=run_dir, name="power-off", timeout=60.0, dry_run=args.dry_run)
        steps.append(off)
        if command_failed(off):
            return finish(args, run_dir, steps, "FAIL", "initial Tapo power-off failed")
        if not args.dry_run:
            import time

            time.sleep(args.power_off_wait)
        on_cmd = list(cycle_cmd)
        on_cmd[on_cmd.index("off")] = "on"
        on = run(on_cmd, run_dir=run_dir, name="power-on", timeout=60.0, dry_run=args.dry_run)
        steps.append(on)
        if command_failed(on):
            return finish(args, run_dir, steps, "FAIL", "initial Tapo power-on failed")
        if not args.dry_run:
            import time

            time.sleep(args.power_on_wait)

    recover_cmd = [
        "scripts/task6/task6_pcie_user_gate.sh",
        "recover-auto",
        args.bdf,
        "--bridge-bdf",
        args.bridge_bdf,
        "--label",
        f"{args.label}-recover",
        "--allow-power-cycle",
        "--max-power-cycles",
        str(args.max_power_cycles),
        "--power-provider",
        args.power_provider,
        "--power-url",
        args.power_url,
        "--secret-file",
        str(args.secret_file),
        "--power-off-wait",
        str(args.power_off_wait),
        "--power-on-wait",
        str(args.power_on_wait),
    ]
    recover = run(recover_cmd, run_dir=run_dir, name="recover-auto", timeout=args.command_timeout, dry_run=args.dry_run)
    steps.append(recover)
    if command_failed(recover):
        return finish(args, run_dir, steps, "FAIL", "PCIe recovery did not reach pcie_ready")

    rowstream_cmd = [
        "scripts/task6/task6_pcie_user_gate.sh",
        "rowstream-top1",
        args.bdf,
        "--sample-count",
        str(args.sample_count),
        "--json-out",
        str(run_dir / "rowstream-top1.json"),
    ]
    reference_json = args.reference_json
    if reference_json is None and DEFAULT_PROMPT_REFERENCE.exists():
        reference_json = DEFAULT_PROMPT_REFERENCE

    if reference_json is not None:
        rowstream_cmd.extend(["--reference-json", str(reference_json)])
    elif args.model_path is not None:
        rowstream_cmd.extend(["--model-path", str(args.model_path)])
    else:
        raise SystemExit("bringup-full requires --reference-json or --model-path for rowstream-top1")
    rowstream = run(rowstream_cmd, run_dir=run_dir, name="rowstream-top1", timeout=args.command_timeout, dry_run=args.dry_run)
    steps.append(rowstream)
    if command_failed(rowstream):
        return finish(args, run_dir, steps, "FAIL", "rowstream-top1 failed")

    mlp_cmd = [
        "scripts/task6/task6_pcie_user_gate.sh",
        "mlp-accel",
        args.bdf,
        "--output-surface",
        "checksum-sample",
        "--require-samples",
        "--json-out",
        str(run_dir / "mlp-accel.json"),
    ]
    mlp = run(mlp_cmd, run_dir=run_dir, name="mlp-accel", timeout=args.command_timeout, dry_run=args.dry_run)
    steps.append(mlp)
    if command_failed(mlp):
        return finish(args, run_dir, steps, "FAIL", "MLP checksum/sample gate failed")

    orchestrator_run_dir = parse_orchestrator_run_dir(str(recover.get("stdout", "")))
    return finish(
        args,
        run_dir,
        steps,
        "PASS",
        "autonomous PCIe bring-up and Task 6 board gates passed",
        extra={"orchestrator_run_dir": orchestrator_run_dir},
    )


def finish(
    args: argparse.Namespace,
    run_dir: Path,
    steps: list[dict[str, Any]],
    status: str,
    reason: str,
    extra: dict[str, Any] | None = None,
) -> int:
    reference_json = args.reference_json
    if reference_json is None and DEFAULT_PROMPT_REFERENCE.exists():
        reference_json = DEFAULT_PROMPT_REFERENCE
    summary: dict[str, Any] = {
        "artifact_name": "task6-pcie-autonomous-bringup-full",
        "status": status,
        "reason": reason,
        "run_dir": str(run_dir),
        "bdf": args.bdf,
        "prompt": args.prompt,
        "reference_json": str(reference_json) if reference_json is not None else None,
        "steps": [
            {
                "name": step.get("name"),
                "argv": step.get("argv"),
                "returncode": step.get("returncode"),
                "timeout": step.get("timeout"),
            }
            for step in steps
        ],
    }
    if extra:
        summary.update(extra)
    (run_dir / "bringup-summary.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(summary, indent=2, sort_keys=True))
    return 0 if status == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
