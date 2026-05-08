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
    parser.add_argument("--adapter-path", type=Path)
    parser.add_argument("--residual-add-rtl-proof-json", required=True, type=Path)
    parser.add_argument("--vocab-size", type=int, required=True)
    parser.add_argument("--physical-vocab-size", type=int)
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
    parser.add_argument("--yosys-stat-json", type=Path)
    parser.add_argument("--mapped-utilization-summary-json", type=Path)
    parser.add_argument("--lanes", type=int, default=4)
    parser.add_argument("--tile-out-dim", type=int, default=64)
    parser.add_argument(
        "--weight-quantization",
        choices=("int8", "ternary2", "ternary-base3-20"),
        default="int8",
    )
    parser.add_argument("--residual-add-requant-shift", type=int, default=24)
    parser.add_argument("--c-proj-output-requant-shift", type=int, default=24)
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
        "top_name": "task6_int8_vocab_output_head_top1_kernel",
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


def load_representative_core_builder(adapter_path: Path | None = None) -> Any:
    if adapter_path is None:
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
    os.environ["TINYSTORIES_CORE_VOCAB_SIZE"] = str(
        args.physical_vocab_size or args.vocab_size
    )
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
    def source_path(key: str, attr: str) -> Path:
        override = getattr(args, attr, None)
        if override is not None:
            return override
        return Path(sources[key])

    return argparse.Namespace(
        residual_contract_manifest=source_path(
            "residual_contract_manifest",
            "residual_contract_manifest",
        ),
        residual_boundary_json=source_path(
            "residual_boundary_json",
            "residual_boundary_json",
        ),
        c_fc_contract_manifest=source_path(
            "c_fc_contract_manifest",
            "c_fc_contract_manifest",
        ),
        c_fc_weight_pack_manifest=source_path(
            "c_fc_weight_pack_manifest",
            "c_fc_weight_pack_manifest",
        ),
        c_proj_contract_manifest=source_path(
            "c_proj_contract_manifest",
            "c_proj_contract_manifest",
        ),
        c_proj_weight_pack_manifest=source_path(
            "c_proj_weight_pack_manifest",
            "c_proj_weight_pack_manifest",
        ),
        post_gelu_requant_json=source_path(
            "post_gelu_requant_json",
            "post_gelu_requant_json",
        ),
        c_proj_output_boundary_json=source_path(
            "c_proj_output_boundary_json",
            "c_proj_output_boundary_json",
        ),
        c_proj_requant_rtl_proof_json=source_path(
            "c_proj_requant_rtl_proof_json",
            "c_proj_requant_rtl_proof_json",
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


def quantize_ternary_symmetric(values: list[float]) -> tuple[list[int], float, float]:
    mean_abs = sum(abs(value) for value in values) / len(values) if values else 0.0
    if mean_abs == 0.0:
        return [0 for _ in values], 1.0, 0.0
    threshold = 0.5 * mean_abs
    quantized = [
        1 if value >= threshold else -1 if value <= -threshold else 0
        for value in values
    ]
    return quantized, mean_abs, threshold


def pack_ternary2_weight_words(
    weight_q: list[int],
    in_features: int,
    out_features: int,
    weights_per_word: int = 16,
) -> list[int]:
    if out_features % weights_per_word != 0:
        raise SystemExit(
            f"out_features {out_features} is not divisible by {weights_per_word}"
        )
    words: list[int] = []
    for output_group_index in range(out_features // weights_per_word):
        for in_index in range(in_features):
            packed_word = 0
            for lane_index in range(weights_per_word):
                out_index = output_group_index * weights_per_word + lane_index
                weight = weight_q[out_index * in_features + in_index]
                if weight == 1:
                    code = 0b01
                elif weight == -1:
                    code = 0b11
                else:
                    code = 0b00
                packed_word |= code << (lane_index * 2)
            words.append(packed_word)
    return words


def pack_ternary_base3_weight_words(
    weight_q: list[int],
    in_features: int,
    out_features: int,
    weights_per_word: int = 20,
) -> list[int]:
    if out_features % weights_per_word != 0:
        raise SystemExit(
            f"out_features {out_features} is not divisible by {weights_per_word}"
        )
    words: list[int] = []
    for output_group_index in range(out_features // weights_per_word):
        for in_index in range(in_features):
            packed_word = 0
            power = 1
            for lane_index in range(weights_per_word):
                out_index = output_group_index * weights_per_word + lane_index
                weight = weight_q[out_index * in_features + in_index]
                if weight == 1:
                    code = 1
                elif weight == -1:
                    code = 2
                else:
                    code = 0
                packed_word += code * power
                power *= 3
            words.append(packed_word)
    return words


def build_payload(args: argparse.Namespace) -> tuple[dict[str, Any], str]:
    physical_vocab_size = args.physical_vocab_size or args.vocab_size
    if physical_vocab_size < args.vocab_size:
        raise SystemExit(
            "physical vocab size must be >= logical vocab size: "
            f"{physical_vocab_size} < {args.vocab_size}"
        )
    if physical_vocab_size % args.tile_out_dim != 0:
        raise SystemExit(
            "physical vocab size must be divisible by tile_out_dim: "
            f"{physical_vocab_size} % {args.tile_out_dim} != 0"
        )

    proof = load_json(args.residual_add_rtl_proof_json)
    hidden_q, hidden_scale, hidden_metadata = build_residual_output_q(args, proof)
    if len(hidden_q) != args.hidden_size:
        raise SystemExit(
            f"hidden vector has {len(hidden_q)} values, expected {args.hidden_size}"
        )

    set_representative_core_env(args)
    build_model = load_representative_core_builder(args.adapter_path)
    model = build_model(str(args.model_path))
    token_embedding = model.transformer.wte.weight.detach().cpu().contiguous()
    lm_head = model.lm_head.weight.detach().cpu().contiguous()
    if list(token_embedding.shape) != [physical_vocab_size, args.hidden_size]:
        raise SystemExit(
            "unexpected token embedding shape "
            f"{list(token_embedding.shape)}"
        )
    lm_head_tied = token_embedding.data_ptr() == lm_head.data_ptr()
    if not lm_head_tied:
        raise SystemExit("expected lm_head.weight to be tied to transformer.wte.weight")

    vocab_weight_f32 = [float(value) for value in token_embedding.flatten().tolist()]
    if args.weight_quantization in {"ternary2", "ternary-base3-20"}:
        vocab_weight_q, vocab_weight_scale, ternary_threshold = (
            quantize_ternary_symmetric(vocab_weight_f32)
        )
        if args.weight_quantization == "ternary-base3-20":
            packed_words = pack_ternary_base3_weight_words(
                vocab_weight_q,
                args.hidden_size,
                physical_vocab_size,
            )
            vocab_weight_mode = 2
            weight_dtype = "ternary-base3-20-per-tensor-symmetric"
        else:
            packed_words = pack_ternary2_weight_words(
                vocab_weight_q,
                args.hidden_size,
                physical_vocab_size,
            )
            vocab_weight_mode = 1
            weight_dtype = "ternary2-per-tensor-symmetric"
    else:
        vocab_weight_q, vocab_weight_scale = quantize_symmetric(vocab_weight_f32, 8)
        ternary_threshold = None
        packed_words = pack_weight_words(
            vocab_weight_q,
            args.hidden_size,
            physical_vocab_size,
            args.lanes,
        )
        vocab_weight_mode = 0
        weight_dtype = "int8-per-tensor-symmetric"
    accumulators = compute_accumulators(
        hidden_q,
        vocab_weight_q[: args.vocab_size * args.hidden_size],
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

    if status != "PASS":
        next_gate = "run the Verilator output-head top1 simulation"
    elif args.mapped_utilization_summary_json is not None:
        next_gate = "wrap the mapped output-head top1 kernel into a v4k board selftest"
    else:
        next_gate = "synthesize mapped utilization or wrap into a v4k board selftest"

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
            "physical_vocab_size": physical_vocab_size,
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
            "weight_dtype": weight_dtype,
            "output": "top1_accumulator_and_index",
            "in_dim": args.hidden_size,
            "vocab_size": physical_vocab_size,
            "valid_vocab_size": args.vocab_size,
            "lanes": args.lanes,
            "tile_out_dim": args.tile_out_dim,
            "packed_weight_words": len(packed_words),
            "local_tied_vocab_weight_memory": True,
        },
        "quantization": {
            **hidden_metadata,
            "vocab_weight_quantization": args.weight_quantization,
            "vocab_weight_mode": vocab_weight_mode,
            "vocab_weight_scale": vocab_weight_scale,
            "vocab_weight_ternary_threshold": ternary_threshold,
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
            "valid_tied_vocab_weight_int8_bytes": args.vocab_size * args.hidden_size,
            "tied_vocab_weight_f32_bytes_replaced": len(vocab_weight_q) * 4,
            "packed_weight_bytes": len(packed_words) * 4,
        },
        "sim_result": sim_result,
        "yosys_result": load_design_stats(args.yosys_stat_json),
        "mapped_utilization": load_utilization(args.mapped_utilization_summary_json),
        "decision": {
            "verdict": "promote" if status == "PASS" else "continue",
            "next_gate": next_gate,
        },
    }

    sv_lines = [
        f"localparam int IN_DIM = {args.hidden_size};",
        f"localparam int VOCAB_SIZE = {physical_vocab_size};",
        f"localparam int VALID_VOCAB_SIZE = {args.vocab_size};",
        f"localparam int TILE_OUT_DIM = {args.tile_out_dim};",
        f"localparam int LANES = {args.lanes};",
        "localparam int ACC_WIDTH = 32;",
        f"localparam int PACKED_WEIGHT_WORDS = {len(packed_words)};",
        f"localparam int PACKED_WEIGHT_ADDR_WIDTH = {addr_width(len(packed_words))};",
        f"localparam int ACTIVATION_ADDR_WIDTH = {addr_width(args.hidden_size)};",
        f"localparam int VOCAB_ADDR_WIDTH = {addr_width(args.vocab_size)};",
        f"localparam int VOCAB_WEIGHT_MODE = {vocab_weight_mode};",
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
