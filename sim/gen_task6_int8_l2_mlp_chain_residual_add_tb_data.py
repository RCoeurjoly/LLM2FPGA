#!/usr/bin/env python3
"""Emit RTL replay data for the composed int8 L2 MLP residual-add proof."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

from gen_task6_int8_l2_c_proj_from_post_gelu_tb_data import (
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
    signed_hex,
    tensor_by_name,
)
from gen_task6_int8_l2_mlp_chain_c_proj_requant_tb_data import (
    build_payload as build_c_proj_requant_payload,
    fixed_c_proj_output_q,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--residual-contract-manifest", required=True, type=Path)
    parser.add_argument("--residual-boundary-json", required=True, type=Path)
    parser.add_argument("--c-fc-contract-manifest", required=True, type=Path)
    parser.add_argument("--c-fc-weight-pack-manifest", required=True, type=Path)
    parser.add_argument("--c-proj-contract-manifest", required=True, type=Path)
    parser.add_argument("--c-proj-weight-pack-manifest", required=True, type=Path)
    parser.add_argument("--post-gelu-requant-json", required=True, type=Path)
    parser.add_argument("--c-proj-output-boundary-json", required=True, type=Path)
    parser.add_argument("--c-proj-requant-rtl-proof-json", required=True, type=Path)
    parser.add_argument(
        "--artifact-name",
        default="h2-int8-l2-mlp-chain-residual-add-rtl-proof",
    )
    parser.add_argument("--out-sv", type=Path)
    parser.add_argument("--out-json", type=Path)
    parser.add_argument("--sim-result-json", type=Path)
    parser.add_argument("--yosys-stat-json", type=Path)
    parser.add_argument("--mapped-utilization-summary-json", type=Path)
    parser.add_argument("--normalized-rmse-threshold", type=float, default=0.02)
    parser.add_argument("--c-proj-output-requant-shift", type=int, default=24)
    parser.add_argument("--residual-add-requant-shift", type=int, default=24)
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
        "top_name": "task6_int8_l2_mlp_chain_residual_add_kernel",
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


def build_c_proj_int8_output(
    args: argparse.Namespace,
) -> tuple[list[int], list[float], dict[str, Any]]:
    c_fc_weight_pack = load_json(args.c_fc_weight_pack_manifest)
    c_proj_weight_pack = load_json(args.c_proj_weight_pack_manifest)
    post_gelu = load_json(args.post_gelu_requant_json)
    output_boundary = load_json(args.c_proj_output_boundary_json)

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
    c_proj_effective_scales = [
        post_gelu_scale * weight_scale
        for weight_scale in c_proj_weight_scales
    ]
    c_proj_output_scale_mul_values = [
        round((scale / output_scale) * (1 << args.c_proj_output_requant_shift))
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
            args.c_proj_output_requant_shift,
        )
        for index, acc in enumerate(c_proj_accs)
    ]
    c_proj_output_dequantized = [value * output_scale for value in c_proj_output_q]

    metadata = {
        "post_gelu_q_sha256": hashlib.sha256(pack_i8(post_gelu_q)).hexdigest(),
        "c_proj_accumulator_sha256": hashlib.sha256(pack_i32(c_proj_accs)).hexdigest(),
        "c_proj_output_scale": output_scale,
        "c_proj_output_q_sha256": hashlib.sha256(pack_i8(c_proj_output_q)).hexdigest(),
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


def quantize_with_scale(values: list[float], scale: float) -> list[int]:
    if scale == 0.0:
        return [0 for _ in values]
    return [
        saturate_i8(round(value / scale))
        for value in values
    ]


def inject_residual_add_data(
    base_sv: str,
    residual_q: list[int],
    expected_output_q: list[int],
    residual_requant_mult: int,
    c_proj_requant_mult: int,
    residual_add_requant_shift: int,
) -> str:
    lines = base_sv.strip().splitlines()
    try:
        initial_index = lines.index("initial begin")
    except ValueError as exc:
        raise SystemExit("base tb_data.sv did not contain an initial block") from exc
    if not lines or lines[-1] != "end":
        raise SystemExit("base tb_data.sv did not end with the expected initial block")

    declarations = [
        f"localparam int RESIDUAL_ADD_REQUANT_SHIFT = {residual_add_requant_shift};",
        (
            "localparam logic signed [31:0] RESIDUAL_REQUANT_MULT = "
            f"32'sh{signed_hex(residual_requant_mult, 32)};"
        ),
        (
            "localparam logic signed [31:0] C_PROJ_RESIDUAL_ADD_REQUANT_MULT = "
            f"32'sh{signed_hex(c_proj_requant_mult, 32)};"
        ),
        "logic signed [7:0] residual_q_values [0:C_PROJ_OUT_DIM - 1];",
        "logic signed [7:0] expected_residual_add_output_q_values [0:C_PROJ_OUT_DIM - 1];",
    ]
    assignments: list[str] = []
    for index, value in enumerate(residual_q):
        assignments.append(
            f"  residual_q_values[{index}] = 8'sh{signed_hex(value, 8)};"
        )
    for index, value in enumerate(expected_output_q):
        assignments.append(
            "  expected_residual_add_output_q_values"
            f"[{index}] = 8'sh{signed_hex(value, 8)};"
        )

    return (
        "\n".join(
            lines[:initial_index]
            + declarations
            + lines[initial_index:-1]
            + assignments
            + lines[-1:]
        )
        + "\n"
    )


def c_proj_requant_args(args: argparse.Namespace) -> argparse.Namespace:
    return argparse.Namespace(
        c_fc_contract_manifest=args.c_fc_contract_manifest,
        c_fc_weight_pack_manifest=args.c_fc_weight_pack_manifest,
        c_proj_contract_manifest=args.c_proj_contract_manifest,
        c_proj_weight_pack_manifest=args.c_proj_weight_pack_manifest,
        post_gelu_requant_json=args.post_gelu_requant_json,
        c_proj_output_boundary_json=args.c_proj_output_boundary_json,
        artifact_name="h2-int8-l2-mlp-chain-c-proj-requant-rtl-proof",
        out_sv=None,
        out_json=None,
        sim_result_json=None,
        yosys_stat_json=None,
        mapped_utilization_summary_json=None,
        normalized_rmse_threshold=args.normalized_rmse_threshold,
        c_proj_output_requant_shift=args.c_proj_output_requant_shift,
    )


def build_payload(args: argparse.Namespace) -> tuple[dict[str, Any], str]:
    c_proj_payload, base_sv = build_c_proj_requant_payload(c_proj_requant_args(args))
    residual_contract = load_json(args.residual_contract_manifest)
    residual_boundary = load_json(args.residual_boundary_json)
    c_proj_requant_proof = load_json(args.c_proj_requant_rtl_proof_json)

    residual_f32 = load_contract_tensor(
        args.residual_contract_manifest,
        "residual_activation_in",
    )
    block_output = load_contract_tensor(
        args.residual_contract_manifest,
        "block_output",
    )
    residual_q, residual_scale = quantize_symmetric(residual_f32, 8)
    residual_dequantized = [value * residual_scale for value in residual_q]

    c_proj_output_q, c_proj_output_dequantized, c_proj_metadata = (
        build_c_proj_int8_output(args)
    )

    final_output_scale = float(
        residual_boundary["quantization"]["final_output_scale"]
    )
    residual_requant_mult = round(
        (residual_scale / final_output_scale)
        * (1 << args.residual_add_requant_shift)
    )
    c_proj_requant_mult = round(
        (c_proj_metadata["c_proj_output_scale"] / final_output_scale)
        * (1 << args.residual_add_requant_shift)
    )
    fixed_output_q = [
        saturate_i8(
            round_shift_signed(
                residual_q[index] * residual_requant_mult
                + c_proj_output_q[index] * c_proj_requant_mult,
                args.residual_add_requant_shift,
            )
        )
        for index in range(len(residual_q))
    ]
    fixed_output_dequantized = [
        value * final_output_scale
        for value in fixed_output_q
    ]
    reference_output_q = quantize_with_scale(
        [
            residual_dequantized[index] + c_proj_output_dequantized[index]
            for index in range(len(residual_q))
        ],
        final_output_scale,
    )

    expected_final_sha = residual_boundary["quantization"].get(
        "final_output_q_sha256"
    )
    fixed_output_sha = hashlib.sha256(pack_i8(fixed_output_q)).hexdigest()
    reference_output_sha = hashlib.sha256(pack_i8(reference_output_q)).hexdigest()
    c_proj_output_sha = c_proj_metadata["c_proj_output_q_sha256"]
    c_proj_proof_sha = c_proj_requant_proof.get("quantization", {}).get(
        "c_proj_output_q_sha256"
    )
    c_proj_boundary_sha = residual_boundary["quantization"].get(
        "c_proj_output_q_sha256"
    )
    residual_boundary_sha = residual_boundary["quantization"].get(
        "residual_q_sha256"
    )
    residual_q_sha = hashlib.sha256(pack_i8(residual_q)).hexdigest()

    sim_result = load_json(args.sim_result_json) if args.sim_result_json else None
    sim_pass = sim_result is not None and sim_result.get("status") == "PASS"
    metrics = {
        "fixed_residual_add_output_vs_block_output": score_error(
            fixed_output_dequantized,
            block_output,
        ),
        "fixed_residual_add_output_vs_boundary_quantizer": score_error(
            fixed_output_dequantized,
            [value * final_output_scale for value in reference_output_q],
        ),
    }
    upstream_pass = (
        residual_contract.get("status") == "PASS"
        and residual_boundary.get("status") == "PASS"
        and c_proj_requant_proof.get("status") == "PASS"
        and residual_q_sha == residual_boundary_sha
        and c_proj_output_sha == c_proj_proof_sha
        and c_proj_output_sha == c_proj_boundary_sha
        and fixed_output_sha == expected_final_sha
        and reference_output_sha == expected_final_sha
    )
    score_pass = (
        metrics["fixed_residual_add_output_vs_block_output"]["normalized_rmse"]
        <= args.normalized_rmse_threshold
    )
    status = "PASS" if upstream_pass and score_pass and sim_pass else "FAIL"
    if sim_result is None and upstream_pass and score_pass:
        status = "partial"
    if status == "PASS":
        verdict = "promote"
        next_gate = "integrate residual-add output into a board-programmable selftest lane"
    elif status == "partial":
        verdict = "continue"
        next_gate = "run Verilator, Yosys, and mapped utilization for residual-add RTL proof"
    else:
        verdict = "stop"
        next_gate = "fix residual-add RTL proof before integration"

    payload = {
        "artifact_name": args.artifact_name,
        "status": status,
        "source_artifacts": {
            "residual_contract_manifest": str(args.residual_contract_manifest),
            "residual_boundary_json": str(args.residual_boundary_json),
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
                "Composed RTL proof for c_fc -> fixed-point GELU -> c_proj "
                "int8 output -> fixed-point residual add requant."
            ),
        },
        "rtl_contract": {
            "top_name": "task6_int8_l2_mlp_chain_residual_add_kernel",
            "base_chain_top_name": c_proj_payload["rtl_contract"]["top_name"],
            "output_dim": len(residual_q),
            "activation_dtype": "int8",
            "c_proj_output_dtype": "int8",
            "residual_dtype": "int8",
            "output_dtype": "int8",
            "residual_quantization": "int8-per-tensor-symmetric",
            "c_proj_output_quantization": "int8-per-tensor-symmetric",
            "final_output_quantization": "int8-per-tensor-symmetric",
            "local_residual_memory": True,
            "local_output_memory": True,
        },
        "fixed_point": {
            **c_proj_payload["fixed_point"],
            "residual_add_requant_shift": args.residual_add_requant_shift,
            "residual_requant_mult": residual_requant_mult,
            "c_proj_residual_add_requant_mult": c_proj_requant_mult,
            "residual_add_formula": (
                "q[i] = saturate_i8(round_shift(residual_q[i] * "
                "residual_requant_mult + c_proj_q[i] * "
                "c_proj_residual_add_requant_mult, residual_add_requant_shift))"
            ),
        },
        "quantization": {
            "normalized_rmse_threshold": args.normalized_rmse_threshold,
            "residual_scale": residual_scale,
            "residual_q_min": min(residual_q),
            "residual_q_max": max(residual_q),
            "residual_q_sha256": residual_q_sha,
            "residual_boundary_q_sha256": residual_boundary_sha,
            "c_proj_output_scale": c_proj_metadata["c_proj_output_scale"],
            "c_proj_output_q_sha256": c_proj_output_sha,
            "c_proj_output_proof_q_sha256": c_proj_proof_sha,
            "c_proj_output_boundary_q_sha256": c_proj_boundary_sha,
            "final_output_scale": final_output_scale,
            "final_output_q_min": min(fixed_output_q),
            "final_output_q_max": max(fixed_output_q),
            "final_output_q_sha256": fixed_output_sha,
            "reference_final_output_q_sha256": reference_output_sha,
            "expected_final_output_q_sha256": expected_final_sha,
            "final_output_matches_boundary_quantizer": fixed_output_sha
            == expected_final_sha,
        },
        "upstream_metrics": {
            **c_proj_metadata,
            "residual_boundary_metrics": residual_boundary.get("metrics", {}),
        },
        "metrics": metrics,
        "byte_budget": residual_boundary.get("byte_budget", {}),
        "sim_result": sim_result,
        "yosys_result": load_design_stats(args.yosys_stat_json),
        "mapped_utilization": load_utilization(args.mapped_utilization_summary_json),
        "decision": {
            "verdict": verdict,
            "next_gate": next_gate,
        },
    }

    sv_text = inject_residual_add_data(
        base_sv,
        residual_q,
        fixed_output_q,
        residual_requant_mult,
        c_proj_requant_mult,
        args.residual_add_requant_shift,
    )
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
