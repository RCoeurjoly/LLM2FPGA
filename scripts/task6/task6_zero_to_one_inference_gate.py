#!/usr/bin/env python3
"""Run auditable zero-to-one parity checks against frozen reference vectors."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any

from task6_zero_to_one_guard import run_locked_tests, verify_inventory, verify_lock_payload


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_TOP1_GATE = ROOT / "scripts" / "task6" / "task6_pcie_rowstream_top1_gate.py"
DEFAULT_OUT_ROOT = ROOT / "artifacts" / "zero-to-one" / "runs"
DEFAULT_BDF = "0000:42:00.0"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lock-json", type=Path, required=True)
    parser.add_argument("--out-json", type=Path, help="Write parity artifact here")
    parser.add_argument("--run-root", type=Path, default=DEFAULT_OUT_ROOT)
    parser.add_argument("--top1-gate", type=Path, default=DEFAULT_TOP1_GATE)
    parser.add_argument("--python", default=os.environ.get("PYTHON", "python3"))
    parser.add_argument("--bdf", default=DEFAULT_BDF, help="PCI BDF")
    parser.add_argument(
        "--image",
        type=Path,
        default=None,
        help="Override rowstream image",
    )
    parser.add_argument(
        "--contract-json",
        type=Path,
        default=None,
        help="Override top1 contract JSON",
    )
    parser.add_argument(
        "--replay-json",
        type=Path,
        default=None,
        help="Override top1 replay JSON",
    )
    parser.add_argument("--top1-timeout", type=float, default=20.0)
    parser.add_argument("--top1-retries", type=int, default=8)
    parser.add_argument("--boot-timeout", type=float, default=5.0)
    parser.add_argument("--poll-timeout", type=float, default=2.0)
    parser.add_argument("--packet-ack-mode", default="auto", choices=("auto", "require", "off"))
    parser.add_argument("--packet-settle", type=float, default=0.001)
    parser.add_argument("--verify-samples", type=int, default=8)
    parser.add_argument("--load-image", action=argparse.BooleanOptionalAction, default=True)
    parser.add_argument("--guard", action="store_true", help="Run lock guard before parity.")
    parser.add_argument("--guard-only", action="store_true", help="Only run guard and write artifact.")
    parser.add_argument("--run-tests", action="store_true", help="Run lock unit tests in guard step")
    parser.add_argument("--skip-inventory", action="store_true", help="Skip inventory regeneration in guard.")
    parser.add_argument(
        "--simulate",
        action="store_true",
        help="Write synthetic parity summaries for audit-only runs without invoking the PCIe gate.",
    )
    return parser.parse_args()


@dataclass(frozen=True)
class VectorRun:
    path: Path
    out_json: Path
    status: str
    mismatch_count: int
    sample_count: int
    failures: list[str]
    summary: dict[str, Any]


class ParityError(RuntimeError):
    pass


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def sha256_hex(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def format_status_path(path: Path) -> str:
    if path.is_relative_to(ROOT):
        return str(path.relative_to(ROOT))
    return str(path)


def resolve_path(base: Path, value: str | Path) -> Path:
    path = Path(value)
    if path.is_absolute():
        return path
    return (base / path).resolve()


def validate_reference_vector(path: Path) -> None:
    payload = read_json(path)
    steps = payload.get("steps")
    if not isinstance(steps, list) or not steps:
        raise ParityError(f"test vector has no steps: {path}")
    generation = payload.get("generation", {})
    tokens = generation.get("q024_generated_token_ids") or []
    if not isinstance(tokens, list):
        raise ParityError(f"test vector generation tokens invalid: {path}")
    if len(steps) != len(tokens):
        raise ParityError(
            f"test vector mismatch between steps and generated tokens: {path}"
            f" ({len(steps)} steps vs {len(tokens)} tokens)"
        )


def run_gate_command(
    gate_path: Path,
    lock_root: Path,
    test_vector_path: Path,
    out_json: Path,
    args: argparse.Namespace,
    python: str,
) -> subprocess.CompletedProcess[str]:
    command = [
        python,
        str(gate_path),
        args.bdf,
        "--reference-json",
        str(test_vector_path),
        "--top1-timeout",
        str(args.top1_timeout),
        "--top1-retries",
        str(args.top1_retries),
        "--boot-timeout",
        str(args.boot_timeout),
        "--poll-timeout",
        str(args.poll_timeout),
        "--packet-ack-mode",
        args.packet_ack_mode,
        "--packet-settle",
        str(args.packet_settle),
        "--verify-samples",
        str(args.verify_samples),
        "--json-out",
        str(out_json),
    ]
    if args.image is not None:
        command.extend(["--image", str(args.image)])
    if args.contract_json is not None:
        command.extend(["--contract-json", str(args.contract_json)])
    if args.replay_json is not None:
        command.extend(["--replay-json", str(args.replay_json)])
    if args.load_image:
        command.append("--load-image")
    else:
        command.append("--no-load-image")

    env = os.environ.copy()
    env.setdefault("TASK6_REPO_ROOT", str(ROOT))
    env["TASK6_REPO_ROOT"] = str(lock_root)

    env.setdefault("PYTHONPATH", str(ROOT / "scripts" / "task6"))
    return subprocess.run(
        command,
        cwd=str(ROOT),
        text=True,
        capture_output=True,
        env=env,
        check=False,
    )


def run_simulated_gate_command(
    vector_path: Path,
    out_json: Path,
    args: argparse.Namespace,
) -> dict[str, Any]:
    payload = read_json(vector_path)
    generation = payload["generation"]["q024_generated_token_ids"]
    sample_count = len(generation)
    if args.verify_samples > 0:
        sample_count = min(sample_count, args.verify_samples)
    samples = [
        {
            "sample_id": index,
            "reference_step": index,
            "top1_token": generation[index],
            "expected_reference_top1_token": generation[index],
            "top1_score_low32": 0,
            "top1_rows_scanned": 0,
            "matches_token": True,
            "matches_score_low32": True,
            "matches_rows_scanned": True,
            "no_top1_error": True,
        }
        for index in range(sample_count)
    ]
    summary = {
        "status": "PASS",
        "simulated": True,
        "validation": {
            "mode": "offline-simulation",
            "mismatch_count": 0,
            "verify_samples": sample_count,
            "verify_samples_requested": args.verify_samples,
        },
        "samples": samples,
    }
    out_json.parent.mkdir(parents=True, exist_ok=True)
    out_json.write_text(json.dumps(summary, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    return summary


def summarize_gate_summary(
    test_summary: dict[str, Any],
) -> tuple[str, int, int, list[str], list[dict[str, Any]]]:
    status = str(test_summary.get("status", "FAIL")).upper()
    validation = test_summary.get("validation", {})
    mismatch_count = int(validation.get("mismatch_count", 0)) if isinstance(validation, dict) else 0
    samples = test_summary.get("samples", [])
    if not isinstance(samples, list):
        samples = []
    sample_count = len(samples)
    failures: list[str] = []
    sample_failures: list[dict[str, Any]] = []
    if status != "PASS":
        mismatches = int(mismatch_count)
        failures.append(f"gate status={status}, mismatch_count={mismatches}")

    for index, sample in enumerate(samples):
        if not isinstance(sample, dict):
            continue
        mismatch_fields = [
            "matches_token",
            "matches_score_low32",
            "matches_rows_scanned",
            "no_top1_error",
        ]
        sample_fail = [name for name in mismatch_fields if sample.get(name) is not True]
        if sample_fail:
            sample_failures.append(
                {
                    "sample_id": sample.get("sample_id", index),
                    "reference_step": sample.get("reference_step"),
                    "failures": sample_fail,
                    "top1_token": sample.get("top1_token"),
                    "expected_reference_top1_token": sample.get("expected_reference_top1_token"),
                }
            )
    if sample_failures:
        failures.append(f"sample mismatches: {len(sample_failures)}")

    return status, mismatch_count, sample_count, failures, sample_failures


def run_single_vector(
    lock_root: Path,
    gate_path: Path,
    vector_entry: dict[str, Any],
    run_dir: Path,
    python: str,
    args: argparse.Namespace,
) -> VectorRun:
    expected_hash = vector_entry.get("sha256")
    vector_path = resolve_path(lock_root, vector_entry.get("path", ""))
    if not vector_path.exists():
        raise ParityError(f"test vector missing: {vector_path}")
    actual_hash = sha256_hex(vector_path)
    if expected_hash and actual_hash != expected_hash:
        raise ParityError(
            f"test vector hash mismatch: {format_status_path(vector_path)} "
            f"expected={expected_hash} actual={actual_hash}"
        )

    validate_reference_vector(vector_path)

    vector_run_out = run_dir / f"{vector_path.stem}.json"
    if args.simulate:
        summary = run_simulated_gate_command(
            vector_path=vector_path,
            out_json=vector_run_out,
            args=args,
        )
    else:
        completed = run_gate_command(
            gate_path=gate_path,
            lock_root=lock_root,
            test_vector_path=vector_path,
            out_json=vector_run_out,
            args=args,
            python=python,
        )
        if completed.returncode != 0:
            return VectorRun(
                path=vector_path,
                out_json=vector_run_out,
                status="FAIL",
                mismatch_count=0,
                sample_count=0,
                failures=[
                    "top1 gate invocation failed",
                    completed.stderr.strip() or completed.stdout.strip() or "no command output",
                ],
                summary={
                    "returncode": completed.returncode,
                    "stdout": completed.stdout,
                    "stderr": completed.stderr,
                },
            )

        try:
            summary = read_json(vector_run_out)
        except (OSError, json.JSONDecodeError) as exc:
            return VectorRun(
                path=vector_path,
                out_json=vector_run_out,
                status="FAIL",
                mismatch_count=0,
                sample_count=0,
                failures=[
                    "top1 gate output parse failed",
                    str(exc),
                ],
                summary={
                    "returncode": completed.returncode,
                    "stdout": completed.stdout,
                    "stderr": completed.stderr,
                },
            )

    status, mismatch_count, sample_count, failures, sample_failures = summarize_gate_summary(summary)
    if sample_failures:
        summary["zero_to_one_sample_failures"] = sample_failures
    return VectorRun(
        path=vector_path,
        out_json=vector_run_out,
        status=status,
        mismatch_count=mismatch_count,
        sample_count=sample_count,
        failures=failures,
        summary=summary,
    )


def run_guard(lock_payload: dict[str, Any], args: argparse.Namespace) -> list[str]:
    failures: list[str] = []
    verify_lock_payload(lock_payload, failures)
    if args.run_tests:
        run_locked_tests(lock_payload, failures, args.python)
    if args.guard or args.guard_only:
        if not args.skip_inventory:
            verify_inventory(lock_payload, failures, args.python)
    return failures


def build_lock_payload_summary(lock_payload: dict[str, Any], guard_failures: list[str]) -> dict[str, Any]:
    repo = lock_payload.get("repo", {})
    return {
        "artifact_name": lock_payload.get("artifact_name"),
        "lock_status": lock_payload.get("status"),
        "lock_tag": lock_payload.get("lock_tag"),
        "repo": repo,
        "repo_commit": repo.get("commit"),
        "references": lock_payload.get("references"),
        "rules": lock_payload.get("rules", []),
        "guard_failures": guard_failures,
        "timestamp": datetime.now().astimezone().isoformat(),
    }


def emit_results(
    lock_payload: dict[str, Any],
    guard_failures: list[str],
    outcomes: list[dict[str, Any]],
    overall_failures: list[str],
    out_json: Path,
    args: argparse.Namespace,
    run_root: Path,
) -> int:
    pass_count = sum(1 for outcome in outcomes if outcome["status"] == "PASS")
    fail_count = len(outcomes) - pass_count
    status = "PASS" if fail_count == 0 and not overall_failures and not guard_failures else "FAIL"

    payload = build_lock_payload_summary(lock_payload, guard_failures)
    payload.update(
        {
            "artifact_name": "task6-zero-to-one-inference-gate",
            "status": status,
            "run_root": format_status_path(run_root),
            "outcomes": outcomes,
            "simulated": args.simulate,
            "totals": {
                "vectors": len(outcomes),
                "passes": pass_count,
                "fails": fail_count,
            },
            "overall_failures": overall_failures,
            "command": {
                "top1_gate": str(args.top1_gate),
                "python": args.python,
                "bdf": args.bdf,
                "load_image": args.load_image,
                "top1_timeout": args.top1_timeout,
                "top1_retries": args.top1_retries,
                "guard": args.guard,
                "guard_only": args.guard_only,
                "simulate": args.simulate,
            },
        }
    )
    if args.simulate:
        payload["warnings"] = [
            "simulate mode was used; outputs are audit-only and do not prove hardware parity.",
        ]
    out_json.parent.mkdir(parents=True, exist_ok=True)
    out_json.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0 if status == "PASS" else 1


def main() -> int:
    args = parse_args()
    args.top1_gate = args.top1_gate.resolve()
    if args.guard_only:
        args.guard = True

    lock_payload = read_json(args.lock_json)
    lock_root = Path(lock_payload.get("repo", {}).get("root", args.lock_json.parent)).resolve()

    guard_failures = run_guard(lock_payload, args)
    if args.guard_only:
        run_root = args.run_root
        run_root.mkdir(parents=True, exist_ok=True)
        out_json = args.out_json or (run_root / "zero-to-one-inference-gate.json")
        return emit_results(lock_payload, guard_failures, [], guard_failures, out_json, args, run_root)

    if guard_failures:
        run_root = args.run_root
        run_root.mkdir(parents=True, exist_ok=True)
        out_json = args.out_json or (run_root / "zero-to-one-inference-gate.json")
        return emit_results(lock_payload, guard_failures, [], guard_failures, out_json, args, run_root)

    test_vectors = lock_payload.get("test_vectors", [])
    if not isinstance(test_vectors, list) or not test_vectors:
        raise ParityError("lock has no test vectors")

    if not args.simulate and not args.top1_gate.exists():
        raise ParityError(f"top1 gate missing: {args.top1_gate}")

    run_root = args.run_root / datetime.now().astimezone().strftime("%Y%m%dT%H%M%S%z")
    run_root.mkdir(parents=True, exist_ok=True)
    out_json = args.out_json or (run_root / "zero-to-one-inference-gate.json")

    outcomes: list[dict[str, Any]] = []
    overall_failures: list[str] = []
    for index, vector_entry in enumerate(test_vectors):
        if not isinstance(vector_entry, dict):
            overall_failures.append(f"test vector entry #{index} invalid type: {vector_entry!r}")
            continue
        if "path" not in vector_entry:
            overall_failures.append(f"test vector entry #{index} missing path")
            continue

        run_dir = run_root / f"vector-{index:02d}"
        run_dir.mkdir(parents=True, exist_ok=True)
        try:
            vector_run = run_single_vector(
                lock_root=lock_root,
                gate_path=args.top1_gate,
                vector_entry=vector_entry,
                run_dir=run_dir,
                python=args.python,
                args=args,
            )
        except ParityError as exc:
            overall_failures.append(f"vector {index:02d}: {exc}")
            vector_run = VectorRun(
                path=run_dir / "missing-reference.json",
                out_json=run_dir / f"vector-{index:02d}.json",
                status="FAIL",
                mismatch_count=0,
                sample_count=0,
                failures=[str(exc)],
                summary={},
            )

        outcome = {
            "path": format_status_path(vector_run.path),
            "status": vector_run.status,
            "mismatch_count": vector_run.mismatch_count,
            "sample_count": vector_run.sample_count,
            "summary_json": format_status_path(vector_run.out_json),
            "failures": vector_run.failures,
        }
        outcomes.append(outcome)

        if vector_run.status == "PASS":
            continue
        if vector_run.failures:
            overall_failures.extend(
                f"vector {index:02d}: {failure}" for failure in vector_run.failures
            )

    return emit_results(lock_payload, guard_failures, outcomes, overall_failures, out_json, args, run_root)


if __name__ == "__main__":
    raise SystemExit(main())
