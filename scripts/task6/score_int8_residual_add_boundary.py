#!/usr/bin/env python3
"""Score residual-add boundaries after the H2 int8 c_proj output proof."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
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
    round_shift_signed,
    saturate_i8,
    score_error,
    tensor_by_name,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--residual-contract-manifest", required=True, type=Path)
    parser.add_argument("--c-fc-contract-manifest", required=True, type=Path)
    parser.add_argument("--c-fc-weight-pack-manifest", required=True, type=Path)
    parser.add_argument("--c-proj-contract-manifest", required=True, type=Path)
    parser.add_argument("--c-proj-weight-pack-manifest", required=True, type=Path)
    parser.add_argument("--post-gelu-requant-json", required=True, type=Path)
    parser.add_argument("--c-proj-output-boundary-json", required=True, type=Path)
    parser.add_argument("--c-proj-requant-rtl-proof-json", required=True, type=Path)
    parser.add_argument("--out-json", required=True, type=Path)
    parser.add_argument(
        "--artifact-name",
        default="h2-int8-l2-residual-add-boundary",
    )
    parser.add_argument("--normalized-rmse-threshold", type=float, default=0.02)
    return parser.parse_args()


def quantize_with_scale(values: list[float], scale: float) -> list[int]:
    if scale == 0.0:
        return [0 for _ in values]
    return [
        max(-127, min(127, int(round(value / scale))))
        for value in values
    ]


def fixed_c_proj_output_q(
    acc: int,
    scale_mul: int,
    bias_q: int,
    shift: int,
) -> int:
    scaled_q = round_shift_signed(acc * scale_mul, shift)
    return saturate_i8(scaled_q + bias_q)


def build_c_proj_int8_output(
    args: argparse.Namespace,
) -> tuple[list[int], list[float], dict[str, Any]]:
    c_fc_weight_pack = load_json(args.c_fc_weight_pack_manifest)
    c_proj_weight_pack = load_json(args.c_proj_weight_pack_manifest)
    post_gelu = load_json(args.post_gelu_requant_json)
    output_boundary = load_json(args.c_proj_output_boundary_json)
    proof = load_json(args.c_proj_requant_rtl_proof_json)

    c_fc_activation = load_contract_tensor(args.c_fc_contract_manifest, "activation_in")
    c_fc_expected = load_contract_tensor(args.c_fc_contract_manifest, "activation_out")
    c_proj_activation_in = load_contract_tensor(
        args.c_proj_contract_manifest,
        "activation_in",
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

    output_scale = float(output_boundary["int8_output_candidate"]["output_scale"])
    c_proj_output_requant_shift = int(
        proof.get("fixed_point", {}).get("c_proj_output_requant_shift", 24)
    )
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
    c_proj_output_dequantized = [value * output_scale for value in c_proj_output_q]

    metadata = {
        "post_gelu_q": post_gelu_q,
        "post_gelu_scale": post_gelu_scale,
        "c_proj_output_scale": output_scale,
        "c_proj_output_q_sha256": hashlib.sha256(pack_i8(c_proj_output_q)).hexdigest(),
        "c_proj_output_q_min": min(c_proj_output_q),
        "c_proj_output_q_max": max(c_proj_output_q),
        "c_proj_accumulator_sha256": hashlib.sha256(pack_i32(c_proj_accs)).hexdigest(),
        "c_proj_output_scale_mul_sha256": hashlib.sha256(
            pack_i32(c_proj_output_scale_mul_values)
        ).hexdigest(),
        "c_proj_output_bias_q_sha256": hashlib.sha256(
            pack_i32(c_proj_output_bias_q_values)
        ).hexdigest(),
        "post_gelu_int8_vs_c_proj_input": score_error(
            post_gelu_dequantized,
            c_proj_activation_in,
        ),
        "c_proj_input_vs_gelu_c_fc_expected": score_error(
            c_proj_activation_in,
            gelu_tanh(c_fc_expected),
        ),
    }
    return c_proj_output_q, c_proj_output_dequantized, metadata


def main() -> None:
    args = parse_args()
    residual_contract = load_json(args.residual_contract_manifest)
    c_proj_output_boundary = load_json(args.c_proj_output_boundary_json)
    c_proj_requant_proof = load_json(args.c_proj_requant_rtl_proof_json)

    residual_f32 = load_contract_tensor(
        args.residual_contract_manifest,
        "residual_activation_in",
    )
    c_proj_expected = load_contract_tensor(
        args.residual_contract_manifest,
        "c_proj_activation_out",
    )
    block_output = load_contract_tensor(
        args.residual_contract_manifest,
        "block_output",
    )
    residual_add_f32 = load_contract_tensor(
        args.residual_contract_manifest,
        "residual_add_f32",
    )

    c_proj_output_q, c_proj_output_dequantized, q_metadata = build_c_proj_int8_output(args)

    residual_plus_c_proj_contract = [
        left + right for left, right in zip(residual_f32, c_proj_expected)
    ]
    residual_plus_c_proj_int8 = [
        left + right for left, right in zip(residual_f32, c_proj_output_dequantized)
    ]

    residual_q, residual_scale = quantize_symmetric(residual_f32, 8)
    residual_dequantized = [value * residual_scale for value in residual_q]
    int8_residual_plus_int8_c_proj = [
        left + right for left, right in zip(residual_dequantized, c_proj_output_dequantized)
    ]

    final_output_scale = max(
        (abs(value) for value in int8_residual_plus_int8_c_proj),
        default=0.0,
    ) / 127.0
    if final_output_scale == 0.0:
        final_output_scale = 1.0
    final_output_q = quantize_with_scale(
        int8_residual_plus_int8_c_proj,
        final_output_scale,
    )
    final_output_dequantized = [
        value * final_output_scale for value in final_output_q
    ]

    metrics = {
        "captured_residual_add_f32_vs_block_output": score_error(
            residual_add_f32,
            block_output,
        ),
        "residual_plus_c_proj_contract_vs_block_output": score_error(
            residual_plus_c_proj_contract,
            block_output,
        ),
        "f32_residual_plus_int8_c_proj_vs_block_output": score_error(
            residual_plus_c_proj_int8,
            block_output,
        ),
        "int8_residual_plus_int8_c_proj_vs_block_output": score_error(
            int8_residual_plus_int8_c_proj,
            block_output,
        ),
        "int8_final_residual_add_output_vs_block_output": score_error(
            final_output_dequantized,
            block_output,
        ),
    }

    proof_q_sha = c_proj_requant_proof.get("quantization", {}).get(
        "c_proj_output_q_sha256"
    )
    boundary_q_sha = c_proj_output_boundary.get("int8_output_candidate", {}).get(
        "output_q_sha256"
    )
    q_hash_matches = (
        q_metadata["c_proj_output_q_sha256"] == proof_q_sha
        and q_metadata["c_proj_output_q_sha256"] == boundary_q_sha
    )
    upstream_pass = (
        residual_contract.get("status") == "PASS"
        and c_proj_requant_proof.get("status") == "PASS"
        and q_hash_matches
    )
    main_pass = (
        metrics["f32_residual_plus_int8_c_proj_vs_block_output"]["normalized_rmse"]
        <= args.normalized_rmse_threshold
    )
    residual_int8_pass = (
        metrics["int8_residual_plus_int8_c_proj_vs_block_output"]["normalized_rmse"]
        <= args.normalized_rmse_threshold
    )
    final_output_int8_pass = (
        metrics["int8_final_residual_add_output_vs_block_output"]["normalized_rmse"]
        <= args.normalized_rmse_threshold
    )
    overall_pass = (
        upstream_pass
        and main_pass
        and residual_int8_pass
        and final_output_int8_pass
    )

    payload = {
        "artifact_name": args.artifact_name,
        "status": "PASS" if overall_pass else "FAIL",
        "source_artifacts": {
            "residual_contract_manifest": str(args.residual_contract_manifest),
            "c_fc_contract_manifest": str(args.c_fc_contract_manifest),
            "c_fc_weight_pack_manifest": str(args.c_fc_weight_pack_manifest),
            "c_proj_contract_manifest": str(args.c_proj_contract_manifest),
            "c_proj_weight_pack_manifest": str(args.c_proj_weight_pack_manifest),
            "post_gelu_requant_json": str(args.post_gelu_requant_json),
            "c_proj_output_boundary_json": str(args.c_proj_output_boundary_json),
            "c_proj_requant_rtl_proof_json": str(args.c_proj_requant_rtl_proof_json),
        },
        "replacement_region": {
            "producer": "transformer.h.0.mlp.c_proj",
            "boundary": "post_c_proj_residual_add",
            "consumer": "transformer.h.0 block output",
            "interpretation": (
                "Score whether the promoted int8 c_proj output can feed the "
                "post-MLP residual add without breaking the captured block output."
            ),
        },
        "quantization": {
            "normalized_rmse_threshold": args.normalized_rmse_threshold,
            "residual_scale": residual_scale,
            "residual_q_min": min(residual_q),
            "residual_q_max": max(residual_q),
            "residual_q_sha256": hashlib.sha256(pack_i8(residual_q)).hexdigest(),
            "c_proj_output_scale": q_metadata["c_proj_output_scale"],
            "c_proj_output_q_min": q_metadata["c_proj_output_q_min"],
            "c_proj_output_q_max": q_metadata["c_proj_output_q_max"],
            "c_proj_output_q_sha256": q_metadata["c_proj_output_q_sha256"],
            "c_proj_output_proof_q_sha256": proof_q_sha,
            "c_proj_output_boundary_q_sha256": boundary_q_sha,
            "c_proj_output_q_hash_matches": q_hash_matches,
            "final_output_scale": final_output_scale,
            "final_output_q_min": min(final_output_q),
            "final_output_q_max": max(final_output_q),
            "final_output_q_sha256": hashlib.sha256(pack_i8(final_output_q)).hexdigest(),
        },
        "upstream_metrics": {
            "post_gelu_int8_vs_c_proj_input": q_metadata[
                "post_gelu_int8_vs_c_proj_input"
            ],
            "c_proj_input_vs_gelu_c_fc_expected": q_metadata[
                "c_proj_input_vs_gelu_c_fc_expected"
            ],
        },
        "metrics": metrics,
        "byte_budget": {
            "residual_f32_bytes": len(residual_f32) * 4,
            "residual_int8_bytes": len(residual_q),
            "c_proj_int8_output_bytes": len(c_proj_output_q),
            "c_proj_output_scale_bytes": 4,
            "final_residual_add_int8_output_bytes": len(final_output_q),
            "final_output_scale_bytes": 4,
            "residual_int8_savings_vs_f32_bytes": len(residual_f32) * 3,
            "final_output_int8_savings_vs_f32_bytes": len(final_output_q) * 3,
        },
        "decision": {
            "verdict": (
                "promote-f32-residual-plus-int8-c-proj"
                if overall_pass
                else "stop"
            ),
            "residual_int8_verdict": "pass" if residual_int8_pass else "fail",
            "final_output_int8_verdict": "pass" if final_output_int8_pass else "fail",
            "next_gate": (
                "implement a bounded residual-add RTL proof"
                if overall_pass
                else "fix residual-add boundary score before RTL"
            ),
        },
    }

    args.out_json.parent.mkdir(parents=True, exist_ok=True)
    args.out_json.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
