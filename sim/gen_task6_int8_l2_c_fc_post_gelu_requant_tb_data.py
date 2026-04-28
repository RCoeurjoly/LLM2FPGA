#!/usr/bin/env python3
"""Emit RTL replay data for the post-GELU int8 requant proof."""

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
    parser.add_argument("--downstream-boundary-json", required=True, type=Path)
    parser.add_argument(
        "--artifact-name",
        default="h2-int8-l2-c-fc-post-gelu-requant-rtl-proof",
    )
    parser.add_argument("--out-sv", type=Path)
    parser.add_argument("--out-json", type=Path)
    parser.add_argument("--sim-result-json", type=Path)
    parser.add_argument("--yosys-stat-json", type=Path)
    parser.add_argument("--mapped-utilization-summary-json", type=Path)
    parser.add_argument("--normalized-rmse-threshold", type=float, default=0.02)
    parser.add_argument("--x-frac", type=int, default=12)
    parser.add_argument("--scale-shift", type=int, default=24)
    parser.add_argument("--output-requant-shift", type=int, default=16)
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


def signed_byte_blob(values: list[int]) -> bytes:
    return bytes((int(value) & 0xFF) for value in values)


def signed_i32_blob(values: list[int]) -> bytes:
    return b"".join(struct.pack("<i", int(value)) for value in values)


def pack_u32(values: list[int]) -> bytes:
    return b"".join(struct.pack("<I", int(value) & 0xFFFFFFFF) for value in values)


