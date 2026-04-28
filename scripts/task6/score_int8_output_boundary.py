#!/usr/bin/env python3
"""Score the scale/bias/output boundary around the H2 int8 L2 c_fc proof."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import struct
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--contract-manifest", required=True, type=Path)
    parser.add_argument("--weight-pack-manifest", required=True, type=Path)
    parser.add_argument("--contract-replay-json", required=True, type=Path)
    parser.add_argument("--out-json", required=True, type=Path)
    parser.add_argument("--normalized-rmse-threshold", type=float, default=0.02)
    return parser.parse_args()


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def tensor_by_name(manifest: dict[str, Any], name: str) -> dict[str, Any]:
    for tensor in manifest["tensors"]:
        if tensor["name"] == name:
            return tensor
    raise SystemExit(f"{manifest.get('module_name', '<unknown>')} has no {name} tensor")


def product(values: list[int]) -> int:
    out = 1
    for value in values:
        out *= int(value)
    return out


def load_f32(path: Path, numel: int) -> list[float]:
    raw = path.read_bytes()
    expected_bytes = numel * 4
    if len(raw) != expected_bytes:
        raise SystemExit(f"{path}: expected {expected_bytes} bytes, got {len(raw)}")
    return list(struct.unpack(f"<{numel}f", raw))


def pack_f32(values: list[float]) -> bytes:
    return struct.pack(f"<{len(values)}f", *[float(value) for value in values])


def pack_i32(values: list[int]) -> bytes:
    return b"".join(struct.pack("<i", int(value)) for value in values)


def quantize_symmetric(values: list[float], bits: int) -> tuple[list[int], float]:
    qmax = (1 << (bits - 1)) - 1
    max_abs = max((abs(value) for value in values), default=0.0)
    if max_abs == 0.0:
        return [0 for _ in values], 1.0
    scale = max_abs / qmax
    qmin = -qmax
    return [
        max(qmin, min(qmax, int(round(value / scale))))
        for value in values
    ], scale


def quantize_per_output_symmetric(
    values: list[float],
    bits: int,
    in_features: int,
    out_features: int,
) -> tuple[list[int], list[float]]:
    quantized: list[int] = []
    scales: list[float] = []
    for out_index in range(out_features):
        row = values[out_index * in_features : (out_index + 1) * in_features]
        row_quantized, row_scale = quantize_symmetric(row, bits)
        quantized.extend(row_quantized)
        scales.append(row_scale)
    return quantized, scales


def compute_accumulators(
    activation_q: list[int],
    weight_q: list[int],
    in_features: int,
    out_features: int,
) -> list[int]:
    accs: list[int] = []
    for out_index in range(out_features):
        weight_offset = out_index * in_features
        acc = 0
        for in_index in range(in_features):
            acc += activation_q[in_index] * weight_q[weight_offset + in_index]
        accs.append(acc)
    return accs


def score_error(actual: list[float], expected: list[float]) -> dict[str, float]:
    errors = [a - e for a, e in zip(actual, expected)]
    abs_errors = [abs(value) for value in errors]
    mse = sum(value * value for value in errors) / len(errors)
    signal_mse = sum(value * value for value in expected) / len(expected)
    rmse = math.sqrt(mse)
    signal_rms = math.sqrt(signal_mse)
    signal_abs = [abs(value) for value in expected]
    return {
        "max_abs_error": max(abs_errors),
        "mean_abs_error": sum(abs_errors) / len(abs_errors),
        "rmse": rmse,
        "normalized_rmse": 0.0 if signal_rms == 0.0 else rmse / signal_rms,
        "signal_max_abs": max(signal_abs),
        "signal_mean_abs": sum(signal_abs) / len(signal_abs),
    }


def main() -> None:
    args = parse_args()
    contract = load_json(args.contract_manifest)
    weight_pack = load_json(args.weight_pack_manifest)
    replay = load_json(args.contract_replay_json)

    contract_dir = args.contract_manifest.parent
    weight_dir = args.weight_pack_manifest.parent
    activation_meta = tensor_by_name(contract, "activation_in")
    expected_meta = tensor_by_name(contract, "activation_out")
    weight_meta = tensor_by_name(weight_pack, "weight")
    bias_meta = tensor_by_name(weight_pack, "bias")

    activation = load_f32(
        contract_dir / activation_meta["filename"],
        product(activation_meta["shape"]),
    )
    expected = load_f32(
        contract_dir / expected_meta["filename"],
        product(expected_meta["shape"]),
    )
    weight = load_f32(
        weight_dir / weight_meta["filename"],
        product(weight_meta["shape"]),
    )
    bias = load_f32(
        weight_dir / bias_meta["filename"],
        product(bias_meta["shape"]),
    )

    out_features, in_features = [int(value) for value in weight_meta["shape"]]
    activation_q, activation_scale = quantize_symmetric(activation, 8)
    weight_q, weight_scales = quantize_per_output_symmetric(
        weight,
        8,
        in_features,
        out_features,
    )
    accs = compute_accumulators(activation_q, weight_q, in_features, out_features)
    effective_scales = [activation_scale * weight_scale for weight_scale in weight_scales]
    dequantized = [
        bias[out_index] + accs[out_index] * effective_scales[out_index]
        for out_index in range(out_features)
    ]
    metrics = score_error(dequantized, expected)
    scale_blob = pack_f32(effective_scales)
    bias_blob = pack_f32(bias)
    dequantized_blob = pack_f32(dequantized)
    acc_blob = pack_i32(accs)

    activation_bytes = len(activation_q)
    weight_value_bytes = len(weight_q)
    packed_weight_words = replay["rtl_contract"]["packed_weight_words"]
    packed_weight_bytes = packed_weight_words * 4
    accumulator_bytes = len(accs) * 4
    scale_bytes = len(effective_scales) * 4
    bias_bytes = len(bias) * 4
    f32_output_bytes = len(dequantized) * 4

    payload = {
        "artifact_name": "h2-int8-l2-c-fc-scale-bias-output-boundary",
        "status": (
            "PASS"
            if metrics["normalized_rmse"] <= args.normalized_rmse_threshold
            and replay.get("status") == "PASS"
            else "FAIL"
        ),
        "source_artifacts": {
            "contract_manifest": str(args.contract_manifest),
            "weight_pack_manifest": str(args.weight_pack_manifest),
            "contract_replay_json": str(args.contract_replay_json),
        },
        "module": {
            "model_label": contract["model_label"],
            "module_name": contract["module_name"],
            "in_features": in_features,
            "out_features": out_features,
            "macs": in_features * out_features,
        },
        "boundary_contract": {
            "rtl_output": "int32 accumulators in local output memory",
            "postprocess_formula": "f32_out[i] = int32_acc[i] * effective_scale[i] + bias[i]",
            "effective_scale": "activation_scale * per-output weight_scale",
            "activation_quantization": "int8-per-tensor-symmetric",
            "weight_quantization": "int8-per-output-symmetric",
            "scale_dtype": "float32",
            "bias_dtype": "float32",
            "output_dtype": "float32",
            "output_count": out_features,
            "postprocess_ops": {
                "f32_muls": out_features,
                "f32_adds": out_features,
            },
        },
        "quantization": {
            "normalized_rmse_threshold": args.normalized_rmse_threshold,
            "activation_scale": activation_scale,
            "effective_scale_min": min(effective_scales),
            "effective_scale_max": max(effective_scales),
            "effective_scale_count": len(effective_scales),
            "accumulator_min": min(accs),
            "accumulator_max": max(accs),
            "effective_scale_sha256": hashlib.sha256(scale_blob).hexdigest(),
            "bias_sha256": hashlib.sha256(bias_blob).hexdigest(),
            "accumulator_sha256": hashlib.sha256(acc_blob).hexdigest(),
            "dequantized_output_sha256": hashlib.sha256(dequantized_blob).hexdigest(),
            **metrics,
            "verdict": (
                "pass"
                if metrics["normalized_rmse"] <= args.normalized_rmse_threshold
                else "fail"
            ),
        },
        "byte_budget": {
            "activation_int8_bytes": activation_bytes,
            "packed_weight_local_memory_bytes": packed_weight_bytes,
            "weight_value_int8_bytes": weight_value_bytes,
            "accumulator_output_int32_bytes": accumulator_bytes,
            "effective_scale_f32_bytes": scale_bytes,
            "bias_f32_bytes": bias_bytes,
            "dequantized_output_f32_bytes": f32_output_bytes,
            "scale_plus_bias_sidecar_bytes": scale_bytes + bias_bytes,
            "postprocess_read_write_bytes": (
                accumulator_bytes + scale_bytes + bias_bytes + f32_output_bytes
            ),
            "minimum_external_payload_bytes_if_sidecars_loaded_once": (
                activation_bytes + packed_weight_bytes + scale_bytes + bias_bytes
            ),
        },
        "mapped_reference": replay.get("mapped_utilization", {}),
        "decision": {
            "replacement_candidate_boundary": (
                "replace the float L2 c_fc GEMV body with the int8 local-memory "
                "accumulator contract plus an explicit scale/bias f32 output boundary"
            ),
            "do_not_assume_yet": (
                "this does not prove the f32 postprocess should be implemented in "
                "the same RTL kernel; that needs a separate cost gate"
            ),
            "next_gate": (
                "measure the scale/bias postprocess option or define an int8-to-int8 "
                "downstream boundary before replacing the full float L2 wrapper"
            ),
        },
    }

    args.out_json.parent.mkdir(parents=True, exist_ok=True)
    args.out_json.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
