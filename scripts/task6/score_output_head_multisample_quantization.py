#!/usr/bin/env python3
"""Multi-sample output-head quantization sweep for Task 6."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import importlib.util
import json
import math
from pathlib import Path
import sys
from typing import Any

import torch


@dataclass(frozen=True)
class Strategy:
    name: str
    family: str
    bits_per_weight_raw: float
    weight_q: torch.Tensor
    scales: torch.Tensor
    per_row_scale: bool
    notes: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-path", required=True, type=Path)
    parser.add_argument("--adapter-path", required=True, type=Path)
    parser.add_argument("--load-pretrained", action="store_true")
    parser.add_argument("--vocab-size", type=int, default=10000)
    parser.add_argument("--num-layers", type=int, default=1)
    parser.add_argument("--max-position-embeddings", type=int, default=128)
    parser.add_argument("--window-size", type=int, default=64)
    parser.add_argument("--hidden-size", type=int, default=64)
    parser.add_argument("--num-heads", type=int, default=16)
    parser.add_argument("--model-label", default="tiny-stories-v10k-h64-l1")
    parser.add_argument("--sample-count", type=int, default=8)
    parser.add_argument("--top-k", type=int, default=10)
    parser.add_argument("--out-json", required=True, type=Path)
    parser.add_argument("--out-md", required=True, type=Path)
    return parser.parse_args()


def default_samples(vocab_size: int) -> list[tuple[str, list[int]]]:
    return [
        ("single_zero", [0]),
        ("single_one", [1]),
        ("single_two", [2]),
        ("single_eos", [vocab_size - 1]),
        ("short_increment", [0, 1, 2, 3]),
        ("short_even", [2, 4, 6, 8]),
        ("mixed_low_mid", [42, min(1024, vocab_size - 1), 17, min(2048, vocab_size - 1)]),
        ("mixed_high", [max(0, vocab_size - 7), 128, min(4096, vocab_size - 1), 7]),
    ]


def load_adapter_build_model(adapter_path: Path) -> Any:
    sys.path.insert(0, str(adapter_path.parent))
    spec = importlib.util.spec_from_file_location("task6_tinystories_adapter", adapter_path)
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


def set_model_env(args: argparse.Namespace) -> None:
    import os

    os.environ["TINYSTORIES_CORE_VOCAB_SIZE"] = str(args.vocab_size)
    os.environ["TINYSTORIES_CORE_NUM_LAYERS"] = str(args.num_layers)
    os.environ["TINYSTORIES_CORE_MAX_POSITION_EMBEDDINGS"] = str(
        args.max_position_embeddings
    )
    os.environ["TINYSTORIES_CORE_WINDOW_SIZE"] = str(args.window_size)
    os.environ["TINYSTORIES_CORE_HIDDEN_SIZE"] = str(args.hidden_size)
    os.environ["TINYSTORIES_CORE_NUM_HEADS"] = str(args.num_heads)


def quantize_symmetric_tensor(tensor: torch.Tensor, bits: int) -> tuple[torch.Tensor, torch.Tensor]:
    qmax = (1 << (bits - 1)) - 1
    max_abs = torch.max(torch.abs(tensor))
    if float(max_abs.item()) == 0.0:
        return torch.zeros_like(tensor, dtype=torch.int16), torch.tensor(1.0, dtype=torch.float64)
    scale = (max_abs / qmax).to(torch.float64)
    quantized = torch.round(tensor / scale).clamp(-qmax, qmax).to(torch.int16)
    return quantized, scale


def quantize_rowwise_symmetric(weight: torch.Tensor, bits: int) -> tuple[torch.Tensor, torch.Tensor]:
    qmax = (1 << (bits - 1)) - 1
    max_abs = torch.amax(torch.abs(weight), dim=1)
    scales = (max_abs / qmax).to(torch.float64)
    safe_scales = torch.where(scales > 0, scales, torch.ones_like(scales))
    quantized = torch.round(weight / safe_scales[:, None]).clamp(-qmax, qmax)
    quantized = torch.where(scales[:, None] > 0, quantized, torch.zeros_like(quantized))
    return quantized.to(torch.int16), scales


def quantize_ternary_per_row_lsq(
    weight: torch.Tensor,
    threshold_factor: float,
) -> tuple[torch.Tensor, torch.Tensor]:
    mean_abs = torch.mean(torch.abs(weight), dim=1)
    threshold = threshold_factor * mean_abs
    q = torch.where(
        weight >= threshold[:, None],
        torch.ones_like(weight),
        torch.where(weight <= -threshold[:, None], -torch.ones_like(weight), torch.zeros_like(weight)),
    )
    numerator = torch.sum(weight * q, dim=1)
    denominator = torch.sum(q * q, dim=1)
    scales = torch.where(denominator > 0, numerator / denominator, torch.ones_like(denominator))
    return q.to(torch.int16), scales.to(torch.float64)


def deterministic_topk(values: torch.Tensor, k: int) -> list[int]:
    as_list = [float(value) for value in values.detach().cpu().tolist()]
    return sorted(range(len(as_list)), key=lambda index: (-as_list[index], index))[:k]


def rank_of(token: int, values: torch.Tensor) -> int:
    as_list = [float(value) for value in values.detach().cpu().tolist()]
    target = as_list[token]
    better = 0
    for index, value in enumerate(as_list):
        if value > target or (value == target and index < token):
            better += 1
    return better + 1


def score_error(candidate: torch.Tensor, reference: torch.Tensor) -> dict[str, float]:
    errors = candidate.to(torch.float64) - reference.to(torch.float64)
    rmse = torch.sqrt(torch.mean(errors * errors)).item()
    signal_rms = torch.sqrt(torch.mean(reference.to(torch.float64) ** 2)).item()
    return {
        "rmse": rmse,
        "normalized_rmse": 0.0 if signal_rms == 0.0 else rmse / signal_rms,
    }


def packed_words(weight_count: int, strategy: Strategy) -> int | None:
    if strategy.family == "ternary":
        return math.ceil(weight_count / 20)
    if strategy.bits_per_weight_raw < 8:
        return math.ceil(weight_count * strategy.bits_per_weight_raw / 32)
    return None


def score_strategy(
    strategy: Strategy,
    hidden_by_sample: list[tuple[str, list[int], torch.Tensor]],
    weight_f32: torch.Tensor,
    top_k: int,
) -> dict[str, Any]:
    top1_matches = 0
    top5_overlaps: list[int] = []
    top10_overlaps: list[int] = []
    ranks: list[int] = []
    errors: list[float] = []
    sample_results: list[dict[str, Any]] = []

    weight_q = strategy.weight_q.to(torch.float64)
    scales = strategy.scales.to(torch.float64)
    zero_fraction = float(torch.mean((strategy.weight_q == 0).to(torch.float64)).item())

    for sample_id, token_ids, hidden in hidden_by_sample:
        f32_logits = weight_f32.matmul(hidden)
        quant_acc = weight_q.matmul(hidden)
        if strategy.per_row_scale:
            quant_logits = quant_acc * scales
        else:
            quant_logits = quant_acc * scales[0]

        f32_top10 = deterministic_topk(f32_logits, top_k)
        quant_top10 = deterministic_topk(quant_logits, top_k)
        f32_top5 = f32_top10[:5]
        quant_top5 = quant_top10[:5]
        f32_top1 = f32_top10[0]
        quant_top1 = quant_top10[0]
        top1_match = f32_top1 == quant_top1
        if top1_match:
            top1_matches += 1
        top5_overlap = len(set(f32_top5) & set(quant_top5))
        top10_overlap = len(set(f32_top10) & set(quant_top10))
        rank = rank_of(f32_top1, quant_logits)
        error = score_error(quant_logits, f32_logits)["normalized_rmse"]
        top5_overlaps.append(top5_overlap)
        top10_overlaps.append(top10_overlap)
        ranks.append(rank)
        errors.append(error)
        sample_results.append(
            {
                "sample_id": sample_id,
                "token_ids": token_ids,
                "f32_top1": f32_top1,
                "quant_top1": quant_top1,
                "top1_match": top1_match,
                "top5_overlap": top5_overlap,
                "top10_overlap": top10_overlap,
                "f32_top1_rank_in_quant": rank,
                "normalized_rmse": error,
            }
        )

    sample_count = len(hidden_by_sample)
    promote = (
        top1_matches == sample_count
        and min(top5_overlaps, default=0) >= 4
        and max(errors, default=1.0) <= 0.30
    )
    return {
        "name": strategy.name,
        "family": strategy.family,
        "bits_per_weight_raw": strategy.bits_per_weight_raw,
        "scale_count": int(strategy.scales.numel()),
        "zero_fraction": zero_fraction,
        "top1_matches": top1_matches,
        "sample_count": sample_count,
        "top1_match_rate": top1_matches / sample_count if sample_count else 0.0,
        "mean_top5_overlap": sum(top5_overlaps) / sample_count if sample_count else 0.0,
        "min_top5_overlap": min(top5_overlaps, default=0),
        "mean_top10_overlap": sum(top10_overlaps) / sample_count if sample_count else 0.0,
        "min_top10_overlap": min(top10_overlaps, default=0),
        "max_f32_top1_rank": max(ranks, default=0),
        "mean_normalized_rmse": sum(errors) / sample_count if sample_count else 0.0,
        "max_normalized_rmse": max(errors, default=0.0),
        "packed_words": packed_words(int(weight_f32.numel()), strategy),
        "promote": promote,
        "notes": strategy.notes,
        "samples": sample_results,
    }


def markdown_table(results: list[dict[str, Any]]) -> str:
    lines = [
        "| strategy | bits/w | scales | zero % | top1 | min top5 | mean top5 | min top10 | max rank | mean RMSE | max RMSE | packed words | promote |",
        "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |",
    ]
    for row in results:
        lines.append(
            "| "
            + " | ".join(
                [
                    row["name"],
                    f"{row['bits_per_weight_raw']:.3f}",
                    str(row["scale_count"]),
                    f"{100.0 * row['zero_fraction']:.1f}",
                    f"{row['top1_matches']}/{row['sample_count']}",
                    str(row["min_top5_overlap"]),
                    f"{row['mean_top5_overlap']:.2f}",
                    str(row["min_top10_overlap"]),
                    str(row["max_f32_top1_rank"]),
                    f"{row['mean_normalized_rmse']:.4f}",
                    f"{row['max_normalized_rmse']:.4f}",
                    "" if row["packed_words"] is None else str(row["packed_words"]),
                    "yes" if row["promote"] else "no",
                ]
            )
            + " |"
        )
    return "\n".join(lines) + "\n"


def main() -> None:
    args = parse_args()
    if not args.load_pretrained:
        set_model_env(args)
    samples = default_samples(args.vocab_size)[: args.sample_count]

    if args.load_pretrained:
        from transformers import AutoModelForCausalLM

        model = AutoModelForCausalLM.from_pretrained(
            args.model_path,
            local_files_only=True,
        ).eval()
        args.vocab_size = int(model.config.vocab_size)
        args.hidden_size = int(model.config.hidden_size)
        samples = default_samples(args.vocab_size)[: args.sample_count]
    else:
        build_model = load_adapter_build_model(args.adapter_path)
        model = build_model(str(args.model_path)).eval()
    for sample_id, token_ids in samples:
        for token_id in token_ids:
            if token_id < 0 or token_id >= args.vocab_size:
                raise SystemExit(f"{sample_id} token {token_id} outside vocab {args.vocab_size}")
    weight = model.lm_head.weight.detach().cpu().to(torch.float64).contiguous()[
        : args.vocab_size, :
    ]

    hidden_by_sample: list[tuple[str, list[int], torch.Tensor]] = []
    with torch.no_grad():
        for sample_id, token_ids in samples:
            input_ids = torch.tensor([token_ids], dtype=torch.long)
            transformer_out = model.transformer(input_ids=input_ids, use_cache=False)
            hidden = transformer_out.last_hidden_state[0, -1].detach().cpu().to(torch.float64)
            hidden_by_sample.append((sample_id, token_ids, hidden))

    strategies: list[Strategy] = []
    q8, s8 = quantize_symmetric_tensor(weight, 8)
    strategies.append(Strategy("int8_per_tensor", "int8", 8.0, q8, s8.reshape(1), False, "per-tensor int8 baseline"))
    for bits in [4, 3, 2]:
        qt, st = quantize_symmetric_tensor(weight, bits)
        strategies.append(Strategy(f"int{bits}_per_tensor", f"int{bits}", float(bits), qt, st.reshape(1), False, "per-tensor signed symmetric"))
        qr, sr = quantize_rowwise_symmetric(weight, bits)
        strategies.append(Strategy(f"int{bits}_per_row", f"int{bits}", float(bits), qr, sr, True, "per-row signed symmetric"))
    tq, ts = quantize_ternary_per_row_lsq(weight, 0.25)
    strategies.append(Strategy("ternary_per_row_t0.25_lsq", "ternary", math.log2(3), tq, ts, True, "best single-sample ternary comparator"))

    results = [score_strategy(strategy, hidden_by_sample, weight, args.top_k) for strategy in strategies]
    results.sort(
        key=lambda row: (
            not row["promote"],
            -row["top1_match_rate"],
            -row["min_top5_overlap"],
            row["max_normalized_rmse"],
            row["bits_per_weight_raw"],
        )
    )

    payload = {
        "artifact_name": "task6-output-head-multisample-quantization-sweep",
        "status": "PASS",
        "model": {
            "model_label": args.model_label,
            "vocab_size": args.vocab_size,
            "hidden_size": args.hidden_size,
            "sample_count": len(samples),
            "samples": [{"sample_id": sample_id, "token_ids": token_ids} for sample_id, token_ids in samples],
        },
        "promotion_rule": {
            "top1_matches_all_samples": True,
            "min_top5_overlap_at_least": 4,
            "max_normalized_rmse_at_most": 0.30,
        },
        "results": results,
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
