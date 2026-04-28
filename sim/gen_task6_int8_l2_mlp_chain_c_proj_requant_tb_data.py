#!/usr/bin/env python3
"""Emit RTL replay data for the composed int8 L2 MLP c_proj requant proof."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

from gen_task6_int8_l2_c_proj_from_post_gelu_tb_data import (
    addr_width,
    compute_accumulators,
    fixed_post_gelu_q,
    gelu_tanh,
    load_contract_tensor,
    load_f32,
    load_json,
    pack_i8,
    pack_i32,
    pack_u32,
    pack_weight_words,
    product,
    quantize_per_output_symmetric,
    quantize_symmetric,
    round_shift_signed,
    saturate_i8,
    score_error,
    signed_hex,
    tensor_by_name,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--c-fc-contract-manifest", required=True, type=Path)
    parser.add_argument("--c-fc-weight-pack-manifest", required=True, type=Path)
    parser.add_argument("--c-proj-contract-manifest", required=True, type=Path)
    parser.add_argument("--c-proj-weight-pack-manifest", required=True, type=Path)
    parser.add_argument("--post-gelu-requant-json", required=True, type=Path)
    parser.add_argument("--c-proj-output-boundary-json", required=True, type=Path)
    parser.add_argument(
        "--artifact-name",
        default="h2-int8-l2-mlp-chain-c-proj-requant-rtl-proof",
    )
    parser.add_argument("--out-sv", type=Path)
    parser.add_argument("--out-json", type=Path)
    parser.add_argument("--sim-result-json", type=Path)
    parser.add_argument("--yosys-stat-json", type=Path)
    parser.add_argument("--mapped-utilization-summary-json", type=Path)
    parser.add_argument("--normalized-rmse-threshold", type=float, default=0.02)
    parser.add_argument("--c-proj-output-requant-shift", type=int, default=24)
    return parser.parse_args()


def load_design_stats(path: Path | None) -> dict[str, Any] | None:
    if path is None:
        return None
    data = load_json(path)
    design = data.get("design", {})
    cells = design.get("num_cells_by_type", {})
    lut_cells = sum(int(cells.get(f"LUT{i}", 0)) for i in range(1, 7))
    return {
        "path": str(path),
        "top_name": "task6_int8_l2_mlp_chain_post_gelu_c_proj_requant_kernel",
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


def fixed_c_proj_output_q(
    acc: int,
    scale_mul: int,
    bias_q: int,
    shift: int,
) -> int:
    scaled_q = round_shift_signed(acc * scale_mul, shift)
    return saturate_i8(scaled_q + bias_q)


def build_payload(args: argparse.Namespace) -> tuple[dict[str, Any], str]:
    c_fc_contract = load_json(args.c_fc_contract_manifest)
    c_fc_weight_pack = load_json(args.c_fc_weight_pack_manifest)
    c_proj_contract = load_json(args.c_proj_contract_manifest)
    c_proj_weight_pack = load_json(args.c_proj_weight_pack_manifest)
    post_gelu = load_json(args.post_gelu_requant_json)
    output_boundary = load_json(args.c_proj_output_boundary_json)

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

    lanes = 4
    tile_out_dim = 64
    c_fc_activation_q, c_fc_activation_scale = quantize_symmetric(c_fc_activation, 8)
    c_fc_weight_q, c_fc_weight_scales = quantize_per_output_symmetric(
        c_fc_weight,
        8,
        c_fc_in_features,
        c_fc_out_features,
    )
    c_fc_packed_words = pack_weight_words(
        c_fc_weight_q,
        c_fc_in_features,
        c_fc_out_features,
        lanes,
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
    post_gelu_scale = float(post_gelu["quantization"]["output_scale"])
    c_fc_effective_scales = [
        c_fc_activation_scale * weight_scale
        for weight_scale in c_fc_weight_scales
    ]
    c_fc_scale_mul_values = [
        round(scale * (1 << (x_frac + scale_shift)))
        for scale in c_fc_effective_scales
    ]
    c_fc_bias_q_values = [round(value * (1 << x_frac)) for value in c_fc_bias]
    post_gelu_q = [
        fixed_post_gelu_q(
            acc,
            c_fc_scale_mul_values[index],
            c_fc_bias_q_values[index],
            gelu_quad_q,
            output_requant_mult,
            x_frac,
            scale_shift,
            output_requant_shift,
        )
        for index, acc in enumerate(c_fc_accs)
    ]
    post_gelu_dequantized = [value * post_gelu_scale for value in post_gelu_q]

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
    c_proj_packed_words = pack_weight_words(
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
    c_proj_f32_dequantized = [
        c_proj_bias[index] + acc * post_gelu_scale * c_proj_weight_scales[index]
        for index, acc in enumerate(c_proj_accs)
    ]

    output_scale = float(output_boundary["int8_output_candidate"]["output_scale"])
    c_proj_output_requant_shift = args.c_proj_output_requant_shift
    c_proj_effective_scales = [
        post_gelu_scale * weight_scale
        for weight_scale in c_proj_weight_scales
    ]
    c_proj_output_scale_mul_values = [
        round((scale / output_scale) * (1 << c_proj_output_requant_shift))
        for scale in c_proj_effective_scales
    ]
    c_proj_output_bias_q_values = [
        round(value / output_scale)
        for value in c_proj_bias
    ]
    c_proj_output_q = [
        fixed_c_proj_output_q(
            acc,
            c_proj_output_scale_mul_values[index],
            c_proj_output_bias_q_values[index],
            c_proj_output_requant_shift,
        )
        for index, acc in enumerate(c_proj_accs)
    ]
    c_proj_output_dequantized = [
        value * output_scale
        for value in c_proj_output_q
    ]

    f32_output_metrics = score_error(c_proj_f32_dequantized, c_proj_expected)
    int8_output_metrics = score_error(c_proj_output_dequantized, c_proj_expected)
    post_gelu_input_metrics = score_error(
        post_gelu_dequantized,
        c_proj_activation_in,
    )
    c_proj_input_relation_metrics = score_error(
        c_proj_activation_in,
        gelu_tanh(c_fc_expected),
    )

    c_fc_activation_blob = pack_i8(c_fc_activation_q)
    c_fc_weight_blob = pack_i8(c_fc_weight_q)
    c_fc_packed_blob = pack_u32(c_fc_packed_words)
    c_fc_acc_blob = pack_i32(c_fc_accs)
    c_fc_scale_mul_blob = pack_i32(c_fc_scale_mul_values)
    c_fc_bias_q_blob = pack_i32(c_fc_bias_q_values)
    post_gelu_blob = pack_i8(post_gelu_q)
    c_proj_weight_blob = pack_i8(c_proj_weight_q)
    c_proj_packed_blob = pack_u32(c_proj_packed_words)
    c_proj_acc_blob = pack_i32(c_proj_accs)
    c_proj_output_scale_mul_blob = pack_i32(c_proj_output_scale_mul_values)
    c_proj_output_bias_q_blob = pack_i32(c_proj_output_bias_q_values)
    c_proj_output_q_blob = pack_i8(c_proj_output_q)

    boundary_output_sha = output_boundary["int8_output_candidate"].get("output_q_sha256")
    output_q_sha = hashlib.sha256(c_proj_output_q_blob).hexdigest()
    output_boundary_match = boundary_output_sha is None or boundary_output_sha == output_q_sha
    c_proj_acc_sha = hashlib.sha256(c_proj_acc_blob).hexdigest()
    boundary_acc_sha = output_boundary.get("accumulator_boundary", {}).get(
        "accumulator_sha256"
    )
    accumulator_match = boundary_acc_sha is None or boundary_acc_sha == c_proj_acc_sha

    sim_result = load_json(args.sim_result_json) if args.sim_result_json else None
    sim_pass = sim_result is not None and sim_result.get("status") == "PASS"
    upstream_pass = (
        post_gelu.get("status") == "PASS"
        and output_boundary.get("status") == "PASS"
        and accumulator_match
    )
    score_pass = (
        upstream_pass
        and int8_output_metrics["normalized_rmse"] <= args.normalized_rmse_threshold
    )
    status = "PASS" if score_pass and sim_pass else "FAIL"
    if sim_result is None and score_pass:
        status = "partial"
    if status == "PASS":
        verdict = "promote"
        next_gate = "capture and score the residual add boundary after c_proj"
    elif status == "partial":
        verdict = "continue"
        next_gate = "run Verilator, Yosys, and mapped utilization for the c_proj requant RTL proof"
    else:
        verdict = "stop"
        next_gate = "fix the c_proj requant/output-memory proof before downstream integration"

    payload: dict[str, Any] = {
        "artifact_name": args.artifact_name,
        "status": status,
        "source_artifacts": {
            "c_fc_contract_manifest": str(args.c_fc_contract_manifest),
            "c_fc_weight_pack_manifest": str(args.c_fc_weight_pack_manifest),
            "c_proj_contract_manifest": str(args.c_proj_contract_manifest),
            "c_proj_weight_pack_manifest": str(args.c_proj_weight_pack_manifest),
            "post_gelu_requant_json": str(args.post_gelu_requant_json),
            "c_proj_output_boundary_json": str(args.c_proj_output_boundary_json),
            "model_label": c_proj_contract["model_label"],
        },
        "replacement_region": {
            "producer": c_fc_contract["module_name"],
            "boundary": "c_fc_to_post_gelu_to_c_proj_int8_output",
            "consumer": c_proj_contract["module_name"],
            "interpretation": (
                "Composed RTL proof for c_fc -> fixed-point GELU -> int8 "
                "activation handoff -> c_proj -> fixed-point int8 output requant."
            ),
        },
        "rtl_contract": {
            "top_name": "task6_int8_l2_mlp_chain_post_gelu_c_proj_requant_kernel",
            "c_fc_in_dim": c_fc_in_features,
            "hidden_dim": c_fc_out_features,
            "c_proj_out_dim": c_proj_out_features,
            "lane_count": lanes,
            "c_fc_packed_weight_words": len(c_fc_packed_words),
            "c_proj_packed_weight_words": len(c_proj_packed_words),
            "activation_dtype": "int8",
            "weight_dtype": "int8",
            "handoff_dtype": "int8",
            "c_proj_accumulator_dtype": "int32",
            "output_dtype": "int8",
            "activation_quantization": "int8-per-tensor-symmetric",
            "c_fc_weight_quantization": "int8-per-output-symmetric",
            "handoff_quantization": "post-GELU int8-per-tensor-symmetric",
            "c_proj_weight_quantization": "int8-per-output-symmetric",
            "output_quantization": "int8-per-tensor-symmetric",
            "local_output_memory": True,
        },
        "fixed_point": {
            "x_frac": x_frac,
            "scale_shift": scale_shift,
            "gelu_approximation": "0.5*x + 0.39894228*x*x",
            "gelu_quad_q": gelu_quad_q,
            "output_requant_shift": output_requant_shift,
            "output_requant_mult": output_requant_mult,
            "c_proj_output_requant_shift": c_proj_output_requant_shift,
            "c_proj_postprocess_formula": (
                "q[i] = saturate_i8(round_shift(acc[i] * scale_mul[i], "
                "c_proj_output_requant_shift) + bias_q[i])"
            ),
        },
        "quantization": {
            "normalized_rmse_threshold": args.normalized_rmse_threshold,
            "c_fc_activation_scale": c_fc_activation_scale,
            "post_gelu_output_scale": post_gelu_scale,
            "c_proj_output_scale": output_scale,
            "c_fc_effective_scale_min": min(c_fc_effective_scales),
            "c_fc_effective_scale_max": max(c_fc_effective_scales),
            "c_fc_scale_mul_min": min(c_fc_scale_mul_values),
            "c_fc_scale_mul_max": max(c_fc_scale_mul_values),
            "c_fc_bias_q_min": min(c_fc_bias_q_values),
            "c_fc_bias_q_max": max(c_fc_bias_q_values),
            "post_gelu_q_min": min(post_gelu_q),
            "post_gelu_q_max": max(post_gelu_q),
            "c_proj_weight_scale_min": min(c_proj_weight_scales),
            "c_proj_weight_scale_max": max(c_proj_weight_scales),
            "c_proj_accumulator_min": min(c_proj_accs),
            "c_proj_accumulator_max": max(c_proj_accs),
            "c_proj_output_scale_mul_min": min(c_proj_output_scale_mul_values),
            "c_proj_output_scale_mul_max": max(c_proj_output_scale_mul_values),
            "c_proj_output_bias_q_min": min(c_proj_output_bias_q_values),
            "c_proj_output_bias_q_max": max(c_proj_output_bias_q_values),
            "c_proj_output_q_min": min(c_proj_output_q),
            "c_proj_output_q_max": max(c_proj_output_q),
            "c_fc_activation_q_sha256": hashlib.sha256(c_fc_activation_blob).hexdigest(),
            "c_fc_weight_q_sha256": hashlib.sha256(c_fc_weight_blob).hexdigest(),
            "c_fc_packed_weight_sha256": hashlib.sha256(c_fc_packed_blob).hexdigest(),
            "c_fc_accumulator_sha256": hashlib.sha256(c_fc_acc_blob).hexdigest(),
            "c_fc_scale_mul_sha256": hashlib.sha256(c_fc_scale_mul_blob).hexdigest(),
            "c_fc_bias_q_sha256": hashlib.sha256(c_fc_bias_q_blob).hexdigest(),
            "post_gelu_q_sha256": hashlib.sha256(post_gelu_blob).hexdigest(),
            "c_proj_weight_q_sha256": hashlib.sha256(c_proj_weight_blob).hexdigest(),
            "c_proj_packed_weight_sha256": hashlib.sha256(c_proj_packed_blob).hexdigest(),
            "c_proj_accumulator_sha256": c_proj_acc_sha,
            "c_proj_output_scale_mul_sha256": hashlib.sha256(
                c_proj_output_scale_mul_blob
            ).hexdigest(),
            "c_proj_output_bias_q_sha256": hashlib.sha256(
                c_proj_output_bias_q_blob
            ).hexdigest(),
            "c_proj_output_q_sha256": output_q_sha,
            "c_proj_output_boundary_q_sha256": boundary_output_sha,
            "c_proj_output_matches_boundary_quantizer": output_boundary_match,
            "c_proj_accumulator_matches_boundary": accumulator_match,
        },
        "metrics": {
            "c_proj_input_vs_gelu_c_fc_expected": c_proj_input_relation_metrics,
            "post_gelu_int8_vs_c_proj_input": post_gelu_input_metrics,
            "c_proj_f32_output_from_chain_accumulators": f32_output_metrics,
            "c_proj_int8_output_from_fixed_requant": int8_output_metrics,
        },
        "byte_budget": {
            "c_fc_activation_int8_bytes": len(c_fc_activation_q),
            "c_fc_packed_weight_bytes": len(c_fc_packed_words) * 4,
            "c_fc_scale_mul_sidecar_bytes": len(c_fc_scale_mul_values) * 4,
            "c_fc_bias_q_sidecar_bytes": len(c_fc_bias_q_values) * 4,
            "handoff_int8_activation_bytes": len(post_gelu_q),
            "c_proj_packed_weight_bytes": len(c_proj_packed_words) * 4,
            "c_proj_accumulator_output_bytes": len(c_proj_accs) * 4,
            "c_proj_output_scale_mul_sidecar_bytes": len(
                c_proj_output_scale_mul_values
            ) * 4,
            "c_proj_output_bias_q_sidecar_bytes": len(c_proj_output_bias_q_values) * 4,
            "c_proj_int8_output_bytes": len(c_proj_output_q),
            "c_proj_f32_output_bytes_replaced": len(c_proj_output_q) * 4,
            "c_proj_int8_output_write_savings_vs_f32_bytes": len(c_proj_output_q) * 3,
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
        f"localparam int C_FC_IN_DIM = {c_fc_in_features};",
        f"localparam int HIDDEN_DIM = {c_fc_out_features};",
        f"localparam int C_PROJ_OUT_DIM = {c_proj_out_features};",
        f"localparam int TILE_OUT_DIM = {tile_out_dim};",
        f"localparam int LANES = {lanes};",
        f"localparam int C_FC_PACKED_WEIGHT_WORDS = {len(c_fc_packed_words)};",
        f"localparam int C_PROJ_PACKED_WEIGHT_WORDS = {len(c_proj_packed_words)};",
        f"localparam int C_FC_PACKED_WEIGHT_ADDR_WIDTH = {addr_width(len(c_fc_packed_words))};",
        f"localparam int C_PROJ_PACKED_WEIGHT_ADDR_WIDTH = {addr_width(len(c_proj_packed_words))};",
        f"localparam int C_FC_ACTIVATION_ADDR_WIDTH = {addr_width(c_fc_in_features)};",
        f"localparam int HIDDEN_ADDR_WIDTH = {addr_width(c_fc_out_features)};",
        f"localparam int C_PROJ_OUT_ADDR_WIDTH = {addr_width(c_proj_out_features)};",
        f"localparam int X_FRAC = {x_frac};",
        f"localparam int SCALE_SHIFT = {scale_shift};",
        f"localparam int GELU_QUAD_Q = {gelu_quad_q};",
        f"localparam int OUTPUT_REQUANT_SHIFT = {output_requant_shift};",
        f"localparam int OUTPUT_REQUANT_MULT = {output_requant_mult};",
        f"localparam int C_PROJ_OUTPUT_REQUANT_SHIFT = {c_proj_output_requant_shift};",
        "logic signed [7:0] c_fc_activation_values [0:C_FC_IN_DIM - 1];",
        "logic [LANES * 8 - 1:0] c_fc_packed_weight_values [0:C_FC_PACKED_WEIGHT_WORDS - 1];",
        "logic signed [31:0] c_fc_requant_scale_mul_values [0:HIDDEN_DIM - 1];",
        "logic signed [31:0] c_fc_requant_bias_q_values [0:HIDDEN_DIM - 1];",
        "logic [LANES * 8 - 1:0] c_proj_packed_weight_values [0:C_PROJ_PACKED_WEIGHT_WORDS - 1];",
        "logic signed [31:0] c_proj_requant_scale_mul_values [0:C_PROJ_OUT_DIM - 1];",
        "logic signed [31:0] c_proj_requant_bias_q_values [0:C_PROJ_OUT_DIM - 1];",
        "logic signed [7:0] expected_c_proj_output_q_values [0:C_PROJ_OUT_DIM - 1];",
        "logic signed [31:0] expected_c_proj_acc_values [0:C_PROJ_OUT_DIM - 1];",
        "initial begin",
    ]
    for index, value in enumerate(c_fc_activation_q):
        sv_lines.append(f"  c_fc_activation_values[{index}] = 8'sh{signed_hex(value, 8)};")
    for index, value in enumerate(c_fc_packed_words):
        sv_lines.append(f"  c_fc_packed_weight_values[{index}] = 32'h{value:08x};")
    for index, value in enumerate(c_fc_scale_mul_values):
        sv_lines.append(
            f"  c_fc_requant_scale_mul_values[{index}] = 32'sh{signed_hex(value, 32)};"
        )
    for index, value in enumerate(c_fc_bias_q_values):
        sv_lines.append(
            f"  c_fc_requant_bias_q_values[{index}] = 32'sh{signed_hex(value, 32)};"
        )
    for index, value in enumerate(c_proj_packed_words):
        sv_lines.append(f"  c_proj_packed_weight_values[{index}] = 32'h{value:08x};")
    for index, value in enumerate(c_proj_output_scale_mul_values):
        sv_lines.append(
            f"  c_proj_requant_scale_mul_values[{index}] = 32'sh{signed_hex(value, 32)};"
        )
    for index, value in enumerate(c_proj_output_bias_q_values):
        sv_lines.append(
            f"  c_proj_requant_bias_q_values[{index}] = 32'sh{signed_hex(value, 32)};"
        )
    for index, value in enumerate(c_proj_output_q):
        sv_lines.append(
            f"  expected_c_proj_output_q_values[{index}] = 8'sh{signed_hex(value, 8)};"
        )
    for index, value in enumerate(c_proj_accs):
        sv_lines.append(
            f"  expected_c_proj_acc_values[{index}] = 32'sh{signed_hex(value, 32)};"
        )
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
