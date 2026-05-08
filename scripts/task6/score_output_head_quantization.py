#!/usr/bin/env python3
"""Sweep output-head quantization fidelity for Task 6.

This is intentionally Python-only.  It answers whether a quantization strategy
is worth turning into RTL before spending time on synthesis or routing.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import sys
from typing import Any


ROOT = Path(os.environ.get("TASK6_REPO_ROOT", Path(__file__).resolve().parents[2]))
SIM_DIR = ROOT / "sim"
if str(SIM_DIR) not in sys.path:
    sys.path.insert(0, str(SIM_DIR))

from gen_task6_int8_vocab_output_head_top1_tb_data import (  # noqa: E402
    build_residual_output_q,
    load_json,
    load_representative_core_builder,
    quantize_symmetric,
    set_representative_core_env,
)


@dataclass(frozen=True)
class StrategyResult:
    name: str
    family: str
    bits_per_weight_raw: float
    scale_count: int
    zero_fraction: float
    top1: int
    top1_match: bool
    top5_overlap: int
    top10_overlap: int
    float_top1_rank: int
    normalized_rmse: float
    packed_words_2bit: int | None
    packed_words_base3_20: int | None
    promote: bool
    notes: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-path", required=True, type=Path)
    parser.add_argument("--adapter-path", type=Path)
    parser.add_argument("--residual-add-rtl-proof-json", required=True, type=Path)
    parser.add_argument("--vocab-size", type=int, default=10000)
    parser.add_argument("--physical-vocab-size", type=int)
    parser.add_argument("--num-layers", type=int, default=1)
    parser.add_argument("--max-position-embeddings", type=int, default=128)
    parser.add_argument("--window-size", type=int, default=64)
    parser.add_argument("--hidden-size", type=int, default=64)
    parser.add_argument("--num-heads", type=int, default=16)
    parser.add_argument("--model-label", default="tiny-stories-v10k-h64-l1")
    parser.add_argument("--top-k", type=int, default=10)
    parser.add_argument("--residual-add-requant-shift", type=int, default=24)
    parser.add_argument("--c-proj-output-requant-shift", type=int, default=24)
    parser.add_argument("--out-json", required=True, type=Path)
    parser.add_argument("--out-md", required=True, type=Path)
    return parser.parse_args()


def first_argmax(values: list[float]) -> int:
    best_index = 0
    best_value = values[0]
    for index, value in enumerate(values[1:], start=1):
        if value > best_value:
            best_index = index
            best_value = value
    return best_index


def top_indices(values: list[float], k: int) -> list[int]:
    return sorted(range(len(values)), key=lambda index: values[index], reverse=True)[:k]


def rank_of(index: int, values: list[float]) -> int:
    target = values[index]
    return 1 + sum(1 for value in values if value > target)


def score_error(candidate: list[float], reference: list[float]) -> dict[str, float]:
    errors = [left - right for left, right in zip(candidate, reference)]
    rmse = math.sqrt(sum(value * value for value in errors) / len(errors))
    signal_rms = math.sqrt(sum(value * value for value in reference) / len(reference))
    return {
        "rmse": rmse,
        "normalized_rmse": 0.0 if signal_rms == 0.0 else rmse / signal_rms,
    }


def dot(row: list[float], vec: list[float]) -> float:
    return sum(left * right for left, right in zip(row, vec))


def matvec_rows(weight: list[float], hidden: list[float], hidden_size: int, vocab_size: int) -> list[float]:
    logits: list[float] = []
    for row_index in range(vocab_size):
        offset = row_index * hidden_size
        logits.append(dot(weight[offset : offset + hidden_size], hidden))
    return logits


def quantized_matvec(
    weight_q: list[int],
    scales: list[float],
    hidden: list[float],
    hidden_size: int,
    vocab_size: int,
    per_row_scale: bool,
) -> list[float]:
    logits: list[float] = []
    for row_index in range(vocab_size):
        offset = row_index * hidden_size
        acc = 0.0
        for in_index in range(hidden_size):
            acc += weight_q[offset + in_index] * hidden[in_index]
        scale = scales[row_index] if per_row_scale else scales[0]
        logits.append(acc * scale)
    return logits


def ternary_quantize_global(values: list[float], threshold: float, scale_mode: str) -> tuple[list[int], list[float]]:
    q = [1 if value >= threshold else -1 if value <= -threshold else 0 for value in values]
    if scale_mode == "mean_abs":
        scale = sum(abs(value) for value in values) / len(values)
    elif scale_mode == "least_squares":
        numerator = sum(value * code for value, code in zip(values, q))
        denominator = sum(code * code for code in q)
        scale = numerator / denominator if denominator else 1.0
    else:
        raise ValueError(scale_mode)
    return q, [scale]


def ternary_quantize_per_row(
    values: list[float],
    hidden_size: int,
    vocab_size: int,
    threshold_factor: float,
    scale_mode: str,
) -> tuple[list[int], list[float]]:
    q: list[int] = []
    scales: list[float] = []
    for row_index in range(vocab_size):
        row = values[row_index * hidden_size : (row_index + 1) * hidden_size]
        mean_abs = sum(abs(value) for value in row) / len(row)
        threshold = threshold_factor * mean_abs
        row_q = [1 if value >= threshold else -1 if value <= -threshold else 0 for value in row]
        if scale_mode == "mean_abs":
            scale = mean_abs
        elif scale_mode == "least_squares":
            numerator = sum(value * code for value, code in zip(row, row_q))
            denominator = sum(code * code for code in row_q)
            scale = numerator / denominator if denominator else 1.0
        else:
            raise ValueError(scale_mode)
        q.extend(row_q)
        scales.append(scale)
    return q, scales


def ternary_quantize_per_row_grid(
    values: list[float],
    hidden_size: int,
    vocab_size: int,
    threshold_factors: list[float],
) -> tuple[list[int], list[float], list[float]]:
    q: list[int] = []
    scales: list[float] = []
    chosen_thresholds: list[float] = []
    for row_index in range(vocab_size):
        row = values[row_index * hidden_size : (row_index + 1) * hidden_size]
        mean_abs = sum(abs(value) for value in row) / len(row)
        best_error = float("inf")
        best_q: list[int] = []
        best_scale = 1.0
        best_threshold = 0.0
        for factor in threshold_factors:
            threshold = factor * mean_abs
            row_q = [1 if value >= threshold else -1 if value <= -threshold else 0 for value in row]
            numerator = sum(value * code for value, code in zip(row, row_q))
            denominator = sum(code * code for code in row_q)
            scale = numerator / denominator if denominator else 1.0
            error = sum((scale * code - value) ** 2 for value, code in zip(row, row_q))
            if error < best_error:
                best_error = error
                best_q = row_q
                best_scale = scale
                best_threshold = threshold
        q.extend(best_q)
        scales.append(best_scale)
        chosen_thresholds.append(best_threshold)
    return q, scales, chosen_thresholds


def quantize_per_row_symmetric(
    values: list[float],
    hidden_size: int,
    vocab_size: int,
    bits: int,
) -> tuple[list[int], list[float]]:
    q: list[int] = []
    scales: list[float] = []
    for row_index in range(vocab_size):
        row = values[row_index * hidden_size : (row_index + 1) * hidden_size]
        row_q, row_scale = quantize_symmetric(row, bits)
        q.extend(row_q)
        scales.append(row_scale)
    return q, scales


def score_strategy(
    *,
    name: str,
    family: str,
    bits_per_weight_raw: float,
    weight_q: list[int],
    scales: list[float],
    per_row_scale: bool,
    hidden: list[float],
    f32_logits: list[float],
    hidden_size: int,
    vocab_size: int,
    notes: str,
) -> StrategyResult:
    logits = quantized_matvec(
        weight_q,
        scales,
        hidden,
        hidden_size,
        vocab_size,
        per_row_scale=per_row_scale,
    )
    f32_top1 = first_argmax(f32_logits)
    top1 = first_argmax(logits)
    f32_top5 = set(top_indices(f32_logits, 5))
    f32_top10 = set(top_indices(f32_logits, 10))
    strategy_top5 = set(top_indices(logits, 5))
    strategy_top10 = set(top_indices(logits, 10))
    metrics = score_error(logits, f32_logits)
    zero_fraction = sum(1 for value in weight_q if value == 0) / len(weight_q)
    packed_words_lowbit = (
        math.ceil(len(weight_q) * bits_per_weight_raw / 32)
        if family.startswith("int") and bits_per_weight_raw < 8.0
        else None
    )
    return StrategyResult(
        name=name,
        family=family,
        bits_per_weight_raw=bits_per_weight_raw,
        scale_count=len(scales),
        zero_fraction=zero_fraction,
        top1=top1,
        top1_match=top1 == f32_top1,
        top5_overlap=len(f32_top5 & strategy_top5),
        top10_overlap=len(f32_top10 & strategy_top10),
        float_top1_rank=rank_of(f32_top1, logits),
        normalized_rmse=metrics["normalized_rmse"],
        packed_words_2bit=math.ceil(len(weight_q) / 16) if family == "ternary" else None,
        packed_words_base3_20=(
            math.ceil(len(weight_q) / 20) if family == "ternary" else packed_words_lowbit
        ),
        promote=top1 == f32_top1 and len(f32_top5 & strategy_top5) >= 3,
        notes=notes,
    )


def markdown_table(results: list[StrategyResult]) -> str:
    lines = [
        "| strategy | family | raw bits/w | scales | zero % | top1 | top1 match | top5 overlap | top10 overlap | float top1 rank | norm RMSE | base3 words | promote |",
        "| --- | --- | ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | --- |",
    ]
    for row in results:
        lines.append(
            "| "
            + " | ".join(
                [
                    row.name,
                    row.family,
                    f"{row.bits_per_weight_raw:.3f}",
                    str(row.scale_count),
                    f"{100.0 * row.zero_fraction:.1f}",
                    str(row.top1),
                    "yes" if row.top1_match else "no",
                    str(row.top5_overlap),
                    str(row.top10_overlap),
                    str(row.float_top1_rank),
                    f"{row.normalized_rmse:.4f}",
                    "" if row.packed_words_base3_20 is None else str(row.packed_words_base3_20),
                    "yes" if row.promote else "no",
                ]
            )
            + " |"
        )
    return "\n".join(lines) + "\n"


def result_to_dict(row: StrategyResult) -> dict[str, Any]:
    return {
        "name": row.name,
        "family": row.family,
        "bits_per_weight_raw": row.bits_per_weight_raw,
        "scale_count": row.scale_count,
        "zero_fraction": row.zero_fraction,
        "top1": row.top1,
        "top1_match": row.top1_match,
        "top5_overlap": row.top5_overlap,
        "top10_overlap": row.top10_overlap,
        "float_top1_rank": row.float_top1_rank,
        "normalized_rmse": row.normalized_rmse,
        "packed_words_2bit": row.packed_words_2bit,
        "packed_words_base3_20": row.packed_words_base3_20,
        "promote": row.promote,
        "notes": row.notes,
    }


def main() -> None:
    args = parse_args()
    os.chdir(ROOT)
    physical_vocab_size = args.physical_vocab_size or args.vocab_size
    proof = load_json(args.residual_add_rtl_proof_json)
    hidden_q, hidden_scale, hidden_metadata = build_residual_output_q(args, proof)
    hidden = [value * hidden_scale for value in hidden_q]

    set_representative_core_env(args)
    build_model = load_representative_core_builder(args.adapter_path)
    model = build_model(str(args.model_path))
    token_embedding = model.transformer.wte.weight.detach().cpu().contiguous()
    if list(token_embedding.shape) != [physical_vocab_size, args.hidden_size]:
        raise SystemExit(
            f"unexpected token embedding shape {list(token_embedding.shape)}"
        )
    weight = [
        float(value)
        for value in token_embedding[: args.vocab_size, :].flatten().tolist()
    ]
    f32_logits = matvec_rows(weight, hidden, args.hidden_size, args.vocab_size)
    f32_top1 = first_argmax(f32_logits)

    results: list[StrategyResult] = []

    int8_q, int8_scale = quantize_symmetric(weight, 8)
    results.append(
        score_strategy(
            name="int8_per_tensor",
            family="int8",
            bits_per_weight_raw=8.0,
            weight_q=int8_q,
            scales=[int8_scale],
            per_row_scale=False,
            hidden=hidden,
            f32_logits=f32_logits,
            hidden_size=args.hidden_size,
            vocab_size=args.vocab_size,
            notes="current simple int8 reference style",
        )
    )

    for bits in [4, 3, 2]:
        q, scale = quantize_symmetric(weight, bits)
        results.append(
            score_strategy(
                name=f"int{bits}_per_tensor",
                family=f"int{bits}",
                bits_per_weight_raw=float(bits),
                weight_q=q,
                scales=[scale],
                per_row_scale=False,
                hidden=hidden,
                f32_logits=f32_logits,
                hidden_size=args.hidden_size,
                vocab_size=args.vocab_size,
                notes=f"{bits}-bit signed symmetric per-tensor scale",
            )
        )

        q, scales = quantize_per_row_symmetric(
            weight,
            args.hidden_size,
            args.vocab_size,
            bits,
        )
        results.append(
            score_strategy(
                name=f"int{bits}_per_row",
                family=f"int{bits}",
                bits_per_weight_raw=float(bits),
                weight_q=q,
                scales=scales,
                per_row_scale=True,
                hidden=hidden,
                f32_logits=f32_logits,
                hidden_size=args.hidden_size,
                vocab_size=args.vocab_size,
                notes=f"{bits}-bit signed symmetric per-output scale",
            )
        )

    mean_abs = sum(abs(value) for value in weight) / len(weight)
    for factor in [0.0, 0.25, 0.5, 0.75, 1.0, 1.25]:
        threshold = factor * mean_abs
        for scale_mode in ["mean_abs", "least_squares"]:
            q, scales = ternary_quantize_global(weight, threshold, scale_mode)
            results.append(
                score_strategy(
                    name=f"ternary_global_t{factor:g}_{scale_mode}",
                    family="ternary",
                    bits_per_weight_raw=math.log2(3),
                    weight_q=q,
                    scales=scales,
                    per_row_scale=False,
                    hidden=hidden,
                    f32_logits=f32_logits,
                    hidden_size=args.hidden_size,
                    vocab_size=args.vocab_size,
                    notes=f"global threshold={threshold:.6g}",
                )
            )

    for factor in [0.25, 0.5, 0.75, 1.0]:
        for scale_mode in ["mean_abs", "least_squares"]:
            q, scales = ternary_quantize_per_row(
                weight,
                args.hidden_size,
                args.vocab_size,
                factor,
                scale_mode,
            )
            results.append(
                score_strategy(
                    name=f"ternary_per_row_t{factor:g}_{scale_mode}",
                    family="ternary",
                    bits_per_weight_raw=math.log2(3),
                    weight_q=q,
                    scales=scales,
                    per_row_scale=True,
                    hidden=hidden,
                    f32_logits=f32_logits,
                    hidden_size=args.hidden_size,
                    vocab_size=args.vocab_size,
                    notes="per-output threshold and scale",
                )
            )

    q, scales, thresholds = ternary_quantize_per_row_grid(
        weight,
        args.hidden_size,
        args.vocab_size,
        [0.0, 0.15, 0.25, 0.35, 0.5, 0.65, 0.8, 1.0, 1.25],
    )
    results.append(
        score_strategy(
            name="ternary_per_row_grid_lsq",
            family="ternary",
            bits_per_weight_raw=math.log2(3),
            weight_q=q,
            scales=scales,
            per_row_scale=True,
            hidden=hidden,
            f32_logits=f32_logits,
            hidden_size=args.hidden_size,
            vocab_size=args.vocab_size,
            notes="per-output threshold selected by row MSE grid",
        )
    )

    results.sort(
        key=lambda row: (
            not row.top1_match,
            -row.top5_overlap,
            row.float_top1_rank,
            row.normalized_rmse,
        )
    )

    payload = {
        "artifact_name": "task6-output-head-quantization-sweep",
        "status": "PASS",
        "model": {
            "model_label": args.model_label,
            "vocab_size": args.vocab_size,
            "physical_vocab_size": physical_vocab_size,
            "hidden_size": args.hidden_size,
            "float_top1": f32_top1,
            "float_top10": top_indices(f32_logits, 10),
        },
        "hidden": {
            "source": str(args.residual_add_rtl_proof_json),
            "scale": hidden_scale,
            "q_sha256": hashlib.sha256(bytes((value & 0xFF) for value in hidden_q)).hexdigest(),
            "metadata": hidden_metadata,
        },
        "results": [result_to_dict(row) for row in results],
        "markdown_table": markdown_table(results),
    }
    args.out_json.parent.mkdir(parents=True, exist_ok=True)
    args.out_json.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    args.out_md.parent.mkdir(parents=True, exist_ok=True)
    args.out_md.write_text(markdown_table(results), encoding="utf-8")
    print(args.out_json)
    print(args.out_md)


if __name__ == "__main__":
    main()
