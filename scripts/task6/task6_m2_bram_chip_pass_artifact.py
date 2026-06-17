#!/usr/bin/env python3
"""Assemble a M2 BRAM chip-pass artifact from board + checkpoint hashes."""

from __future__ import annotations

import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_BOARD_SUMMARY = ROOT / "artifacts" / "task6" / "runs" / "m2-full-block-board-summary.json"
DEFAULT_CHECKPOINT_HASH_INT8 = ROOT / "artifacts" / "zero-to-one" / "m2-bram-checkpoint-hashes.json"
DEFAULT_CHECKPOINT_HASH_INT4 = ROOT / "artifacts" / "zero-to-one" / "m2-bram-checkpoint-hashes-int4.json"
DEFAULT_CHECKPOINT_HASH_TERNARY2 = ROOT / "artifacts" / "zero-to-one" / "m2-bram-checkpoint-hashes-ternary2.json"
DEFAULT_OUT_INT8 = ROOT / "artifacts" / "zero-to-one" / "m2-bram-chip-pass.json"
DEFAULT_OUT_INT4 = ROOT / "artifacts" / "zero-to-one" / "m2-bram-chip-pass-int4.json"
DEFAULT_OUT_TERNARY2 = ROOT / "artifacts" / "zero-to-one" / "m2-bram-chip-pass-ternary2.json"
VALID_QUANTIZATIONS = ("int8", "int4", "ternary2")
REQUIRED_BOARD_CHECKS = (
    "checksum",
    "sample0",
    "sample1",
    "first_64_output",
    "output_count",
    "state_done",
    "no_error",
    "output_valid",
    "output_count_live",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--quantization",
        choices=VALID_QUANTIZATIONS,
        default="int8",
        help="Quantization family to validate.",
    )
    parser.add_argument("--board-summary-json", type=Path, default=None)
    parser.add_argument("--checkpoint-hash-json", type=Path, default=None)
    parser.add_argument("--out-json", type=Path, default=None)
    parser.add_argument(
        "--require-checkpoint-pass",
        action="store_true",
        default=True,
        help="Require checkpoint hash artifact status to be PASS (default).",
    )
    parser.add_argument(
        "--allow-checkpoint-warning",
        action="store_true",
        help="Do not fail the chip artifact if checkpoint status is non-PASS.",
    )
    return parser.parse_args()


def resolve_path(path: Path | None, default: Path) -> Path:
    if path is None:
        return default
    if path.is_absolute():
        return path
    return ROOT / path


def resolve_default_paths(quantization: str) -> tuple[Path, Path]:
    checkpoint_map = {
        "int8": DEFAULT_CHECKPOINT_HASH_INT8,
        "int4": DEFAULT_CHECKPOINT_HASH_INT4,
        "ternary2": DEFAULT_CHECKPOINT_HASH_TERNARY2,
    }
    out_map = {
        "int8": DEFAULT_OUT_INT8,
        "int4": DEFAULT_OUT_INT4,
        "ternary2": DEFAULT_OUT_TERNARY2,
    }
    return checkpoint_map[quantization], out_map[quantization]


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def parse_u32(text: Any) -> int:
    if isinstance(text, int):
        return int(text)
    if isinstance(text, str):
        return int(text, 0)
    raise ValueError(f"cannot parse integer field from {type(text)!r}: {text!r}")


def parse_output_hex(value: Any, field_name: str, failures: list[str]) -> bytes | None:
    if not isinstance(value, str):
        failures.append(f"{field_name} is not a hex string")
        return None
    text = value.strip().lower().removeprefix("0x")
    if len(text) % 2 == 1:
        failures.append(f"{field_name} has odd-length hex string")
        return None
    try:
        data = bytes.fromhex(text)
    except ValueError as exc:
        failures.append(f"{field_name} is not valid hex: {exc}")
        return None
    return data


def collect_checkpoint_mismatches(checkpoint: dict[str, Any]) -> list[str]:
    mismatches: list[str] = []
    for step in checkpoint.get("steps", []):
        if not isinstance(step, dict):
            continue
        step_id = step.get("step", "unknown")
        for section in ("layer", "block"):
            section_payload = step.get(section)
            if not isinstance(section_payload, dict):
                continue
            for name, entry in section_payload.items():
                if isinstance(entry, dict) and not entry.get("matches", True):
                    mismatches.append(f"step {step_id} {section}.{name}")
    return mismatches


