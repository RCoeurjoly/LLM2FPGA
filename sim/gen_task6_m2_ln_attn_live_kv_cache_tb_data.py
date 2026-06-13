#!/usr/bin/env python3
"""Generate constants for an offline M2 live K/V cache proof."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts" / "task6"))
sys.path.insert(0, str(ROOT / "sim"))

import score_m2_ln1_qkv_lowering as attention  # noqa: E402
import gen_task6_m2_ln_attn_sublane_selftest_tb_data as sublane  # noqa: E402


Q15 = 1 << 15
Q20 = 1 << 20


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--contract-manifest", required=True, type=Path)
    parser.add_argument("--weight-manifest", required=True, type=Path)
    parser.add_argument("--out-sv", required=True, type=Path)
    parser.add_argument("--out-json", required=True, type=Path)
    parser.add_argument("--step-index", type=int, default=0)
    parser.add_argument("--token-index", type=int, default=-1)
    parser.add_argument("--head-index", type=int, default=0)
    parser.add_argument("--num-heads", type=int, default=1)
    return parser.parse_args()


def project_rows(
    ln_fixtures: list[dict],
    attn: dict,
    weight_base: Path,
    weights: dict,
    head_index: int,
) -> dict[str, list[dict]]:
    projections: dict[str, list[dict]] = {"q": [], "k": [], "v": []}
    for token_ln in ln_fixtures:
        for name in ("q", "k", "v"):
            projections[name].append(
                sublane.projection_fixture(
                    token_ln["actual_q"],
                    token_ln["output_scale"],
                    attn[f"{name}_scale"],
                    weight_base,
                    weights,
                    name,
                    head_index,
                    attn["head_dim"],
                )
            )
    return projections


def score_softmax_weights_q15(score_acc: list[int], score_scale_q20: int) -> list[int]:
    max_score = max(score_acc)
    weights = []
    for score in score_acc:
        diff = max_score - score
        x_q12 = sublane.round_shift_signed(diff * score_scale_q20, 8)
        term1 = sublane.round_shift_signed(x_q12 * Q15, 12)
        term2 = sublane.round_shift_signed(x_q12 * x_q12 * Q15, 25)
        weights.append(max(1, min(0xFFFF, Q15 - term1 + term2)))
    return weights


def normalize_weights_q15(weights: list[int]) -> list[int]:
    denom = sum(weights)
    if denom <= 0:
        raise SystemExit("softmax weight denominator must be positive")
    probs = []
    running = 0
    for index, weight in enumerate(weights):
        if index == len(weights) - 1:
            prob = Q15 - running
        else:
            prob = (weight * Q15 + (denom // 2)) // denom
            running += prob
        if prob < 0 or prob > 0xFFFF:
            raise SystemExit(f"probability q15 out of range: {prob}")
        probs.append(prob)
    return probs


def live_cache_expectations(attn: dict, projections: dict[str, list[dict]], token_index: int) -> dict:
    head_dim = int(attn["head_dim"])
    final_q = projections["q"][token_index]["expected_q"]
    k_cache = [projections["k"][src]["expected_q"] for src in range(token_index + 1)]
    v_cache = [projections["v"][src]["expected_q"] for src in range(token_index + 1)]

    score_acc = []
    for src in range(token_index + 1):
        score_acc.append(sum(final_q[dim] * k_cache[src][dim] for dim in range(head_dim)))
    score_scale_q20 = round((attn["q_scale"] * attn["k_scale"] / (head_dim ** 0.5)) * Q20)
    softmax_weight_q15 = score_softmax_weights_q15(score_acc, score_scale_q20)
    prob_q = normalize_weights_q15(softmax_weight_q15)

    value_acc = []
    value_q = []
    for dim in range(head_dim):
        acc = 0
        for src in range(token_index + 1):
            acc += prob_q[src] * v_cache[src][dim]
        value_acc.append(acc)
        value_q.append(sublane.clamp_i8(sublane.round_shift_signed(acc, 15)))

    return {
        "q_final": final_q,
        "k_cache": k_cache,
        "v_cache": v_cache,
        "score_scale_q20": score_scale_q20,
        "score_acc": score_acc,
        "softmax_weight_q15": softmax_weight_q15,
        "prob_q": prob_q,
        "value_acc": value_acc,
        "value_q": value_q,
    }


def emit_2d(lines: list[str], name: str, rows: list[list[int]], formatter) -> None:
    for row_index, row in enumerate(rows):
        for col_index, value in enumerate(row):
            lines.append(f"  {name}[{row_index}][{col_index}] = {formatter(value)};")


def main() -> None:
    args = parse_args()
    contract = attention.load_json(args.contract_manifest)
    weights = attention.load_json(args.weight_manifest)
    weight_base = args.weight_manifest.parent
    contract_base = args.contract_manifest.parent
    step = contract["steps"][args.step_index]
    seq_len = int(step["sequence_length"])
    token_index = args.token_index if args.token_index >= 0 else seq_len - 1
    if token_index < 0 or token_index >= seq_len:
        raise SystemExit(f"token-index {token_index} outside sequence length {seq_len}")
    hidden = int(step["tensors"]["block_input_f32"]["shape"][-1])

    block_input = attention.reshape2(
        attention.read_f32(attention.tensor_path(contract_base, step["tensors"]["block_input_f32"])),
        seq_len,
        hidden,
    )
    gamma = attention.read_f32(weight_base / attention.weight_tensor(weights, "transformer.h.0.ln_1.weight")["filename"])
    beta = attention.read_f32(weight_base / attention.weight_tensor(weights, "transformer.h.0.ln_1.bias")["filename"])
    ln_fixtures = [
        sublane.layernorm_fixture(block_input[src], gamma, beta)
        for src in range(token_index + 1)
    ]

    ln1_rows = attention.layernorm_rows(block_input, gamma, beta)
    projection_rows = {}
    for name in ("q", "k", "v"):
        expected = attention.reshape2(
            attention.read_f32(attention.tensor_path(contract_base, step["tensors"][f"{name}_proj_output_f32"])),
            seq_len,
            hidden,
        )
        _scored, rows = attention.score_projection(weight_base, weights, name, ln1_rows, expected)
        projection_rows[name] = rows

    attn = sublane.attention_fixture(
        projection_rows["q"],
        projection_rows["k"],
        projection_rows["v"],
        token_index,
        args.head_index,
        args.num_heads,
    )
    projections = project_rows(ln_fixtures, attn, weight_base, weights, args.head_index)
    live = live_cache_expectations(attn, projections, token_index)

    lines = [
        "localparam int LN_DIM = 64;",
        f"localparam int CACHE_SEQ = {token_index + 1};",
        f"localparam int ATTN_HEAD_DIM = {attn['head_dim']};",
        f"localparam logic signed [31:0] SOFTMAX_SCORE_SCALE_Q20 = {sublane.sv_i32(live['score_scale_q20'])};",
        "logic signed [15:0] ln_input_q12_by_token [0:CACHE_SEQ-1][0:LN_DIM-1];",
        "logic signed [31:0] ln_gamma_q16 [0:LN_DIM-1];",
        "logic signed [15:0] ln_beta_q12 [0:LN_DIM-1];",
        "logic signed [31:0] ln_inv_std_q16_by_token [0:CACHE_SEQ-1];",
        "logic signed [31:0] ln_output_scale_mul_q20_by_token [0:CACHE_SEQ-1];",
        "logic signed [7:0] ln_expected_q_by_token [0:CACHE_SEQ-1][0:LN_DIM-1];",
        "logic signed [7:0] q_proj_weight_q [0:ATTN_HEAD_DIM-1][0:LN_DIM-1];",
        "logic signed [7:0] k_proj_weight_q [0:ATTN_HEAD_DIM-1][0:LN_DIM-1];",
        "logic signed [7:0] v_proj_weight_q [0:ATTN_HEAD_DIM-1][0:LN_DIM-1];",
        "logic signed [31:0] q_proj_output_mul_q20_final [0:ATTN_HEAD_DIM-1];",
        "logic signed [31:0] k_proj_output_mul_q20_by_token [0:CACHE_SEQ-1][0:ATTN_HEAD_DIM-1];",
        "logic signed [31:0] v_proj_output_mul_q20_by_token [0:CACHE_SEQ-1][0:ATTN_HEAD_DIM-1];",
        "logic signed [7:0] q_proj_expected_q_final [0:ATTN_HEAD_DIM-1];",
        "logic signed [7:0] k_proj_expected_q_by_token [0:CACHE_SEQ-1][0:ATTN_HEAD_DIM-1];",
        "logic signed [7:0] v_proj_expected_q_by_token [0:CACHE_SEQ-1][0:ATTN_HEAD_DIM-1];",
        "logic [15:0] attn_expected_weight_q15 [0:CACHE_SEQ-1];",
        "logic [15:0] attn_prob_q15 [0:CACHE_SEQ-1];",
        "logic signed [31:0] attn_expected_score_acc [0:CACHE_SEQ-1];",
        "logic signed [31:0] attn_expected_value_acc [0:ATTN_HEAD_DIM-1];",
        "logic signed [7:0] attn_expected_value_q [0:ATTN_HEAD_DIM-1];",
        "initial begin",
    ]

    emit_2d(lines, "ln_input_q12_by_token", [ln["input_q"] for ln in ln_fixtures], sublane.sv_i16)
    for index, value in enumerate(ln_fixtures[0]["gamma_q"]):
        lines.append(f"  ln_gamma_q16[{index}] = {sublane.sv_i32(value)};")
    for index, value in enumerate(ln_fixtures[0]["beta_q"]):
        lines.append(f"  ln_beta_q12[{index}] = {sublane.sv_i16(value)};")
    for token, ln in enumerate(ln_fixtures):
        lines.append(f"  ln_inv_std_q16_by_token[{token}] = {sublane.sv_i32(ln['inv_std_q'])};")
        lines.append(
            f"  ln_output_scale_mul_q20_by_token[{token}] = {sublane.sv_i32(ln['output_scale_mul'])};"
        )
    emit_2d(lines, "ln_expected_q_by_token", [ln["actual_q"] for ln in ln_fixtures], sublane.sv_i8)

    for proj_name in ("q", "k", "v"):
        for out_index, row in enumerate(projections[proj_name][token_index]["weight_q"]):
            for in_index, value in enumerate(row):
                lines.append(f"  {proj_name}_proj_weight_q[{out_index}][{in_index}] = {sublane.sv_i8(value)};")
    for dim, value in enumerate(projections["q"][token_index]["output_mul_q20"]):
        lines.append(f"  q_proj_output_mul_q20_final[{dim}] = {sublane.sv_i32(value)};")
    for token in range(token_index + 1):
        for dim, value in enumerate(projections["k"][token]["output_mul_q20"]):
            lines.append(f"  k_proj_output_mul_q20_by_token[{token}][{dim}] = {sublane.sv_i32(value)};")
        for dim, value in enumerate(projections["v"][token]["output_mul_q20"]):
            lines.append(f"  v_proj_output_mul_q20_by_token[{token}][{dim}] = {sublane.sv_i32(value)};")

    for dim, value in enumerate(live["q_final"]):
        lines.append(f"  q_proj_expected_q_final[{dim}] = {sublane.sv_i8(value)};")
    emit_2d(lines, "k_proj_expected_q_by_token", live["k_cache"], sublane.sv_i8)
    emit_2d(lines, "v_proj_expected_q_by_token", live["v_cache"], sublane.sv_i8)
    for src, value in enumerate(live["softmax_weight_q15"]):
        lines.append(f"  attn_expected_weight_q15[{src}] = {sublane.sv_u16(value)};")
    for src, value in enumerate(live["prob_q"]):
        lines.append(f"  attn_prob_q15[{src}] = {sublane.sv_u16(value)};")
    for src, value in enumerate(live["score_acc"]):
        lines.append(f"  attn_expected_score_acc[{src}] = {sublane.sv_i32(value)};")
    for dim, value in enumerate(live["value_acc"]):
        lines.append(f"  attn_expected_value_acc[{dim}] = {sublane.sv_i32(value)};")
    for dim, value in enumerate(live["value_q"]):
        lines.append(f"  attn_expected_value_q[{dim}] = {sublane.sv_i8(value)};")
    lines.append("end")

    args.out_sv.parent.mkdir(parents=True, exist_ok=True)
    args.out_sv.write_text("\n".join(lines) + "\n", encoding="utf-8")
    summary = {
        "artifact_name": "task6-m2-ln-attn-live-kv-cache-tb-data",
        "status": "PASS",
        "step": args.step_index,
        "token": token_index,
        "head": args.head_index,
        "num_heads": args.num_heads,
        "cache_seq": token_index + 1,
        "head_dim": attn["head_dim"],
        "expectation_path": "live-ln-kv-cache-final-token-attention",
        "probability_path": "live-score-derived-quadratic-softmax-q15",
        "softmax_score_scale_q20": live["score_scale_q20"],
        "softmax_weight_q15": live["softmax_weight_q15"],
        "prob_q15": live["prob_q"],
        "q_scale": attn["q_scale"],
        "k_scale": attn["k_scale"],
        "v_scale": attn["v_scale"],
        "q_final_min": min(live["q_final"]),
        "q_final_max": max(live["q_final"]),
        "k_cache_min": min(min(row) for row in live["k_cache"]),
        "k_cache_max": max(max(row) for row in live["k_cache"]),
        "v_cache_min": min(min(row) for row in live["v_cache"]),
        "v_cache_max": max(max(row) for row in live["v_cache"]),
        "score_acc_min": min(live["score_acc"]),
        "score_acc_max": max(live["score_acc"]),
        "value_checksum": sum((value & 0xFF) * (index + 1) for index, value in enumerate(live["value_q"])),
    }
    args.out_json.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
