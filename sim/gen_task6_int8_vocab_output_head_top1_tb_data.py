#!/usr/bin/env python3
"""Emit data for the v4k tied vocab output-head top-1 RTL proof."""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import sys
from typing import Any

from gen_task6_int8_l2_c_proj_from_post_gelu_tb_data import (
    compute_accumulators,
    load_contract_tensor,
    load_json,
    pack_i8,
    pack_i32,
    pack_u32,
    pack_weight_words,
    quantize_symmetric,
    round_shift_signed,
    saturate_i8,
    signed_hex,
)
from gen_task6_int8_l2_mlp_chain_residual_add_tb_data import (
    build_c_proj_int8_output,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-path", required=True, type=Path)
    parser.add_argument("--residual-add-rtl-proof-json", required=True, type=Path)
    parser.add_argument("--vocab-size", type=int, required=True)
    parser.add_argument("--num-layers", type=int, required=True)
    parser.add_argument("--max-position-embeddings", type=int, required=True)
    parser.add_argument("--window-size", type=int, required=True)
    parser.add_argument("--hidden-size", type=int, required=True)
    parser.add_argument("--num-heads", type=int, required=True)
    parser.add_argument("--model-label", required=True)
    parser.add_argument(
        "--artifact-name",
        default="h2-v4k-int8-vocab-output-head-top1-rtl-proof",
    )
    parser.add_argument("--out-sv", type=Path)
    parser.add_argument("--out-json", type=Path)
    parser.add_argument("--sim-result-json", type=Path)
    parser.add_argument("--lanes", type=int, default=4)
    parser.add_argument("--tile-out-dim", type=int, default=64)
    parser.add_argument("--residual-add-requant-shift", type=int, default=24)
    parser.add_argument("--c-proj-output-requant-shift", type=int, default=24)
    return parser.parse_args()


def load_representative_core_builder() -> Any:
    repo_root = Path(__file__).resolve().parents[1]
    adapter_path = repo_root / "TinyStories" / "model_adapter_representative_core.py"
    sys.path.insert(0, str(adapter_path.parent))
    spec = importlib.util.spec_from_file_location(
        "model_adapter_representative_core", adapter_path
    )
    if spec is None or spec.loader is None:
        raise SystemExit(f"unable to load adapter from {adapter_path}")
    module = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(module)
    finally:
        try:
            sys.path.remove(str(adapter_path.parent))
        except ValueError:
            pass
    return module.build_model


def set_representative_core_env(args: argparse.Namespace) -> None:
    os.environ["TINYSTORIES_CORE_VOCAB_SIZE"] = str(args.vocab_size)
    os.environ["TINYSTORIES_CORE_NUM_LAYERS"] = str(args.num_layers)
    os.environ["TINYSTORIES_CORE_MAX_POSITION_EMBEDDINGS"] = str(
        args.max_position_embeddings
    )
    os.environ["TINYSTORIES_CORE_WINDOW_SIZE"] = str(args.window_size)
    os.environ["TINYSTORIES_CORE_HIDDEN_SIZE"] = str(args.hidden_size)
    os.environ["TINYSTORIES_CORE_NUM_HEADS"] = str(args.num_heads)


def product(values: list[int]) -> int:
    result = 1
    for value in values:
        result *= int(value)
    return result


def score_error(candidate: list[float], reference: list[float]) -> dict[str, float]:
    if len(candidate) != len(reference):
        raise ValueError("length mismatch")
    errors = [left - right for left, right in zip(candidate, reference)]
    abs_errors = [abs(value) for value in errors]
    max_abs = max(abs_errors, default=0.0)
    mean_abs = sum(abs_errors) / len(abs_errors) if abs_errors else 0.0
    rmse = (
        (sum(value * value for value in errors) / len(errors)) ** 0.5
        if errors
        else 0.0
    )
    signal_abs = [abs(value) for value in reference]
    signal_max = max(signal_abs, default=0.0)
    signal_mean = sum(signal_abs) / len(signal_abs) if signal_abs else 0.0
    denom = max(signal_mean, 1e-12)
    return {
        "max_abs_error": max_abs,
        "mean_abs_error": mean_abs,
        "rmse": rmse,
        "normalized_rmse": rmse / denom,
        "signal_max_abs": signal_max,
        "signal_mean_abs": signal_mean,
    }


def addr_width(depth: int) -> int:
    return max(1, (depth - 1).bit_length())


def residual_args_from_proof(
    args: argparse.Namespace,
    proof: dict[str, Any],
) -> argparse.Namespace:
    sources = proof["source_artifacts"]
    return argparse.Namespace(
        residual_contract_manifest=Path(sources["residual_contract_manifest"]),
        residual_boundary_json=Path(sources["residual_boundary_json"]),
        c_fc_contract_manifest=Path(sources["c_fc_contract_manifest"]),
        c_fc_weight_pack_manifest=Path(sources["c_fc_weight_pack_manifest"]),
        c_proj_contract_manifest=Path(sources["c_proj_contract_manifest"]),
        c_proj_weight_pack_manifest=Path(sources["c_proj_weight_pack_manifest"]),
        post_gelu_requant_json=Path(sources["post_gelu_requant_json"]),
        c_proj_output_boundary_json=Path(sources["c_proj_output_boundary_json"]),
        c_proj_requant_rtl_proof_json=Path(
            sources["c_proj_requant_rtl_proof_json"]
        ),
        c_proj_output_requant_shift=args.c_proj_output_requant_shift,
    )


def build_residual_output_q(
    args: argparse.Namespace,
    proof: dict[str, Any],
) -> tuple[list[int], float, dict[str, Any]]:
    residual_args = residual_args_from_proof(args, proof)
    residual_boundary = load_json(residual_args.residual_boundary_json)
    residual_f32 = load_contract_tensor(
        residual_args.residual_contract_manifest,
        "residual_activation_in",
    )
    residual_q, residual_scale = quantize_symmetric(residual_f32, 8)
    c_proj_output_q, _c_proj_output_dequantized, c_proj_metadata = (
        build_c_proj_int8_output(residual_args)
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
    final_output_q = [
        saturate_i8(
            round_shift_signed(
                residual_q[index] * residual_requant_mult
                + c_proj_output_q[index] * c_proj_requant_mult,
                args.residual_add_requant_shift,
            )
        )
        for index in range(len(residual_q))
    ]
    expected_sha = proof["quantization"]["final_output_q_sha256"]
    actual_sha = hashlib.sha256(pack_i8(final_output_q)).hexdigest()
    if actual_sha != expected_sha:
        raise SystemExit(
            "residual-add output hash mismatch: "
            f"expected {expected_sha}, got {actual_sha}"
        )
    return final_output_q, final_output_scale, {
        "residual_output_q_sha256": actual_sha,
        "residual_output_scale": final_output_scale,
        "residual_requant_mult": residual_requant_mult,
        "c_proj_residual_add_requant_mult": c_proj_requant_mult,
    }


def dot(lhs: list[float], rhs: list[float]) -> float:
    return sum(left * right for left, right in zip(lhs, rhs))


def first_argmax(values: list[int] | list[float]) -> int:
    if not values:
        raise ValueError("empty values")
    best_index = 0
    best_value = values[0]
    for index, value in enumerate(values[1:], start=1):
        if value > best_value:
            best_index = index
            best_value = value
    return best_index


def build_payload(args: argparse.Namespace) -> tuple[dict[str, Any], str]:
    proof = load_json(args.residual_add_rtl_proof_json)
    hidden_q, hidden_scale, hidden_metadata = build_residual_output_q(args, proof)
    if len(hidden_q) != args.hidden_size:
        raise SystemExit(
            f"hidden vector has {len(hidden_q)} values, expected {args.hidden_size}"
        )

    set_representative_core_env(args)
    build_model = load_representative_core_builder()
    model = build_model(str(args.model_path))
    token_embedding = model.transformer.wte.weight.detach().cpu().contiguous()
    lm_head = model.lm_head.weight.detach().cpu().contiguous()
    if list(token_embedding.shape) != [args.vocab_size, args.hidden_size]:
        raise SystemExit(
            "unexpected token embedding shape "
            f"{list(token_embedding.shape)}"
        )
    lm_head_tied = token_embedding.data_ptr() == lm_head.data_ptr()
    if not lm_head_tied:
        raise SystemExit("expected lm_head.weight to be tied to transformer.wte.weight")

    vocab_weight_f32 = [float(value) for value in token_embedding.flatten().tolist()]
    vocab_weight_q, vocab_weight_scale = quantize_symmetric(vocab_weight_f32, 8)
    packed_words = pack_weight_words(
        vocab_weight_q,
        args.hidden_size,
        args.vocab_size,
        args.lanes,
    )
    accumulators = compute_accumulators(
        hidden_q,
        vocab_weight_q,
        args.hidden_size,
        args.vocab_size,
    )
    top_index = first_argmax(accumulators)
    top_acc = accumulators[top_index]

    hidden_dequant = [value * hidden_scale for value in hidden_q]
    f32_logits = [
        dot(
            hidden_dequant,
            vocab_weight_f32[index * args.hidden_size:(index + 1) * args.hidden_size],
        )
        for index in range(args.vocab_size)
    ]
    int8_logits = [
        value * hidden_scale * vocab_weight_scale
        for value in accumulators
    ]
    f32_top_index = first_argmax(f32_logits)
    int8_top_index = first_argmax(int8_logits)

    sim_result = load_json(args.sim_result_json) if args.sim_result_json else None
    sim_pass = (
        sim_result is not None
        and sim_result.get("status") == "PASS"
        and int(sim_result.get("top_index", -1)) == top_index
        and int(sim_result.get("top_acc", 0)) == top_acc
    )
    status = "PASS" if sim_pass else "partial"
    if sim_result is not None and not sim_pass:
        status = "FAIL"

    payload = {
        "artifact_name": args.artifact_name,
        "status": status,
        "source_artifacts": {
            "model_path": str(args.model_path),
            "residual_add_rtl_proof_json": str(args.residual_add_rtl_proof_json),
        },
        "model": {
            "model_label": args.model_label,
            "vocab_size": args.vocab_size,
            "hidden_size": args.hidden_size,
            "num_layers": args.num_layers,
            "max_position_embeddings": args.max_position_embeddings,
            "window_size": args.window_size,
            "num_heads": args.num_heads,
            "lm_head_tied_to_token_embedding": lm_head_tied,
        },
        "rtl_contract": {
            "top_name": "task6_int8_vocab_output_head_top1_kernel",
            "input_dtype": "int8",
            "weight_dtype": "int8-per-tensor-symmetric",
            "output": "top1_accumulator_and_index",
            "in_dim": args.hidden_size,
            "vocab_size": args.vocab_size,
            "lanes": args.lanes,
            "tile_out_dim": args.tile_out_dim,
            "packed_weight_words": len(packed_words),
            "local_tied_vocab_weight_memory": True,
        },
        "quantization": {
            **hidden_metadata,
            "vocab_weight_scale": vocab_weight_scale,
            "vocab_weight_q_min": min(vocab_weight_q),
            "vocab_weight_q_max": max(vocab_weight_q),
            "vocab_weight_q_sha256": hashlib.sha256(pack_i8(vocab_weight_q)).hexdigest(),
            "packed_weight_sha256": hashlib.sha256(pack_u32(packed_words)).hexdigest(),
            "accumulator_sha256": hashlib.sha256(pack_i32(accumulators)).hexdigest(),
        },
        "top1": {
            "fixed_int8_top_index": top_index,
            "fixed_int8_top_acc": top_acc,
            "fixed_int8_top_logit": int8_logits[top_index],
            "f32_reference_top_index": f32_top_index,
            "f32_reference_top_logit": f32_logits[f32_top_index],
            "int8_top_matches_f32_top": top_index == f32_top_index,
        },
        "metrics": {
            "int8_logits_vs_f32_logits": score_error(int8_logits, f32_logits),
        },
        "byte_budget": {
            "hidden_int8_bytes": len(hidden_q),
            "tied_vocab_weight_int8_bytes": len(vocab_weight_q),
            "tied_vocab_weight_f32_bytes_replaced": len(vocab_weight_q) * 4,
            "packed_weight_bytes": len(packed_words) * 4,
        },
        "sim_result": sim_result,
        "decision": {
            "verdict": "promote" if status == "PASS" else "continue",
            "next_gate": (
                "synthesize mapped utilization or wrap into a v4k board selftest"
                if status == "PASS"
                else "run the Verilator output-head top1 simulation"
            ),
        },
    }

    sv_lines = [
        f"localparam int IN_DIM = {args.hidden_size};",
        f"localparam int VOCAB_SIZE = {args.vocab_size};",
        f"localparam int TILE_OUT_DIM = {args.tile_out_dim};",
        f"localparam int LANES = {args.lanes};",
        "localparam int ACC_WIDTH = 32;",
        f"localparam int PACKED_WEIGHT_WORDS = {len(packed_words)};",
        f"localparam int PACKED_WEIGHT_ADDR_WIDTH = {addr_width(len(packed_words))};",
        f"localparam int ACTIVATION_ADDR_WIDTH = {addr_width(args.hidden_size)};",
        f"localparam int VOCAB_ADDR_WIDTH = {addr_width(args.vocab_size)};",
        f"localparam logic [VOCAB_ADDR_WIDTH - 1:0] EXPECTED_TOP_INDEX = {addr_width(args.vocab_size)}'d{top_index};",
        f"localparam logic signed [ACC_WIDTH - 1:0] EXPECTED_TOP_ACC = 32'sh{signed_hex(top_acc, 32)};",
        "logic signed [7:0] activation_values [0:IN_DIM - 1];",
        "logic [LANES * 8 - 1:0] packed_weight_values [0:PACKED_WEIGHT_WORDS - 1];",
        "initial begin",
    ]
    for index, value in enumerate(hidden_q):
        sv_lines.append(f"  activation_values[{index}] = 8'sh{signed_hex(value, 8)};")
    for index, value in enumerate(packed_words):
        sv_lines.append(f"  packed_weight_values[{index}] = 32'h{value:08x};")
    sv_lines.append("end")

    return payload, "\n".join(sv_lines) + "\n"


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
