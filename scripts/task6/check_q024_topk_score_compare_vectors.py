#!/usr/bin/env python3
"""Validate the Q0.24 top-k score comparator cutout vectors."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import subprocess
from pathlib import Path
from typing import Any


SCORE_MIN = -(1 << 45)
INITIAL_TOKEN = 0xFFFF


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--vectors", type=Path, required=True)
    parser.add_argument("--expected-state", type=Path, required=True)
    parser.add_argument("--sim-bin", type=Path)
    parser.add_argument("--out", type=Path, required=True)
    return parser.parse_args()


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def parse_hex(value: str) -> int:
    return int(value, 16)


def candidate_score(candidate: dict[str, Any]) -> tuple[int, int, int]:
    sidecar = parse_hex(candidate["sidecar_word_hex"])
    scale = sidecar & 0x00FFFFFF
    reserved = (sidecar >> 24) & 0xFF
    score = int(candidate["accumulator"]) * scale
    return scale, reserved, score


def update_top(
    top_token: int,
    top_score: int,
    candidate: dict[str, Any],
) -> tuple[int, int, bool, bool, int]:
    scale, reserved, score = candidate_score(candidate)
    if reserved != 0:
        return top_token, top_score, True, False, score
    token = int(candidate["token"])
    wins = score > top_score or (score == top_score and token < top_token)
    if wins:
        return token, score, False, True, score
    return top_token, top_score, False, False, score


def check_vector_payload(vectors_payload: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    for vector in vectors_payload["vectors"]:
        top_token = INITIAL_TOKEN
        top_score = SCORE_MIN
        saw_reserved_error = False
        for candidate in vector["candidates"]:
            scale, reserved, score = candidate_score(candidate)
            expected_scale = candidate.get("scale_q0_24")
            if expected_scale is None:
                expected_scale = candidate.get("scale_q0_24_low24")
            if expected_scale is not None and scale != int(expected_scale):
                errors.append(
                    f"{vector['name']}: scale mismatch for token "
                    f"{candidate['token']}: got {scale}, expected {expected_scale}"
                )
            if reserved != int(candidate.get("reserved_upper_byte", 0)):
                errors.append(
                    f"{vector['name']}: reserved mismatch for token "
                    f"{candidate['token']}: got {reserved}"
                )
            if candidate.get("valid", True):
                expected_score = candidate.get("score_q0_24")
                if expected_score is not None and score != int(expected_score):
                    errors.append(
                        f"{vector['name']}: score mismatch for token "
                        f"{candidate['token']}: got {score}, expected {expected_score}"
                    )
            else:
                expected_score = candidate.get("score_q0_24_if_accepted")
                if expected_score is not None and score != int(expected_score):
                    errors.append(
                        f"{vector['name']}: rejected-score mismatch for token "
                        f"{candidate['token']}: got {score}, expected {expected_score}"
                    )

            top_token, top_score, error, _, _ = update_top(
                top_token, top_score, candidate
            )
            saw_reserved_error |= error

        expected_top = vector.get("expected_top_token")
        if expected_top is not None and top_token != int(expected_top):
            errors.append(
                f"{vector['name']}: final top token got {top_token}, "
                f"expected {expected_top}"
            )
        expected_decoder_valid = vector.get("expected_decoder_valid")
        if expected_decoder_valid is not None:
            if bool(expected_decoder_valid) == saw_reserved_error:
                errors.append(
                    f"{vector['name']}: decoder valid/error mismatch; "
                    f"reserved_error={saw_reserved_error}"
                )
    return errors


def check_expected_state(expected_payload: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    for sequence in expected_payload["expected_sequences"]:
        top_token = INITIAL_TOKEN
        top_score = SCORE_MIN
        for index, step in enumerate(sequence["steps"]):
            candidate = {
                "token": step["candidate_token"],
                "accumulator": step["candidate_accumulator"],
                "sidecar_word_hex": step["sidecar_word_hex"],
            }
            top_token, top_score, error, update, score = update_top(
                top_token, top_score, candidate
            )
            expected_error = bool(step["expected_error_reserved_bits"])
            if error != expected_error:
                errors.append(
                    f"{sequence['name']} step {index}: error got {error}, "
                    f"expected {expected_error}"
                )
            if top_token != int(step["expected_top_token_id"]):
                errors.append(
                    f"{sequence['name']} step {index}: top token got "
                    f"{top_token}, expected {step['expected_top_token_id']}"
                )
            if top_score != int(step["expected_top_score_signed_q024"]):
                errors.append(
                    f"{sequence['name']} step {index}: top score got "
                    f"{top_score}, expected {step['expected_top_score_signed_q024']}"
                )
            if update != bool(step["expected_update"]):
                errors.append(
                    f"{sequence['name']} step {index}: update got {update}, "
                    f"expected {step['expected_update']}"
                )
            if step.get("candidate_valid", True):
                expected_score = int(step["candidate_score_signed_q024"])
                if score != expected_score:
                    errors.append(
                        f"{sequence['name']} step {index}: candidate score got "
                        f"{score}, expected {expected_score}"
                    )
        if top_token != int(sequence["expected_final_top_token"]):
            errors.append(
                f"{sequence['name']}: final top token got {top_token}, "
                f"expected {sequence['expected_final_top_token']}"
            )
    return errors


def run_sim(sim_bin: Path | None) -> dict[str, Any] | None:
    if sim_bin is None:
        return None
    completed = subprocess.run(
        [str(sim_bin)],
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    return {
        "command": str(sim_bin),
        "exit_code": completed.returncode,
        "stdout": completed.stdout,
        "pass_line_seen": "PASS task6_q024_topk_score_compare_tb"
        in completed.stdout,
    }


def main() -> None:
    args = parse_args()
    vectors_payload = load_json(args.vectors)
    expected_payload = load_json(args.expected_state)

    vector_errors = check_vector_payload(vectors_payload)
    expected_errors = check_expected_state(expected_payload)
    sim_result = run_sim(args.sim_bin)

    sim_pass = (
        sim_result is None
        or (sim_result["exit_code"] == 0 and sim_result["pass_line_seen"])
    )
    all_errors = vector_errors + expected_errors
    status = "PASS" if not all_errors and sim_pass else "FAIL"

    payload = {
        "artifact_name": "h2-q024-topk-comparator-cutout-result",
        "status": status,
        "date": dt.date.today().isoformat(),
        "hypothesis": (
            "The Q0.24 rowwise sidecar score comparator can be validated as a "
            "tiny deterministic cutout before full-vocab replay or DDR3 work."
        ),
        "source_artifacts": {
            "vectors": str(args.vectors),
            "expected_state": str(args.expected_state),
        },
        "validation": {
            "python_run": True,
            "simulation_run": sim_result is not None,
            "synthesis_run": False,
            "hardware_run": False,
            "vector_error_count": len(vector_errors),
            "expected_state_error_count": len(expected_errors),
            "sim_pass": sim_pass,
        },
        "simulator": sim_result,
        "checks": {
            "vector_errors": vector_errors,
            "expected_state_errors": expected_errors,
            "sequence_count": len(expected_payload["expected_sequences"]),
            "candidate_step_count": sum(
                len(sequence["steps"])
                for sequence in expected_payload["expected_sequences"]
            ),
        },
        "decision": {
            "verdict": (
                "promote-simulator-pass"
                if status == "PASS"
                else "do-not-promote"
            ),
            "rationale": (
                "The cutout accepts scaled-score ordering, signed comparison, "
                "arrival-order-independent lower-token tie break, reserved "
                "sidecar rejection, and the conservative 46-bit bound vector."
                if status == "PASS"
                else "At least one vector, expected-state, or simulator check failed."
            ),
            "next_gate": (
                "Use this as the no-board arithmetic gate for full-vocab "
                "rowwise top-k, then run an 8-sample replay against f32 top1/top5 "
                "before DDR3 integration."
                if status == "PASS"
                else "Fix the Q0.24 cutout before model replay or DDR3 integration."
            ),
        },
    }

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    if status != "PASS":
        raise SystemExit(1)


if __name__ == "__main__":
    main()
