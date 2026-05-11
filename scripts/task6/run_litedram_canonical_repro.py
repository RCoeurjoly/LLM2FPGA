#!/usr/bin/env python3
"""Run LiteDRAM DDR3 evidence scripts for canonical repro and deterministic ladder."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import json
from pathlib import Path
import subprocess
import sys
from typing import Any

from summarize_litedram_bringup_gate import evaluate_gate_pass, summarize_one


ROOT = Path(__file__).resolve().parents[2]
BOARD_RUN = ROOT / "scripts" / "task6" / "task6_board_run.py"
READER = ROOT / "scripts" / "task6" / "read_litedram_probe_jtag_ftdi.py"
SUMMARIZER = ROOT / "scripts" / "task6" / "summarize_litedram_bringup_gate.py"


def run(argv: list[str], *, cwd: Path = ROOT) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        argv,
        cwd=cwd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        check=False,
    )


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def extract_json_from_log(path: Path) -> dict[str, Any]:
    text = path.read_text(encoding="utf-8")
    start = text.find("{")
    end = text.rfind("}")
    if start < 0 or end < start:
        raise SystemExit(f"log does not contain JSON output: {path}")
    return json.loads(text[start : end + 1])


def init_run(args: argparse.Namespace) -> Path:
    proc = run(
        [
            sys.executable,
            str(BOARD_RUN),
            "init",
            "--label",
            args.label,
            "--experiment",
            args.experiment,
            "--bitstream",
            str(args.bitstream),
            "--notes",
            "LiteDRAM DDR3 ladder/canonical evidence run.",
        ]
    )
    if proc.returncode != 0:
        raise SystemExit(proc.stdout)
    return Path(proc.stdout.strip().splitlines()[-1])


def with_lock(run_dir: Path, log_name: str, command: list[str]) -> None:
    proc = run(
        [
            sys.executable,
            str(BOARD_RUN),
            "with-lock",
            "--run-dir",
            str(run_dir),
            "--log-name",
            log_name,
            "--",
            *command,
        ]
    )
    if proc.returncode != 0:
        raise SystemExit(proc.stdout)


def read_command(
    args: argparse.Namespace,
    *,
    bits: int | None = None,
    poll_count: int | None = None,
    poll_interval: float | None = None,
) -> list[str]:
    return [
        sys.executable,
        str(READER),
        "--serial",
        args.serial,
        "--backend",
        "mpsse",
        "--freq-hz",
        str(args.freq_hz),
        "--tdo-bit",
        str(args.tdo_bit),
        "--bits",
        str(bits if bits is not None else args.bits),
        "--ir-len",
        str(args.ir_len),
        "--user-ir",
        args.user_ir,
        "--poll",
        "--poll-count",
        str(poll_count if poll_count is not None else args.poll_count),
        "--poll-interval",
        str(poll_interval if poll_interval is not None else args.poll_interval),
        "--json-only",
    ]


def program_command(args: argparse.Namespace, bitstream: Path) -> list[str]:
    return [
        "openFPGALoader",
        "-c",
        args.jtag_cable,
        "--ftdi-serial",
        args.serial,
        str(bitstream),
    ]


@dataclass(frozen=True)
class LadderStep:
    name: str
    target_gate: str
    index: int
    bitstream: Path
    read_count: int
    program_each_read: bool
    bits: int


def write_run_metadata(
    run_dir: Path,
    args: argparse.Namespace,
    *,
    mode: str,
    note: str,
    steps: list[LadderStep] | None = None,
) -> None:
    if steps:
        step_bits = {step.target_gate: step.bits for step in steps}
    else:
        step_bits = {}
    manifest = {
        "schema": "task6-litedram-ddr3-run-manifest-v1",
        "name": args.label,
        "mode": mode,
        "bitstream": str(args.bitstream),
        "programmer": program_command(args, args.bitstream),
        "reader": {
            "backend": "mpsse",
            "freq_hz": args.freq_hz,
            "tdo_bit": args.tdo_bit,
            "ir_len": args.ir_len,
            "user_ir": args.user_ir,
            "bits": args.bits,
            "poll_count": args.poll_count,
            "poll_interval": args.poll_interval,
        },
        "expected": {
            "magic_ok": True,
            "expected_version": args.expected_version,
            "expected_state": args.expected_state,
            "expected_bits": args.expected_bits or args.bits,
            "step_bits": step_bits,
            "note": note,
        },
    }
    write_json(run_dir / "references" / "canonical-repro-manifest.json", manifest)


def parse_expected_state(value: str) -> str:
    value = value.strip()
    if not value:
        raise argparse.ArgumentTypeError("expected_state must not be empty")
    return value


def build_ladder_steps(args: argparse.Namespace) -> list[LadderStep]:
    for gate_index in range(1, 6):
        key = f"g{gate_index}_bitstream"
        if getattr(args, key) is None:
            raise SystemExit(
                f"run-ladder mode requires explicit --g{gate_index}-bitstream arguments for all gates."
            )
    return [
        LadderStep(
            name="G1-init-only",
            target_gate="G1",
            index=1,
            bitstream=args.g1_bitstream,
            read_count=args.g1_read_count,
            program_each_read=True,
            bits=args.g1_bits,
        ),
        LadderStep(
            name="G2-dfii-one-beat",
            target_gate="G2",
            index=2,
            bitstream=args.g2_bitstream,
            read_count=args.g2_read_count,
            program_each_read=False,
            bits=args.g2_bits,
        ),
        LadderStep(
            name="G3-dfii-addrwalk",
            target_gate="G3",
            index=3,
            bitstream=args.g3_bitstream,
            read_count=args.g3_read_count,
            program_each_read=False,
            bits=args.g3_bits,
        ),
        LadderStep(
            name="G4-native-read",
            target_gate="G4",
            index=4,
            bitstream=args.g4_bitstream,
            read_count=args.g4_read_count,
            program_each_read=False,
            bits=args.g4_bits,
        ),
        LadderStep(
            name="G5-native-write-read",
            target_gate="G5",
            index=5,
            bitstream=args.g5_bitstream,
            read_count=args.g5_read_count,
            program_each_read=False,
            bits=args.g5_bits,
        ),
    ]


def read_once(
    args: argparse.Namespace,
    run_dir: Path,
    step: LadderStep,
    attempt: int,
    read_prefix: str,
) -> dict[str, Any]:
    if step.program_each_read:
        with_lock(
            run_dir,
            f"{read_prefix}-program-{attempt:02d}.log",
            program_command(args, step.bitstream),
        )

    log_name = f"{read_prefix}-read-{attempt:02d}.log"
    with_lock(
        run_dir,
        log_name,
        read_command(
            args,
            bits=step.bits,
            poll_count=args.poll_count,
            poll_interval=args.poll_interval,
        ),
    )
    payload = extract_json_from_log(run_dir / "logs" / log_name)
    readback = run_dir / "readback" / f"{read_prefix}-read-{attempt:02d}.json"
    write_json(readback, payload)
    summary = summarize_one(
        readback,
        expected_version=args.expected_version,
        expected_state=args.expected_state,
        expected_bits=args.expected_bits if args.expected_bits is not None else step.bits,
        max_gate=step.target_gate,
    )
    _, _, gate_pass = evaluate_gate_pass(
        payload,
        expected_version=args.expected_version,
        expected_state=args.expected_state,
        expected_bits=args.expected_bits if args.expected_bits is not None else step.bits,
        max_gate=step.target_gate,
    )
    summary["step_target_gate"] = step.target_gate
    summary["step_target_gate_pass"] = bool(gate_pass.get(step.target_gate, False))
    return {"path": str(readback), "summary": summary}


def run_ladder_step(
    args: argparse.Namespace,
    run_dir: Path,
    step: LadderStep,
) -> dict[str, Any]:
    read_prefix = f"step-{step.index}-{step.name.lower().replace('_', '-')}"
    if not step.program_each_read:
        with_lock(
            run_dir,
            f"{read_prefix}-program-setup.log",
            program_command(args, step.bitstream),
        )
    summaries: list[dict[str, Any]] = []
    readback_paths: list[str] = []
    read_targets_met = 0
    highest_gate = "G0"
    last_reason: str | None = None

    for attempt in range(1, step.read_count + 1):
        payload_result = read_once(args, run_dir, step, attempt, read_prefix)
        readback_paths.append(payload_result["path"])
        summary = payload_result["summary"]
        summaries.append(summary)
        if summary["highest_gate_with_evidence"]:
            highest_gate = summary["highest_gate_with_evidence"]
        if summary["stop_reason"]:
            last_reason = summary["stop_reason"]
            break
        if summary["step_target_gate_pass"]:
            read_targets_met += 1
        else:
            break

    return {
        "name": step.name,
        "target_gate": step.target_gate,
        "index": step.index,
        "bitstream": str(step.bitstream),
        "bits": step.bits,
        "program_each_read": step.program_each_read,
        "read_count_requested": step.read_count,
        "read_count_observed": len(summaries),
        "read_target_gate_pass_count": read_targets_met,
        "readback_paths": readback_paths,
        "readbacks": summaries,
        "target_gate_reached": read_targets_met == len(summaries) and len(summaries) > 0,
        "highest_gate_with_evidence": highest_gate,
        "stop_reason": last_reason,
    }


def run_canonical_repro(args: argparse.Namespace, run_dir: Path) -> list[Path]:
    with_lock(run_dir, "program-1.log", program_command(args, args.bitstream))
    readbacks: list[Path] = []
    for index in range(1, 3):
        log_name = f"read-{index}.log"
        with_lock(
            run_dir,
            log_name,
            read_command(
                args,
                bits=args.bits,
                poll_count=args.poll_count,
                poll_interval=args.poll_interval,
            ),
        )
        readback = extract_json_from_log(run_dir / "logs" / log_name)
        out = run_dir / "readback" / f"read-{index}.json"
        write_json(out, readback)
        readbacks.append(out)

    with_lock(run_dir, "program-2.log", program_command(args, args.bitstream))
    for index in range(3, 5):
        log_name = f"read-{index}.log"
        with_lock(
            run_dir,
            log_name,
            read_command(
                args,
                bits=args.bits,
                poll_count=args.poll_count,
                poll_interval=args.poll_interval,
            ),
        )
        readback = extract_json_from_log(run_dir / "logs" / log_name)
        out = run_dir / "readback" / f"read-{index}.json"
        write_json(out, readback)
        readbacks.append(out)
    return readbacks


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bitstream", required=True, type=Path)
    parser.add_argument("--run-ladder", action="store_true", help="Run deterministic G1..G5 ladder.")
    parser.add_argument("--label", default="ddr3-v117-native-classifier-canonical")
    parser.add_argument(
        "--experiment",
        default="task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-cmdaddr-trace-init-bandwidth-probe",
    )
    parser.add_argument("--serial", default="210299BF3824")
    parser.add_argument("--jtag-cable", default="digilent_hs3")
    parser.add_argument("--freq-hz", type=int, default=6_000_000)
    parser.add_argument("--tdo-bit", type=int, default=7)
    parser.add_argument("--bits", type=int, default=11264)
    parser.add_argument("--ir-len", type=int, default=6)
    parser.add_argument("--user-ir", default="0x02")
    parser.add_argument("--poll-count", type=int, default=10)
    parser.add_argument("--poll-interval", type=float, default=0.2)
    parser.add_argument(
        "--expected-version",
        type=int,
        help="Optional expected payload version for G0 checks (reject otherwise).",
    )
    parser.add_argument(
        "--expected-state",
        type=parse_expected_state,
        default="PROBE_DONE",
        help="Expected top-level state for G0 checks (default: PROBE_DONE).",
    )
    parser.add_argument(
        "--expected-bits",
        type=int,
        help="Optional expected payload bit width for G0 checks.",
    )
    parser.add_argument(
        "--continue-on-gate-fail",
        action="store_true",
        help="Continue ladder even after a gate failure.",
    )
    parser.add_argument(
        "--g1-bitstream",
        type=Path,
        help="Required for --run-ladder: G1 init-only bitstream.",
    )
    parser.add_argument(
        "--g2-bitstream",
        type=Path,
        help="Required for --run-ladder: G2 DFII one-beat bitstream.",
    )
    parser.add_argument(
        "--g3-bitstream",
        type=Path,
        help="Required for --run-ladder: G3 DFII addrwalk bitstream.",
    )
    parser.add_argument(
        "--g4-bitstream",
        type=Path,
        help="Required for --run-ladder: G4 native read-only bitstream.",
    )
    parser.add_argument(
        "--g5-bitstream",
        type=Path,
        help="Required for --run-ladder: G5 native write/read bitstream.",
    )
    parser.add_argument("--g1-bits", type=int, default=11264)
    parser.add_argument("--g2-bits", type=int, default=11264)
    parser.add_argument("--g3-bits", type=int, default=11264)
    parser.add_argument("--g4-bits", type=int, default=11264)
    parser.add_argument("--g5-bits", type=int, default=11264)
    parser.add_argument("--g1-read-count", type=int, default=20)
    parser.add_argument("--g2-read-count", type=int, default=1)
    parser.add_argument("--g3-read-count", type=int, default=1)
    parser.add_argument("--g4-read-count", type=int, default=1)
    parser.add_argument("--g5-read-count", type=int, default=1)
    args = parser.parse_args()

    if not args.run_ladder:
        run_dir = init_run(args)
        write_run_metadata(
            run_dir,
            args,
            mode="canonical",
            note="v117-native-classifier canonical repro.",
        )
        readbacks = run_canonical_repro(args, run_dir)
        proc = run(
            [
                sys.executable,
                str(SUMMARIZER),
                *[str(path) for path in readbacks],
                *(["--expected-version", str(args.expected_version)] if args.expected_version is not None else []),
                *(["--expected-state", args.expected_state] if args.expected_state is not None else []),
                *(["--expected-bits", str(args.expected_bits or args.bits)]),
                "--output",
                str(run_dir / "verdict-ddr3-bringup.json"),
            ]
        )
        if proc.returncode != 0:
            raise SystemExit(proc.stdout)
        print(run_dir)
        return

    ladder_steps = build_ladder_steps(args)
    run_dir = init_run(args)
    write_run_metadata(
        run_dir,
        args,
        mode="ladder",
        note="LiteDRAM deterministic ladder for G1..G5.",
        steps=ladder_steps,
    )
    step_results = []
    all_readbacks: list[Path] = []
    all_passed = True

    for step in ladder_steps:
        result = run_ladder_step(args, run_dir, step)
        step_results.append(result)
        all_readbacks.extend(Path(path) for path in result["readback_paths"])
        step_ok = bool(result["target_gate_reached"])
        if not step_ok:
            all_passed = False
            if not args.continue_on_gate_fail:
                break

    unique_step_bits = sorted({step.bits for step in ladder_steps})
    summary_expected_bits = args.expected_bits
    if summary_expected_bits is None and len(unique_step_bits) == 1:
        summary_expected_bits = unique_step_bits[0]
    if unique_step_bits and len(unique_step_bits) > 1 and args.expected_bits is not None:
        raise SystemExit(
            "Cannot set --expected-bits with mixed per-step bit widths. "
            "Use --expected-bits and matching --g*-bits values, or run with a single bit width."
        )

    proc = run(
        [
            sys.executable,
            str(SUMMARIZER),
            *[str(path) for path in all_readbacks],
            *(["--expected-version", str(args.expected_version)] if args.expected_version is not None else []),
            *(["--expected-state", args.expected_state] if args.expected_state is not None else []),
            *(["--expected-bits", str(summary_expected_bits)] if summary_expected_bits is not None else []),
            "--output",
            str(run_dir / "verdict-ddr3-bringup.json"),
        ]
    )
    if proc.returncode != 0:
        raise SystemExit(proc.stdout)
    verdict_path = run_dir / "verdict-ddr3-bringup.json"
    verdict = json.loads(verdict_path.read_text(encoding="utf-8"))
    verdict["ladder_steps"] = step_results
    verdict["ladder_all_pass"] = all_passed
    write_json(run_dir / "verdict-ddr3-ladder.json", verdict)

    if not all_passed:
        raise SystemExit(f"ladder failed in {run_dir} (see verdict-ddr3-ladder.json)")

    print(run_dir)


if __name__ == "__main__":
    main()
