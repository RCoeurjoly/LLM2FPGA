#!/usr/bin/env python3
"""Generate constants for M2 layernorm and attention sublane selftests."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts" / "task6"))

import score_m2_ln1_qkv_lowering as attention  # noqa: E402


EPS = 1e-5
Q12 = 1 << 12
Q15 = 1 << 15
Q16 = 1 << 16
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
    parser.add_argument("--num-heads", type=int, default=16)
    return parser.parse_args()


def round_shift_signed(value: int, shift: int) -> int:
    if shift == 0:
        return value
    half = 1 << (shift - 1)
    if value >= 0:
        return (value + half) >> shift
    return -(((-value) + half) >> shift)


def clamp_i8(value: int) -> int:
    return max(-127, min(127, int(value)))


def quantize_i8(values: list[float]) -> tuple[list[int], float]:
    max_abs = max(abs(value) for value in values)
    if max_abs == 0.0:
        return [0 for _ in values], 1.0
    scale = max_abs / 127.0
    return [clamp_i8(round(value / scale)) for value in values], scale


def sv_i8(value: int) -> str:
    return f"-8'sd{abs(value)}" if value < 0 else f"8'sd{value}"


def sv_i16(value: int) -> str:
    return f"-16'sd{abs(value)}" if value < 0 else f"16'sd{value}"


def sv_i32(value: int) -> str:
    return f"-32'sd{abs(value)}" if value < 0 else f"32'sd{value}"


def layernorm_fixture(row: list[float], gamma: list[float], beta: list[float]) -> dict:
    mean = sum(row) / len(row)
    var = sum((value - mean) * (value - mean) for value in row) / len(row)
    inv_std = 1.0 / math.sqrt(var + EPS)
    expected = [(value - mean) * inv_std * gamma[index] + beta[index] for index, value in enumerate(row)]
    expected_q, output_scale = quantize_i8(expected)
    input_q = [round(value * Q12) for value in row]
    gamma_q = [round(value * Q16) for value in gamma]
    beta_q = [round(value * Q12) for value in beta]
    inv_std_q = round(inv_std * Q16)
    output_scale_mul = round((1.0 / (Q12 * output_scale)) * Q20)

    actual_q = []
    mean_q = round_shift_signed(sum(input_q), 6)
    for index, value_q in enumerate(input_q):
        centered_q = value_q - mean_q
        norm_q = round_shift_signed(centered_q * inv_std_q, 16)
        affine_q = round_shift_signed(norm_q * gamma_q[index], 16) + beta_q[index]
        actual_q.append(clamp_i8(round_shift_signed(affine_q * output_scale_mul, 20)))
    if actual_q != expected_q:
        max_abs = max(abs(a - e) for a, e in zip(actual_q, expected_q))
        if max_abs > 1:
            raise SystemExit(f"layernorm fixture mismatch exceeds 1 LSB: max_abs={max_abs}")

    return {
        "input_q": input_q,
        "gamma_q": gamma_q,
        "beta_q": beta_q,
        "inv_std_q": inv_std_q,
        "output_scale": output_scale,
        "output_scale_mul": output_scale_mul,
        "expected_q": expected_q,
        "actual_q": actual_q,
        "max_abs_lsb": max(abs(a - e) for a, e in zip(actual_q, expected_q)),
    }


def attention_fixture(
    q_rows: list[list[float]],
    k_rows: list[list[float]],
    v_rows: list[list[float]],
    token_index: int,
    head_index: int,
    num_heads: int,
) -> dict:
    hidden = len(q_rows[0])
    head_dim = hidden // num_heads
    base = head_index * head_dim
    q_vec = q_rows[token_index][base : base + head_dim]
    k_vecs = [row[base : base + head_dim] for row in k_rows[: token_index + 1]]
    v_vecs = [row[base : base + head_dim] for row in v_rows[: token_index + 1]]

    q_q, q_scale = quantize_i8(q_vec)
    k_flat = [value for row in k_vecs for value in row]
    v_flat = [value for row in v_vecs for value in row]
    k_q_flat, k_scale = quantize_i8(k_flat)
    v_q_flat, v_scale = quantize_i8(v_flat)
    k_q = [k_q_flat[index * head_dim : (index + 1) * head_dim] for index in range(token_index + 1)]
    v_q = [v_q_flat[index * head_dim : (index + 1) * head_dim] for index in range(token_index + 1)]

    score_acc = [sum(q_q[dim] * k_q[src][dim] for dim in range(head_dim)) for src in range(token_index + 1)]
    f32_scores = [
        sum(q_vec[dim] * k_vecs[src][dim] for dim in range(head_dim)) / math.sqrt(head_dim)
        for src in range(token_index + 1)
    ]
    max_score = max(f32_scores)
    exps = [math.exp(score - max_score) for score in f32_scores]
    denom = sum(exps)
    probs = [value / denom for value in exps]
    prob_q = [round(prob * Q15) for prob in probs]
    prob_q[-1] += Q15 - sum(prob_q)

    value_acc = []
    value_q = []
    for dim in range(head_dim):
        acc = sum(prob_q[src] * v_q[src][dim] for src in range(token_index + 1))
        value_acc.append(acc)
        value_q.append(clamp_i8(round_shift_signed(acc, 15)))

    return {
        "head_dim": head_dim,
        "seq_len": token_index + 1,
        "q_q": q_q,
        "k_q": k_q,
        "v_q": v_q,
        "prob_q": prob_q,
        "score_acc": score_acc,
        "value_acc": value_acc,
        "value_q": value_q,
        "q_scale": q_scale,
        "k_scale": k_scale,
        "v_scale": v_scale,
    }


def main() -> None:
    args = parse_args()
    contract = attention.load_json(args.contract_manifest)
    weights = attention.load_json(args.weight_manifest)
    weight_base = args.weight_manifest.parent
    contract_base = args.contract_manifest.parent
    step = contract["steps"][args.step_index]
    seq_len = int(step["sequence_length"])
    token_index = args.token_index if args.token_index >= 0 else seq_len - 1
    hidden = int(step["tensors"]["block_input_f32"]["shape"][-1])

    block_input = attention.reshape2(
        attention.read_f32(attention.tensor_path(contract_base, step["tensors"]["block_input_f32"])),
        seq_len,
        hidden,
    )
    gamma = attention.read_f32(weight_base / attention.weight_tensor(weights, "transformer.h.0.ln_1.weight")["filename"])
    beta = attention.read_f32(weight_base / attention.weight_tensor(weights, "transformer.h.0.ln_1.bias")["filename"])
    ln = layernorm_fixture(block_input[token_index], gamma, beta)

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
    attn = attention_fixture(
        projection_rows["q"],
        projection_rows["k"],
        projection_rows["v"],
        token_index,
        args.head_index,
        args.num_heads,
    )

    lines = [
        "localparam int LN_DIM = 64;",
        "localparam int ATTN_SEQ = %d;" % attn["seq_len"],
        "localparam int ATTN_HEAD_DIM = %d;" % attn["head_dim"],
        "localparam logic signed [31:0] LN_INV_STD_Q16 = %s;" % sv_i32(ln["inv_std_q"]),
        "localparam logic signed [31:0] LN_OUTPUT_SCALE_MUL_Q20 = %s;" % sv_i32(ln["output_scale_mul"]),
        "logic signed [15:0] ln_input_q12 [0:LN_DIM-1];",
        "logic signed [31:0] ln_gamma_q16 [0:LN_DIM-1];",
        "logic signed [15:0] ln_beta_q12 [0:LN_DIM-1];",
        "logic signed [7:0] ln_expected_q [0:LN_DIM-1];",
        "logic signed [7:0] attn_q_q [0:ATTN_HEAD_DIM-1];",
        "logic signed [7:0] attn_k_q [0:ATTN_SEQ-1][0:ATTN_HEAD_DIM-1];",
        "logic signed [7:0] attn_v_q [0:ATTN_SEQ-1][0:ATTN_HEAD_DIM-1];",
        "logic signed [15:0] attn_prob_q15 [0:ATTN_SEQ-1];",
        "logic signed [31:0] attn_expected_score_acc [0:ATTN_SEQ-1];",
        "logic signed [31:0] attn_expected_value_acc [0:ATTN_HEAD_DIM-1];",
        "logic signed [7:0] attn_expected_value_q [0:ATTN_HEAD_DIM-1];",
        "initial begin",
    ]
    for index, value in enumerate(ln["input_q"]):
        lines.append(f"  ln_input_q12[{index}] = {sv_i16(value)};")
    for index, value in enumerate(ln["gamma_q"]):
        lines.append(f"  ln_gamma_q16[{index}] = {sv_i32(value)};")
    for index, value in enumerate(ln["beta_q"]):
        lines.append(f"  ln_beta_q12[{index}] = {sv_i16(value)};")
    for index, value in enumerate(ln["actual_q"]):
        lines.append(f"  ln_expected_q[{index}] = {sv_i8(value)};")
    for dim, value in enumerate(attn["q_q"]):
        lines.append(f"  attn_q_q[{dim}] = {sv_i8(value)};")
    for src, row in enumerate(attn["k_q"]):
        for dim, value in enumerate(row):
            lines.append(f"  attn_k_q[{src}][{dim}] = {sv_i8(value)};")
    for src, row in enumerate(attn["v_q"]):
        for dim, value in enumerate(row):
            lines.append(f"  attn_v_q[{src}][{dim}] = {sv_i8(value)};")
    for src, value in enumerate(attn["prob_q"]):
        lines.append(f"  attn_prob_q15[{src}] = {sv_i16(value)};")
    for src, value in enumerate(attn["score_acc"]):
        lines.append(f"  attn_expected_score_acc[{src}] = {sv_i32(value)};")
    for dim, value in enumerate(attn["value_acc"]):
        lines.append(f"  attn_expected_value_acc[{dim}] = {sv_i32(value)};")
    for dim, value in enumerate(attn["value_q"]):
        lines.append(f"  attn_expected_value_q[{dim}] = {sv_i8(value)};")
    lines.append("end")

    args.out_sv.parent.mkdir(parents=True, exist_ok=True)
    args.out_sv.write_text("\n".join(lines) + "\n", encoding="utf-8")
    summary = {
        "artifact_name": "task6-m2-ln-attn-sublane-selftest-tb-data",
        "status": "PASS",
        "step": args.step_index,
        "token": token_index,
        "head": args.head_index,
        "layernorm": {
            "output_scale": ln["output_scale"],
            "output_scale_mul_q20": ln["output_scale_mul"],
            "inv_std_q16": ln["inv_std_q"],
            "max_abs_lsb": ln["max_abs_lsb"],
        },
        "attention": {
            "seq_len": attn["seq_len"],
            "head_dim": attn["head_dim"],
            "q_scale": attn["q_scale"],
            "k_scale": attn["k_scale"],
            "v_scale": attn["v_scale"],
            "score_acc_min": min(attn["score_acc"]),
            "score_acc_max": max(attn["score_acc"]),
        },
    }
    args.out_json.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
