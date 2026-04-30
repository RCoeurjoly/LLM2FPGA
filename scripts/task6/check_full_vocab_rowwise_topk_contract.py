#!/usr/bin/env python3
"""Replay full-vocab rowwise int8/Q0.24 top-k against f32 TinyStories logits."""

from __future__ import annotations

import argparse
import datetime as dt
import importlib.util
import json
from pathlib import Path
import sys
from typing import Any

import torch


QMAX = 127
Q024_SCALE = 1 << 24
Q024_MAX = Q024_SCALE - 1
DEFAULT_SAMPLES = [
    ("single_zero", [0]),
    ("single_one", [1]),
    ("single_two", [2]),
    ("single_eos", [50256]),
    ("short_increment", [0, 1, 2, 3]),
    ("short_even", [2, 4, 6, 8]),
    ("mixed_low_mid", [42, 1024, 17, 2048]),
    ("mixed_high", [50250, 128, 4096, 7]),
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-path", required=True, type=Path)
    parser.add_argument("--adapter-path", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--artifact-name", default="h2-full-vocab-rowwise-topk-replay")
    parser.add_argument("--date", default=dt.date.today().isoformat())
    parser.add_argument("--sample-count", type=int, default=8)
    parser.add_argument("--top-k", type=int, default=5)
    parser.add_argument("--q024-fractional-bits", type=int, default=24)
    parser.add_argument("--max-normalized-rmse", type=float, default=0.02)
    parser.add_argument("--min-top5-overlap", type=int, default=4)
    parser.add_argument("--fail-on-threshold", action="store_true")
    return parser.parse_args()


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


def quantize_symmetric_tensor(
    tensor: torch.Tensor,
) -> tuple[torch.Tensor, float]:
    max_abs = float(torch.max(torch.abs(tensor)).item())
    if max_abs == 0.0:
        return torch.zeros_like(tensor, dtype=torch.int16), 0.0
    scale = max_abs / QMAX
    quantized = torch.round(tensor / scale).clamp(-QMAX, QMAX).to(torch.int16)
    return quantized, scale


def quantize_rowwise_symmetric(
    weight: torch.Tensor,
) -> tuple[torch.Tensor, torch.Tensor]:
    max_abs = torch.amax(torch.abs(weight), dim=1)
    scales = max_abs / QMAX
    safe_scales = torch.where(scales > 0, scales, torch.ones_like(scales))
    quantized = torch.round(weight / safe_scales[:, None]).clamp(-QMAX, QMAX)
    quantized = torch.where(scales[:, None] > 0, quantized, torch.zeros_like(quantized))
    return quantized.to(torch.int16), scales.to(torch.float64)


def deterministic_topk(values: torch.Tensor, k: int) -> list[int]:
    as_list = [float(value) for value in values.detach().cpu().tolist()]
    return sorted(range(len(as_list)), key=lambda index: (-as_list[index], index))[:k]


def deterministic_topk_int(values: torch.Tensor, k: int) -> list[int]:
    as_list = [int(value) for value in values.detach().cpu().tolist()]
    return sorted(range(len(as_list)), key=lambda index: (-as_list[index], index))[:k]


def rank_of_token(scores: torch.Tensor, token: int) -> int:
    values = [int(value) for value in scores.detach().cpu().tolist()]
    target = values[token]
    better = 0
    for index, value in enumerate(values):
        if value > target or (value == target and index < token):
            better += 1
    return better + 1


def score_error(candidate: torch.Tensor, reference: torch.Tensor) -> dict[str, float]:
    errors = (candidate.to(torch.float64) - reference.to(torch.float64)).detach().cpu()
    reference = reference.to(torch.float64).detach().cpu()
    abs_errors = torch.abs(errors)
    rmse = torch.sqrt(torch.mean(errors * errors)).item()
    mean_abs = torch.mean(abs_errors).item()
    max_abs = torch.max(abs_errors).item()
    signal_mean_abs = torch.mean(torch.abs(reference)).item()
    return {
        "rmse": rmse,
        "normalized_rmse": rmse / max(signal_mean_abs, 1e-12),
        "mean_abs_error": mean_abs,
        "max_abs_error": max_abs,
        "signal_mean_abs": signal_mean_abs,
        "signal_max_abs": torch.max(torch.abs(reference)).item(),
    }


def percentile(values: list[float], q: float) -> float:
    if not values:
        return 0.0
    sorted_values = sorted(values)
    index = min(len(sorted_values) - 1, max(0, round((len(sorted_values) - 1) * q)))
    return sorted_values[index]


def summarize_errors(errors: list[dict[str, float]]) -> dict[str, float]:
    normalized = [entry["normalized_rmse"] for entry in errors]
    return {
        "min_normalized_rmse": min(normalized, default=0.0),
        "p50_normalized_rmse": percentile(normalized, 0.50),
        "p90_normalized_rmse": percentile(normalized, 0.90),
        "p95_normalized_rmse": percentile(normalized, 0.95),
        "max_normalized_rmse": max(normalized, default=0.0),
        "mean_normalized_rmse": (
            sum(normalized) / len(normalized) if normalized else 0.0
        ),
    }


def validate_samples(samples: list[tuple[str, list[int]]], vocab_size: int) -> None:
    for sample_id, token_ids in samples:
        if not token_ids:
            raise SystemExit(f"sample {sample_id} has no tokens")
        for token_id in token_ids:
            if token_id < 0 or token_id >= vocab_size:
                raise SystemExit(
                    f"sample {sample_id} token {token_id} outside vocab {vocab_size}"
                )


def main() -> None:
    args = parse_args()
    if args.q024_fractional_bits != 24:
        raise SystemExit("only Q0.24 sidecars are implemented")
    samples = DEFAULT_SAMPLES[: args.sample_count]

    build_model = load_adapter_build_model(args.adapter_path)
    model = build_model(str(args.model_path)).eval()
    if not hasattr(model, "transformer") or not hasattr(model, "lm_head"):
        raise SystemExit("expected GPT-Neo-style transformer and lm_head modules")

    tied = (
        model.transformer.wte.weight.detach().data_ptr()
        == model.lm_head.weight.detach().data_ptr()
    )
    weight = model.lm_head.weight.detach().cpu().to(torch.float64).contiguous()
    vocab_size, hidden_size = list(weight.shape)
    validate_samples(samples, vocab_size)
    bias = getattr(model.lm_head, "bias", None)
    bias_is_supported = bias is None
    if bias is not None:
        bias_is_supported = bool(torch.all(bias.detach().cpu() == 0).item())

    rowwise_q, rowwise_scales = quantize_rowwise_symmetric(weight)
    per_tensor_q, per_tensor_scale = quantize_symmetric_tensor(weight)
    q024_scales = torch.round(rowwise_scales * Q024_SCALE).to(torch.int64)
    reserved_nonzero = q024_scales > Q024_MAX
    reserved_nonzero_count = int(torch.sum(reserved_nonzero).item())
    clamped_q024_scales = torch.clamp(q024_scales, 0, Q024_MAX)

    rowwise_errors: list[dict[str, float]] = []
    per_tensor_errors: list[dict[str, float]] = []
    sample_results: list[dict[str, Any]] = []
    rowwise_top1_matches = 0
    per_tensor_top1_matches = 0
    rowwise_top5_overlaps: list[int] = []
    per_tensor_top5_overlaps: list[int] = []
    changed_top1_rows: list[dict[str, Any]] = []

    with torch.no_grad():
        for sample_id, token_ids in samples:
            input_ids = torch.tensor([token_ids], dtype=torch.long)
            transformer_out = model.transformer(input_ids=input_ids, use_cache=False)
            hidden = transformer_out.last_hidden_state[0, -1].detach().cpu().to(
                torch.float64
            )
            f32_logits = weight.matmul(hidden)
            if bias is not None:
                f32_logits = f32_logits + bias.detach().cpu().to(torch.float64)

            hidden_q, hidden_scale = quantize_symmetric_tensor(hidden)
            hidden_i64 = hidden_q.to(torch.int64)
            rowwise_acc = torch.sum(rowwise_q.to(torch.int64) * hidden_i64, dim=1)
            per_tensor_acc = torch.sum(per_tensor_q.to(torch.int64) * hidden_i64, dim=1)
            rowwise_score_q024 = rowwise_acc * clamped_q024_scales
            rowwise_logits = (
                rowwise_score_q024.to(torch.float64)
                * float(hidden_scale)
                / Q024_SCALE
            )
            per_tensor_logits = (
                per_tensor_acc.to(torch.float64)
                * float(hidden_scale)
                * float(per_tensor_scale)
            )

            f32_top5 = deterministic_topk(f32_logits, args.top_k)
            rowwise_top5 = deterministic_topk_int(rowwise_score_q024, args.top_k)
            per_tensor_top5 = deterministic_topk_int(per_tensor_acc, args.top_k)
            f32_top1 = f32_top5[0]
            rowwise_top1 = rowwise_top5[0]
            per_tensor_top1 = per_tensor_top5[0]
            rowwise_overlap = len(set(f32_top5) & set(rowwise_top5))
            per_tensor_overlap = len(set(f32_top5) & set(per_tensor_top5))

            if rowwise_top1 == f32_top1:
                rowwise_top1_matches += 1
            else:
                changed_top1_rows.append(
                    {
                        "sample_id": sample_id,
                        "f32_top1": f32_top1,
                        "rowwise_top1": rowwise_top1,
                        "f32_top1_logit": float(f32_logits[f32_top1].item()),
                        "rowwise_top1_logit": float(
                            rowwise_logits[rowwise_top1].item()
                        ),
                        "f32_top1_rowwise_rank": rank_of_token(
                            rowwise_score_q024, f32_top1
                        ),
                    }
                )
            if per_tensor_top1 == f32_top1:
                per_tensor_top1_matches += 1

            rowwise_top5_overlaps.append(rowwise_overlap)
            per_tensor_top5_overlaps.append(per_tensor_overlap)
            rowwise_error = score_error(rowwise_logits, f32_logits)
            per_tensor_error = score_error(per_tensor_logits, f32_logits)
            rowwise_errors.append(rowwise_error)
            per_tensor_errors.append(per_tensor_error)

            sample_results.append(
                {
                    "sample_id": sample_id,
                    "token_ids": token_ids,
                    "position": len(token_ids) - 1,
                    "hidden_scale": hidden_scale,
                    "f32_top5": f32_top5,
                    "rowwise_q024_top5": rowwise_top5,
                    "per_tensor_int8_top5": per_tensor_top5,
                    "rowwise_top5_overlap": rowwise_overlap,
                    "per_tensor_top5_overlap": per_tensor_overlap,
                    "rowwise_f32_top1_rank": rank_of_token(
                        rowwise_score_q024, f32_top1
                    ),
                    "per_tensor_f32_top1_rank": rank_of_token(per_tensor_acc, f32_top1),
                    "rowwise_error": rowwise_error,
                    "per_tensor_error": per_tensor_error,
                }
            )

    sample_count = len(samples)
    rowwise_match_rate = rowwise_top1_matches / sample_count if sample_count else 0.0
    per_tensor_match_rate = (
        per_tensor_top1_matches / sample_count if sample_count else 0.0
    )
    rowwise_summary = summarize_errors(rowwise_errors)
    per_tensor_summary = summarize_errors(per_tensor_errors)
    rowwise_pass = (
        bias_is_supported
        and reserved_nonzero_count == 0
        and rowwise_top1_matches == sample_count
        and min(rowwise_top5_overlaps, default=0) >= args.min_top5_overlap
        and rowwise_summary["max_normalized_rmse"] <= args.max_normalized_rmse
    )

    payload = {
        "artifact_name": args.artifact_name,
        "status": "PASS" if rowwise_pass else "FAIL",
        "date": args.date,
        "hypothesis": (
            "Full-vocab rowwise int8 weights with Q0.24 sidecar scores preserve "
            "TinyStories f32 top1/top5 on a deterministic 8-sample replay."
        ),
        "source_artifacts": {
            "model_path": str(args.model_path),
            "adapter_path": str(args.adapter_path),
            "full_vocab_rowwise_topk_contract": (
                "artifacts/task6/parallel-hypotheses/"
                "h2-full-vocab-rowwise-topk-contract.json"
            ),
            "q024_comparator_cutout_result": (
                "artifacts/task6/parallel-hypotheses/"
                "h2-q024-topk-comparator-cutout-result.json"
            ),
            "baseline_bundle": (
                "artifacts/task6/baselines/"
                "tiny-stories-1m-baseline-float-selftest-all-memory-utilization"
            ),
        },
        "model": {
            "model_label": "tiny-stories-1m-full",
            "vocab_size": vocab_size,
            "hidden_size": hidden_size,
            "sample_count": sample_count,
            "lm_head_tied_to_token_embedding": tied,
            "lm_head_bias_supported": bias_is_supported,
        },
        "quantization": {
            "activation": "per-sample symmetric int8",
            "profile_a": {
                "name": "payload-only-per-tensor",
                "weight_scale": per_tensor_scale,
                "compare_rule": "raw int32 accumulator, lower token id tie-break",
            },
            "profile_b": {
                "name": "rowwise-int8-q024-sidecar",
                "sidecar_scale": "unsigned Q0.24 in low 24 bits",
                "scale_q024_min": int(torch.min(clamped_q024_scales).item()),
                "scale_q024_max": int(torch.max(clamped_q024_scales).item()),
                "reserved_nonzero_count": reserved_nonzero_count,
                "compare_rule": (
                    "signed accumulator times unsigned Q0.24 sidecar, "
                    "lower token id tie-break"
                ),
            },
        },
        "thresholds": {
            "top1_match_rate_vs_f32": 1.0,
            "top5_overlap_min": args.min_top5_overlap,
            "max_scaled_logit_normalized_rmse": args.max_normalized_rmse,
            "allowed_changed_top1_samples": 0,
        },
        "metrics": {
            "profile_b_rowwise_q024": {
                "top1_match_count": rowwise_top1_matches,
                "top1_match_rate_vs_f32": rowwise_match_rate,
                "top5_overlap_min": min(rowwise_top5_overlaps, default=0),
                "top5_overlap_mean": (
                    sum(rowwise_top5_overlaps) / sample_count if sample_count else 0.0
                ),
                **rowwise_summary,
            },
            "profile_a_per_tensor": {
                "top1_match_count": per_tensor_top1_matches,
                "top1_match_rate_vs_f32": per_tensor_match_rate,
                "top5_overlap_min": min(per_tensor_top5_overlaps, default=0),
                "top5_overlap_mean": (
                    sum(per_tensor_top5_overlaps) / sample_count
                    if sample_count
                    else 0.0
                ),
                **per_tensor_summary,
            },
        },
        "samples": sample_results,
        "changed_top1_rows": changed_top1_rows[:8],
        "validation": {
            "python_run": True,
            "simulation_run": False,
            "synthesis_run": False,
            "hardware_run": False,
            "replay_kind": "full-vocab-output-head-only",
        },
        "decision": {
            "verdict": (
                "promote-rowwise-q024-replay"
                if rowwise_pass
                else "do-not-promote-rowwise-q024-yet"
            ),
            "rationale": (
                "The rowwise Q0.24 profile matched f32 top1/top5 thresholds on "
                "the deterministic replay."
                if rowwise_pass
                else "The rowwise Q0.24 profile missed at least one top-k or "
                "error threshold; inspect changed_top1_rows and sample metrics "
                "before DDR3 integration."
            ),
            "next_gate": (
                "Define the DDR3 row-stream interface and keep the Q0.24 "
                "comparator as the row-score unit."
                if rowwise_pass
                else "Tune calibration/profile choice or add more replay samples "
                "before any DDR3 controller work."
            ),
        },
    }

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    if args.fail_on_threshold and not rowwise_pass:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
