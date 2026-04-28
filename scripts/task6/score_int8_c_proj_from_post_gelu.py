#!/usr/bin/env python3
"""Score the L2 c_proj handoff from the post-GELU int8 c_fc boundary."""

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
    parser.add_argument("--c-fc-contract-manifest", required=True, type=Path)
    parser.add_argument("--c-fc-weight-pack-manifest", required=True, type=Path)
    parser.add_argument("--c-proj-contract-manifest", required=True, type=Path)
    parser.add_argument("--c-proj-weight-pack-manifest", required=True, type=Path)
    parser.add_argument("--post-gelu-requant-json", required=True, type=Path)
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


def pack_i8(values: list[int]) -> bytes:
    return bytes((int(value) & 0xFF) for value in values)


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


def gelu_tanh(values: list[float]) -> list[float]:
    sqrt_2_over_pi = math.sqrt(2.0 / math.pi)
    return [
        0.5
        * value
        * (1.0 + math.tanh(sqrt_2_over_pi * (value + 0.044715 * value * value * value)))
        for value in values
    ]


def round_shift_signed(value: int, shift: int) -> int:
    if shift == 0:
        return value
    half = 1 << (shift - 1)
    if value >= 0:
        return (value + half) >> shift
    return -(((-value) + half) >> shift)


def saturate_i8(value: int) -> int:
    return max(-127, min(127, value))


def fixed_post_gelu_q(
    acc: int,
    scale_mul: int,
    bias_q: int,
    gelu_quad_q: int,
    output_requant_mult: int,
    x_frac: int,
    scale_shift: int,
    output_requant_shift: int,
) -> int:
    x_q = round_shift_signed(acc * scale_mul, scale_shift) + bias_q
    y_q = (x_q >> 1) + round_shift_signed(gelu_quad_q * x_q * x_q, 2 * x_frac)
    output_q = round_shift_signed(y_q * output_requant_mult, output_requant_shift)
    return saturate_i8(output_q)


def score_error(actual: list[float], expected: list[float]) -> dict[str, float]:
    if len(actual) != len(expected):
        raise SystemExit(f"length mismatch: actual={len(actual)} expected={len(expected)}")
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


def load_contract_tensor(manifest_path: Path, tensor_name: str) -> list[float]:
    manifest = load_json(manifest_path)
    meta = tensor_by_name(manifest, tensor_name)
    return load_f32(manifest_path.parent / meta["filename"], product(meta["shape"]))


