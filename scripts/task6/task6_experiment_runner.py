#!/usr/bin/env python3
"""Run and record Task 6 vocab/quantization experiments.

The runner intentionally wraps the existing Nix targets instead of replacing
the repo's build graph.  It gives each experiment a durable JSON record with
the parameters, gate outcomes, output paths, and cheap correctness/route
metrics that are easy to sweep later.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import datetime
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
EXPERIMENT_ROOT = ROOT / "artifacts" / "task6" / "experiments"


@dataclass(frozen=True)
class Gate:
    name: str
    attr_suffix: str


GATES: dict[str, Gate] = {
    "tb-data": Gate("tb-data", "tb-data-sv"),
    "sv-sim": Gate("sv-sim", "sv-sim"),
    "json": Gate("json", "jtag-debug-json"),
    "fasm": Gate("fasm", "jtag-debug-5mhz-fasm"),
    "bitstream": Gate("bitstream", "jtag-debug-5mhz-bitstream"),
}

DEFAULT_GATE_ORDER = ("tb-data", "sv-sim", "json")


def iso_timestamp() -> str:
    return datetime.now().astimezone().strftime("%Y-%m-%dT%H-%M-%S%z")


def sanitize_label(value: str) -> str:
    cleaned: list[str] = []
    for char in value.lower():
        if char.isalnum():
            cleaned.append(char)
        elif char in ("-", "_", ".", "+"):
            cleaned.append(char)
        elif char.isspace():
            cleaned.append("-")
    return "".join(cleaned).strip("-") or "task6-experiment"


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def relpath(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(ROOT))
    except ValueError:
        return str(path)


def derive_prefix(args: argparse.Namespace) -> str:
    if args.flake_prefix:
        return args.flake_prefix

    if args.weight_quantization == "ternary2":
        if args.vocab_size == 9984 and (args.physical_vocab_size in (None, 9984)):
            return "task6-ternary-v9984-l2-residual-add-output-head-selftest"
        raise SystemExit(
            "no default ternary2 flake target for this shape; pass --flake-prefix"
        )

    if args.weight_quantization == "ternary-base3-20":
        if args.vocab_size == 10000 and (args.physical_vocab_size in (None, 10000)):
            return "task6-ternary-base3-v10k-l2-residual-add-output-head-selftest"
        raise SystemExit(
            "no default ternary-base3-20 flake target for this shape; pass --flake-prefix"
        )

    if args.weight_quantization != "int8":
        raise SystemExit(
            f"no default flake target for quantization {args.weight_quantization!r}; "
            "pass --flake-prefix"
        )

    if args.vocab_size == 4096 and (args.physical_vocab_size in (None, 4096)):
        return "task6-int8-v4k-l2-residual-add-output-head-selftest"
    if args.vocab_size == 9984 and (args.physical_vocab_size in (None, 9984)):
        return "task6-int8-v9984-l2-residual-add-output-head-selftest"

    raise SystemExit("no default int8 flake target for this shape; pass --flake-prefix")


def parse_nix_out_paths(stdout: str) -> list[str]:
    paths: list[str] = []
    for line in stdout.splitlines():
        stripped = line.strip()
        if stripped.startswith("/nix/store/"):
            paths.append(stripped)
    return paths


def parse_route_iterations(log_text: str) -> dict[str, Any]:
    rows: list[dict[str, int]] = []
    pattern = re.compile(
        r"iter=(?P<iter>\d+)\s+wires=(?P<wires>\d+)\s+"
        r"overused=(?P<overused>\d+)\s+overuse=(?P<overuse>\d+)"
    )
    for match in pattern.finditer(log_text):
        rows.append(
            {
                "iter": int(match.group("iter")),
                "wires": int(match.group("wires")),
                "overused": int(match.group("overused")),
                "overuse": int(match.group("overuse")),
            }
        )
    return {
        "iterations": rows,
        "last": rows[-1] if rows else None,
        "routed": any(row["overused"] == 0 for row in rows),
    }


def parse_max_frequencies(log_text: str) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    pattern = re.compile(
        r"Max frequency for clock\s+'?(?P<clock>[^':]+)'?:\s+"
        r"(?P<mhz>[0-9.]+)\s+MHz\s+\((?P<status>PASS|FAIL)"
    )
    for match in pattern.finditer(log_text):
        rows.append(
            {
                "clock": match.group("clock").strip(),
                "mhz": float(match.group("mhz")),
                "status": match.group("status"),
            }
        )
    return rows


def summarize_tb_data(out_path: Path) -> dict[str, Any]:
    summary_path = out_path / "summary.json"
    if not summary_path.exists():
        return {}
    summary = read_json(summary_path)
    output_head = summary.get("output_head_top1") or {}
    rtl_contract = summary.get("rtl_contract") or {}
    result: dict[str, Any] = {
        "status": summary.get("status"),
        "artifact_name": summary.get("artifact_name"),
    }
    keys = (
        "vocab_size",
        "physical_vocab_size",
        "hidden_size",
        "tile_out_dim",
        "lanes",
    )
    for key in keys:
        if key in rtl_contract:
            result[key] = rtl_contract[key]
    output_keys = (
        "weight_quantization",
        "weight_dtype",
        "packed_weight_words",
        "fixed_int8_top_index",
        "fixed_int8_top_acc",
        "f32_reference_top_index",
        "int8_top_matches_f32_top",
        "normalized_rmse",
        "vocab_weight_mode",
        "vocab_weight_ternary_threshold",
    )
    for key in output_keys:
        if key in output_head:
            result[key] = output_head[key]
    return result


def summarize_sv_sim(out_path: Path) -> dict[str, Any]:
    if not out_path.is_file():
        return {}
    payload = read_json(out_path)
    return {
        "pass": bool(payload.get("pass") or payload.get("status") == "PASS"),
        "status": payload.get("status"),
        "top_index": payload.get("top_index"),
        "top_acc": payload.get("top_acc"),
        "cycles": payload.get("cycles"),
        "led_pass": payload.get("led_pass"),
        "led_fail": payload.get("led_fail"),
    }


def summarize_gate(name: str, out_paths: list[str], log_text: str) -> dict[str, Any]:
    if not out_paths:
        return {}
    out_path = Path(out_paths[-1])
    if name == "tb-data":
        return summarize_tb_data(out_path)
    if name == "sv-sim":
        return summarize_sv_sim(out_path)
    if name in {"fasm", "bitstream"}:
        return {
            "route": parse_route_iterations(log_text),
            "max_frequencies": parse_max_frequencies(log_text),
        }
    return {}


def run_gate(
    *,
    gate: Gate,
    attr: str,
    run_dir: Path,
    timeout_s: int | None,
    extra_nix_args: list[str],
) -> dict[str, Any]:
    log_path = run_dir / "logs" / f"{gate.name}.log"
    argv = [
        "nix",
        "build",
        f".#{attr}",
        "--no-link",
        "--print-out-paths",
        "-L",
        *extra_nix_args,
    ]
    started_at = datetime.now().astimezone().isoformat()
    proc = subprocess.run(
        argv,
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        check=False,
        timeout=timeout_s,
    )
    finished_at = datetime.now().astimezone().isoformat()
    log_path.parent.mkdir(parents=True, exist_ok=True)
    log_path.write_text("$ " + shlex.join(argv) + "\n" + proc.stdout, encoding="utf-8")
    out_paths = parse_nix_out_paths(proc.stdout)
    return {
        "name": gate.name,
        "attr": attr,
        "argv": argv,
        "status": "PASS" if proc.returncode == 0 else "FAIL",
        "returncode": proc.returncode,
        "started_at": started_at,
        "finished_at": finished_at,
        "log": relpath(log_path),
        "out_paths": out_paths,
        "summary": summarize_gate(gate.name, out_paths, proc.stdout),
    }


def run_board_gate(
    *,
    args: argparse.Namespace,
    run_dir: Path,
    bitstream: str,
) -> dict[str, Any]:
    board_run = ROOT / "scripts" / "task6" / "task6_board_run.py"
    board_label = f"{run_dir.name}-board"
    init_argv = [
        sys.executable,
        str(board_run),
        "init",
        "--label",
        board_label,
        "--experiment",
        args.label,
        "--bitstream",
        bitstream,
        "--notes",
        "created by task6_experiment_runner.py",
    ]
    init_proc = subprocess.run(
        init_argv,
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        check=False,
    )
    board_dir = init_proc.stdout.strip().splitlines()[-1] if init_proc.returncode == 0 else None
    result: dict[str, Any] = {
        "name": "board-program",
        "status": "FAIL" if init_proc.returncode != 0 else "CREATED",
        "init_argv": init_argv,
        "init_returncode": init_proc.returncode,
        "init_output": init_proc.stdout,
        "board_run_dir": board_dir,
    }
    if init_proc.returncode != 0 or board_dir is None:
        return result

    program_argv = [
        sys.executable,
        str(board_run),
        "with-lock",
        "--run-dir",
        board_dir,
        "--log-name",
        "program-openfpgaloader.log",
        "--",
        "openFPGALoader",
        "-c",
        args.jtag_cable,
        "--ftdi-serial",
        args.ftdi_serial,
        bitstream,
    ]
    proc = subprocess.run(
        program_argv,
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        check=False,
    )
    result.update(
        {
            "status": "PASS" if proc.returncode == 0 else "FAIL",
            "program_argv": program_argv,
            "program_returncode": proc.returncode,
            "program_output": proc.stdout,
        }
    )
    return result


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--label", required=True)
    parser.add_argument("--vocab-size", type=int, required=True)
    parser.add_argument("--physical-vocab-size", type=int)
    parser.add_argument("--tile-out-dim", type=int, default=64)
    parser.add_argument(
        "--weight-quantization",
        choices=("int8", "ternary2", "ternary-base3-20"),
        required=True,
    )
    parser.add_argument("--flake-prefix")
    parser.add_argument(
        "--gate",
        action="append",
        choices=tuple(GATES),
        help="Gate to run. May be repeated. Defaults to tb-data, sv-sim, json.",
    )
    parser.add_argument("--timeout-s", type=int)
    parser.add_argument("--nix-arg", action="append", default=[])
    parser.add_argument("--program-board", action="store_true")
    parser.add_argument("--jtag-cable", default="digilent_hs3")
    parser.add_argument("--ftdi-serial", default="210299BF3824")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    prefix = derive_prefix(args)
    gate_names = tuple(args.gate or DEFAULT_GATE_ORDER)
    run_dir = EXPERIMENT_ROOT / f"{iso_timestamp()}-{sanitize_label(args.label)}"
    run_dir.mkdir(parents=True, exist_ok=False)

    payload: dict[str, Any] = {
        "schema": "task6-experiment-result-v1",
        "created_at": datetime.now().astimezone().isoformat(),
        "label": args.label,
        "run_dir": relpath(run_dir),
        "repo": {
            "root": str(ROOT),
            "git_head": None,
            "git_dirty": None,
        },
        "parameters": {
            "vocab_size": args.vocab_size,
            "physical_vocab_size": args.physical_vocab_size or args.vocab_size,
            "tile_out_dim": args.tile_out_dim,
            "weight_quantization": args.weight_quantization,
            "flake_prefix": prefix,
        },
        "gates": [],
        "status": "RUNNING",
    }

    head = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        check=False,
    )
    dirty = subprocess.run(
        ["git", "status", "--short"],
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        check=False,
    )
    if head.returncode == 0:
        payload["repo"]["git_head"] = head.stdout.strip()
    if dirty.returncode == 0:
        payload["repo"]["git_dirty"] = bool(dirty.stdout.strip())

    result_path = run_dir / "result.json"
    write_json(result_path, payload)

    final_status = "PASS"
    bitstream_path: str | None = None
    try:
        for gate_name in gate_names:
            gate = GATES[gate_name]
            attr = f"{prefix}-{gate.attr_suffix}"
            result = run_gate(
                gate=gate,
                attr=attr,
                run_dir=run_dir,
                timeout_s=args.timeout_s,
                extra_nix_args=args.nix_arg,
            )
            payload["gates"].append(result)
            if result["out_paths"] and gate_name == "bitstream":
                bitstream_path = result["out_paths"][-1]
            if result["status"] != "PASS":
                final_status = "FAIL"
                break
            write_json(result_path, {**payload, "status": "RUNNING"})
    except subprocess.TimeoutExpired as exc:
        final_status = "TIMEOUT"
        payload["gates"].append(
            {
                "name": "timeout",
                "status": "TIMEOUT",
                "argv": exc.cmd,
                "timeout_s": exc.timeout,
            }
        )

    if final_status == "PASS" and args.program_board:
        if bitstream_path is None:
            final_status = "FAIL"
            payload["gates"].append(
                {
                    "name": "board-program",
                    "status": "FAIL",
                    "error": "--program-board requires the bitstream gate",
                }
            )
        else:
            board_result = run_board_gate(args=args, run_dir=run_dir, bitstream=bitstream_path)
            payload["gates"].append(board_result)
            if board_result["status"] != "PASS":
                final_status = "FAIL"

    payload["status"] = final_status
    payload["finished_at"] = datetime.now().astimezone().isoformat()
    write_json(result_path, payload)
    print(result_path)
    return 0 if final_status == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
