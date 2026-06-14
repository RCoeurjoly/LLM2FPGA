#!/usr/bin/env python3
"""Generate constants for an integrated all-head M2 live K/V context proof."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts" / "task6"))
sys.path.insert(0, str(ROOT / "sim"))

import score_m2_ln1_qkv_lowering as attention  # noqa: E402
import gen_task6_m2_ln_attn_live_kv_cache_tb_data as live_kv  # noqa: E402
import gen_task6_m2_ln_attn_sublane_selftest_tb_data as sublane  # noqa: E402


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--contract-manifest", required=True, type=Path)
    parser.add_argument("--weight-manifest", required=True, type=Path)
    parser.add_argument("--out-sv", required=True, type=Path)
    parser.add_argument("--out-json", required=True, type=Path)
    parser.add_argument("--step-index", type=int, default=0)
    parser.add_argument("--token-index", type=int, default=-1)
    parser.add_argument("--num-heads", type=int, default=16)
    return parser.parse_args()


def emit_2d(lines: list[str], name: str, rows: list[list[int]], formatter) -> None:
    for row_index, row in enumerate(rows):
        for col_index, value in enumerate(row):
            lines.append(f"  {name}[{row_index}][{col_index}] = {formatter(value)};")


def emit_3d(lines: list[str], name: str, rows: list[list[list[int]]], formatter) -> None:
    for index0, row0 in enumerate(rows):
        for index1, row1 in enumerate(row0):
            for index2, value in enumerate(row1):
                lines.append(f"  {name}[{index0}][{index1}][{index2}] = {formatter(value)};")


def flatten_3d(rows: list[list[list[int]]]) -> list[int]:
    return [value for row0 in rows for row1 in row0 for value in row1]


def write_hex_i8(path: Path, values: list[int]) -> None:
    path.write_text("\n".join(f"{value & 0xFF:02x}" for value in values) + "\n", encoding="utf-8")


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
    if hidden % args.num_heads != 0:
        raise SystemExit(f"hidden size {hidden} is not divisible by {args.num_heads} heads")

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

    head_dim = hidden // args.num_heads
    q_weight_rows = []
    k_weight_rows = []
    v_weight_rows = []
    q_output_mul = []
    k_output_mul = []
    v_output_mul = []
    q_expected = []
    k_expected = []
    v_expected = []
    score_scale = []
    score_acc = []
    weight_q15 = []
    prob_q15 = []
    value_acc = []
    value_q = []
    context_value_q_by_head = []
    context_float = [0.0 for _ in range(hidden)]
    head_summaries = []

    for head_index in range(args.num_heads):
        attn = sublane.attention_fixture(
            projection_rows["q"],
            projection_rows["k"],
            projection_rows["v"],
            token_index,
            head_index,
            args.num_heads,
        )
        projections = live_kv.project_rows(
            ln_fixtures,
            attn,
            weight_base,
            weights,
            head_index,
        )
        live = live_kv.live_cache_expectations(attn, projections, token_index)
        q_weight_rows.append(projections["q"][token_index]["weight_q"])
        k_weight_rows.append(projections["k"][token_index]["weight_q"])
        v_weight_rows.append(projections["v"][token_index]["weight_q"])
        q_output_mul.append(projections["q"][token_index]["output_mul_q20"])
        k_output_mul.append([projections["k"][src]["output_mul_q20"] for src in range(token_index + 1)])
        v_output_mul.append([projections["v"][src]["output_mul_q20"] for src in range(token_index + 1)])
        q_expected.append(live["q_final"])
        k_expected.append(live["k_cache"])
        v_expected.append(live["v_cache"])
        score_scale.append(live["score_scale_q20"])
        score_acc.append(live["score_acc"])
        weight_q15.append(live["softmax_weight_q15"])
        prob_q15.append(live["prob_q"])
        value_acc.append(live["value_acc"])
        value_q.append(live["value_q"])
        context_value_q_by_head.append(live["value_q"])
        base = head_index * head_dim
        for dim, value in enumerate(live["value_q"]):
            context_float[base + dim] = float(value) * float(attn["v_scale"])
        head_summaries.append(
            {
                "head": head_index,
                "value_checksum": sum((value & 0xFF) * (index + 1) for index, value in enumerate(live["value_q"])),
                "score_scale_q20": live["score_scale_q20"],
                "v_scale": attn["v_scale"],
            }
        )

    context_q, context_scale = sublane.quantize_i8(context_float)
    context_requant_mul = []
    for head_index, summary in enumerate(head_summaries):
        mul = round((float(summary["v_scale"]) / context_scale) * sublane.Q20)
        context_requant_mul.append(mul)
        base = head_index * head_dim
        for dim, raw_value in enumerate(context_value_q_by_head[head_index]):
            requant = sublane.clamp_i8(sublane.round_shift_signed(raw_value * mul, 20))
            expected = context_q[base + dim]
            if requant != expected:
                raise SystemExit(
                    "context requant mismatch "
                    f"head={head_index} dim={dim}: got {requant} expected {expected}"
                )

    args.out_sv.parent.mkdir(parents=True, exist_ok=True)
    q_weight_hex = args.out_sv.parent / "q_proj_weight_q.hex"
    k_weight_hex = args.out_sv.parent / "k_proj_weight_q.hex"
    v_weight_hex = args.out_sv.parent / "v_proj_weight_q.hex"
    write_hex_i8(q_weight_hex, flatten_3d(q_weight_rows))
    write_hex_i8(k_weight_hex, flatten_3d(k_weight_rows))
    write_hex_i8(v_weight_hex, flatten_3d(v_weight_rows))

    lines = [
        "localparam int LN_DIM = 64;",
        f"localparam int CACHE_SEQ = {token_index + 1};",
        f"localparam int NUM_HEADS = {args.num_heads};",
        f"localparam int ATTN_HEAD_DIM = {head_dim};",
        "localparam int CONTEXT_DIM = NUM_HEADS * ATTN_HEAD_DIM;",
        "localparam int PROJ_WEIGHT_COUNT = NUM_HEADS * ATTN_HEAD_DIM * LN_DIM;",
        "logic signed [15:0] ln_input_q12_by_token [0:CACHE_SEQ-1][0:LN_DIM-1];",
        "logic signed [31:0] ln_gamma_q16 [0:LN_DIM-1];",
        "logic signed [15:0] ln_beta_q12 [0:LN_DIM-1];",
        "logic signed [31:0] ln_inv_std_q16_by_token [0:CACHE_SEQ-1];",
        "logic signed [31:0] ln_output_scale_mul_q20_by_token [0:CACHE_SEQ-1];",
        "logic signed [7:0] ln_expected_q_by_token [0:CACHE_SEQ-1][0:LN_DIM-1];",
        "logic signed [31:0] softmax_score_scale_q20_by_head [0:NUM_HEADS-1];",
        "logic signed [31:0] context_requant_mul_q20_by_head [0:NUM_HEADS-1];",
        "(* rom_style = \"block\", ram_style = \"block\" *) logic signed [7:0] q_proj_weight_q [0:PROJ_WEIGHT_COUNT-1];",
        "(* rom_style = \"block\", ram_style = \"block\" *) logic signed [7:0] k_proj_weight_q [0:PROJ_WEIGHT_COUNT-1];",
        "(* rom_style = \"block\", ram_style = \"block\" *) logic signed [7:0] v_proj_weight_q [0:PROJ_WEIGHT_COUNT-1];",
        "logic signed [31:0] q_proj_output_mul_q20_final [0:NUM_HEADS-1][0:ATTN_HEAD_DIM-1];",
        "logic signed [31:0] k_proj_output_mul_q20_by_token [0:NUM_HEADS-1][0:CACHE_SEQ-1][0:ATTN_HEAD_DIM-1];",
        "logic signed [31:0] v_proj_output_mul_q20_by_token [0:NUM_HEADS-1][0:CACHE_SEQ-1][0:ATTN_HEAD_DIM-1];",
        "logic signed [7:0] q_proj_expected_q_final [0:NUM_HEADS-1][0:ATTN_HEAD_DIM-1];",
        "logic signed [7:0] k_proj_expected_q_by_token [0:NUM_HEADS-1][0:CACHE_SEQ-1][0:ATTN_HEAD_DIM-1];",
        "logic signed [7:0] v_proj_expected_q_by_token [0:NUM_HEADS-1][0:CACHE_SEQ-1][0:ATTN_HEAD_DIM-1];",
        "logic [15:0] attn_expected_weight_q15 [0:NUM_HEADS-1][0:CACHE_SEQ-1];",
        "logic [15:0] attn_prob_q15 [0:NUM_HEADS-1][0:CACHE_SEQ-1];",
        "logic signed [31:0] attn_expected_score_acc [0:NUM_HEADS-1][0:CACHE_SEQ-1];",
        "logic signed [31:0] attn_expected_value_acc [0:NUM_HEADS-1][0:ATTN_HEAD_DIM-1];",
        "logic signed [7:0] attn_expected_value_q [0:NUM_HEADS-1][0:ATTN_HEAD_DIM-1];",
        "logic signed [7:0] context_expected_q [0:CONTEXT_DIM-1];",
        "function automatic logic signed [31:0] read_ln_inv_std_q16_by_token_const(input logic [31:0] token_index);",
        "  begin",
        "    unique case (token_index)",
    ]
    for token, ln in enumerate(ln_fixtures):
        lines.append(
            f"      32'd{token}: read_ln_inv_std_q16_by_token_const = {sublane.sv_i32(ln['inv_std_q'])};"
        )
    lines.extend(
        [
            f"      default: read_ln_inv_std_q16_by_token_const = {sublane.sv_i32(ln_fixtures[-1]['inv_std_q'])};",
            "    endcase",
            "  end",
            "endfunction",
        ]
    )
    lines.extend(
        [
        "initial $readmemh(\"%s\", q_proj_weight_q);" % q_weight_hex,
        "initial $readmemh(\"%s\", k_proj_weight_q);" % k_weight_hex,
        "initial $readmemh(\"%s\", v_proj_weight_q);" % v_weight_hex,
        "initial begin",
        ]
    )
    emit_2d(lines, "ln_input_q12_by_token", [ln["input_q"] for ln in ln_fixtures], sublane.sv_i16)
    for index, value in enumerate(ln_fixtures[0]["gamma_q"]):
        lines.append(f"  ln_gamma_q16[{index}] = {sublane.sv_i32(value)};")
    for index, value in enumerate(ln_fixtures[0]["beta_q"]):
        lines.append(f"  ln_beta_q12[{index}] = {sublane.sv_i16(value)};")
    for token, ln in enumerate(ln_fixtures):
        lines.append(f"  ln_inv_std_q16_by_token[{token}] = {sublane.sv_i32(ln['inv_std_q'])};")
        lines.append(f"  ln_output_scale_mul_q20_by_token[{token}] = {sublane.sv_i32(ln['output_scale_mul'])};")
    emit_2d(lines, "ln_expected_q_by_token", [ln["actual_q"] for ln in ln_fixtures], sublane.sv_i8)
    for head_index, value in enumerate(score_scale):
        lines.append(f"  softmax_score_scale_q20_by_head[{head_index}] = {sublane.sv_i32(value)};")
    for head_index, value in enumerate(context_requant_mul):
        lines.append(f"  context_requant_mul_q20_by_head[{head_index}] = {sublane.sv_i32(value)};")
    emit_2d(lines, "q_proj_output_mul_q20_final", q_output_mul, sublane.sv_i32)
    emit_3d(lines, "k_proj_output_mul_q20_by_token", k_output_mul, sublane.sv_i32)
    emit_3d(lines, "v_proj_output_mul_q20_by_token", v_output_mul, sublane.sv_i32)
    emit_2d(lines, "q_proj_expected_q_final", q_expected, sublane.sv_i8)
    emit_3d(lines, "k_proj_expected_q_by_token", k_expected, sublane.sv_i8)
    emit_3d(lines, "v_proj_expected_q_by_token", v_expected, sublane.sv_i8)
    emit_2d(lines, "attn_expected_weight_q15", weight_q15, sublane.sv_u16)
    emit_2d(lines, "attn_prob_q15", prob_q15, sublane.sv_u16)
    emit_2d(lines, "attn_expected_score_acc", score_acc, sublane.sv_i32)
    emit_2d(lines, "attn_expected_value_acc", value_acc, sublane.sv_i32)
    emit_2d(lines, "attn_expected_value_q", value_q, sublane.sv_i8)
    for index, value in enumerate(context_q):
        lines.append(f"  context_expected_q[{index}] = {sublane.sv_i8(value)};")
    lines.append("end")

    args.out_sv.write_text("\n".join(lines) + "\n", encoding="utf-8")
    checksum = sum((value & 0xFF) * (index + 1) for index, value in enumerate(context_q))
    args.out_json.write_text(
        json.dumps(
            {
                "artifact_name": "task6-m2-ln-attn-live-kv-all-heads-context-tb-data",
                "status": "PASS",
                "step": args.step_index,
                "token": token_index,
                "num_heads": args.num_heads,
                "head_dim": head_dim,
                "cache_seq": token_index + 1,
                "context_checksum": checksum,
                "context_scale": context_scale,
                "context_sample0": "".join(f"{value & 0xff:02x}" for value in reversed(context_q[:4])),
                "context_sample1": "".join(f"{value & 0xff:02x}" for value in reversed(context_q[4:8])),
                "heads": head_summaries,
            },
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
