#!/usr/bin/env python3
"""Generate SV constants for the M2 full-block replay selftest."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts" / "task6"))

import score_m2_full_block_lowering as full_block  # noqa: E402
import score_m2_ln1_qkv_lowering as attention  # noqa: E402
import score_m2_mlp_residual_lowering as mlp  # noqa: E402


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--contract-manifest", required=True, type=Path)
    parser.add_argument("--weight-manifest", required=True, type=Path)
    parser.add_argument("--post-gelu-proof-json", required=True, type=Path)
    parser.add_argument("--c-proj-proof-json", required=True, type=Path)
    parser.add_argument("--residual-add-proof-json", required=True, type=Path)
    parser.add_argument("--num-heads", type=int, default=16)
    parser.add_argument("--out-sv", required=True, type=Path)
    parser.add_argument("--out-json", required=True, type=Path)
    return parser.parse_args()


def quantize_symmetric(values: list[float]) -> tuple[list[int], float]:
    max_abs = max(abs(value) for value in values)
    if max_abs == 0.0:
        return [0 for _ in values], 1.0
    scale = max_abs / 127.0
    return [max(-127, min(127, int(round(value / scale)))) for value in values], scale


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


def sv_i8_literal(value: int) -> str:
    if value < 0:
        return f"-8'sd{abs(value)}"
    return f"8'sd{value}"


def replay_block_outputs(args: argparse.Namespace) -> list[float]:
    contract = attention.load_json(args.contract_manifest)
    weights = attention.load_json(args.weight_manifest)
    post_gelu_proof = attention.load_json(args.post_gelu_proof_json)
    c_proj_proof = attention.load_json(args.c_proj_proof_json)
    residual_proof = attention.load_json(args.residual_add_proof_json)
    if post_gelu_proof.get("status") != "PASS":
        raise SystemExit("post-GELU proof is not PASS")
    if c_proj_proof.get("status") != "PASS":
        raise SystemExit("c_proj proof is not PASS")
    if residual_proof.get("status") != "PASS":
        raise SystemExit("residual-add proof is not PASS")

    contract_base = args.contract_manifest.parent
    weight_base = args.weight_manifest.parent
    ln1_gamma = attention.read_f32(weight_base / attention.weight_tensor(weights, "transformer.h.0.ln_1.weight")["filename"])
    ln1_beta = attention.read_f32(weight_base / attention.weight_tensor(weights, "transformer.h.0.ln_1.bias")["filename"])
    ln2_gamma = attention.read_f32(weight_base / attention.weight_tensor(weights, "transformer.h.0.ln_2.weight")["filename"])
    ln2_beta = attention.read_f32(weight_base / attention.weight_tensor(weights, "transformer.h.0.ln_2.bias")["filename"])
    out_proj_bias = attention.read_f32(
        weight_base / attention.weight_tensor(weights, "transformer.h.0.attn.attention.out_proj.bias")["filename"]
    )
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
        raise SystemExit(f"c_proj input {c_proj_in} does not match c_fc output {c_fc_out}")
    c_fc_bias = attention.read_f32(weight_base / attention.weight_tensor(weights, "transformer.h.0.mlp.c_fc.bias")["filename"])
    c_proj_bias = attention.read_f32(weight_base / attention.weight_tensor(weights, "transformer.h.0.mlp.c_proj.bias")["filename"])
    fixed_point = dict(c_proj_proof["fixed_point"])
    post_gelu_output_scale = float(post_gelu_proof["quantization"]["output_scale"])
    c_proj_output_scale = float(c_proj_proof["quantization"]["c_proj_output_scale"])

    block_outputs: list[float] = []
    block_expected: list[float] = []
    for step in contract["steps"]:
        seq_len = int(step["sequence_length"])
        hidden = int(step["tensors"]["block_input_f32"]["shape"][-1])
        block_input = attention.reshape2(
            attention.read_f32(attention.tensor_path(contract_base, step["tensors"]["block_input_f32"])),
            seq_len,
            hidden,
        )
        ln1_actual = attention.layernorm_rows(block_input, ln1_gamma, ln1_beta)
        projection_rows = {}
        for name in ("q", "k", "v"):
            expected = attention.reshape2(
                attention.read_f32(attention.tensor_path(contract_base, step["tensors"][f"{name}_proj_output_f32"])),
                seq_len,
                hidden,
            )
            _scored, actual_rows = attention.score_projection(weight_base, weights, name, ln1_actual, expected)
            projection_rows[name] = actual_rows
        context_rows = attention.causal_attention_rows(
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
        _out_projected_metrics, out_projected_rows = attention.score_projection(
            weight_base,
            weights,
            "out",
            context_rows,
            attention_expected,
        )
        attention_actual = attention.add_bias(out_projected_rows, out_proj_bias)
        residual_after_attention = [
            [block_input[row][col] + attention_actual[row][col] for col in range(hidden)]
            for row in range(seq_len)
        ]
        ln2_actual = attention.layernorm_rows(residual_after_attention, ln2_gamma, ln2_beta)
        mlp_actual = []
        for row in ln2_actual:
            actual_row, _debug = mlp.replay_mlp_row(
                row,
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
            mlp_actual.append(actual_row)
        block_actual = [
            [residual_after_attention[row][col] + mlp_actual[row][col] for col in range(hidden)]
            for row in range(seq_len)
        ]
        block_outputs.extend(attention.flatten(block_actual))
        block_expected.extend(
            attention.flatten(
                attention.reshape2(
                    attention.read_f32(attention.tensor_path(contract_base, step["tensors"]["block_output_f32"])),
                    seq_len,
                    hidden,
                )
            )
        )

    result = full_block.attention.metrics(block_outputs, block_expected)
    if result["normalized_rmse"] > 0.07:
        raise SystemExit(f"composed block replay exceeds threshold: {result}")
    return block_outputs


def main() -> None:
    args = parse_args()
    block_outputs = replay_block_outputs(args)
    block_q, scale = quantize_symmetric(block_outputs)
    sample0 = sample_word(block_q, 0)
    sample1 = sample_word(block_q, 4)
    expected_checksum = checksum(block_q)

    lines = [
        "localparam int M2_FULL_BLOCK_OUTPUT_COUNT = %d;" % len(block_q),
        "localparam logic [31:0] M2_FULL_BLOCK_EXPECTED_CHECKSUM = 32'h%08x;" % expected_checksum,
        "localparam logic [31:0] M2_FULL_BLOCK_EXPECTED_SAMPLE0 = 32'h%08x;" % sample0,
        "localparam logic [31:0] M2_FULL_BLOCK_EXPECTED_SAMPLE1 = 32'h%08x;" % sample1,
        "localparam int M2_FULL_BLOCK_OUTPUT_SCALE_Q24 = %d;" % int(round(scale * (1 << 24))),
        "logic signed [7:0] m2_full_block_output_q [0:M2_FULL_BLOCK_OUTPUT_COUNT-1];",
        "initial begin",
    ]
    for index, value in enumerate(block_q):
        lines.append("  m2_full_block_output_q[%d] = %s;" % (index, sv_i8_literal(value)))
    lines.append("end")

    args.out_sv.parent.mkdir(parents=True, exist_ok=True)
    args.out_sv.write_text("\n".join(lines) + "\n", encoding="utf-8")

    summary = {
        "artifact_name": "task6-m2-full-block-replay-selftest-tb-data",
        "status": "PASS",
        "output_count": len(block_q),
        "output_scale": scale,
        "output_scale_q24": int(round(scale * (1 << 24))),
        "expected_checksum": expected_checksum,
        "expected_sample0": sample0,
        "expected_sample1": sample1,
        "q_min": min(block_q),
        "q_max": max(block_q),
    }
    args.out_json.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
