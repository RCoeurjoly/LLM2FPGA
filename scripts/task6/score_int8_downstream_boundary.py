#!/usr/bin/env python3
"""Score int8 downstream activation boundaries after the H2 c_fc proof."""

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


def pack_i8(values: list[int]) -> bytes:
    return bytes((int(value) & 0xFF) for value in values)


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


def dequantize(values: list[int], scale: float) -> list[float]:
    return [int(value) * scale for value in values]


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


def score_requantized_boundary(
    name: str,
    produced: list[float],
    calibration_reference: list[float],
    expected: list[float],
    gelu_expected: list[float],
    produced_is_post_gelu: bool = False,
) -> dict[str, Any]:
    q_values, output_scale = quantize_symmetric(calibration_reference, 8)
    # The output scale comes from the reference/calibration tensor, but the
    # candidate values are the actual int8-kernel outputs.
    q_values = [
        max(-127, min(127, int(round(value / output_scale))))
        for value in produced
    ]
    dequantized = dequantize(q_values, output_scale)
    c_fc_metrics = score_error(dequantized, expected)
    gelu_candidate = dequantized if produced_is_post_gelu else gelu_tanh(dequantized)
    gelu_metrics = score_error(gelu_candidate, gelu_expected)
    q_blob = pack_i8(q_values)
    return {
        "name": name,
        "output_quantization": "int8-per-tensor-symmetric",
        "output_scale": output_scale,
        "output_q_min": min(q_values),
        "output_q_max": max(q_values),
        "output_q_sha256": hashlib.sha256(q_blob).hexdigest(),
        "output_int8_bytes": len(q_values),
        "output_scale_bytes": 4,
        "c_fc_output_metrics": c_fc_metrics,
        "gelu_output_metrics": gelu_metrics,
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
    expected_c_fc = load_f32(
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
    produced_c_fc = [
        bias[out_index] + accs[out_index] * effective_scales[out_index]
        for out_index in range(out_features)
    ]
    f32_boundary_metrics = score_error(produced_c_fc, expected_c_fc)
    expected_gelu = gelu_tanh(expected_c_fc)
    produced_gelu = gelu_tanh(produced_c_fc)

    pre_gelu = score_requantized_boundary(
        "pre_gelu_int8_activation",
        produced_c_fc,
        expected_c_fc,
        expected_c_fc,
        expected_gelu,
    )
    post_gelu = score_requantized_boundary(
        "post_gelu_int8_activation",
        produced_gelu,
        expected_gelu,
        expected_gelu,
        expected_gelu,
        produced_is_post_gelu=True,
    )
    post_gelu["c_fc_output_metrics"] = score_error(produced_c_fc, expected_c_fc)

    candidates = [pre_gelu, post_gelu]
    for candidate in candidates:
        c_fc_ok = (
            candidate["c_fc_output_metrics"]["normalized_rmse"]
            <= args.normalized_rmse_threshold
        )
        gelu_ok = (
            candidate["gelu_output_metrics"]["normalized_rmse"]
            <= args.normalized_rmse_threshold
        )
        candidate["verdict"] = "pass" if c_fc_ok and gelu_ok else "fail"

    payload = {
        "artifact_name": "h2-int8-l2-c-fc-downstream-int8-boundary",
        "status": "PASS" if any(candidate["verdict"] == "pass" for candidate in candidates) else "FAIL",
        "source_artifacts": {
            "contract_manifest": str(args.contract_manifest),
            "weight_pack_manifest": str(args.weight_pack_manifest),
            "contract_replay_json": str(args.contract_replay_json),
        },
        "assumptions": {
            "gelu_variant": "tanh approximation",
            "output_scale_source": "single captured contract sample used as calibration reference",
            "threshold": args.normalized_rmse_threshold,
            "calibration_caveat": (
                "This is a bounded single-sample gate. A production activation scale "
                "needs a calibration set before board-level claims."
            ),
        },
        "module": {
            "model_label": contract["model_label"],
            "module_name": contract["module_name"],
            "in_features": in_features,
            "out_features": out_features,
            "macs": in_features * out_features,
        },
        "input_replay": {
            "contract_replay_status": replay.get("status"),
            "activation_scale": activation_scale,
            "effective_scale_min": min(effective_scales),
            "effective_scale_max": max(effective_scales),
            "accumulator_min": min(accs),
            "accumulator_max": max(accs),
            "f32_boundary_metrics": f32_boundary_metrics,
        },
        "candidates": candidates,
        "byte_budget": {
            "pre_gelu_int8_output_bytes": pre_gelu["output_int8_bytes"],
            "post_gelu_int8_output_bytes": post_gelu["output_int8_bytes"],
            "f32_output_bytes_replaced": out_features * 4,
            "output_scale_bytes": 4,
            "int8_output_write_savings_vs_f32_bytes": out_features * 3,
        },
        "decision": {
            "recommended_boundary": (
                "post_gelu_int8_activation"
                if post_gelu["verdict"] == "pass"
                else "pre_gelu_int8_activation"
                if pre_gelu["verdict"] == "pass"
                else "none"
            ),
            "next_gate": (
                "if a candidate passes, implement a bounded fixed-point requant/output "
                "memory proof; otherwise fall back to the explicit f32 scale/bias boundary"
            ),
        },
    }

    args.out_json.parent.mkdir(parents=True, exist_ok=True)
    args.out_json.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
