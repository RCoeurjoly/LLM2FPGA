#!/usr/bin/env python3
"""Score composed M2 block lowering: attention replay into ln_2, MLP, output."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path

import score_m2_ln1_qkv_lowering as attention
import score_m2_mlp_residual_lowering as mlp


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CONTRACT = (
    ROOT
    / "artifacts"
    / "task6"
    / "parallel-hypotheses"
    / "h2-tinystories-1m-m2-one-block-contract"
    / "manifest.json"
)
DEFAULT_WEIGHTS = (
    ROOT
    / "artifacts"
    / "task6"
    / "weights_pack"
    / "tiny-stories-1m-m2-block0-int8"
    / "manifest.json"
)
DEFAULT_POST_GELU = (
    ROOT
    / "artifacts"
    / "task6"
    / "parallel-hypotheses"
    / "h2-full-tinystories-1m-block0-c-fc-post-gelu-pwl-requant-rtl-proof.json"
)
DEFAULT_C_PROJ = (
    ROOT
    / "artifacts"
    / "task6"
    / "parallel-hypotheses"
    / "h2-full-tinystories-1m-block0-pwl-mlp-chain-c-proj-requant-rtl-proof.json"
)
DEFAULT_RESIDUAL = (
    ROOT
    / "artifacts"
    / "task6"
    / "parallel-hypotheses"
    / "h2-full-tinystories-1m-block0-pwl-mlp-chain-residual-add-rtl-proof.json"
)
DEFAULT_OUT = (
    ROOT
    / "artifacts"
    / "task6"
    / "parallel-hypotheses"
    / "h2-tinystories-1m-m2-full-block-lowering-score.json"
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--contract-manifest", type=Path, default=DEFAULT_CONTRACT)
    parser.add_argument("--weight-manifest", type=Path, default=DEFAULT_WEIGHTS)
    parser.add_argument("--post-gelu-proof-json", type=Path, default=DEFAULT_POST_GELU)
    parser.add_argument("--c-proj-proof-json", type=Path, default=DEFAULT_C_PROJ)
    parser.add_argument("--residual-add-proof-json", type=Path, default=DEFAULT_RESIDUAL)
    parser.add_argument("--out-json", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--num-heads", type=int, default=16)
    parser.add_argument("--ln1-nrmse-threshold", type=float, default=1e-6)
    parser.add_argument("--qkv-nrmse-threshold", type=float, default=0.02)
    parser.add_argument("--attention-nrmse-threshold", type=float, default=0.12)
    parser.add_argument("--ln2-nrmse-threshold", type=float, default=0.05)
    parser.add_argument("--mlp-nrmse-threshold", type=float, default=0.09)
    parser.add_argument("--block-output-nrmse-threshold", type=float, default=0.07)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    contract = attention.load_json(args.contract_manifest)
    weights = attention.load_json(args.weight_manifest)
    post_gelu_proof = attention.load_json(args.post_gelu_proof_json)
    c_proj_proof = attention.load_json(args.c_proj_proof_json)
    residual_proof = attention.load_json(args.residual_add_proof_json)
    contract_base = args.contract_manifest.parent
    weight_base = args.weight_manifest.parent

    ln1_gamma = attention.read_f32(weight_base / attention.weight_tensor(weights, "transformer.h.0.ln_1.weight")["filename"])
    ln1_beta = attention.read_f32(weight_base / attention.weight_tensor(weights, "transformer.h.0.ln_1.bias")["filename"])
    ln2_gamma = attention.read_f32(weight_base / attention.weight_tensor(weights, "transformer.h.0.ln_2.weight")["filename"])
    ln2_beta = attention.read_f32(weight_base / attention.weight_tensor(weights, "transformer.h.0.ln_2.bias")["filename"])
    out_proj_bias = attention.read_f32(
        weight_base / attention.weight_tensor(weights, "transformer.h.0.attn.attention.out_proj.bias")["filename"]
    )

    c_fc_weight_q, c_fc_scales, c_fc_out, _c_fc_in, c_fc_tensor = mlp.read_weight_pack(
        weight_base,
        weights,
        "transformer.h.0.mlp.c_fc.weight",
    )
    c_proj_weight_q, c_proj_scales, _c_proj_out, c_proj_in, c_proj_tensor = mlp.read_weight_pack(
        weight_base,
        weights,
        "transformer.h.0.mlp.c_proj.weight",
    )
    if c_proj_in != c_fc_out:
        raise SystemExit(f"c_proj input {c_proj_in} does not match c_fc output {c_fc_out}")
    c_fc_bias = attention.read_f32(weight_base / attention.weight_tensor(weights, "transformer.h.0.mlp.c_fc.bias")["filename"])
    c_proj_bias = attention.read_f32(weight_base / attention.weight_tensor(weights, "transformer.h.0.mlp.c_proj.bias")["filename"])
    fixed_point = dict(c_proj_proof["fixed_point"])
    if fixed_point.get("gelu_approx_mode") != "pwl":
        raise SystemExit("M2 full-block scorer expects a PWL GELU proof")
    post_gelu_output_scale = float(post_gelu_proof["quantization"]["output_scale"])
    c_proj_output_scale = float(c_proj_proof["quantization"]["c_proj_output_scale"])

    step_results: list[dict] = []
    all_ln1_actual: list[float] = []
    all_ln1_expected: list[float] = []
    all_proj_results: dict[str, list[dict]] = {"q": [], "k": [], "v": []}
    all_attention_actual: list[float] = []
    all_attention_expected: list[float] = []
    all_ln2_actual: list[float] = []
    all_ln2_expected: list[float] = []
    all_mlp_actual: list[float] = []
    all_mlp_expected: list[float] = []
    all_block_actual: list[float] = []
    all_block_expected: list[float] = []
    all_ln2_q: list[int] = []
    all_post_gelu_q: list[int] = []
    all_c_proj_q: list[int] = []
    all_c_fc_accs: list[int] = []
    all_c_proj_accs: list[int] = []

    for step in contract["steps"]:
        step_index = int(step["step"])
        seq_len = int(step["sequence_length"])
        hidden = int(step["tensors"]["block_input_f32"]["shape"][-1])
        block_input = attention.reshape2(
            attention.read_f32(attention.tensor_path(contract_base, step["tensors"]["block_input_f32"])),
            seq_len,
            hidden,
        )
        ln1_expected = attention.reshape2(
            attention.read_f32(attention.tensor_path(contract_base, step["tensors"]["ln1_output_f32"])),
            seq_len,
            hidden,
        )
        attention_expected = attention.reshape2(
            attention.read_f32(attention.tensor_path(contract_base, step["tensors"]["attention_output_f32"])),
            seq_len,
            hidden,
        )
        ln2_expected = attention.reshape2(
            attention.read_f32(attention.tensor_path(contract_base, step["tensors"]["ln2_output_f32"])),
            seq_len,
            hidden,
        )
        mlp_expected = attention.reshape2(
            attention.read_f32(attention.tensor_path(contract_base, step["tensors"]["mlp_output_f32"])),
            seq_len,
            hidden,
        )
        block_expected = attention.reshape2(
            attention.read_f32(attention.tensor_path(contract_base, step["tensors"]["block_output_f32"])),
            seq_len,
            hidden,
        )

        ln1_actual = attention.layernorm_rows(block_input, ln1_gamma, ln1_beta)
        all_ln1_actual.extend(attention.flatten(ln1_actual))
        all_ln1_expected.extend(attention.flatten(ln1_expected))
        ln1_metrics = attention.metrics(attention.flatten(ln1_actual), attention.flatten(ln1_expected))

        projections: dict[str, dict] = {}
        projection_rows: dict[str, list[list[float]]] = {}
        for name in ("q", "k", "v"):
            expected = attention.reshape2(
                attention.read_f32(attention.tensor_path(contract_base, step["tensors"][f"{name}_proj_output_f32"])),
                seq_len,
                hidden,
            )
            scored, actual_rows = attention.score_projection(weight_base, weights, name, ln1_actual, expected)
            projections[name] = scored
            projection_rows[name] = actual_rows
            all_proj_results[name].append(scored)

        context_rows = attention.causal_attention_rows(
            projection_rows["q"],
            projection_rows["k"],
            projection_rows["v"],
            args.num_heads,
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

        mlp_actual: list[list[float]] = []
        row_debug: list[dict] = []
        for row in ln2_actual:
            actual_row, debug = mlp.replay_mlp_row(
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
            row_debug.append({key: value for key, value in debug.items() if not isinstance(value, list)})
            all_ln2_q.extend(debug["ln2_q"])
            all_post_gelu_q.extend(debug["post_gelu_q"])
            all_c_proj_q.extend(debug["c_proj_q"])
            all_c_fc_accs.extend(debug["c_fc_accs"])
            all_c_proj_accs.extend(debug["c_proj_accs"])

        block_actual = [
            [residual_after_attention[row][col] + mlp_actual[row][col] for col in range(hidden)]
            for row in range(seq_len)
        ]

        attention_metrics = attention.metrics(attention.flatten(attention_actual), attention.flatten(attention_expected))
        ln2_metrics = attention.metrics(attention.flatten(ln2_actual), attention.flatten(ln2_expected))
        mlp_metrics = attention.metrics(attention.flatten(mlp_actual), attention.flatten(mlp_expected))
        block_metrics = attention.metrics(attention.flatten(block_actual), attention.flatten(block_expected))
        all_attention_actual.extend(attention.flatten(attention_actual))
        all_attention_expected.extend(attention.flatten(attention_expected))
        all_ln2_actual.extend(attention.flatten(ln2_actual))
        all_ln2_expected.extend(attention.flatten(ln2_expected))
        all_mlp_actual.extend(attention.flatten(mlp_actual))
        all_mlp_expected.extend(attention.flatten(mlp_expected))
        all_block_actual.extend(attention.flatten(block_actual))
        all_block_expected.extend(attention.flatten(block_expected))

        step_results.append(
            {
                "step": step_index,
                "sequence_length": seq_len,
                "ln1_f32_replay": ln1_metrics,
                "qkv_int8_replay": projections,
                "attention_int8_replay": attention_metrics,
                "ln2_from_replayed_attention": ln2_metrics,
                "mlp_from_replayed_ln2": mlp_metrics,
                "block_output_replay": block_metrics,
                "row_quantization_ranges": {
                    "ln2_scale_min": min(item["ln2_scale"] for item in row_debug),
                    "ln2_scale_max": max(item["ln2_scale"] for item in row_debug),
                    "post_gelu_q_min": min(item["post_gelu_q_min"] for item in row_debug),
                    "post_gelu_q_max": max(item["post_gelu_q_max"] for item in row_debug),
                    "c_proj_q_min": min(item["c_proj_q_min"] for item in row_debug),
                    "c_proj_q_max": max(item["c_proj_q_max"] for item in row_debug),
                },
            }
        )

    aggregate_proj = {}
    for name in ("q", "k", "v"):
        aggregate_proj[name] = {
            "max_normalized_rmse": max(item["normalized_rmse"] for item in all_proj_results[name]),
            "max_abs_error": max(item["max_abs_error"] for item in all_proj_results[name]),
        }
    aggregate = {
        "ln1_f32_replay": attention.metrics(all_ln1_actual, all_ln1_expected),
        "qkv_int8_replay": aggregate_proj,
        "attention_int8_replay": attention.metrics(all_attention_actual, all_attention_expected),
        "ln2_from_replayed_attention": attention.metrics(all_ln2_actual, all_ln2_expected),
        "mlp_from_replayed_ln2": attention.metrics(all_mlp_actual, all_mlp_expected),
        "block_output_replay": attention.metrics(all_block_actual, all_block_expected),
    }
    verdict = (
        aggregate["ln1_f32_replay"]["normalized_rmse"] <= args.ln1_nrmse_threshold
        and all(item["max_normalized_rmse"] <= args.qkv_nrmse_threshold for item in aggregate_proj.values())
        and aggregate["attention_int8_replay"]["normalized_rmse"] <= args.attention_nrmse_threshold
        and aggregate["ln2_from_replayed_attention"]["normalized_rmse"] <= args.ln2_nrmse_threshold
        and aggregate["mlp_from_replayed_ln2"]["normalized_rmse"] <= args.mlp_nrmse_threshold
        and aggregate["block_output_replay"]["normalized_rmse"] <= args.block_output_nrmse_threshold
        and post_gelu_proof.get("status") == "PASS"
        and c_proj_proof.get("status") == "PASS"
        and residual_proof.get("status") == "PASS"
    )

    artifact = {
        "schema_version": 1,
        "artifact_name": "h2-tinystories-1m-m2-full-block-lowering-score",
        "status": "PASS" if verdict else "FAIL",
        "date": dt.datetime.now(dt.timezone.utc).isoformat(),
        "stage": "M2-one-full-block",
        "contract_manifest": str(args.contract_manifest),
        "weight_manifest": str(args.weight_manifest),
        "source_proofs": {
            "post_gelu": str(args.post_gelu_proof_json),
            "c_proj": str(args.c_proj_proof_json),
            "residual_add": str(args.residual_add_proof_json),
        },
        "policy": {
            "input_boundary": "oracle block_input tensors from the M2 one-block contract",
            "ln1": "f32 layernorm formula with f32 gamma/beta",
            "qkv": "per-token symmetric int8 activations, rowwise symmetric int8 weights, f32 row scales",
            "attention": "causal f32 softmax over replayed q/k/v; out projection uses int8 activation/weight replay plus f32 bias",
            "ln2": "f32 layernorm formula over block_input plus replayed attention output",
            "mlp": "per-token symmetric int8 ln_2 activations, rowwise symmetric int8 c_fc/c_proj weights, accepted fixed PWL GELU handoff",
            "block_output": "replayed attention residual plus replayed MLP output compared directly to oracle block_output_f32",
        },
        "thresholds": {
            "ln1_normalized_rmse": args.ln1_nrmse_threshold,
            "qkv_normalized_rmse": args.qkv_nrmse_threshold,
            "attention_normalized_rmse": args.attention_nrmse_threshold,
            "ln2_normalized_rmse": args.ln2_nrmse_threshold,
            "mlp_normalized_rmse": args.mlp_nrmse_threshold,
            "block_output_normalized_rmse": args.block_output_nrmse_threshold,
        },
        "fixed_point": fixed_point,
        "quantization": {
            "post_gelu_output_scale": post_gelu_output_scale,
            "c_proj_output_scale": c_proj_output_scale,
            "c_fc_weight_quantization": c_fc_tensor["quantization"],
            "c_proj_weight_quantization": c_proj_tensor["quantization"],
            "ln2_q_min": min(all_ln2_q),
            "ln2_q_max": max(all_ln2_q),
            "post_gelu_q_min": min(all_post_gelu_q),
            "post_gelu_q_max": max(all_post_gelu_q),
            "c_proj_q_min": min(all_c_proj_q),
            "c_proj_q_max": max(all_c_proj_q),
            "c_fc_accumulator_min": min(all_c_fc_accs),
            "c_fc_accumulator_max": max(all_c_fc_accs),
            "c_proj_accumulator_min": min(all_c_proj_accs),
            "c_proj_accumulator_max": max(all_c_proj_accs),
            "ln2_q_sha256": hashlib.sha256(mlp.pack_i8(all_ln2_q)).hexdigest(),
            "post_gelu_q_sha256": hashlib.sha256(mlp.pack_i8(all_post_gelu_q)).hexdigest(),
            "c_proj_q_sha256": hashlib.sha256(mlp.pack_i8(all_c_proj_q)).hexdigest(),
            "c_fc_accumulator_sha256": hashlib.sha256(mlp.pack_i32(all_c_fc_accs)).hexdigest(),
            "c_proj_accumulator_sha256": hashlib.sha256(mlp.pack_i32(all_c_proj_accs)).hexdigest(),
        },
        "aggregate": aggregate,
        "steps": step_results,
        "next_stage": (
            "generate an M2 full-block RTL/selftest lane from the composed fixed-point replay"
            if verdict
            else "tighten composed block scale policy before RTL generation"
        ),
    }
    args.out_json.parent.mkdir(parents=True, exist_ok=True)
    args.out_json.write_text(json.dumps(artifact, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(args.out_json)
    return 0 if verdict else 1


if __name__ == "__main__":
    raise SystemExit(main())