def main() -> None:
    args = parse_args()
    c_fc_contract = load_json(args.c_fc_contract_manifest)
    c_fc_weight_pack = load_json(args.c_fc_weight_pack_manifest)
    c_proj_contract = load_json(args.c_proj_contract_manifest)
    c_proj_weight_pack = load_json(args.c_proj_weight_pack_manifest)
    post_gelu = load_json(args.post_gelu_requant_json)

    c_fc_activation = load_contract_tensor(args.c_fc_contract_manifest, "activation_in")
    c_fc_expected = load_contract_tensor(args.c_fc_contract_manifest, "activation_out")
    c_proj_activation_in = load_contract_tensor(args.c_proj_contract_manifest, "activation_in")
    c_proj_expected = load_contract_tensor(args.c_proj_contract_manifest, "activation_out")

    c_fc_weight_meta = tensor_by_name(c_fc_weight_pack, "weight")
    c_fc_bias_meta = tensor_by_name(c_fc_weight_pack, "bias")
    c_fc_weight = load_f32(
        args.c_fc_weight_pack_manifest.parent / c_fc_weight_meta["filename"],
        product(c_fc_weight_meta["shape"]),
    )
    c_fc_bias = load_f32(
        args.c_fc_weight_pack_manifest.parent / c_fc_bias_meta["filename"],
        product(c_fc_bias_meta["shape"]),
    )
    c_fc_out_features, c_fc_in_features = [int(value) for value in c_fc_weight_meta["shape"]]

    c_fc_activation_q, c_fc_activation_scale = quantize_symmetric(c_fc_activation, 8)
    c_fc_weight_q, c_fc_weight_scales = quantize_per_output_symmetric(
        c_fc_weight,
        8,
        c_fc_in_features,
        c_fc_out_features,
    )
    c_fc_accs = compute_accumulators(
        c_fc_activation_q,
        c_fc_weight_q,
        c_fc_in_features,
        c_fc_out_features,
    )
    fixed_point = post_gelu["fixed_point"]
    x_frac = int(fixed_point["x_frac"])
    scale_shift = int(fixed_point["scale_shift"])
    output_requant_shift = int(fixed_point["output_requant_shift"])
    gelu_quad_q = int(fixed_point["gelu_quad_q"])
    output_requant_mult = int(fixed_point["output_requant_mult"])
    post_gelu_output_scale = float(post_gelu["quantization"]["output_scale"])
    c_fc_effective_scales = [
        c_fc_activation_scale * weight_scale
        for weight_scale in c_fc_weight_scales
    ]
    c_fc_scale_mul = [
        round(scale * (1 << (x_frac + scale_shift)))
        for scale in c_fc_effective_scales
    ]
    c_fc_bias_q = [round(value * (1 << x_frac)) for value in c_fc_bias]
    post_gelu_q = [
        fixed_post_gelu_q(
            acc,
            c_fc_scale_mul[index],
            c_fc_bias_q[index],
            gelu_quad_q,
            output_requant_mult,
            x_frac,
            scale_shift,
            output_requant_shift,
        )
        for index, acc in enumerate(c_fc_accs)
    ]
    post_gelu_dequantized = [
        value * post_gelu_output_scale
        for value in post_gelu_q
    ]

    c_proj_weight_meta = tensor_by_name(c_proj_weight_pack, "weight")
    c_proj_bias_meta = tensor_by_name(c_proj_weight_pack, "bias")
    c_proj_weight = load_f32(
        args.c_proj_weight_pack_manifest.parent / c_proj_weight_meta["filename"],
        product(c_proj_weight_meta["shape"]),
    )
    c_proj_bias = load_f32(
        args.c_proj_weight_pack_manifest.parent / c_proj_bias_meta["filename"],
        product(c_proj_bias_meta["shape"]),
    )
    c_proj_out_features, c_proj_in_features = [
        int(value) for value in c_proj_weight_meta["shape"]
    ]
    if c_proj_in_features != len(post_gelu_q):
        raise SystemExit(
            f"c_proj input features {c_proj_in_features} != post-GELU q length {len(post_gelu_q)}"
        )

    c_proj_weight_q, c_proj_weight_scales = quantize_per_output_symmetric(
        c_proj_weight,
        8,
        c_proj_in_features,
        c_proj_out_features,
    )
    c_proj_accs = compute_accumulators(
        post_gelu_q,
        c_proj_weight_q,
        c_proj_in_features,
        c_proj_out_features,
    )
    c_proj_dequantized = [
        c_proj_bias[index]
        + acc * post_gelu_output_scale * c_proj_weight_scales[index]
        for index, acc in enumerate(c_proj_accs)
    ]

    c_proj_input_relation_metrics = score_error(
        c_proj_activation_in,
        gelu_tanh(c_fc_expected),
    )
    post_gelu_input_metrics = score_error(
        post_gelu_dequantized,
        c_proj_activation_in,
    )
    c_proj_output_metrics = score_error(c_proj_dequantized, c_proj_expected)
    output_pass = (
        c_proj_output_metrics["normalized_rmse"] <= args.normalized_rmse_threshold
    )
    input_pass = (
        post_gelu_input_metrics["normalized_rmse"] <= args.normalized_rmse_threshold
    )
    upstream_pass = post_gelu.get("status") == "PASS"
    status_pass = output_pass and input_pass and upstream_pass

    payload = {
        "artifact_name": "h2-int8-l2-c-proj-from-post-gelu-boundary",
        "status": "PASS" if status_pass else "FAIL",
        "source_artifacts": {
            "c_fc_contract_manifest": str(args.c_fc_contract_manifest),
            "c_fc_weight_pack_manifest": str(args.c_fc_weight_pack_manifest),
            "c_proj_contract_manifest": str(args.c_proj_contract_manifest),
            "c_proj_weight_pack_manifest": str(args.c_proj_weight_pack_manifest),
            "post_gelu_requant_json": str(args.post_gelu_requant_json),
        },
        "replacement_region": {
            "producer": c_fc_contract["module_name"],
            "boundary": post_gelu["rtl_contract"]["boundary"],
            "consumer": c_proj_contract["module_name"],
            "interpretation": (
                "The accepted replacement region is c_fc -> GELU -> int8 activation, "
                "and this artifact scores the immediate c_proj consumer."
            ),
        },
        "c_fc_post_gelu_activation": {
            "dtype": "int8",
            "quantization": "int8-per-tensor-symmetric",
            "scale": post_gelu_output_scale,
            "q_min": min(post_gelu_q),
            "q_max": max(post_gelu_q),
            "q_sha256": hashlib.sha256(pack_i8(post_gelu_q)).hexdigest(),
            "dequantized_bytes": len(post_gelu_q) * 4,
            "int8_bytes": len(post_gelu_q),
        },
        "c_proj_contract": {
            "in_features": c_proj_in_features,
            "out_features": c_proj_out_features,
            "macs": c_proj_in_features * c_proj_out_features,
            "activation_quantization": "post-GELU int8-per-tensor-symmetric",
            "weight_quantization": "int8-per-output-symmetric",
            "accumulator_dtype": "int32",
            "output_dtype_for_score": "float32",
        },
        "c_proj_quantization": {
            "normalized_rmse_threshold": args.normalized_rmse_threshold,
            "weight_scale_min": min(c_proj_weight_scales),
            "weight_scale_max": max(c_proj_weight_scales),
            "weight_q_min": min(c_proj_weight_q),
            "weight_q_max": max(c_proj_weight_q),
            "accumulator_min": min(c_proj_accs),
            "accumulator_max": max(c_proj_accs),
            "activation_q_sha256": hashlib.sha256(pack_i8(post_gelu_q)).hexdigest(),
            "weight_q_sha256": hashlib.sha256(pack_i8(c_proj_weight_q)).hexdigest(),
            "accumulator_sha256": hashlib.sha256(pack_i32(c_proj_accs)).hexdigest(),
        },
        "metrics": {
            "c_proj_input_vs_gelu_c_fc_expected": c_proj_input_relation_metrics,
            "post_gelu_int8_vs_c_proj_input": post_gelu_input_metrics,
            "c_proj_output_from_post_gelu_int8": c_proj_output_metrics,
        },
        "byte_budget": {
            "post_gelu_int8_activation_bytes": len(post_gelu_q),
            "f32_activation_bytes_replaced": len(post_gelu_q) * 4,
            "activation_transfer_savings_bytes": len(post_gelu_q) * 3,
            "c_proj_weight_int8_bytes": len(c_proj_weight_q),
            "c_proj_weight_f32_bytes_replaced": len(c_proj_weight_q) * 4,
            "c_proj_weight_transfer_savings_bytes": len(c_proj_weight_q) * 3,
            "c_proj_weight_scale_sidecar_bytes": len(c_proj_weight_scales) * 4,
        },
        "decision": {
            "verdict": "promote" if status_pass else "stop",
            "next_gate": (
                "implement a bounded 256x64 int8 c_proj RTL proof fed by the post-GELU int8 activation"
                if status_pass
                else "fall back to f32 c_proj input or widen calibration/scoring"
            ),
        },
    }

    args.out_json.parent.mkdir(parents=True, exist_ok=True)
    args.out_json.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
