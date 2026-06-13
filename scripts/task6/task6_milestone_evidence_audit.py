#!/usr/bin/env python3
"""Audit Task 6 milestone evidence without touching board hardware."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


M1_STAGE = "M1-transformer-boundary-mlp"
M2_STAGE = "M2-one-full-block"
M3_STAGE = "M3-full-tinystories-1m"


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def contract_stage(payload: dict[str, Any]) -> str:
    contract = payload.get("contract", {})
    return str(contract.get("stage", ""))


def contract_notes(payload: dict[str, Any]) -> str:
    contract = payload.get("contract", {})
    return str(contract.get("notes", ""))


def lower_join(value: Any) -> str:
    if isinstance(value, dict):
        return " ".join(lower_join(item) for item in value.values())
    if isinstance(value, list):
        return " ".join(lower_join(item) for item in value)
    return str(value).lower()


def artifact_status(payload: dict[str, Any]) -> str:
    return str(payload.get("status", payload.get("prompt_infer_status", "")))


def audit_m1(payload: dict[str, Any]) -> list[str]:
    failures: list[str] = []
    if artifact_status(payload) != "PASS":
        failures.append("M1 artifact status is not PASS")
    if contract_stage(payload) != M1_STAGE:
        failures.append(f"M1 artifact contract stage is not {M1_STAGE}")
    notes = contract_notes(payload).lower()
    if "selftest" in notes:
        failures.append("M1 artifact is selftest evidence, not prompt-derived boundary evidence")
    reference_contract = payload.get("reference_contract", {})
    if reference_contract.get("compatible") is not True:
        failures.append("M1 artifact lacks compatible full-checkpoint reference contract evidence")
    reason = str(reference_contract.get("reason", "")).lower()
    if "full tinystories-1m" not in reason and "prompt-derived" not in reason:
        failures.append("M1 artifact does not tie inputs to prompt-derived TinyStories-1M reference data")
    validation = payload.get("validation", {})
    if validation.get("mismatch_count") not in (0, "0"):
        failures.append("M1 artifact reports nonzero or missing mismatch_count")
    registers = payload.get("registers", {})
    observed = payload.get("observed", {})
    samples = payload.get("samples", [])
    first_sample = samples[0] if samples else {}
    sample_observed = first_sample.get("observed", {}) if isinstance(first_sample, dict) else {}
    output_hex = (
        observed.get("output_hex")
        or sample_observed.get("output_hex")
        or registers.get("mlp_accel_output_vector_hex")
    )
    if output_hex is None:
        failures.append("M1 artifact lacks full output-vector evidence")
    if not samples:
        failures.append("M1 artifact lacks sample-level boundary evidence")
    for index, sample in enumerate(samples):
        if not isinstance(sample, dict):
            failures.append(f"M1 sample {index} is not an object")
            continue
        if sample.get("status") != "PASS":
            failures.append(f"M1 sample {index} status is not PASS")
        checks = sample.get("checks", {})
        for check_name in (
            "activation_echo",
            "residual_echo",
            "start_count_incremented",
            "done_bit",
            "output_valid",
            "state_done",
            "checksum",
            "sample0",
            "sample1",
            "output_vector",
        ):
            if checks.get(check_name) is not True:
                failures.append(f"M1 sample {index} missing passing {check_name} check")
        expected = sample.get("expected", {})
        observed_sample = sample.get("observed", {})
        if expected.get("output_hex") != observed_sample.get("output_hex"):
            failures.append(f"M1 sample {index} observed output does not match expected output")
        sample_input = sample.get("input", {})
        if sample_input.get("activation_hex") != observed_sample.get("activation_echo_hex"):
            failures.append(f"M1 sample {index} activation echo does not match input")
        if sample_input.get("residual_hex") != observed_sample.get("residual_echo_hex"):
            failures.append(f"M1 sample {index} residual echo does not match input")
    return failures


def audit_m2(payload: dict[str, Any]) -> list[str]:
    failures: list[str] = []
    if artifact_status(payload) != "PASS":
        failures.append("M2 artifact status is not PASS")
    if contract_stage(payload) != M2_STAGE:
        failures.append(f"M2 artifact contract stage is not {M2_STAGE}")
    contract = payload.get("contract", {})
    if contract.get("live_compute") is not True:
        failures.append("M2 artifact contract does not declare live_compute=true")
    contract_text = lower_join(contract)
    if "complete tinystories block" not in contract_text and "one complete tinystories transformer block" not in contract_text:
        failures.append("M2 artifact contract does not describe complete TinyStories block execution")
    if "replay" in contract_text or "fixture" in contract_text or "host-assisted" in contract_text:
        failures.append("M2 artifact is replay/fixture evidence, not live one-full-block compute")
    if "first-token" in contract_text or "sublane" in contract_text:
        failures.append("M2 artifact is first-token/sublane evidence, not a complete live block")
    input_payload = payload.get("input", payload.get("host_input", {}))
    token_ids = input_payload.get("token_ids") or input_payload.get("prompt_token_ids")
    control = input_payload.get("control", {})
    block_index = input_payload.get("block_index", control.get("block_index"))
    if not isinstance(token_ids, list) or not token_ids:
        failures.append("M2 artifact lacks host-supplied token/control token IDs")
    if block_index not in (0, "0"):
        failures.append("M2 artifact does not identify live block_index=0 control input")
    observed = payload.get("observed", {})
    expected = payload.get("expected", {})
    board = payload.get("board", {})
    lspci = str(payload.get("lspci", board.get("lspci", ""))).lower()
    bdf = payload.get("bdf", board.get("bdf"))
    board_status = str(board.get("status", payload.get("board_status", "")))
    if board_status and board_status != "PASS":
        failures.append("M2 board status is not PASS")
    if not bdf and "10ee:0480" not in lspci and "ypcb" not in lower_join(board):
        failures.append("M2 artifact lacks YPCB board/PCIe acceptance evidence")
    if str(observed.get("compute_path", "")).lower() not in ("live", "live_block", "live-full-block"):
        failures.append("M2 artifact observed compute_path is not live")
    observed_text = lower_join(observed)
    if "first-token" in observed_text or "sublane" in observed_text:
        failures.append("M2 observed path is first-token/sublane evidence, not complete block execution")
    if not observed.get("first_64_output_hex"):
        failures.append("M2 artifact lacks observed first-64-byte output evidence")
    if not expected.get("first_64_output_hex"):
        failures.append("M2 artifact lacks expected first-64-byte output evidence")
    if (
        observed.get("first_64_output_hex")
        and expected.get("first_64_output_hex")
        and observed.get("first_64_output_hex") != expected.get("first_64_output_hex")
    ):
        failures.append("M2 observed first-64-byte output does not match expected output")
    return failures


def audit_m3(payload: dict[str, Any]) -> list[str]:
    failures: list[str] = []
    if artifact_status(payload) != "PASS":
        failures.append("M3 artifact status is not PASS")
    if contract_stage(payload) != M3_STAGE:
        failures.append(f"M3 artifact contract stage is not {M3_STAGE}")
    contract = payload.get("contract", {})
    if contract.get("live_compute") is not True:
        failures.append("M3 artifact contract does not declare live_compute=true")
    if contract.get("all_blocks") is not True:
        failures.append("M3 artifact contract does not declare all_blocks=true")
    contract_text = lower_join(contract)
    if "host-assisted" in contract_text or "replay" in contract_text or "fixture" in contract_text:
        failures.append("M3 artifact is host-assisted/replay/fixture evidence, not full board inference")
    reference = payload.get("reference", {})
    board = payload.get("board", {})
    model_text = lower_join(payload.get("model", {})) + " " + lower_join(reference)
    if "tinystories" not in model_text or "1m" not in model_text:
        failures.append("M3 artifact lacks TinyStories-1M model identity")
    input_payload = payload.get("input", payload.get("host_input", {}))
    prompt = input_payload.get("prompt") or reference.get("prompt")
    prompt_tokens = input_payload.get("prompt_token_ids") or input_payload.get("token_ids")
    if not prompt:
        failures.append("M3 artifact lacks prompt evidence")
    if not isinstance(prompt_tokens, list) or not prompt_tokens:
        failures.append("M3 artifact lacks host-supplied prompt token IDs")
    reference_tokens = reference.get("generated_tokens")
    board_tokens = payload.get("board_tokens") or board.get("generated_tokens")
    if not isinstance(reference_tokens, list) or not reference_tokens:
        failures.append("M3 artifact lacks reference greedy token IDs")
    if not isinstance(board_tokens, list) or not board_tokens:
        failures.append("M3 artifact lacks board-generated token IDs")
    if isinstance(reference_tokens, list) and isinstance(board_tokens, list) and reference_tokens != board_tokens:
        failures.append("M3 board token IDs do not match reference greedy token IDs")
    board_status = str(board.get("status", payload.get("board_status", "")))
    if board_status and board_status != "PASS":
        failures.append("M3 board status is not PASS")
    sample_count = board.get("sample_count", payload.get("sample_count"))
    if isinstance(board_tokens, list) and sample_count is not None and sample_count != len(board_tokens):
        failures.append("M3 board sample_count does not match board token count")
    return failures


def audit_payload(milestone: str, payload: dict[str, Any]) -> list[str]:
    if milestone == "M1":
        return audit_m1(payload)
    if milestone == "M2":
        return audit_m2(payload)
    if milestone == "M3":
        return audit_m3(payload)
    raise ValueError(f"unknown milestone: {milestone}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("milestone", choices=("M1", "M2", "M3"))
    parser.add_argument("artifact", type=Path)
    parser.add_argument("--json-out", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    payload = read_json(args.artifact)
    failures = audit_payload(args.milestone, payload)
    result = {
        "artifact_name": "task6-milestone-evidence-audit",
        "milestone": args.milestone,
        "artifact": str(args.artifact),
        "status": "PASS" if not failures else "FAIL",
        "failures": failures,
    }
    if args.json_out is not None:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
