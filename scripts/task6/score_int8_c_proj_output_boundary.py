#!/usr/bin/env python3
"""Score post-c_proj output boundaries for the H2 int8 MLP chain."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import struct
from typing import Any

from score_int8_c_proj_from_post_gelu import (
    compute_accumulators,
    fixed_post_gelu_q,
    gelu_tanh,
    load_contract_tensor,
    load_f32,
    load_json,
    pack_i8,
    pack_i32,
    product,
    quantize_per_output_symmetric,
    quantize_symmetric,
    score_error,
    tensor_by_name,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--c-fc-contract-manifest", required=True, type=Path)
    parser.add_argument("--c-fc-weight-pack-manifest", required=True, type=Path)
    parser.add_argument("--c-proj-contract-manifest", required=True, type=Path)
    parser.add_argument("--c-proj-weight-pack-manifest", required=True, type=Path)
    parser.add_argument("--post-gelu-requant-json", required=True, type=Path)
    parser.add_argument("--mlp-chain-rtl-proof-json", required=True, type=Path)
    parser.add_argument("--c-proj-candidate-json", type=Path)
    parser.add_argument("--out-json", required=True, type=Path)
    parser.add_argument("--normalized-rmse-threshold", type=float, default=0.02)
    return parser.parse_args()


def pack_f32(values: list[float]) -> bytes:
    return struct.pack(f"<{len(values)}f", *[float(value) for value in values])


def quantize_with_scale(values: list[float], scale: float) -> list[int]:
    if scale == 0.0:
        return [0 for _ in values]
    return [
        max(-127, min(127, int(round(value / scale))))
        for value in values
    ]


def extract_next_linalg_context(candidate_path: Path | None) -> dict[str, Any] | None:
    if candidate_path is None:
        return None
    candidate = load_json(candidate_path)
    selected = candidate.get("selected_candidate", {})
    context = selected.get("context", [])
    next_lines = [
        row
        for row in context
        if int(row.get("line_number", -1)) > int(selected.get("line_number", -1))
    ]
    return {
        "candidate_json": str(candidate_path),
        "selected_line": selected.get("line_number"),
        "selected_value": selected.get("result_value"),
        "next_lines": next_lines,
        "interpretation": (
            "The captured Linalg context shows c_proj bias add immediately after "
            "the matmul, then a same-shape add with another 1x1x64 tensor. A "
            "residual/add proof needs that residual tensor captured explicitly."
        ),
    }


def main() -> None:
    args = parse_args()
    c_fc_contract = load_json(args.c_fc_contract_manifest)
    c_fc_weight_pack = load_json(args.c_fc_weight_pack_manifest)
    c_proj_contract = load_json(args.c_proj_contract_manifest)
    c_proj_weight_pack = load_json(args.c_proj_weight_pack_manifest)
    post_gelu = load_json(args.post_gelu_requant_json)
    chain_proof = load_json(args.mlp_chain_rtl_proof_json)

    c_fc_activation = load_contract_tensor(args.c_fc_contract_manifest, "activation_in")
    c_fc_expected = load_contract_tensor(args.c_fc_contract_manifest, "activation_out")
    c_proj_activation_in = load_contract_tensor(
        args.c_proj_contract_manifest,
        "activation_in",
    )
    c_proj_expected = load_contract_tensor(
        args.c_proj_contract_manifest,
        "activation_out",
    )

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
    c_fc_out_features, c_fc_in_features = [
        int(value) for value in c_fc_weight_meta["shape"]
    ]
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

    c_proj_acc_sha = hashlib.sha256(pack_i32(c_proj_accs)).hexdigest()
    expected_acc_sha = (
        chain_proof.get("quantization", {}).get("c_proj_accumulator_sha256")
    )
    f32_metrics = score_error(c_proj_dequantized, c_proj_expected)

    output_scale = max((abs(value) for value in c_proj_expected), default=0.0) / 127.0
    if output_scale == 0.0:
        output_scale = 1.0
    c_proj_output_q = quantize_with_scale(c_proj_dequantized, output_scale)
    c_proj_output_int8_dequantized = [
        value * output_scale
        for value in c_proj_output_q
    ]
    int8_metrics = score_error(c_proj_output_int8_dequantized, c_proj_expected)
    f32_pass = f32_metrics["normalized_rmse"] <= args.normalized_rmse_threshold
    int8_pass = int8_metrics["normalized_rmse"] <= args.normalized_rmse_threshold
    upstream_pass = (
        chain_proof.get("status") == "PASS"
        and post_gelu.get("status") == "PASS"
        and (expected_acc_sha is None or expected_acc_sha == c_proj_acc_sha)
    )

    effective_scales = [
        post_gelu_scale * weight_scale
        for weight_scale in c_proj_weight_scales
    ]
    effective_scale_blob = pack_f32(effective_scales)
    bias_blob = pack_f32(c_proj_bias)
    dequantized_blob = pack_f32(c_proj_dequantized)
    output_q_blob = pack_i8(c_proj_output_q)

    payload = {
        "artifact_name": "h2-int8-l2-c-proj-output-boundary",
        "status": "PASS" if upstream_pass and f32_pass else "FAIL",
        "source_artifacts": {
            "c_fc_contract_manifest": str(args.c_fc_contract_manifest),
            "c_fc_weight_pack_manifest": str(args.c_fc_weight_pack_manifest),
            "c_proj_contract_manifest": str(args.c_proj_contract_manifest),
            "c_proj_weight_pack_manifest": str(args.c_proj_weight_pack_manifest),
            "post_gelu_requant_json": str(args.post_gelu_requant_json),
            "mlp_chain_rtl_proof_json": str(args.mlp_chain_rtl_proof_json),
            "c_proj_candidate_json": (
                str(args.c_proj_candidate_json)
                if args.c_proj_candidate_json is not None
                else None
            ),
        },
        "replacement_region": {
            "producer": c_fc_contract["module_name"],
            "consumer": c_proj_contract["module_name"],
            "boundary": "c_proj_output",
            "interpretation": (
                "Score the output side of the composed int8 MLP chain after "
                "the c_proj int32 accumulators."
            ),
        },
        "module": {
            "model_label": c_proj_contract["model_label"],
            "c_proj_in_features": c_proj_in_features,
            "c_proj_out_features": c_proj_out_features,
            "c_proj_macs": c_proj_in_features * c_proj_out_features,
        },
        "input_boundary": {
            "activation_dtype": "post-GELU int8",
            "activation_scale": post_gelu_scale,
            "activation_q_min": min(post_gelu_q),
            "activation_q_max": max(post_gelu_q),
            "activation_q_sha256": hashlib.sha256(pack_i8(post_gelu_q)).hexdigest(),
            "activation_vs_c_proj_input": score_error(
                post_gelu_dequantized,
                c_proj_activation_in,
            ),
            "c_proj_input_vs_gelu_c_fc_expected": score_error(
                c_proj_activation_in,
                gelu_tanh(c_fc_expected),
            ),
        },
        "accumulator_boundary": {
            "accumulator_dtype": "int32",
            "accumulator_min": min(c_proj_accs),
            "accumulator_max": max(c_proj_accs),
            "accumulator_sha256": c_proj_acc_sha,
            "chain_proof_accumulator_sha256": expected_acc_sha,
            "matches_chain_proof": expected_acc_sha is None or expected_acc_sha == c_proj_acc_sha,
        },
        "f32_output_candidate": {
            "boundary": "int32_accumulator_to_f32_output",
            "formula": "f32_out[i] = int32_acc[i] * post_gelu_scale * weight_scale[i] + bias[i]",
            "scale_dtype": "float32",
            "bias_dtype": "float32",
            "output_dtype": "float32",
            "effective_scale_min": min(effective_scales),
            "effective_scale_max": max(effective_scales),
            "effective_scale_sha256": hashlib.sha256(effective_scale_blob).hexdigest(),
            "bias_sha256": hashlib.sha256(bias_blob).hexdigest(),
            "dequantized_output_sha256": hashlib.sha256(dequantized_blob).hexdigest(),
            "metrics": f32_metrics,
            "verdict": "pass" if f32_pass else "fail",
        },
        "int8_output_candidate": {
            "boundary": "int32_accumulator_to_int8_output",
            "calibration": "single captured c_proj activation_out max-abs scale",
            "output_scale": output_scale,
            "output_q_min": min(c_proj_output_q),
            "output_q_max": max(c_proj_output_q),
            "output_q_sha256": hashlib.sha256(output_q_blob).hexdigest(),
            "metrics": int8_metrics,
            "verdict": "pass" if int8_pass else "fail",
            "calibration_caveat": (
                "A production output scale still needs a calibration set before "
                "board-level claims."
            ),
        },
        "byte_budget": {
            "c_proj_accumulator_int32_bytes": len(c_proj_accs) * 4,
            "c_proj_effective_scale_f32_bytes": len(effective_scales) * 4,
            "c_proj_bias_f32_bytes": len(c_proj_bias) * 4,
            "c_proj_f32_output_bytes": len(c_proj_dequantized) * 4,
            "c_proj_int8_output_bytes": len(c_proj_output_q),
            "c_proj_int8_output_scale_bytes": 4,
            "f32_output_postprocess_read_write_bytes": (
                len(c_proj_accs) * 4
                + len(effective_scales) * 4
                + len(c_proj_bias) * 4
                + len(c_proj_dequantized) * 4
            ),
            "int8_output_write_savings_vs_f32_bytes": (
                len(c_proj_dequantized) * 4 - len(c_proj_output_q)
            ),
        },
        "mapped_chain_reference": chain_proof.get("mapped_utilization", {}),
        "next_linalg_context": extract_next_linalg_context(args.c_proj_candidate_json),
        "decision": {
            "verdict": (
                "promote-int8-output-boundary"
                if upstream_pass and int8_pass
                else ("promote-f32-output-boundary" if upstream_pass and f32_pass else "stop")
            ),
            "next_gate": (
                "implement a bounded fixed-point c_proj requant/output-memory RTL proof"
                if upstream_pass and int8_pass
                else (
                    "keep f32 scale/bias output boundary and capture the residual add tensor"
                    if upstream_pass and f32_pass
                    else "fix the c_proj output boundary before downstream integration"
                )
            ),
        },
    }

    args.out_json.parent.mkdir(parents=True, exist_ok=True)
    args.out_json.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