def load_design_stats(path: Path | None) -> dict[str, Any] | None:
    if path is None:
        return None
    data = load_json(path)
    design = data.get("design", {})
    cells = design.get("num_cells_by_type", {})
    lut_cells = sum(int(cells.get(f"LUT{i}", 0)) for i in range(1, 7))
    return {
        "path": str(path),
        "top_name": "task6_int8_l2_c_fc_post_gelu_requant_kernel",
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


def post_gelu_candidate(boundary: dict[str, Any]) -> dict[str, Any]:
    for candidate in boundary["candidates"]:
        if candidate["name"] == "post_gelu_int8_activation":
            return candidate
    raise SystemExit("downstream boundary artifact has no post_gelu_int8_activation candidate")


def build_payload(args: argparse.Namespace) -> tuple[dict[str, Any], str]:
    contract = load_json(args.contract_manifest)
    weight_pack = load_json(args.weight_pack_manifest)
    boundary = load_json(args.downstream_boundary_json)
    post_candidate = post_gelu_candidate(boundary)

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
    lanes = 4
    activation_q, activation_scale = quantize_symmetric(activation, 8)
    weight_q, weight_scales = quantize_per_output_symmetric(
        weight,
        8,
        in_features,
        out_features,
    )
    packed_words = pack_weight_words(weight_q, in_features, out_features, lanes)
    accs = compute_accumulators(activation_q, weight_q, in_features, out_features)
    effective_scales = [activation_scale * weight_scale for weight_scale in weight_scales]
    produced_c_fc = [
        bias[out_index] + accs[out_index] * effective_scales[out_index]
        for out_index in range(out_features)
    ]
    expected_gelu = gelu_tanh(expected_c_fc)

    x_frac = args.x_frac
    scale_shift = args.scale_shift
    output_requant_shift = args.output_requant_shift
    output_scale = float(post_candidate["output_scale"])
    gelu_quad_q = round(0.3989422804014327 * (1 << x_frac))
    output_requant_mult = round(
        (1 << output_requant_shift) / ((1 << x_frac) * output_scale)
    )
    scale_mul_values = [
        round(scale * (1 << (x_frac + scale_shift)))
        for scale in effective_scales
    ]
    bias_q_values = [round(value * (1 << x_frac)) for value in bias]
    output_q_values = [
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
    output_dequantized = [value * output_scale for value in output_q_values]
    metrics = score_error(output_dequantized, expected_gelu)

    activation_blob = signed_byte_blob(activation_q)
    weight_blob = signed_byte_blob(weight_q)
    packed_blob = pack_u32(packed_words)
    acc_blob = signed_i32_blob(accs)
    scale_mul_blob = signed_i32_blob(scale_mul_values)
    bias_q_blob = signed_i32_blob(bias_q_values)
    output_q_blob = signed_byte_blob(output_q_values)

    sim_result = load_json(args.sim_result_json) if args.sim_result_json else None
    status = (
        "PASS"
        if metrics["normalized_rmse"] <= args.normalized_rmse_threshold
        and post_candidate.get("verdict") == "pass"
        else "FAIL"
    )
    if sim_result is None or sim_result.get("status") != "PASS":
        status = "partial" if status == "PASS" else status

    payload: dict[str, Any] = {
        "artifact_name": args.artifact_name,
        "status": status,
        "source_artifacts": {
            "contract_manifest": str(args.contract_manifest),
            "weight_pack_manifest": str(args.weight_pack_manifest),
            "downstream_boundary_json": str(args.downstream_boundary_json),
            "model_label": contract["model_label"],
            "module_name": contract["module_name"],
        },
        "rtl_contract": {
            "top_name": "task6_int8_l2_c_fc_post_gelu_requant_kernel",
            "in_dim": in_features,
            "out_dim": out_features,
            "lane_count": lanes,
            "packed_weight_words": len(packed_words),
            "activation_dtype": "int8",
            "weight_dtype": "int8",
            "accumulator_dtype": "int32",
            "output_dtype": "int8",
            "activation_quantization": "int8-per-tensor-symmetric",
            "weight_quantization": "int8-per-output-symmetric",
            "output_quantization": "int8-per-tensor-symmetric",
            "boundary": "post_gelu_int8_activation",
            "local_activation_memory": True,
            "local_packed_weight_memory": True,
            "local_requant_sidecar_memory": True,
            "local_output_memory": True,
        },
        "fixed_point": {
            "x_frac": x_frac,
            "scale_shift": scale_shift,
            "gelu_approximation": "0.5*x + 0.39894228*x*x",
            "gelu_quad_q": gelu_quad_q,
            "output_requant_shift": output_requant_shift,
            "output_requant_mult": output_requant_mult,
            "postprocess_formula": (
                "x_q = round_shift(acc * scale_mul, scale_shift) + bias_q; "
                "y_q = (x_q >> 1) + round_shift(gelu_quad_q * x_q * x_q, 2*x_frac); "
                "q = saturate_i8(round_shift(y_q * output_requant_mult, output_requant_shift))"
            ),
        },
        "quantization": {
            "normalized_rmse_threshold": args.normalized_rmse_threshold,
            "activation_scale": activation_scale,
            "output_scale": output_scale,
            "effective_scale_min": min(effective_scales),
            "effective_scale_max": max(effective_scales),
            "scale_mul_min": min(scale_mul_values),
            "scale_mul_max": max(scale_mul_values),
            "bias_q_min": min(bias_q_values),
            "bias_q_max": max(bias_q_values),
            "accumulator_min": min(accs),
            "accumulator_max": max(accs),
            "pre_gelu_min": min(produced_c_fc),
            "pre_gelu_max": max(produced_c_fc),
            "output_q_min": min(output_q_values),
            "output_q_max": max(output_q_values),
            "activation_q_sha256": hashlib.sha256(activation_blob).hexdigest(),
            "weight_q_sha256": hashlib.sha256(weight_blob).hexdigest(),
            "packed_weight_sha256": hashlib.sha256(packed_blob).hexdigest(),
            "expected_acc_sha256": hashlib.sha256(acc_blob).hexdigest(),
            "scale_mul_sha256": hashlib.sha256(scale_mul_blob).hexdigest(),
            "bias_q_sha256": hashlib.sha256(bias_q_blob).hexdigest(),
            "output_q_sha256": hashlib.sha256(output_q_blob).hexdigest(),
            **metrics,
            "verdict": (
                "pass"
                if metrics["normalized_rmse"] <= args.normalized_rmse_threshold
                else "fail"
            ),
        },
        "byte_budget": {
            "activation_int8_bytes": len(activation_q),
            "packed_weight_bytes": len(packed_words) * 4,
            "scale_mul_sidecar_bytes": len(scale_mul_values) * 4,
            "bias_q_sidecar_bytes": len(bias_q_values) * 4,
            "output_int8_bytes": len(output_q_values),
            "f32_output_bytes_replaced": len(output_q_values) * 4,
            "int8_output_write_savings_vs_f32_bytes": len(output_q_values) * 3,
        },
        "sim_result": sim_result,
        "yosys_result": load_design_stats(args.yosys_stat_json),
        "mapped_utilization": load_utilization(args.mapped_utilization_summary_json),
        "interpretation": [
            "This proof keeps c_fc accumulation in the existing int8 local-I/O RTL and adds a fixed-point post-GELU requant/output-memory stage.",
            "The GELU stage is a bounded small-range quadratic approximation, matched to the captured L2 c_fc activation range.",
            "The output is checked as an int8 post-GELU activation, so this avoids the explicit f32 scale/bias/output buffer boundary.",
        ],
    }

    sv_lines = [
        f"localparam int IN_DIM = {in_features};",
        "localparam int TILE_OUT_DIM = 64;",
        f"localparam int OUT_DIM = {out_features};",
        f"localparam int LANES = {lanes};",
        f"localparam int PACKED_WEIGHT_WORDS = {len(packed_words)};",
        "localparam int PACKED_WEIGHT_ADDR_WIDTH = 12;",
        "localparam int ACTIVATION_ADDR_WIDTH = 6;",
        "localparam int OUT_ADDR_WIDTH = 8;",
        f"localparam int X_FRAC = {x_frac};",
        f"localparam int SCALE_SHIFT = {scale_shift};",
        f"localparam int GELU_QUAD_Q = {gelu_quad_q};",
        f"localparam int OUTPUT_REQUANT_SHIFT = {output_requant_shift};",
        f"localparam int OUTPUT_REQUANT_MULT = {output_requant_mult};",
        "logic signed [7:0] activation_values [0:IN_DIM - 1];",
        "logic [LANES * 8 - 1:0] packed_weight_values [0:PACKED_WEIGHT_WORDS - 1];",
        "logic signed [31:0] requant_scale_mul_values [0:OUT_DIM - 1];",
        "logic signed [31:0] requant_bias_q_values [0:OUT_DIM - 1];",
        "logic signed [7:0] expected_output_q_values [0:OUT_DIM - 1];",
        "logic signed [31:0] expected_acc_values [0:OUT_DIM - 1];",
        "initial begin",
    ]
    for index, value in enumerate(activation_q):
        sv_lines.append(f"  activation_values[{index}] = 8'sh{signed_hex(value, 8)};")
    for index, value in enumerate(packed_words):
        sv_lines.append(f"  packed_weight_values[{index}] = 32'h{value:08x};")
    for index, value in enumerate(scale_mul_values):
        sv_lines.append(
            f"  requant_scale_mul_values[{index}] = 32'sh{signed_hex(value, 32)};"
        )
    for index, value in enumerate(bias_q_values):
        sv_lines.append(f"  requant_bias_q_values[{index}] = 32'sh{signed_hex(value, 32)};")
    for index, value in enumerate(output_q_values):
        sv_lines.append(f"  expected_output_q_values[{index}] = 8'sh{signed_hex(value, 8)};")
    for index, value in enumerate(accs):
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
