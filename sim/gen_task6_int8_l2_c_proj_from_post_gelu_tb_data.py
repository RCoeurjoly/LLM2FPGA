#!/usr/bin/env python3
"""Emit RTL replay data for the post-GELU int8 c_proj proof."""

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
    parser.add_argument(
        "--artifact-name",
        default="h2-int8-l2-c-proj-from-post-gelu-rtl-proof",
    )
    parser.add_argument("--out-sv", type=Path)
    parser.add_argument("--out-json", type=Path)
    parser.add_argument("--sim-result-json", type=Path)
    parser.add_argument("--yosys-stat-json", type=Path)
    parser.add_argument("--mapped-utilization-summary-json", type=Path)
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


def addr_width(count: int) -> int:
    return max(1, (count - 1).bit_length())


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


def pack_u32(values: list[int]) -> bytes:
    return b"".join(struct.pack("<I", int(value) & 0xFFFFFFFF) for value in values)


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


def pack_weight_words(
    weight_q: list[int],
    in_features: int,
    out_features: int,
    lanes: int,
) -> list[int]:
    if out_features % lanes != 0:
        raise SystemExit(f"out_features {out_features} is not divisible by lanes {lanes}")
    words: list[int] = []
    for output_group_index in range(out_features // lanes):
        for in_index in range(in_features):
            packed_word = 0
            for lane_index in range(lanes):
                out_index = output_group_index * lanes + lane_index
                weight = weight_q[out_index * in_features + in_index]
                packed_word |= (weight & 0xFF) << (lane_index * 8)
            words.append(packed_word)
    return words


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


def signed_hex(value: int, bits: int) -> str:
    mask = (1 << bits) - 1
    digits = (bits + 3) // 4
    return f"{value & mask:0{digits}x}"


def load_contract_tensor(manifest_path: Path, tensor_name: str) -> list[float]:
    manifest = load_json(manifest_path)
    meta = tensor_by_name(manifest, tensor_name)
    return load_f32(manifest_path.parent / meta["filename"], product(meta["shape"]))


def load_design_stats(path: Path | None) -> dict[str, Any] | None:
    if path is None:
        return None
    data = load_json(path)
    design = data.get("design", {})
    cells = design.get("num_cells_by_type", {})
    lut_cells = sum(int(cells.get(f"LUT{i}", 0)) for i in range(1, 7))
    return {
        "path": str(path),
        "top_name": "task6_int8_l2_c_proj_from_post_gelu_kernel",
        "num_cells": design.get("num_cells"),
        "num_wires": design.get("num_wires"),
        "num_wire_bits": design.get("num_wire_bits"),
        "dsp48e1": cells.get("DSP48E1", 0),
        "ramb36e1": cells.get("RAMB36E1", 0),
        "ramb18e1": cells.get("RAMB18E1", 0),
        "ram64m": cells.get("RAM64M", 0),
        "fdre": cells.get("FDRE", 0),
        "carry4": cells.get("CARRY4", 0),
        "lut_primitive_cells": lut_cells,
        "lut_breakdown": {
            f"LUT{i}": cells.get(f"LUT{i}", 0)
            for i in range(1, 7)
            if cells.get(f"LUT{i}", 0)
        },
    }


def load_utilization(path: Path | None) -> dict[str, Any] | None:
    if path is None:
        return None
    data = load_json(path)
    resources = data.get("resources", data)
    return {
        "path": str(path),
        "resources": {
            key: resources.get(key)
            for key in (
                "clb_luts",
                "clb_ffs",
                "dsp",
                "bram36",
                "bram18",
                "bram36_equiv",
                "bram_kb",
                "slices_lower_bound",
            )
            if key in resources
        },
    }


def build_post_gelu_activation_q(
    c_fc_activation: list[float],
    c_fc_weight: list[float],
    c_fc_bias: list[float],
    c_fc_in_features: int,
    c_fc_out_features: int,
    post_gelu: dict[str, Any],
) -> tuple[list[int], list[float], float, list[int]]:
    activation_q, activation_scale = quantize_symmetric(c_fc_activation, 8)
    weight_q, weight_scales = quantize_per_output_symmetric(
        c_fc_weight,
        8,
        c_fc_in_features,
        c_fc_out_features,
    )
    accs = compute_accumulators(
        activation_q,
        weight_q,
        c_fc_in_features,
        c_fc_out_features,
    )
    fixed_point = post_gelu["fixed_point"]
    x_frac = int(fixed_point["x_frac"])
    scale_shift = int(fixed_point["scale_shift"])
    output_requant_shift = int(fixed_point["output_requant_shift"])
    gelu_quad_q = int(fixed_point["gelu_quad_q"])
    output_requant_mult = int(fixed_point["output_requant_mult"])
    output_scale = float(post_gelu["quantization"]["output_scale"])
    effective_scales = [
        activation_scale * weight_scale
        for weight_scale in weight_scales
    ]
    scale_mul_values = [
        round(scale * (1 << (x_frac + scale_shift)))
        for scale in effective_scales
    ]
    bias_q_values = [round(value * (1 << x_frac)) for value in c_fc_bias]
    post_gelu_q = [
        fixed_post_gelu_q(
            acc,
            scale_mul_values[index],
            bias_q_values[index],
            gelu_quad_q,
            output_requant_mult,
            x_frac,
            scale_shift,
            output_requant_shift,
        )
        for index, acc in enumerate(accs)
    ]
    dequantized = [value * output_scale for value in post_gelu_q]
    return post_gelu_q, dequantized, output_scale, accs


def build_payload(args: argparse.Namespace) -> tuple[dict[str, Any], str]:
    c_fc_contract = load_json(args.c_fc_contract_manifest)
    c_fc_weight_pack = load_json(args.c_fc_weight_pack_manifest)
    c_proj_contract = load_json(args.c_proj_contract_manifest)
    c_proj_weight_pack = load_json(args.c_proj_weight_pack_manifest)
    post_gelu = load_json(args.post_gelu_requant_json)

    c_fc_activation = load_contract_tensor(args.c_fc_contract_manifest, "activation_in")
    c_fc_expected = load_contract_tensor(args.c_fc_contract_manifest, "activation_out")
    c_proj_activation_in = load_contract_tensor(
        args.c_proj_contract_manifest,
        "activation_in",
    )
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
    post_gelu_q, post_gelu_dequantized, post_gelu_scale, c_fc_accs = (
        build_post_gelu_activation_q(
            c_fc_activation,
            c_fc_weight,
            c_fc_bias,
            c_fc_in_features,
            c_fc_out_features,
            post_gelu,
        )
    )

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

    lanes = 4
    c_proj_weight_q, c_proj_weight_scales = quantize_per_output_symmetric(
        c_proj_weight,
        8,
        c_proj_in_features,
        c_proj_out_features,
    )
    packed_words = pack_weight_words(
        c_proj_weight_q,
        c_proj_in_features,
        c_proj_out_features,
        lanes,
    )
    c_proj_accs = compute_accumulators(
        post_gelu_q,
        c_proj_weight_q,
        c_proj_in_features,
        c_proj_out_features,
    )
    c_proj_dequantized = [
        c_proj_bias[index] + acc * post_gelu_scale * c_proj_weight_scales[index]
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
    sim_result = load_json(args.sim_result_json) if args.sim_result_json else None
    sim_pass = sim_result is not None and sim_result.get("status") == "PASS"
    score_pass = output_pass and input_pass and upstream_pass
    status = "PASS" if score_pass and sim_pass else "FAIL"
    if sim_result is None and score_pass:
        status = "partial"
    if status == "PASS":
        verdict = "promote"
        next_gate = "compose the proven c_fc post-GELU int8 producer with this c_proj consumer"
    elif status == "partial":
        verdict = "continue"
        next_gate = "run Verilator, Yosys, and mapped utilization for this bounded c_proj RTL proof"
    else:
        verdict = "stop"
        next_gate = "fix the bounded c_proj RTL proof or fall back to the narrower boundary"

    activation_blob = pack_i8(post_gelu_q)
    weight_blob = pack_i8(c_proj_weight_q)
    packed_blob = pack_u32(packed_words)
    acc_blob = pack_i32(c_proj_accs)
    c_fc_acc_blob = pack_i32(c_fc_accs)

    payload: dict[str, Any] = {
        "artifact_name": args.artifact_name,
        "status": status,
        "source_artifacts": {
            "c_fc_contract_manifest": str(args.c_fc_contract_manifest),
            "c_fc_weight_pack_manifest": str(args.c_fc_weight_pack_manifest),
            "c_proj_contract_manifest": str(args.c_proj_contract_manifest),
            "c_proj_weight_pack_manifest": str(args.c_proj_weight_pack_manifest),
            "post_gelu_requant_json": str(args.post_gelu_requant_json),
            "model_label": c_proj_contract["model_label"],
        },
        "replacement_region": {
            "producer": c_fc_contract["module_name"],
            "boundary": post_gelu["rtl_contract"]["boundary"],
            "consumer": c_proj_contract["module_name"],
            "interpretation": (
                "RTL proof for c_proj consuming the accepted post-GELU int8 "
                "activation from the c_fc proof."
            ),
        },
        "rtl_contract": {
            "top_name": "task6_int8_l2_c_proj_from_post_gelu_kernel",
            "in_dim": c_proj_in_features,
            "out_dim": c_proj_out_features,
            "lane_count": lanes,
            "packed_weight_words": len(packed_words),
            "activation_dtype": "int8",
            "weight_dtype": "int8",
            "accumulator_dtype": "int32",
            "output_dtype": "int32",
            "output_score_dtype": "float32",
            "activation_quantization": "post-GELU int8-per-tensor-symmetric",
            "weight_quantization": "int8-per-output-symmetric",
            "local_activation_memory": True,
            "local_packed_weight_memory": True,
            "local_output_memory": True,
        },
        "c_fc_post_gelu_activation": {
            "dtype": "int8",
            "scale": post_gelu_scale,
            "q_min": min(post_gelu_q),
            "q_max": max(post_gelu_q),
            "q_sha256": hashlib.sha256(activation_blob).hexdigest(),
            "source_accumulator_sha256": hashlib.sha256(c_fc_acc_blob).hexdigest(),
        },
        "c_proj_quantization": {
            "normalized_rmse_threshold": args.normalized_rmse_threshold,
            "weight_scale_min": min(c_proj_weight_scales),
            "weight_scale_max": max(c_proj_weight_scales),
            "weight_q_min": min(c_proj_weight_q),
            "weight_q_max": max(c_proj_weight_q),
            "bias_min": min(c_proj_bias),
            "bias_max": max(c_proj_bias),
            "accumulator_min": min(c_proj_accs),
            "accumulator_max": max(c_proj_accs),
            "activation_q_sha256": hashlib.sha256(activation_blob).hexdigest(),
            "weight_q_sha256": hashlib.sha256(weight_blob).hexdigest(),
            "packed_weight_sha256": hashlib.sha256(packed_blob).hexdigest(),
            "accumulator_sha256": hashlib.sha256(acc_blob).hexdigest(),
        },
        "metrics": {
            "c_proj_input_vs_gelu_c_fc_expected": c_proj_input_relation_metrics,
            "post_gelu_int8_vs_c_proj_input": post_gelu_input_metrics,
            "c_proj_output_from_rtl_accumulators": c_proj_output_metrics,
        },
        "byte_budget": {
            "post_gelu_int8_activation_bytes": len(post_gelu_q),
            "f32_activation_bytes_replaced": len(post_gelu_q) * 4,
            "activation_transfer_savings_bytes": len(post_gelu_q) * 3,
            "c_proj_weight_int8_bytes": len(c_proj_weight_q),
            "c_proj_weight_f32_bytes_replaced": len(c_proj_weight_q) * 4,
            "c_proj_weight_transfer_savings_bytes": len(c_proj_weight_q) * 3,
            "c_proj_weight_scale_sidecar_bytes": len(c_proj_weight_scales) * 4,
            "c_proj_accumulator_output_bytes": len(c_proj_accs) * 4,
        },
        "sim_result": sim_result,
        "yosys_result": load_design_stats(args.yosys_stat_json),
        "mapped_utilization": load_utilization(args.mapped_utilization_summary_json),
        "decision": {
            "verdict": verdict,
            "next_gate": next_gate,
        },
    }

    sv_lines = [
        f"localparam int IN_DIM = {c_proj_in_features};",
        f"localparam int OUT_DIM = {c_proj_out_features};",
        f"localparam int LANES = {lanes};",
        f"localparam int PACKED_WEIGHT_WORDS = {len(packed_words)};",
        f"localparam int PACKED_WEIGHT_ADDR_WIDTH = {addr_width(len(packed_words))};",
        f"localparam int ACTIVATION_ADDR_WIDTH = {addr_width(c_proj_in_features)};",
        f"localparam int OUT_ADDR_WIDTH = {addr_width(c_proj_out_features)};",
        "logic signed [7:0] activation_values [0:IN_DIM - 1];",
        "logic [LANES * 8 - 1:0] packed_weight_values [0:PACKED_WEIGHT_WORDS - 1];",
        "logic signed [31:0] expected_acc_values [0:OUT_DIM - 1];",
        "initial begin",
    ]
    for index, value in enumerate(post_gelu_q):
        sv_lines.append(f"  activation_values[{index}] = 8'sh{signed_hex(value, 8)};")
    for index, value in enumerate(packed_words):
        sv_lines.append(f"  packed_weight_values[{index}] = 32'h{value:08x};")
    for index, value in enumerate(c_proj_accs):
        sv_lines.append(f"  expected_acc_values[{index}] = 32'sh{signed_hex(value, 32)};")
    sv_lines.append("end")
    sv_text = "\n".join(sv_lines) + "\n"
    return payload, sv_text


def main() -> None:
    args = parse_args()
    payload, sv_text = build_payload(args)
    if args.out_sv is not None:
        args.out_sv.parent.mkdir(parents=True, exist_ok=True)
        args.out_sv.write_text(sv_text, encoding="utf-8")
    if args.out_json is not None:
        args.out_json.parent.mkdir(parents=True, exist_ok=True)
        args.out_json.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    if args.out_sv is None and args.out_json is None:
        print(sv_text, end="")


if __name__ == "__main__":
    main()
