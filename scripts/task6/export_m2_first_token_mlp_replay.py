#!/usr/bin/env python3
"""Replay first-token M2 MLP from the fixed-point LN2 boundary."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts" / "task6"))

import score_m2_ln1_qkv_lowering as attention  # noqa: E402
import score_m2_mlp_residual_lowering as mlp  # noqa: E402


QMAX = 127


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--contract-manifest", required=True, type=Path)
    parser.add_argument("--weight-manifest", required=True, type=Path)
    parser.add_argument("--attention-boundary-json", required=True, type=Path)
    parser.add_argument("--post-gelu-proof-json", required=True, type=Path)
    parser.add_argument("--c-proj-proof-json", required=True, type=Path)
    parser.add_argument("--step-index", type=int, default=0)
    parser.add_argument("--token-index", type=int, default=0)
    parser.add_argument("--out-sv", type=Path)
    parser.add_argument("--out-json", required=True, type=Path)
    return parser.parse_args()


def u8(value: int) -> int:
    return int(value) & 0xFF


def checksum(values: list[int]) -> int:
    acc = 0
    for index, value in enumerate(values):
        acc = (acc + (((index + 1) * u8(value)) & 0xFFFFFFFF)) & 0xFFFFFFFF
    return acc


def sample_word(values: list[int], offset: int) -> int:
    out = 0
    for index in range(4):
        out |= u8(values[offset + index]) << (8 * index)
    return out


def clamp_i8(value: int) -> int:
    return max(-QMAX, min(QMAX, int(value)))


def round_shift_signed(value: int, shift: int) -> int:
    if shift == 0:
        return value
    half = 1 << (shift - 1)
    if value >= 0:
        return (value + half) >> shift
    return -(((-value) + half) >> shift)


def quantize_symmetric(values: list[float]) -> tuple[list[int], float]:
    max_abs = max(abs(value) for value in values)
    if max_abs == 0.0:
        return [0 for _ in values], 1.0
    scale = max_abs / QMAX
    return [clamp_i8(round(value / scale)) for value in values], scale


def bytes_to_i8(hex_value: str, expected_len: int) -> list[int]:
    raw = bytes.fromhex(hex_value)
    if len(raw) != expected_len:
        raise SystemExit(f"hex vector length {len(raw)} != expected {expected_len}")
    return [value - 256 if value >= 128 else value for value in raw]


def sv_i8(value: int) -> str:
    return f"-8'sd{abs(value)}" if value < 0 else f"8'sd{value}"


def sv_i32(value: int) -> str:
    return f"-32'sd{abs(value)}" if value < 0 else f"32'sd{value}"


def main() -> int:
    args = parse_args()
    contract = attention.load_json(args.contract_manifest)
    weights = attention.load_json(args.weight_manifest)
    attention_boundary = attention.load_json(args.attention_boundary_json)
    post_gelu_proof = attention.load_json(args.post_gelu_proof_json)
    c_proj_proof = attention.load_json(args.c_proj_proof_json)
    contract_base = args.contract_manifest.parent
    weight_base = args.weight_manifest.parent
    step = contract["steps"][args.step_index]
    seq_len = int(step["sequence_length"])
    hidden = int(step["tensors"]["block_input_f32"]["shape"][-1])
    if args.token_index < 0 or args.token_index >= seq_len:
        raise SystemExit(f"token index {args.token_index} outside sequence length {seq_len}")

    ln2_q = bytes_to_i8(attention_boundary["ln2_replay_first_64_hex"], hidden)
    ln2_scale = float(attention_boundary["ln2_replay_scale"])
    ln2_row = [value * ln2_scale for value in ln2_q]
    residual_q = bytes_to_i8(attention_boundary["attention_residual_first_64_hex"], hidden)
    residual_scale = float(attention_boundary["attention_residual_scale"])
    residual_row = [value * residual_scale for value in residual_q]

    c_fc_weight_q, c_fc_scales, c_fc_out, _c_fc_in, _c_fc_tensor = mlp.read_weight_pack(
        weight_base,
        weights,
        "transformer.h.0.mlp.c_fc.weight",
    )
    c_proj_weight_q, c_proj_scales, _c_proj_out, c_proj_in, _c_proj_tensor = mlp.read_weight_pack(
        weight_base,
        weights,
        "transformer.h.0.mlp.c_proj.weight",
    )
    if c_proj_in != c_fc_out:
        raise SystemExit(f"c_proj input {c_proj_in} != c_fc output {c_fc_out}")
    c_fc_bias = attention.read_f32(weight_base / attention.weight_tensor(weights, "transformer.h.0.mlp.c_fc.bias")["filename"])
    c_proj_bias = attention.read_f32(weight_base / attention.weight_tensor(weights, "transformer.h.0.mlp.c_proj.bias")["filename"])

    fixed_point = dict(c_proj_proof["fixed_point"])
    post_gelu_output_scale = float(post_gelu_proof["quantization"]["output_scale"])
    c_proj_output_scale = float(c_proj_proof["quantization"]["c_proj_output_scale"])
    mlp_row, debug = mlp.replay_mlp_row(
        ln2_row,
        c_fc_weight_q,
        c_fc_scales,
        c_fc_bias,
        c_proj_weight_q,
        c_proj_scales,
        c_proj_bias,
        fixed_point,
        post_gelu_output_scale,
        c_proj_output_scale,
    )
    post_gelu_q = list(debug["post_gelu_q"])
    c_proj_q = list(debug["c_proj_q"])
    final_row = [residual_row[index] + mlp_row[index] for index in range(hidden)]
    final_q, final_scale = quantize_symmetric(final_row)
    c_proj_shift = int(fixed_point["c_proj_output_requant_shift"])
    c_proj_scale_mul = [
        round((post_gelu_output_scale * c_proj_scales[index] / c_proj_output_scale) * (1 << c_proj_shift))
        for index in range(hidden)
    ]
    c_proj_bias_q = [round(value / c_proj_output_scale) for value in c_proj_bias]
    residual_to_final_mul = round((residual_scale / final_scale) * (1 << c_proj_shift))
    c_proj_to_final_mul = round((c_proj_output_scale / final_scale) * (1 << c_proj_shift))
    fixed_final_q = [
        clamp_i8(
            round_shift_signed(
                residual_q[index] * residual_to_final_mul
                + c_proj_q[index] * c_proj_to_final_mul,
                c_proj_shift,
            )
        )
        for index in range(hidden)
    ]
    fixed_final_mismatches = sum(1 for actual, expected in zip(fixed_final_q, final_q) if actual != expected)

    block_expected_rows = attention.reshape2(
        attention.read_f32(attention.tensor_path(contract_base, step["tensors"]["block_output_f32"])),
        seq_len,
        hidden,
    )
    block_expected = block_expected_rows[args.token_index]
    block_expected_q, _block_expected_scale = quantize_symmetric(block_expected)
    mlp_expected_rows = attention.reshape2(
        attention.read_f32(attention.tensor_path(contract_base, step["tensors"]["mlp_output_f32"])),
        seq_len,
        hidden,
    )
    mlp_expected = mlp_expected_rows[args.token_index]
    mlp_metrics = attention.metrics(mlp_row, mlp_expected)
    final_metrics = attention.metrics(final_row, block_expected)
    final_q_mismatches = sum(1 for actual, expected in zip(final_q, block_expected_q) if actual != expected)

    if args.out_sv is not None:
        lines = [
            "localparam int MLP_C_FC_IN_DIM = %d;" % hidden,
            "localparam int MLP_C_FC_OUT_DIM = %d;" % c_fc_out,
            "localparam int MLP_C_FC_SCALE_SHIFT = %d;" % int(fixed_point["scale_shift"]),
            "localparam int MLP_C_FC_X_FRAC = %d;" % int(fixed_point["x_frac"]),
            "localparam int MLP_GELU_PWL_NODE_COUNT = %d;" % len(fixed_point["gelu_pwl_x_nodes"]),
            "localparam logic [31:0] MLP_POST_GELU_EXPECTED_CHECKSUM = 32'h%08x;" % checksum(post_gelu_q),
            "localparam logic [31:0] MLP_POST_GELU_EXPECTED_SAMPLE0 = 32'h%08x;" % sample_word(post_gelu_q, 0),
            "localparam logic [31:0] MLP_POST_GELU_EXPECTED_SAMPLE1 = 32'h%08x;" % sample_word(post_gelu_q, 4),
            "localparam int MLP_C_PROJ_IN_DIM = %d;" % c_fc_out,
            "localparam int MLP_C_PROJ_OUT_DIM = %d;" % hidden,
            "localparam int MLP_C_PROJ_REQUANT_SHIFT = %d;" % c_proj_shift,
            "localparam logic signed [31:0] MLP_FINAL_RESIDUAL_MUL_Q = %s;" % sv_i32(residual_to_final_mul),
            "localparam logic signed [31:0] MLP_FINAL_C_PROJ_MUL_Q = %s;" % sv_i32(c_proj_to_final_mul),
            "localparam logic [31:0] MLP_C_PROJ_EXPECTED_CHECKSUM = 32'h%08x;" % checksum(c_proj_q),
            "localparam logic [31:0] MLP_C_PROJ_EXPECTED_SAMPLE0 = 32'h%08x;" % sample_word(c_proj_q, 0),
            "localparam logic [31:0] MLP_C_PROJ_EXPECTED_SAMPLE1 = 32'h%08x;" % sample_word(c_proj_q, 4),
            "localparam logic [31:0] MLP_FINAL_EXPECTED_CHECKSUM = 32'h%08x;" % checksum(fixed_final_q),
            "localparam logic [31:0] MLP_FINAL_EXPECTED_SAMPLE0 = 32'h%08x;" % sample_word(fixed_final_q, 0),
            "localparam logic [31:0] MLP_FINAL_EXPECTED_SAMPLE1 = 32'h%08x;" % sample_word(fixed_final_q, 4),
            "logic signed [7:0] mlp_ln2_q [0:MLP_C_FC_IN_DIM-1];",
            "logic signed [7:0] mlp_c_fc_weight_q [0:MLP_C_FC_OUT_DIM-1][0:MLP_C_FC_IN_DIM-1];",
            "logic signed [31:0] mlp_c_fc_scale_mul_q [0:MLP_C_FC_OUT_DIM-1];",
            "logic signed [31:0] mlp_c_fc_bias_q [0:MLP_C_FC_OUT_DIM-1];",
            "logic signed [31:0] mlp_c_fc_expected_acc [0:MLP_C_FC_OUT_DIM-1];",
            "logic signed [31:0] mlp_c_fc_expected_x_q [0:MLP_C_FC_OUT_DIM-1];",
            "logic signed [31:0] mlp_gelu_pwl_x_nodes [0:MLP_GELU_PWL_NODE_COUNT-1];",
            "logic signed [7:0] mlp_gelu_pwl_y_nodes [0:MLP_GELU_PWL_NODE_COUNT-1];",
            "logic signed [7:0] mlp_post_gelu_q [0:MLP_C_PROJ_IN_DIM-1];",
            "logic signed [7:0] mlp_c_proj_weight_q [0:MLP_C_PROJ_OUT_DIM-1][0:MLP_C_PROJ_IN_DIM-1];",
            "logic signed [31:0] mlp_c_proj_scale_mul_q [0:MLP_C_PROJ_OUT_DIM-1];",
            "logic signed [31:0] mlp_c_proj_bias_q [0:MLP_C_PROJ_OUT_DIM-1];",
            "logic signed [31:0] mlp_c_proj_expected_acc [0:MLP_C_PROJ_OUT_DIM-1];",
            "logic signed [7:0] mlp_c_proj_expected_q [0:MLP_C_PROJ_OUT_DIM-1];",
            "logic signed [7:0] mlp_residual_q [0:MLP_C_PROJ_OUT_DIM-1];",
            "logic signed [7:0] mlp_final_expected_q [0:MLP_C_PROJ_OUT_DIM-1];",
            "initial begin",
        ]
        c_fc_scale_mul = [
            round(ln2_scale * c_fc_scales[index] * (1 << (int(fixed_point["x_frac"]) + int(fixed_point["scale_shift"]))))
            for index in range(c_fc_out)
        ]
        c_fc_bias_q = [round(value * (1 << int(fixed_point["x_frac"]))) for value in c_fc_bias]
        for index, value in enumerate(debug["ln2_q"]):
            lines.append(f"  mlp_ln2_q[{index}] = {sv_i8(value)};")
        for out_index in range(c_fc_out):
            offset = out_index * hidden
            for in_index in range(hidden):
                lines.append(
                    f"  mlp_c_fc_weight_q[{out_index}][{in_index}] = "
                    f"{sv_i8(c_fc_weight_q[offset + in_index])};"
                )
        for index, value in enumerate(c_fc_scale_mul):
            lines.append(f"  mlp_c_fc_scale_mul_q[{index}] = {sv_i32(value)};")
        for index, value in enumerate(c_fc_bias_q):
            lines.append(f"  mlp_c_fc_bias_q[{index}] = {sv_i32(value)};")
        for index, value in enumerate(debug["c_fc_accs"]):
            lines.append(f"  mlp_c_fc_expected_acc[{index}] = {sv_i32(value)};")
        x_frac = int(fixed_point["x_frac"])
        scale_shift = int(fixed_point["scale_shift"])
        c_fc_x_q = [
            round_shift_signed(debug["c_fc_accs"][index] * c_fc_scale_mul[index], scale_shift)
            + c_fc_bias_q[index]
            for index in range(c_fc_out)
        ]
        for index, value in enumerate(c_fc_x_q):
            lines.append(f"  mlp_c_fc_expected_x_q[{index}] = {sv_i32(value)};")
        for index, value in enumerate(fixed_point["gelu_pwl_x_nodes"]):
            lines.append(f"  mlp_gelu_pwl_x_nodes[{index}] = {sv_i32(int(value))};")
        for index, value in enumerate(fixed_point["gelu_pwl_y_nodes"]):
            lines.append(f"  mlp_gelu_pwl_y_nodes[{index}] = {sv_i8(int(value))};")
        for index, value in enumerate(post_gelu_q):
            lines.append(f"  mlp_post_gelu_q[{index}] = {sv_i8(value)};")
        for out_index in range(hidden):
            offset = out_index * c_fc_out
            for in_index in range(c_fc_out):
                lines.append(
                    f"  mlp_c_proj_weight_q[{out_index}][{in_index}] = "
                    f"{sv_i8(c_proj_weight_q[offset + in_index])};"
                )
        for index, value in enumerate(c_proj_scale_mul):
            lines.append(f"  mlp_c_proj_scale_mul_q[{index}] = {sv_i32(value)};")
        for index, value in enumerate(c_proj_bias_q):
            lines.append(f"  mlp_c_proj_bias_q[{index}] = {sv_i32(value)};")
        for index, value in enumerate(debug["c_proj_accs"]):
            lines.append(f"  mlp_c_proj_expected_acc[{index}] = {sv_i32(value)};")
        for index, value in enumerate(c_proj_q):
            lines.append(f"  mlp_c_proj_expected_q[{index}] = {sv_i8(value)};")
        for index, value in enumerate(residual_q):
            lines.append(f"  mlp_residual_q[{index}] = {sv_i8(value)};")
        for index, value in enumerate(fixed_final_q):
            lines.append(f"  mlp_final_expected_q[{index}] = {sv_i8(value)};")
        lines.append("end")
        args.out_sv.parent.mkdir(parents=True, exist_ok=True)
        args.out_sv.write_text("\n".join(lines) + "\n", encoding="utf-8")

    output = {
        "artifact_name": "task6-m2-first-token-mlp-replay",
        "status": "PASS",
        "stage": "M2-first-token-mlp-replay-oracle",
        "milestone_target": "M2-one-full-block",
        "live_compute": False,
        "artifact_role": "offline-first-token-mlp-prerequisite",
        "step": args.step_index,
        "token": args.token_index,
        "hidden": hidden,
        "ln2_replay_checksum": attention_boundary["ln2_replay_checksum"],
        "ln2_replay_scale": ln2_scale,
        "post_gelu_checksum": checksum(list(debug["post_gelu_q"])),
        "post_gelu_sample0": sample_word(list(debug["post_gelu_q"]), 0),
        "post_gelu_sample1": sample_word(list(debug["post_gelu_q"]), 4),
        "c_proj_output_scale": c_proj_output_scale,
        "c_proj_checksum": checksum(c_proj_q),
        "c_proj_sample0": sample_word(c_proj_q, 0),
        "c_proj_sample1": sample_word(c_proj_q, 4),
        "c_proj_first_64_hex": bytes(u8(value) for value in c_proj_q).hex(),
        "fixed_final_checksum": checksum(fixed_final_q),
        "fixed_final_sample0": sample_word(fixed_final_q, 0),
        "fixed_final_sample1": sample_word(fixed_final_q, 4),
        "fixed_final_first_64_hex": bytes(u8(value) for value in fixed_final_q).hex(),
        "fixed_final_vs_float_quant_mismatches": fixed_final_mismatches,
        "final_replay_scale": final_scale,
        "final_replay_checksum": checksum(final_q),
        "final_replay_sample0": sample_word(final_q, 0),
        "final_replay_sample1": sample_word(final_q, 4),
        "final_replay_first_64_hex": bytes(u8(value) for value in final_q).hex(),
        "final_replay_vs_contract_q_mismatches": final_q_mismatches,
        "mlp_metrics": mlp_metrics,
        "final_block_metrics": final_metrics,
        "debug_ranges": {
            key: debug[key]
            for key in (
                "ln2_q_min",
                "ln2_q_max",
                "c_fc_accumulator_min",
                "c_fc_accumulator_max",
                "c_fc_x_q_min",
                "c_fc_x_q_max",
                "post_gelu_q_min",
                "post_gelu_q_max",
                "c_proj_accumulator_min",
                "c_proj_accumulator_max",
                "c_proj_q_min",
                "c_proj_q_max",
            )
        },
    }
    args.out_json.parent.mkdir(parents=True, exist_ok=True)
    args.out_json.write_text(json.dumps(output, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
