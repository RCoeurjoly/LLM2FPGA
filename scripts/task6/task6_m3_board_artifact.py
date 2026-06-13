#!/usr/bin/env python3
"""Shape a board full-inference run into a Task 6 M3 audit artifact."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from task6_milestone_evidence_audit import audit_payload


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_MANIFEST_JSON = ROOT / "artifacts" / "task6" / "parallel-hypotheses" / "task6-m3-reference-manifest.json"
DEFAULT_OUT_JSON = ROOT / "artifacts" / "task6" / "runs" / "task6-m3-board-artifact.json"
M3_STAGE = "M3-full-tinystories-1m"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest-json", type=Path, default=DEFAULT_MANIFEST_JSON)
    parser.add_argument("--board-summary-json", type=Path, required=True)
    parser.add_argument("--out-json", type=Path, default=DEFAULT_OUT_JSON)
    parser.add_argument("--json-only", action="store_true")
    return parser.parse_args()


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def lower_join(value: Any) -> str:
    if isinstance(value, dict):
        return " ".join(lower_join(item) for item in value.values())
    if isinstance(value, list):
        return " ".join(lower_join(item) for item in value)
    return str(value).lower()


def status_of(payload: dict[str, Any]) -> str:
    return str(payload.get("status", payload.get("prompt_infer_status", "")))


def first_list(*values: Any) -> list[Any]:
    for value in values:
        if isinstance(value, list) and value:
            return value
    return []


def get_path(payload: dict[str, Any], *keys: str) -> Any:
    value: Any = payload
    for key in keys:
        if not isinstance(value, dict):
            return None
        value = value.get(key)
    return value


def board_generated_tokens(board_summary: dict[str, Any]) -> list[int]:
    tokens = first_list(
        board_summary.get("board_tokens"),
        get_path(board_summary, "board", "generated_tokens"),
        get_path(board_summary, "gate_summary", "board", "generated_tokens"),
        board_summary.get("generated_tokens"),
    )
    if tokens:
        return [int(token) for token in tokens]

    samples = get_path(board_summary, "gate_summary", "samples") or board_summary.get("samples")
    if isinstance(samples, list) and samples:
        sample_tokens: list[int] = []
        for sample in samples:
            if not isinstance(sample, dict):
                continue
            observed = sample.get("observed", {})
            token = (
                sample.get("top1_token")
                or observed.get("top1_token")
                or sample.get("board_token")
                or sample.get("generated_token")
            )
            if token is None:
                return []
            sample_tokens.append(int(token))
        return sample_tokens
    return []


def board_identity(board_summary: dict[str, Any]) -> dict[str, Any]:
    board = board_summary.get("board", {})
    gate = board_summary.get("gate_summary", {})
    gate_board = gate.get("board", {}) if isinstance(gate, dict) else {}
    identity = {
        "bdf": board_summary.get("bdf") or board.get("bdf") or gate.get("bdf") or gate_board.get("bdf"),
        "lspci": board_summary.get("lspci") or board.get("lspci") or gate.get("lspci") or gate_board.get("lspci"),
        "source_artifact": board_summary.get("artifact_name") or gate.get("artifact_name"),
    }
    return {key: value for key, value in identity.items() if value is not None}


def source_contract(board_summary: dict[str, Any]) -> dict[str, Any]:
    contract = board_summary.get("contract")
    if isinstance(contract, dict):
        return contract
    gate_contract = get_path(board_summary, "gate_summary", "contract")
    if isinstance(gate_contract, dict):
        return gate_contract
    return {}


def source_declares_live_m3(board_summary: dict[str, Any]) -> bool:
    contract = source_contract(board_summary)
    text = lower_join(contract)
    return (
        contract.get("stage") == M3_STAGE
        and contract.get("live_compute") is True
        and contract.get("all_blocks") is True
        and "host-assisted" not in text
        and "replay" not in text
        and "fixture" not in text
    )


def build_board_artifact(
    manifest: dict[str, Any],
    board_summary: dict[str, Any],
    manifest_path: Path,
    board_summary_path: Path,
) -> dict[str, Any]:
    reference = manifest.get("reference", {})
    input_payload = manifest.get("input", {})
    model = manifest.get("model", {})
    expected_tokens = [int(token) for token in reference.get("generated_tokens", [])]
    observed_tokens = board_generated_tokens(board_summary)
    identity = board_identity(board_summary)

    board = {
        "status": status_of(board_summary),
        "generated_tokens": observed_tokens,
        "sample_count": len(observed_tokens),
        **identity,
    }
    contract = {
        "stage": M3_STAGE,
        "live_compute": source_declares_live_m3(board_summary),
        "all_blocks": source_declares_live_m3(board_summary),
        "notes": "Board executes all TinyStories-1M transformer blocks for token-exact greedy generation.",
        "responsibilities": {
            "host": ["prompt token/control input", "artifact/reference comparison"],
            "fpga": ["all TinyStories-1M transformer blocks", "greedy token selection"],
        },
    }
    artifact = {
        "artifact_name": "task6-m3-board-artifact",
        "status": "PASS",
        "contract": contract,
        "model": model,
        "input": {
            "prompt": input_payload.get("prompt"),
            "prompt_token_ids": input_payload.get("prompt_token_ids"),
        },
        "reference": {
            "prompt": reference.get("prompt"),
            "generated_tokens": expected_tokens,
            "generated_text": reference.get("generated_text"),
            "manifest_json": str(manifest_path),
        },
        "board": board,
        "source": {
            "board_summary_json": str(board_summary_path),
            "board_summary_artifact": board_summary.get("artifact_name"),
            "board_summary_status": status_of(board_summary),
            "source_contract": source_contract(board_summary),
        },
    }

    failures = audit_payload("M3", artifact)
    if failures:
        artifact["status"] = "FAIL"
        artifact["m3_audit_failures"] = failures
    else:
        artifact["m3_audit_failures"] = []
    artifact["closes_m3"] = artifact["status"] == "PASS"
    return artifact


def main() -> int:
    args = parse_args()
    manifest = read_json(args.manifest_json)
    board_summary = read_json(args.board_summary_json)
    artifact = build_board_artifact(
        manifest,
        board_summary,
        args.manifest_json,
        args.board_summary_json,
    )
    args.out_json.parent.mkdir(parents=True, exist_ok=True)
    args.out_json.write_text(json.dumps(artifact, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    if args.json_only:
        print(json.dumps(artifact, indent=2, sort_keys=True))
    else:
        print(artifact["status"])
        if artifact.get("m3_audit_failures"):
            for failure in artifact["m3_audit_failures"]:
                print(f"- {failure}")
    return 0 if artifact["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