def main() -> int:
    args = parse_args()
    default_checkpoint, default_out = resolve_default_paths(args.quantization)
    board_summary_path = resolve_path(args.board_summary_json, DEFAULT_BOARD_SUMMARY)
    checkpoint_path = resolve_path(args.checkpoint_hash_json, default_checkpoint)
    out_json = resolve_path(args.out_json, default_out)

    if not board_summary_path.exists():
        raise SystemExit(f"board summary JSON does not exist: {board_summary_path}")
    if not checkpoint_path.exists():
        raise SystemExit(f"checkpoint hash JSON does not exist: {checkpoint_path}")

    board_summary = read_json(board_summary_path)
    checkpoint = read_json(checkpoint_path)

    failures: list[str] = []
    checks: dict[str, Any] = {}
    matches: dict[str, bool] = {}

    board_status = str(board_summary.get("status", "")).upper()
    checks["board_summary_status"] = board_status == "PASS"
    if board_status != "PASS":
        failures.append(f"board summary status is {board_status}")

    board_checks = board_summary.get("checks")
    if not isinstance(board_checks, dict):
        failures.append("board summary missing checks object")
        board_checks = {}

    board_check_statuses: dict[str, bool] = {}
    for key in REQUIRED_BOARD_CHECKS:
        value = board_checks.get(key)
        board_check_statuses[key] = bool(value)
        if not isinstance(value, bool):
            failures.append(f"board check missing or invalid: {key}")
        elif not value:
            failures.append(f"board check failed: {key}")
    checks["board_required_checks"] = board_check_statuses

    expected_block = board_summary.get("expected", {}) if isinstance(board_summary.get("expected"), dict) else {}
    observed_block = board_summary.get("observed", {}) if isinstance(board_summary.get("observed"), dict) else {}
    if not expected_block:
        failures.append("board summary missing expected payload")
    if not observed_block:
        failures.append("board summary missing observed payload")

    scalar_checks: dict[str, Any] = {}
    for key in ("checksum", "sample0", "sample1", "output_count"):
        expected_value = expected_block.get(key)
        observed_value = observed_block.get(key)
        try:
            if key == "output_count":
                parsed_expected = int(expected_value)
                parsed_observed = int(observed_value)
            else:
                parsed_expected = parse_u32(expected_value)
                parsed_observed = parse_u32(observed_value)
            ok = parsed_expected == parsed_observed
        except Exception as exc:
            failures.append(f"board {key} comparison failed to parse: {exc}")
            parsed_expected = None
            parsed_observed = None
            ok = False
        scalar_checks[key] = {
            "expected": f"0x{parsed_expected:08x}" if isinstance(parsed_expected, int) else str(expected_value),
            "observed": f"0x{parsed_observed:08x}" if isinstance(parsed_observed, int) else str(observed_value),
            "match": ok,
        }
        checks[f"board_matches_{key}"] = ok
        if not ok:
            failures.append(f"board output mismatch in {key}")

    expected_output = parse_output_hex(expected_block.get("first_64_output_hex"), "expected first_64_output_hex", failures)
    observed_output = parse_output_hex(observed_block.get("first_64_output_hex"), "observed first_64_output_hex", failures)

    output_vector_checks = {
        "expected_first_64_output_len": None,
        "observed_first_64_output_len": None,
        "expected_first_64_output_sha256": None,
        "observed_first_64_output_sha256": None,
        "match": False,
    }
    if expected_output is not None and observed_output is not None:
        output_vector_checks["expected_first_64_output_len"] = len(expected_output)
        output_vector_checks["observed_first_64_output_len"] = len(observed_output)
        output_vector_checks["expected_first_64_output_sha256"] = sha256_bytes(expected_output)
        output_vector_checks["observed_first_64_output_sha256"] = sha256_bytes(observed_output)
        output_match = expected_output == observed_output
        output_vector_checks["match"] = output_match
        checks["board_matches_first_64_output_bytes"] = output_match
        if not output_match:
            failures.append("board first_64_output bytes mismatch")
    else:
        checks["board_matches_first_64_output_bytes"] = False

    board_input = board_summary.get("input", {})
    board_token_ids = board_input.get("token_ids") if isinstance(board_input, dict) else None

    checkpoint_steps = checkpoint.get("steps", [])
    checkpoint_step0 = checkpoint_steps[0] if isinstance(checkpoint_steps, list) and checkpoint_steps else {}
    checkpoint_context_tokens = checkpoint_step0.get("context_token_ids")
    if isinstance(board_token_ids, list) and isinstance(checkpoint_context_tokens, list):
        context_match = [int(v) for v in board_token_ids] == [int(v) for v in checkpoint_context_tokens]
        checks["input_token_ids_match_checkpoint_step0_context"] = context_match
        if not context_match:
            failures.append("board input.token_ids do not match checkpoint step-0 context_token_ids")
    elif board_token_ids is not None:
        failures.append("board input.token_ids unavailable for comparison with checkpoint step-0 context")

    checkpoint_quant = checkpoint.get("quantization")
    if checkpoint_quant is not None and checkpoint_quant != args.quantization:
        failures.append(
            f"checkpoint quantization mismatch: checkpoint={checkpoint_quant} requested={args.quantization}"
        )

    checkpoint_status = str(checkpoint.get("status", "")).upper()
    checkpoint_pass = checkpoint_status == "PASS"
    checks["checkpoint_hash_pass"] = checkpoint_pass
    if not checkpoint_pass:
        if args.require_checkpoint_pass and not args.allow_checkpoint_warning:
            failures.append(f"checkpoint hash artifact status is {checkpoint_status}")

    checkpoint_step_mismatches = collect_checkpoint_mismatches(checkpoint)
    checks["checkpoint_step_tensor_mismatches"] = checkpoint_step_mismatches
    checks["checkpoint_summary_match_flags"] = checkpoint.get("matches") if isinstance(checkpoint.get("matches"), dict) else {}
    if checkpoint_step_mismatches:
        failures.append(f"checkpoint tensor mismatch count: {len(checkpoint_step_mismatches)}")

    artifact_name = "task6-zero-to-one-m2-bram-chip-pass"
    if args.quantization != "int8":
        artifact_name = f"task6-zero-to-one-m2-bram-chip-pass-{args.quantization}"

    matches = {
        "board_summary_pass": bool(checks["board_summary_status"]),
        "board_required_check_pass": all(
            board_check_statuses.get(key) for key in REQUIRED_BOARD_CHECKS if key in board_check_statuses
        ),
        "board_output_scalar_match": all(
            scalar_checks[key]["match"] for key in ("checksum", "sample0", "sample1", "output_count")
        ),
        "board_output_bytes_match": bool(output_vector_checks["match"]),
        "checkpoint_status_pass": checkpoint_pass,
        "checkpoint_tensor_match": not bool(checkpoint_step_mismatches),
    }

    if args.allow_checkpoint_warning and not args.require_checkpoint_pass:
        matches["checkpoint_status_pass"] = checkpoint_pass

    status = "PASS" if all(matches.values()) else "FAIL"

    source_artifacts = {
        "board_summary_json": str(board_summary_path),
        "checkpoint_hash_json": str(checkpoint_path),
    }
    source_artifacts.update(
        {
            "checkpoint_source_artifacts": checkpoint.get("source_artifacts", {}),
        }
    )

    artifact = {
        "schema_version": 1,
        "artifact_name": artifact_name,
        "stage": "M2-one-full-block",
        "milestone_target": "M2-one-full-block",
        "live_compute": False,
        "quantization": args.quantization,
        "status": status,
        "date": datetime.now(timezone.utc).isoformat(),
        "source_artifacts": source_artifacts,
        "board": {
            "status": board_status,
            "artifact_name": board_summary.get("artifact_name"),
            "bdf": board_summary.get("bdf"),
            "contract": board_summary.get("contract", {}),
            "checks": board_check_statuses,
            "expected": {
                "checksum": expected_block.get("checksum"),
                "sample0": expected_block.get("sample0"),
                "sample1": expected_block.get("sample1"),
                "output_count": expected_block.get("output_count"),
                "token_ids": board_input.get("token_ids") if isinstance(board_input, dict) else None,
                "first_64_output_hex": expected_block.get("first_64_output_hex"),
                "first_64_output_sha256": output_vector_checks["expected_first_64_output_sha256"],
            },
            "observed": {
                "checksum": observed_block.get("checksum"),
                "sample0": observed_block.get("sample0"),
                "sample1": observed_block.get("sample1"),
                "output_count": observed_block.get("output_count"),
                "first_64_output_hex": observed_block.get("first_64_output_hex"),
                "first_64_output_sha256": output_vector_checks["observed_first_64_output_sha256"],
            },
            "vector_hashes": output_vector_checks,
        },
        "checkpoint_hashes": {
            "status": checkpoint_status,
            "source_artifacts": checkpoint.get("source_artifacts", {}),
            "aggregate": checkpoint.get("aggregate", {}),
            "matches": checkpoint.get("matches", {}),
            "model_level": checkpoint.get("model_level", {}),
            "policy": checkpoint.get("policy", {}),
            "mismatches": checkpoint_step_mismatches[:16],
            "mismatch_count": len(checkpoint_step_mismatches),
        },
        "checks": checks,
        "matches": matches,
        "failures": failures,
        "scalar_checks": scalar_checks,
    }

    out_json.parent.mkdir(parents=True, exist_ok=True)
    out_json.write_text(json.dumps(artifact, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"status": status, "artifact": str(out_json)}, sort_keys=True))
    return 0 if status == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
