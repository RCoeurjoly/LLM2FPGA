#!/usr/bin/env python3
"""Emit M2 BRAM-only checkpoint hashes from frozen contracts and score outputs."""

from __future__ import annotations

import argparse
import hashlib
import json
import struct
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CONTRACT = (
    ROOT
    / "artifacts"
    / "task6"
    / "parallel-hypotheses"
    / "h2-tinystories-1m-m2-one-block-contract"
    / "manifest.json"
)
DEFAULT_SCORE_ARTIFACT = (
    ROOT
    / "artifacts"
    / "task6"
    / "parallel-hypotheses"
    / "h2-tinystories-1m-m2-full-block-lowering-score.json"
)
DEFAULT_OUT = ROOT / "artifacts" / "zero-to-one" / "m2-bram-checkpoint-hashes.json"
VALID_QUANTIZATIONS = ("int8", "int4", "ternary2")
DEFAULT_SCORE_ARTIFACT_BY_QUANTIZATION = {
    "int8": DEFAULT_SCORE_ARTIFACT,
    "int4": (
        ROOT
        / "artifacts"
        / "task6"
        / "parallel-hypotheses"
        / "h2-tinystories-1m-m2-full-block-lowering-score-int4.json"
    ),
    "ternary2": (
        ROOT
        / "artifacts"
        / "task6"
        / "parallel-hypotheses"
        / "h2-tinystories-1m-m2-full-block-lowering-score-ternary2.json"
    ),
}
DEFAULT_OUT_BY_QUANTIZATION = {
    "int8": DEFAULT_OUT,
    "int4": ROOT / "artifacts" / "zero-to-one" / "m2-bram-checkpoint-hashes-int4.json",
    "ternary2": ROOT / "artifacts" / "zero-to-one" / "m2-bram-checkpoint-hashes-ternary2.json",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--quantization", choices=VALID_QUANTIZATIONS, default="int8")
    parser.add_argument("--contract-manifest", type=Path, default=None)
    parser.add_argument("--score-artifact", type=Path, default=None)
    parser.add_argument("--reference-json", type=Path, default=None)
    parser.add_argument("--out-json", type=Path, default=None)
    return parser.parse_args()


def resolve_score_artifact(quantization: str, supplied: Path | None) -> Path:
    if supplied is not None:
        if not supplied.is_absolute():
            supplied = ROOT / supplied
        return supplied
    score = DEFAULT_SCORE_ARTIFACT_BY_QUANTIZATION[quantization]
    if not score.exists():
        raise SystemExit(
            f"default score artifact for quantization='{quantization}' is missing: {score}. "
            "Pass --score-artifact explicitly."
        )
    return score


def resolve_out_json(quantization: str, supplied: Path | None) -> Path:
    if supplied is not None:
        if not supplied.is_absolute():
            supplied = ROOT / supplied
        return supplied
    return DEFAULT_OUT_BY_QUANTIZATION[quantization]


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def resolve_reference_path(contract: dict[str, Any], override: Path | None) -> Path:
    if override is not None:
        if not override.is_absolute():
            override = ROOT / override
        return override
    reference = contract.get("reference_json")
    if not isinstance(reference, str):
        raise SystemExit("contract is missing a valid 'reference_json' path")
    reference_path = Path(reference)
    if not reference_path.is_absolute():
        reference_path = ROOT / reference_path
    return reference_path


def hash_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def tensor_path(base: Path, tensor_meta: dict[str, Any]) -> Path:
    return base / tensor_meta["filename"]


def hash_i8(values: list[int]) -> str:
    return hashlib.sha256(bytes((int(value) & 0xFF) for value in values)).hexdigest()


def hash_u32(values: list[int]) -> str:
    payload = bytearray()
    for value in values:
        payload.extend(int(value).to_bytes(4, byteorder="little", signed=False))
    return hashlib.sha256(payload).hexdigest()


def hash_f32(value: float) -> str:
    return hashlib.sha256(struct.pack("<f", float(value))).hexdigest()


def hash_f32_sequence(values: list[float]) -> str:
    payload = bytearray()
    for value in values:
        payload.extend(struct.pack("<f", float(value)))
    return hashlib.sha256(payload).hexdigest()


def collect_layer_block_hashes(
    contract_base: Path,
    step: dict[str, Any],
    step_key: str,
) -> tuple[dict[str, Any], dict[str, Any], list[str]]:
    tensor_meta = step["tensors"]
    layer_names = (
        "ln1_output_f32",
        "q_proj_output_f32",
        "k_proj_output_f32",
        "v_proj_output_f32",
        "attention_output_f32",
        "ln2_output_f32",
        "mlp_output_f32",
    )
    block_names = ("block_output_f32",)

    layer_hashes: dict[str, Any] = {}
    block_hashes: dict[str, Any] = {}
    failures: list[str] = []

    for name in layer_names:
        meta = tensor_meta.get(name)
        if not isinstance(meta, dict):
            failures.append(f"{step_key}:{name} tensor metadata missing or invalid")
            continue
        path = tensor_path(contract_base, meta)
        try:
            observed = hash_file(path)
        except OSError as exc:
            failures.append(f"{step_key}:{name} cannot read tensor file {path}: {exc}")
            continue
        expected = str(meta.get("sha256"))
        entry = {
            "path": str(path),
            "expected_sha256": expected,
            "actual_sha256": observed,
            "bytes": int(meta.get("byte_length", path.stat().st_size)),
            "numel": int(meta.get("numel", path.stat().st_size)),
            "dtype": meta.get("dtype"),
            "shape": meta.get("shape"),
            "matches": observed == expected,
        }
        if not entry["matches"]:
            failures.append(f"{step_key}:{name} hash mismatch")
        layer_hashes[name] = entry

    for name in block_names:
        meta = tensor_meta.get(name)
        if not isinstance(meta, dict):
            failures.append(f"{step_key}:{name} tensor metadata missing or invalid")
            continue
        path = tensor_path(contract_base, meta)
        try:
            observed = hash_file(path)
        except OSError as exc:
            failures.append(f"{step_key}:{name} cannot read tensor file {path}: {exc}")
            continue
        expected = str(meta.get("sha256"))
        entry = {
            "path": str(path),
            "expected_sha256": expected,
            "actual_sha256": observed,
            "bytes": int(meta.get("byte_length", path.stat().st_size)),
            "numel": int(meta.get("numel", path.stat().st_size)),
            "dtype": meta.get("dtype"),
            "shape": meta.get("shape"),
            "matches": observed == expected,
        }
        if not entry["matches"]:
            failures.append(f"{step_key}:{name} hash mismatch")
        block_hashes[name] = entry

    return layer_hashes, block_hashes, failures


def collect_reference_model_hashes(
    reference: dict[str, Any],
) -> dict[str, Any]:
    generation = reference.get("generation", {})
    hidden_scale_max = reference.get("quantization", {}).get("q024_scale_max")
    hidden_scale_min = reference.get("quantization", {}).get("q024_scale_min")
    generated_token_ids = [int(token) for token in generation.get("q024_generated_token_ids", [])]
    hidden_scales: list[float] = []
    step_hashes: list[dict[str, Any]] = []
    all_hidden_bytes = bytearray()
    all_token_ids: list[int] = []
    hidden_steps = reference.get("steps", [])
    for index, step in enumerate(hidden_steps):
        hidden_q = [int(value) for value in step.get("hidden_q", [])]
        hidden_scale = float(step.get("hidden_scale", 0.0))
        hidden_scales.append(hidden_scale)
        all_hidden_bytes.extend(bytes((int(value) & 0xFF) for value in hidden_q))
        if index < len(generated_token_ids):
            all_token_ids.append(generated_token_ids[index])
        step_hashes.append(
            {
                "step": index,
                "step_id": step.get("step", index),
                "hidden_q_len": len(hidden_q),
                "hidden_scale": hidden_scale,
                "hidden_scale_sha256": hash_f32(hidden_scale),
                "hidden_q_sha256": hash_i8(hidden_q),
                "top1_token": int(step.get("q024_topk_token_ids", [None])[0])
                if step.get("q024_topk_token_ids")
                else None,
                "q024_top1_low32": int(step.get("q024_topk_scores_low32", [0])[0])
                if step.get("q024_topk_scores_low32")
                else None,
            }
        )

    context_token_ids = [
        step.get("q024_context_token_ids") or step.get("f32_context_token_ids") or []
        for step in hidden_steps
    ]
    return {
        "generation": {
            "steps": len(hidden_steps),
            "model": reference.get("model", {}),
            "quantization": reference.get("quantization", {}),
            "generated_token_ids": generated_token_ids,
            "generated_token_ids_sha256": hash_u32(generated_token_ids),
            "hidden_scale_min": hidden_scale_min,
            "hidden_scale_max": hidden_scale_max,
            "hidden_scale_set_sha256": hash_f32_sequence(hidden_scales),
            "hidden_scale_set_count": len(hidden_scales),
            "context_token_ids": context_token_ids,
        },
        "hidden_scale_sha256s": [entry["hidden_scale_sha256"] for entry in step_hashes],
        "hidden_q_concat_sha256": hashlib.sha256(all_hidden_bytes).hexdigest(),
        "top1_token_ids": all_token_ids,
        "top1_token_ids_sha256": hash_u32(all_token_ids),
        "steps": step_hashes,
    }


def compare_generation(
    contract_steps: list[dict[str, Any]],
    reference: dict[str, Any],
) -> tuple[bool, list[str]]:
    failures: list[str] = []
    expected_tokens = [int(step.get("expected_next_token", 0)) for step in contract_steps]
    generation = reference.get("generation", {}).get("q024_generated_token_ids", [])
    observed_tokens = [int(token) for token in generation]

    if len(expected_tokens) != len(observed_tokens):
        failures.append(
            f"generation token count mismatch: contract {len(expected_tokens)} vs reference {len(observed_tokens)}"
        )
        return False, failures

    token_mismatches = [
        (index, expected, observed)
        for index, (expected, observed) in enumerate(zip(expected_tokens, observed_tokens))
        if expected != observed
    ]
    if token_mismatches:
        for index, expected, observed in token_mismatches[:4]:
            failures.append(f"token mismatch at step {index}: contract={expected} reference={observed}")
        if len(token_mismatches) > 4:
            failures.append(f"... plus {len(token_mismatches) - 4} more token mismatches")
        return False, failures
    return True, failures


def compare_context_tokens(
    contract_steps: list[dict[str, Any]],
    reference_steps: list[dict[str, Any]],
) -> tuple[bool, list[str]]:
    failures: list[str] = []
    if len(reference_steps) < len(contract_steps):
        failures.append(
            f"contract/reference step count mismatch: contract {len(contract_steps)} vs reference {len(reference_steps)}"
        )
        return False, failures

    for index, contract_step in enumerate(contract_steps):
        reference_step = reference_steps[index]
        contract_context = [int(value) for value in contract_step.get("context_token_ids", [])]
        reference_context = reference_step.get("q024_context_token_ids") or reference_step.get(
            "f32_context_token_ids"
        ) or []
        if len(contract_context) != len(reference_context):
            failures.append(
                f"context token length mismatch at step {index}: contract {len(contract_context)} vs reference {len(reference_context)}"
            )
            continue
        if contract_context != reference_context:
            mismatched = [
                (contract_value, reference_value)
                for contract_value, reference_value in zip(contract_context, reference_context)
                if contract_value != reference_value
            ]
            failures.append(
                f"context token mismatch at step {index}: first diff contract={mismatched[0][0]} reference={mismatched[0][1]}"
            )
    return len(failures) == 0, failures


def collect_score_status(path: Path, expected_contract_manifest: Path) -> tuple[bool, dict[str, Any], list[str]]:
    summary = load_json(path)
    status = str(summary.get("status", "")).upper() == "PASS"
    failures: list[str] = []
    if not status:
        failures.append(f"score artifact status was not PASS: {summary.get('status')}")
    score_contract = str(summary.get("contract_manifest", ""))
    expected_contract = str(expected_contract_manifest.resolve())
    if score_contract:
        try:
            score_contract = str(Path(score_contract).resolve())
        except OSError:
            score_contract = str(Path(score_contract))
    if score_contract and score_contract != expected_contract:
        failures.append(
            f"score contract_manifest mismatch: score={score_contract} expected={expected_contract}"
        )
    return status, summary, failures


def main() -> int:
    args = parse_args()
    quantization = args.quantization
    contract_manifest = args.contract_manifest or DEFAULT_CONTRACT
    if not contract_manifest.is_absolute():
        contract_manifest = ROOT / contract_manifest
    score_artifact = resolve_score_artifact(quantization, args.score_artifact)
    out_json = resolve_out_json(quantization, args.out_json)
    if not contract_manifest.exists():
        raise SystemExit(f"contract manifest does not exist: {contract_manifest}")
    contract = load_json(contract_manifest)
    contract_base = contract_manifest.parent
    score_status, score_payload, score_failures = collect_score_status(
        score_artifact, contract_manifest
    )
    failures: list[str] = []
    failures.extend(score_failures)

    contract_steps = contract.get("steps", [])
    if not isinstance(contract_steps, list) or not contract_steps:
        raise SystemExit(f"contract has no steps: {args.contract_manifest}")

    reference_path = resolve_reference_path(contract, args.reference_json)
    reference = load_json(reference_path)
    reference_steps = reference.get("steps", [])
    if not isinstance(reference_steps, list) or not reference_steps:
        raise SystemExit(f"reference has no steps: {reference_path}")
    if len(reference_steps) != len(contract_steps):
        failures.append(f"contract/reference step count mismatch: {len(contract_steps)} vs {len(reference_steps)}")
        reference_steps = reference_steps[: len(contract_steps)]

    context_ok, context_failures = compare_context_tokens(contract_steps, reference_steps)
    if not context_ok:
        failures.extend(context_failures)

    token_ok, token_failures = compare_generation(contract_steps, reference)
    if not token_ok:
        failures.extend(token_failures)

    per_step: list[dict[str, Any]] = []
    layer_hashes_all: dict[str, Any] = {}
    block_hashes_all: dict[str, Any] = {}
    layer_concat = bytearray()
    block_concat = bytearray()

    for step in contract_steps:
        step_index = int(step.get("step", 0))
        step_key = f"step-{step_index:02d}"
        layer, block, step_failures = collect_layer_block_hashes(contract_base, step, step_key)
        failures.extend(step_failures)
        layer_hashes_all[step_key] = layer
        block_hashes_all[step_key] = block
        for tensor_name, entry in layer.items():
            layer_concat.extend(bytes.fromhex(entry["actual_sha256"]))
        for tensor_name, entry in block.items():
            block_concat.extend(bytes.fromhex(entry["actual_sha256"]))

        per_step.append(
            {
                "step": step_index,
                "sequence_length": int(step.get("sequence_length", 0)),
                "context_token_ids": step.get("context_token_ids", []),
                "expected_next_token": int(step.get("expected_next_token")),
                "layer": layer,
                "block": block,
            }
        )

    reference_hashes = collect_reference_model_hashes(reference)
    aggregate = {
        "layer_actual_sha256": hashlib.sha256(layer_concat).hexdigest() if layer_concat else hashlib.sha256().hexdigest(),
        "block_actual_sha256": hashlib.sha256(block_concat).hexdigest() if block_concat else hashlib.sha256().hexdigest(),
        "model_hidden_q_concat_sha256": reference_hashes["hidden_q_concat_sha256"],
        "model_top1_tokens_concat_sha256": reference_hashes["top1_token_ids_sha256"],
        "score_artifact": {
            "path": str(score_artifact),
            "status": score_payload.get("status"),
            "schema_version": score_payload.get("schema_version"),
            "contract_manifest": score_payload.get("contract_manifest"),
            "weight_manifest": score_payload.get("weight_manifest"),
            "quantization": score_payload.get("quantization", {}),
        },
    }

    artifact_name = "task6-zero-to-one-m2-bram-checkpoint-hashes"
    if quantization != "int8":
        artifact_name = f"task6-zero-to-one-m2-bram-checkpoint-hashes-{quantization}"

    artifact = {
        "schema_version": 1,
        "artifact_name": artifact_name,
        "quantization": quantization,
        "status": "PASS" if not failures else "FAIL",
        "date": datetime.now(timezone.utc).isoformat(),
        "stage": "M2-one-full-block",
        "milestone_target": "M2-one-full-block",
        "live_compute": False,
        "source_artifacts": {
            "contract_manifest": str(contract_manifest),
            "reference_json": str(reference_path),
            "score_artifact": str(score_artifact),
        },
        "policy": {
            "layer_block_model_scope": "contract tensors + generation hidden_q + score quantized checkpoint hashes",
            "checkpoint_hash_denomination": "sha256 of raw tensor bytes at each checkpoint",
            "score_gate": "full block lowering score artifact must be PASS",
        },
        "steps": per_step,
        "aggregate": aggregate,
        "model_level": reference_hashes,
        "matches": {
            "score_pass": bool(score_status),
            "step_tokens_match_reference": bool(token_ok),
            "all_tensor_hashes_match_reference": all(
                entry["matches"] for step in per_step for entry in (*step["layer"].values(), *step["block"].values())
            ),
        },
        "failures": failures,
    }

    out_json.parent.mkdir(parents=True, exist_ok=True)
    out_json.write_text(json.dumps(artifact, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(out_json)
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
