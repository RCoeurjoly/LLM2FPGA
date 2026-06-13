#!/usr/bin/env python3
"""Export the M2 first-token attention out-projection contract."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts" / "task6"))
sys.path.insert(0, str(ROOT / "sim"))

import score_m2_ln1_qkv_lowering as attention  # noqa: E402


QMAX = 127
Q12 = 1 << 12
Q16 = 1 << 16
Q20 = 1 << 20
EPS = 1e-5


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--contract-manifest", required=True, type=Path)
    parser.add_argument("--weight-manifest", required=True, type=Path)
    parser.add_argument("--step-index", type=int, default=0)
    parser.add_argument("--token-index", type=int, default=0)
    parser.add_argument("--num-heads", type=int, default=16)
    parser.add_argument(
        "--context-source",
        choices=("float-attention", "live-kv-cache"),
        default="float-attention",
        help="Source for the out-projection context row.",
    )
    parser.add_argument("--out-sv", type=Path)
    parser.add_argument("--out-json", required=True, type=Path)
    return parser.parse_args()


def quantize_symmetric(values: list[float]) -> tuple[list[int], float]:
    max_abs = max(abs(value) for value in values)
    if max_abs == 0.0:
        return [0 for _ in values], 1.0
    scale = max_abs / QMAX
    return [max(-QMAX, min(QMAX, int(round(value / scale)))) for value in values], scale


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


def round_shift_signed(value: int, shift: int) -> int:
    if shift == 0:
        return value
    half = 1 << (shift - 1)
    if value >= 0:
        return (value + half) >> shift
    return -(((-value) + half) >> shift)


def clamp_i8(value: int) -> int:
    return max(-QMAX, min(QMAX, int(value)))


def sv_i8(value: int) -> str:
    return f"-8'sd{abs(value)}" if value < 0 else f"8'sd{value}"


def sv_i16(value: int) -> str:
    return f"-16'sd{abs(value)}" if value < 0 else f"16'sd{value}"


def sv_i32(value: int) -> str:
    return f"-32'sd{abs(value)}" if value < 0 else f"32'sd{value}"


def layernorm_q12_fixture(
    input_q12: list[int],
    gamma: list[float],
    beta: list[float],
) -> dict[str, object]:
    input_row = [value / Q12 for value in input_q12]
    expected = attention.layernorm_rows([input_row], gamma, beta)[0]
    expected_q, output_scale = quantize_symmetric(expected)
    gamma_q = [round(value * Q16) for value in gamma]
    beta_q = [round(value * Q12) for value in beta]
    mean = sum(input_row) / len(input_row)
    var = sum((value - mean) * (value - mean) for value in input_row) / len(input_row)
    inv_std_q = round((1.0 / ((var + EPS) ** 0.5)) * Q16)
    output_scale_mul = round((1.0 / (Q12 * output_scale)) * Q20)
    mean_q = round_shift_signed(sum(input_q12), 6)
    actual_q: list[int] = []
    for index, value_q12 in enumerate(input_q12):
        centered_q12 = value_q12 - mean_q
        norm_q12 = round_shift_signed(centered_q12 * inv_std_q, 16)
        affine_q12 = round_shift_signed(norm_q12 * gamma_q[index], 16) + beta_q[index]
        actual_q.append(clamp_i8(round_shift_signed(affine_q12 * output_scale_mul, 20)))
    return {
        "input_q12": input_q12,
        "gamma_q16": gamma_q,
        "beta_q12": beta_q,
        "inv_std_q16": inv_std_q,
        "output_scale": output_scale,
        "output_scale_mul_q20": output_scale_mul,
        "expected_q": expected_q,
        "actual_q": actual_q,
        "max_abs_lsb": max(abs(actual - expected) for actual, expected in zip(actual_q, expected_q)),
    }


def live_kv_context_row(
    block_input: list[list[float]],
    projection_rows: dict[str, list[list[float]]],
    token_index: int,
    num_heads: int,
    gamma: list[float],
    beta: list[float],
    weight_base: Path,
    weights: dict,
) -> tuple[list[float], dict[str, object]]:
    import gen_task6_m2_ln_attn_live_kv_cache_tb_data as live_kv  # noqa: PLC0415
    import gen_task6_m2_ln_attn_sublane_selftest_tb_data as sublane  # noqa: PLC0415

    ln_fixtures = [
        sublane.layernorm_fixture(block_input[src], gamma, beta)
        for src in range(token_index + 1)
    ]
    context: list[float] = []
    head_summaries: list[dict[str, object]] = []
    for head_index in range(num_heads):
        attn = sublane.attention_fixture(
            projection_rows["q"],
            projection_rows["k"],
            projection_rows["v"],
            token_index,
            head_index,
            num_heads,
        )
        projections = live_kv.project_rows(
            ln_fixtures,
            attn,
            weight_base,
            weights,
            head_index,
        )
        live = live_kv.live_cache_expectations(attn, projections, token_index)
        context.extend([
            float(value) * float(attn["v_scale"])
            for value in live["value_q"]
        ])
        head_summaries.append(
            {
                "head": head_index,
                "head_dim": attn["head_dim"],
                "score_scale_q20": live["score_scale_q20"],
                "prob_q15": live["prob_q"],
                "value_q": live["value_q"],
                "value_checksum": checksum(list(live["value_q"])),
            }
        )
    hidden = len(block_input[0])
    if len(context) != hidden:
        raise SystemExit(f"live K/V context width {len(context)} != hidden {hidden}")
    return context, {
        "heads": head_summaries,
        "probability_path": "live-score-derived-quadratic-softmax-q15",
        "cache_seq": token_index + 1,
    }


def main() -> int:
    args = parse_args()
    contract = attention.load_json(args.contract_manifest)
    weights = attention.load_json(args.weight_manifest)
    contract_base = args.contract_manifest.parent
    weight_base = args.weight_manifest.parent
    step = contract["steps"][args.step_index]
    seq_len = int(step["sequence_length"])
    hidden = int(step["tensors"]["block_input_f32"]["shape"][-1])
    if args.token_index < 0 or args.token_index >= seq_len:
        raise SystemExit(f"token index {args.token_index} outside sequence length {seq_len}")
    if seq_len < 1:
        raise SystemExit("contract step has no tokens")

    block_input = attention.reshape2(
        attention.read_f32(attention.tensor_path(contract_base, step["tensors"]["block_input_f32"])),
        seq_len,
        hidden,
    )
    ln1_gamma = attention.read_f32(
        weight_base / attention.weight_tensor(weights, "transformer.h.0.ln_1.weight")["filename"]
    )
    ln1_beta = attention.read_f32(
        weight_base / attention.weight_tensor(weights, "transformer.h.0.ln_1.bias")["filename"]
    )
    out_proj_bias = attention.read_f32(
        weight_base / attention.weight_tensor(weights, "transformer.h.0.attn.attention.out_proj.bias")["filename"]
    )
    ln2_gamma = attention.read_f32(
        weight_base / attention.weight_tensor(weights, "transformer.h.0.ln_2.weight")["filename"]
    )
    ln2_beta = attention.read_f32(
        weight_base / attention.weight_tensor(weights, "transformer.h.0.ln_2.bias")["filename"]
    )

    ln1_rows = attention.layernorm_rows(block_input, ln1_gamma, ln1_beta)
    projection_rows = {}
    for name in ("q", "k", "v"):
        expected = attention.reshape2(
            attention.read_f32(attention.tensor_path(contract_base, step["tensors"][f"{name}_proj_output_f32"])),
            seq_len,
            hidden,
        )
        _scored, rows = attention.score_projection(weight_base, weights, name, ln1_rows, expected)
        projection_rows[name] = rows

    float_context_rows = attention.causal_attention_rows(
        projection_rows["q"],
        projection_rows["k"],
        projection_rows["v"],
        args.num_heads,
    )
    attention_expected = attention.reshape2(
        attention.read_f32(attention.tensor_path(contract_base, step["tensors"]["attention_output_f32"])),
        seq_len,
        hidden,
    )
    out_scored, out_projected_rows = attention.score_projection(
        weight_base,
        weights,
        "out",
        float_context_rows,
        attention_expected,
    )
    attention_rows = attention.add_bias(out_projected_rows, out_proj_bias)
    first_block_input = block_input[args.token_index]
    expected_first_attention = attention_expected[args.token_index]
    live_context_summary: dict[str, object] | None = None
    if args.context_source == "live-kv-cache":
        first_context, live_context_summary = live_kv_context_row(
            block_input,
            projection_rows,
            args.token_index,
            args.num_heads,
            ln1_gamma,
            ln1_beta,
            weight_base,
            weights,
        )
    else:
        first_context = float_context_rows[args.token_index]

    context_q, context_scale = quantize_symmetric(first_context)
    block_input_q, block_input_scale = quantize_symmetric(first_block_input)
    out_wq, out_scales, out_features, in_features, _out_tensor = attention.projection_weights(
        weight_base,
        weights,
        "out",
    )
    if out_features != hidden or in_features != hidden:
        raise SystemExit(f"expected square hidden out projection, got {out_features}x{in_features}")

    out_acc: list[int] = []
    out_mul_q20: list[int] = []
    out_projected_q: list[int] = []
    residual_projected_mul_q20: list[int] = []
    residual_block_input_mul_q20: list[int] = []
    residual_bias_q20: list[int] = []
    residual_replayed_q: list[int] = []
    projected_float: list[float] = []
    for out_index in range(hidden):
        offset = out_index * hidden
        acc = sum(context_q[index] * out_wq[offset + index] for index in range(hidden))
        projected_float.append(float(acc) * context_scale * out_scales[out_index])
    first_attention = [
        projected_float[index] + out_proj_bias[index]
        for index in range(hidden)
    ]
    first_residual = [
        first_block_input[index] + first_attention[index] for index in range(hidden)
    ]
    metrics = attention.metrics(first_attention, expected_first_attention)
    projected_q, projected_scale = quantize_symmetric(projected_float)
    attention_q, attention_scale = quantize_symmetric(first_attention)
    residual_q, residual_scale = quantize_symmetric(first_residual)
    for out_index in range(hidden):
        offset = out_index * hidden
        acc = sum(context_q[index] * out_wq[offset + index] for index in range(hidden))
        mul = round((context_scale * out_scales[out_index] / projected_scale) * Q20)
        out_acc.append(acc)
        out_mul_q20.append(mul)
        out_projected_q.append(clamp_i8(round_shift_signed(acc * mul, 20)))
        projected_to_residual = round((projected_scale / residual_scale) * Q20)
        block_input_to_residual = round((block_input_scale / residual_scale) * Q20)
        bias_to_residual = round((out_proj_bias[out_index] / residual_scale) * Q20)
        residual_projected_mul_q20.append(projected_to_residual)
        residual_block_input_mul_q20.append(block_input_to_residual)
        residual_bias_q20.append(bias_to_residual)
        residual_replayed_q.append(
            clamp_i8(
                round_shift_signed(
                    out_projected_q[out_index] * projected_to_residual
                    + block_input_q[out_index] * block_input_to_residual
                    + bias_to_residual,
                    20,
                )
            )
        )
    if out_projected_q != projected_q:
        mismatches = sum(1 for actual, expected in zip(out_projected_q, projected_q) if actual != expected)
        raise SystemExit(f"out projection fixed-point mismatch count {mismatches}")
    residual_float_q = residual_q
    residual_float_mismatches = sum(
        1 for actual, expected in zip(residual_replayed_q, residual_float_q) if actual != expected
    )
    residual_q = residual_replayed_q
    residual_input_q12 = [round(value * residual_scale * Q12) for value in residual_q]
    ln2 = layernorm_q12_fixture(residual_input_q12, ln2_gamma, ln2_beta)
    ln2_expected_q = list(ln2["expected_q"])
    ln2_actual_q = list(ln2["actual_q"])
    ln2_contract_expected = attention.reshape2(
        attention.read_f32(attention.tensor_path(contract_base, step["tensors"]["ln2_output_f32"])),
        seq_len,
        hidden,
    )[args.token_index]
    ln2_contract_q, _ln2_contract_scale = quantize_symmetric(ln2_contract_expected)
    ln2_contract_mismatches = sum(
        1 for actual, expected in zip(ln2_actual_q, ln2_contract_q) if actual != expected
    )

    if args.out_sv is not None:
        lines = [
            "localparam int M2_FULL_BLOCK_TOKEN_INDEX = %d;" % args.token_index,
            "localparam int OUT_PROJ_DIM = %d;" % hidden,
            "localparam logic [31:0] OUT_PROJ_EXPECTED_CHECKSUM = 32'h%08x;" % checksum(projected_q),
            "localparam logic [31:0] OUT_PROJ_EXPECTED_SAMPLE0 = 32'h%08x;" % sample_word(projected_q, 0),
            "localparam logic [31:0] OUT_PROJ_EXPECTED_SAMPLE1 = 32'h%08x;" % sample_word(projected_q, 4),
            "localparam logic [31:0] ATTN_RESIDUAL_EXPECTED_CHECKSUM = 32'h%08x;" % checksum(residual_q),
            "localparam logic [31:0] ATTN_RESIDUAL_EXPECTED_SAMPLE0 = 32'h%08x;" % sample_word(residual_q, 0),
            "localparam logic [31:0] ATTN_RESIDUAL_EXPECTED_SAMPLE1 = 32'h%08x;" % sample_word(residual_q, 4),
            "localparam logic signed [31:0] LN2_INV_STD_Q16 = %s;" % sv_i32(int(ln2["inv_std_q16"])),
            "localparam logic signed [31:0] LN2_OUTPUT_SCALE_MUL_Q20 = %s;" % sv_i32(int(ln2["output_scale_mul_q20"])),
            "localparam logic [31:0] LN2_EXPECTED_CHECKSUM = 32'h%08x;" % checksum(ln2_actual_q),
            "localparam logic [31:0] LN2_EXPECTED_SAMPLE0 = 32'h%08x;" % sample_word(ln2_actual_q, 0),
            "localparam logic [31:0] LN2_EXPECTED_SAMPLE1 = 32'h%08x;" % sample_word(ln2_actual_q, 4),
            "logic signed [7:0] out_proj_context_q [0:OUT_PROJ_DIM-1];",
            "logic signed [7:0] out_proj_block_input_q [0:OUT_PROJ_DIM-1];",
            "logic signed [7:0] out_proj_weight_q [0:OUT_PROJ_DIM-1][0:OUT_PROJ_DIM-1];",
            "logic signed [31:0] out_proj_expected_acc [0:OUT_PROJ_DIM-1];",
            "logic signed [31:0] out_proj_mul_q20 [0:OUT_PROJ_DIM-1];",
            "logic signed [7:0] out_proj_expected_q [0:OUT_PROJ_DIM-1];",
            "logic signed [31:0] attn_residual_projected_mul_q20 [0:OUT_PROJ_DIM-1];",
            "logic signed [31:0] attn_residual_block_input_mul_q20 [0:OUT_PROJ_DIM-1];",
            "logic signed [31:0] attn_residual_bias_q20 [0:OUT_PROJ_DIM-1];",
            "logic signed [7:0] attn_residual_expected_q [0:OUT_PROJ_DIM-1];",
            "logic signed [15:0] ln2_input_q12 [0:OUT_PROJ_DIM-1];",
            "logic signed [31:0] ln2_gamma_q16 [0:OUT_PROJ_DIM-1];",
            "logic signed [15:0] ln2_beta_q12 [0:OUT_PROJ_DIM-1];",
            "logic signed [7:0] ln2_expected_q [0:OUT_PROJ_DIM-1];",
            "initial begin",
        ]
        for index, value in enumerate(context_q):
            lines.append(f"  out_proj_context_q[{index}] = {sv_i8(value)};")
        for index, value in enumerate(block_input_q):
            lines.append(f"  out_proj_block_input_q[{index}] = {sv_i8(value)};")
        for out_index in range(hidden):
            offset = out_index * hidden
            for in_index in range(hidden):
                lines.append(
                    f"  out_proj_weight_q[{out_index}][{in_index}] = {sv_i8(out_wq[offset + in_index])};"
                )
        for index, value in enumerate(out_acc):
            lines.append(f"  out_proj_expected_acc[{index}] = {sv_i32(value)};")
        for index, value in enumerate(out_mul_q20):
            lines.append(f"  out_proj_mul_q20[{index}] = {sv_i32(value)};")
        for index, value in enumerate(projected_q):
            lines.append(f"  out_proj_expected_q[{index}] = {sv_i8(value)};")
        for index, value in enumerate(residual_projected_mul_q20):
            lines.append(f"  attn_residual_projected_mul_q20[{index}] = {sv_i32(value)};")
        for index, value in enumerate(residual_block_input_mul_q20):
            lines.append(f"  attn_residual_block_input_mul_q20[{index}] = {sv_i32(value)};")
        for index, value in enumerate(residual_bias_q20):
            lines.append(f"  attn_residual_bias_q20[{index}] = {sv_i32(value)};")
        for index, value in enumerate(residual_q):
            lines.append(f"  attn_residual_expected_q[{index}] = {sv_i8(value)};")
        for index, value in enumerate(residual_input_q12):
            lines.append(f"  ln2_input_q12[{index}] = {sv_i16(value)};")
        for index, value in enumerate(ln2["gamma_q16"]):
            lines.append(f"  ln2_gamma_q16[{index}] = {sv_i32(int(value))};")
        for index, value in enumerate(ln2["beta_q12"]):
            lines.append(f"  ln2_beta_q12[{index}] = {sv_i16(int(value))};")
        for index, value in enumerate(ln2_actual_q):
            lines.append(f"  ln2_expected_q[{index}] = {sv_i8(value)};")
        lines.append("end")
        args.out_sv.parent.mkdir(parents=True, exist_ok=True)
        args.out_sv.write_text("\n".join(lines) + "\n", encoding="utf-8")

    output = {
        "artifact_name": "task6-m2-first-token-attention-out-projection",
        "status": "PASS",
        "stage": "M2-first-token-attention-out-projection-oracle",
        "milestone_target": "M2-one-full-block",
        "live_compute": False,
        "artifact_role": "offline-first-token-attention-out-projection-prerequisite",
        "step": args.step_index,
        "token": args.token_index,
        "num_heads": args.num_heads,
        "hidden": hidden,
        "context_scale": context_scale,
        "context_q_min": min(context_q),
        "context_q_max": max(context_q),
        "block_input_scale": block_input_scale,
        "block_input_q_min": min(block_input_q),
        "block_input_q_max": max(block_input_q),
        "out_projected_scale": projected_scale,
        "out_projected_q_min": min(projected_q),
        "out_projected_q_max": max(projected_q),
        "out_projected_checksum": checksum(projected_q),
        "out_projected_sample0": sample_word(projected_q, 0),
        "out_projected_sample1": sample_word(projected_q, 4),
        "out_projected_first_64_hex": bytes(u8(value) for value in projected_q).hex(),
        "attention_residual_scale": residual_scale,
        "attention_residual_q_min": min(residual_q),
        "attention_residual_q_max": max(residual_q),
        "attention_residual_checksum": checksum(residual_q),
        "attention_residual_sample0": sample_word(residual_q, 0),
        "attention_residual_sample1": sample_word(residual_q, 4),
        "attention_residual_first_64_hex": bytes(u8(value) for value in residual_q).hex(),
        "attention_residual_float_q_checksum": checksum(residual_float_q),
        "attention_residual_float_q_sample0": sample_word(residual_float_q, 0),
        "attention_residual_float_q_sample1": sample_word(residual_float_q, 4),
        "attention_residual_float_q_mismatches": residual_float_mismatches,
        "ln2_replay_scale": ln2["output_scale"],
        "ln2_replay_q_min": min(ln2_actual_q),
        "ln2_replay_q_max": max(ln2_actual_q),
        "ln2_replay_checksum": checksum(ln2_actual_q),
        "ln2_replay_sample0": sample_word(ln2_actual_q, 0),
        "ln2_replay_sample1": sample_word(ln2_actual_q, 4),
        "ln2_replay_first_64_hex": bytes(u8(value) for value in ln2_actual_q).hex(),
        "ln2_replay_vs_q12_fixture_max_abs_lsb": ln2["max_abs_lsb"],
        "ln2_replay_vs_contract_q_mismatches": ln2_contract_mismatches,
        "attention_output_scale": attention_scale,
        "attention_output_q_min": min(attention_q),
        "attention_output_q_max": max(attention_q),
        "attention_output_checksum": checksum(attention_q),
        "attention_output_sample0": sample_word(attention_q, 0),
        "attention_output_sample1": sample_word(attention_q, 4),
        "attention_output_first_64_hex": bytes(u8(value) for value in attention_q).hex(),
        "context_first_64_hex": bytes(u8(value) for value in context_q).hex(),
        "out_projection_metrics": out_scored,
        "attention_output_metrics": metrics,
    }
    if live_context_summary is not None:
        output["live_kv_context"] = live_context_summary
    args.out_json.parent.mkdir(parents=True, exist_ok=True)
    args.out_json.write_text(json.dumps(output, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
