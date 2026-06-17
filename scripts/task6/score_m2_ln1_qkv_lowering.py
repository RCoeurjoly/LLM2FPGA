#!/usr/bin/env python3
"""Score the first M2 lowering slice: ln_1, q/k/v, attention, and residual."""

from __future__ import annotations

import argparse
from array import array
import datetime as dt
import json
import math
from pathlib import Path
from typing import Iterable


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
DEFAULT_OUT = (
    ROOT
    / "artifacts"
    / "task6"
    / "parallel-hypotheses"
    / "h2-tinystories-1m-m2-attention-lowering-score.json"
)
QMAX = 127
EPS = 1e-5


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--contract-manifest", type=Path, default=DEFAULT_CONTRACT)
    parser.add_argument("--weight-manifest", type=Path, default=DEFAULT_WEIGHTS)
    parser.add_argument("--out-json", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--num-heads", type=int, default=16)
    parser.add_argument("--ln1-nrmse-threshold", type=float, default=1e-6)
    parser.add_argument("--qkv-nrmse-threshold", type=float, default=0.02)
    parser.add_argument("--attention-nrmse-threshold", type=float, default=0.12)
    parser.add_argument("--ln2-nrmse-threshold", type=float, default=0.05)
    return parser.parse_args()


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def read_f32(path: Path) -> list[float]:
    values = array("f")
    values.frombytes(path.read_bytes())
    return [float(item) for item in values]


def read_i8(path: Path) -> list[int]:
    values = array("b")
    values.frombytes(path.read_bytes())
    return [int(item) for item in values]


def reshape2(values: list[float], rows: int, cols: int) -> list[list[float]]:
    if len(values) != rows * cols:
        raise SystemExit(f"length {len(values)} does not match shape [{rows}, {cols}]")
    return [values[row * cols : (row + 1) * cols] for row in range(rows)]


def metrics(actual: Iterable[float], expected: Iterable[float]) -> dict[str, float]:
    actual_list = [float(item) for item in actual]
    expected_list = [float(item) for item in expected]
    if len(actual_list) != len(expected_list):
        raise SystemExit(f"metric length mismatch {len(actual_list)} vs {len(expected_list)}")
    if not actual_list:
        raise SystemExit("cannot score empty vector")
    sq_err = 0.0
    sq_sig = 0.0
    max_abs = 0.0
    for a, e in zip(actual_list, expected_list):
        err = a - e
        sq_err += err * err
        sq_sig += e * e
        max_abs = max(max_abs, abs(err))
    rmse = math.sqrt(sq_err / len(actual_list))
    signal_rms = math.sqrt(sq_sig / len(actual_list))
    return {
        "count": len(actual_list),
        "rmse": rmse,
        "signal_rms": signal_rms,
        "normalized_rmse": 0.0 if signal_rms == 0.0 else rmse / signal_rms,
        "max_abs_error": max_abs,
    }


def layernorm_rows(rows: list[list[float]], gamma: list[float], beta: list[float]) -> list[list[float]]:
    hidden = len(gamma)
    out: list[list[float]] = []
    for row in rows:
        if len(row) != hidden:
            raise SystemExit(f"layernorm row width {len(row)} != hidden {hidden}")
        mean = sum(row) / hidden
        var = sum((item - mean) * (item - mean) for item in row) / hidden
        inv_std = 1.0 / math.sqrt(var + EPS)
        out.append([(item - mean) * inv_std * gamma[index] + beta[index] for index, item in enumerate(row)])
    return out


def quantize_row_i8(row: list[float]) -> tuple[list[int], float]:
    max_abs = max(abs(item) for item in row)
    if max_abs == 0.0:
        return [0 for _ in row], 0.0
    scale = max_abs / QMAX
    return [max(-QMAX, min(QMAX, int(round(item / scale)))) for item in row], scale


def project_rows_i8(
    activation_rows: list[list[float]],
    weight_q: list[int],
    row_scales: list[float],
    out_features: int,
    in_features: int,
) -> list[list[float]]:
    if len(weight_q) != out_features * in_features:
        raise SystemExit("q weight length does not match projection shape")
    if len(row_scales) != out_features:
        raise SystemExit("row scale length does not match projection shape")
    out_rows: list[list[float]] = []
    for row in activation_rows:
        activation_q, activation_scale = quantize_row_i8(row)
        projected: list[float] = []
        for out_index in range(out_features):
            offset = out_index * in_features
            acc = 0
            for in_index in range(in_features):
                acc += activation_q[in_index] * weight_q[offset + in_index]
            projected.append(float(acc) * activation_scale * row_scales[out_index])
        out_rows.append(projected)
    return out_rows


def project_rows_dequant_weight(
    activation_rows: list[list[float]],
    weight_q: list[int],
    row_scales: list[float],
    out_features: int,
    in_features: int,
) -> list[list[float]]:
    if len(weight_q) != out_features * in_features:
        raise SystemExit("q weight length does not match projection shape")
    out_rows: list[list[float]] = []
    for row in activation_rows:
        projected: list[float] = []
        for out_index in range(out_features):
            offset = out_index * in_features
            acc = 0.0
            for in_index in range(in_features):
                acc += row[in_index] * (weight_q[offset + in_index] * row_scales[out_index])
            projected.append(acc)
        out_rows.append(projected)
    return out_rows


def add_bias(rows: list[list[float]], bias: list[float]) -> list[list[float]]:
    return [[value + bias[index] for index, value in enumerate(row)] for row in rows]


def causal_attention_rows(
    q_rows: list[list[float]],
    k_rows: list[list[float]],
    v_rows: list[list[float]],
    num_heads: int,
) -> list[list[float]]:
    seq_len = len(q_rows)
    hidden = len(q_rows[0])
    if hidden % num_heads != 0:
        raise SystemExit(f"hidden size {hidden} is not divisible by num_heads {num_heads}")
    head_dim = hidden // num_heads
    scale = 1.0 / math.sqrt(head_dim)
    output = [[0.0 for _ in range(hidden)] for _ in range(seq_len)]

    for token_index in range(seq_len):
        for head in range(num_heads):
            base = head * head_dim
            scores = []
            for src_index in range(token_index + 1):
                dot = 0.0
                for dim in range(head_dim):
                    dot += q_rows[token_index][base + dim] * k_rows[src_index][base + dim]
                scores.append(dot * scale)
            max_score = max(scores)
            exps = [math.exp(score - max_score) for score in scores]
            denom = sum(exps)
            probs = [value / denom for value in exps]
            for dim in range(head_dim):
                total = 0.0
                for src_index, prob in enumerate(probs):
                    total += prob * v_rows[src_index][base + dim]
                output[token_index][base + dim] = total
    return output


def flatten(rows: list[list[float]]) -> list[float]:
    return [item for row in rows for item in row]


def tensor_path(base: Path, tensor_meta: dict) -> Path:
    return base / tensor_meta["filename"]


def weight_tensor(weight_manifest: dict, name: str) -> dict:
    for tensor in weight_manifest["tensors"]:
        if tensor["name"] == name:
            return tensor
    raise SystemExit(f"missing weight tensor {name}")


def ensure_int8_rowwise_tensor(tensor: dict) -> None:
    q_bits = tensor.get("q_bits")
    if q_bits is None:
        if tensor.get("q_dtype") == "int8":
            q_bits = 8
        elif tensor.get("q_dtype") is not None and str(tensor.get("q_dtype")).startswith("int"):
            q_bits = str(tensor.get("q_dtype"))[3:]
        elif "int8" in tensor.get("quantization", ""):
            q_bits = 8
        else:
            q_bits = None
    if q_bits is None:
        raise SystemExit(f"tensor {tensor.get('name', '<unknown>')} missing q_bits")
    if int(q_bits) != 8:
        raise SystemExit(
            f"tensor {tensor.get('name', '<unknown>')} is quantized with q_bits={q_bits}; "
            "score_m2_ln1_qkv_lowering currently supports int8 rowwise weights only"
        )


def score_projection(
    weight_base: Path,
    weight_manifest: dict,
    projection_name: str,
    ln1_rows: list[list[float]],
    expected_rows: list[list[float]],
) -> tuple[dict, list[list[float]]]:
    tensor = weight_tensor(weight_manifest, f"transformer.h.0.attn.attention.{projection_name}_proj.weight")
    ensure_int8_rowwise_tensor(tensor)
    shape = [int(dim) for dim in tensor["shape"]]
    out_features, in_features = shape
    weight_q = read_i8(weight_base / tensor["q_filename"])
    row_scales = read_f32(weight_base / tensor["scale_filename"])
    actual_rows = project_rows_i8(ln1_rows, weight_q, row_scales, out_features, in_features)
    result = metrics(flatten(actual_rows), flatten(expected_rows))
    result["projection"] = projection_name
    result["activation_quantization"] = "per-token symmetric int8"
    result["weight_quantization"] = tensor["quantization"]
    return result, actual_rows


def projection_weights(
    weight_base: Path,
    weight_manifest: dict,
    projection_name: str,
) -> tuple[list[int], list[float], int, int, dict]:
    tensor = weight_tensor(weight_manifest, f"transformer.h.0.attn.attention.{projection_name}_proj.weight")
    ensure_int8_rowwise_tensor(tensor)
    shape = [int(dim) for dim in tensor["shape"]]
    out_features, in_features = shape
    return (
        read_i8(weight_base / tensor["q_filename"]),
        read_f32(weight_base / tensor["scale_filename"]),
        out_features,
        in_features,
        tensor,
    )


def main() -> int:
    args = parse_args()
    contract = load_json(args.contract_manifest)
    weights = load_json(args.weight_manifest)
    contract_base = args.contract_manifest.parent
    weight_base = args.weight_manifest.parent

    ln_gamma = read_f32(weight_base / weight_tensor(weights, "transformer.h.0.ln_1.weight")["filename"])
    ln_beta = read_f32(weight_base / weight_tensor(weights, "transformer.h.0.ln_1.bias")["filename"])
    ln2_gamma = read_f32(weight_base / weight_tensor(weights, "transformer.h.0.ln_2.weight")["filename"])
    ln2_beta = read_f32(weight_base / weight_tensor(weights, "transformer.h.0.ln_2.bias")["filename"])
    out_proj_bias = read_f32(weight_base / weight_tensor(weights, "transformer.h.0.attn.attention.out_proj.bias")["filename"])

    step_results: list[dict] = []
    all_ln_actual: list[float] = []
    all_ln_expected: list[float] = []
    all_proj_results: dict[str, list[dict]] = {"q": [], "k": [], "v": []}
    all_attention_actual: list[float] = []
    all_attention_expected: list[float] = []
    all_attention_dequant_actual: list[float] = []
    all_ln2_actual: list[float] = []
    all_ln2_expected: list[float] = []

    for step in contract["steps"]:
        step_index = int(step["step"])
        seq_len = int(step["sequence_length"])
        hidden = int(step["tensors"]["block_input_f32"]["shape"][-1])
        block_input = reshape2(read_f32(tensor_path(contract_base, step["tensors"]["block_input_f32"])), seq_len, hidden)
        ln_expected = reshape2(read_f32(tensor_path(contract_base, step["tensors"]["ln1_output_f32"])), seq_len, hidden)
        ln_actual = layernorm_rows(block_input, ln_gamma, ln_beta)
        ln_metrics = metrics(flatten(ln_actual), flatten(ln_expected))
        all_ln_actual.extend(flatten(ln_actual))
        all_ln_expected.extend(flatten(ln_expected))

        projections: dict[str, dict] = {}
        projection_rows: dict[str, list[list[float]]] = {}
        for name in ("q", "k", "v"):
            expected = reshape2(
                read_f32(tensor_path(contract_base, step["tensors"][f"{name}_proj_output_f32"])),
                seq_len,
                hidden,
            )
            scored, actual_rows = score_projection(weight_base, weights, name, ln_actual, expected)
            projections[name] = scored
            projection_rows[name] = actual_rows
            all_proj_results[name].append(scored)

        context_rows = causal_attention_rows(
            projection_rows["q"],
            projection_rows["k"],
            projection_rows["v"],
            args.num_heads,
        )
        out_proj_scored, out_projected_rows = score_projection(
            weight_base,
            weights,
            "out",
            context_rows,
            reshape2(read_f32(tensor_path(contract_base, step["tensors"]["attention_output_f32"])), seq_len, hidden),
        )
        out_wq, out_scales, out_features, in_features, _out_tensor = projection_weights(weight_base, weights, "out")
        out_projected_dequant_rows = project_rows_dequant_weight(
            context_rows,
            out_wq,
            out_scales,
            out_features,
            in_features,
        )
        attention_actual = add_bias(out_projected_rows, out_proj_bias)
        attention_dequant_actual = add_bias(out_projected_dequant_rows, out_proj_bias)
        attention_expected = reshape2(read_f32(tensor_path(contract_base, step["tensors"]["attention_output_f32"])), seq_len, hidden)
        attention_metrics = metrics(flatten(attention_actual), flatten(attention_expected))
        attention_dequant_metrics = metrics(flatten(attention_dequant_actual), flatten(attention_expected))
        residual_rows = [
            [block_input[row][col] + attention_actual[row][col] for col in range(hidden)]
            for row in range(seq_len)
        ]
        ln2_actual = layernorm_rows(residual_rows, ln2_gamma, ln2_beta)
        ln2_expected = reshape2(read_f32(tensor_path(contract_base, step["tensors"]["ln2_output_f32"])), seq_len, hidden)
        ln2_metrics = metrics(flatten(ln2_actual), flatten(ln2_expected))
        all_attention_actual.extend(flatten(attention_actual))
        all_attention_expected.extend(flatten(attention_expected))
        all_attention_dequant_actual.extend(flatten(attention_dequant_actual))
        all_ln2_actual.extend(flatten(ln2_actual))
        all_ln2_expected.extend(flatten(ln2_expected))

        step_results.append(
            {
                "step": step_index,
                "sequence_length": seq_len,
                "ln1_f32_replay": ln_metrics,
                "qkv_int8_replay": projections,
                "attention_int8_replay": {
                    "context_policy": "causal softmax over replayed q/k/v, f32 exp/div",
                    "out_projection": out_proj_scored,
                    "attention_output": attention_metrics,
                    "attention_output_without_context_requant": attention_dequant_metrics,
                },
                "attention_residual_ln2_replay": ln2_metrics,
            }
        )

    aggregate_proj = {}
    for name in ("q", "k", "v"):
        aggregate_proj[name] = {
            "max_normalized_rmse": max(item["normalized_rmse"] for item in all_proj_results[name]),
            "max_abs_error": max(item["max_abs_error"] for item in all_proj_results[name]),
        }

    aggregate = {
        "ln1_f32_replay": metrics(all_ln_actual, all_ln_expected),
        "qkv_int8_replay": aggregate_proj,
        "attention_int8_replay": metrics(all_attention_actual, all_attention_expected),
        "attention_without_context_requant": metrics(all_attention_dequant_actual, all_attention_expected),
        "attention_residual_ln2_replay": metrics(all_ln2_actual, all_ln2_expected),
    }
    verdict = (
        aggregate["ln1_f32_replay"]["normalized_rmse"] <= args.ln1_nrmse_threshold
        and all(item["max_normalized_rmse"] <= args.qkv_nrmse_threshold for item in aggregate_proj.values())
        and aggregate["attention_int8_replay"]["normalized_rmse"] <= args.attention_nrmse_threshold
        and aggregate["attention_residual_ln2_replay"]["normalized_rmse"] <= args.ln2_nrmse_threshold
    )
    artifact = {
        "schema_version": 1,
        "artifact_name": "h2-tinystories-1m-m2-attention-lowering-score",
        "status": "PASS" if verdict else "FAIL",
        "date": dt.datetime.now(dt.timezone.utc).isoformat(),
        "stage": "M2-one-full-block-ln1-qkv-lowering-replay",
        "milestone_target": "M2-one-full-block",
        "live_compute": False,
        "artifact_role": "offline-ln1-qkv-lowering-score",
        "contract_manifest": str(args.contract_manifest),
        "weight_manifest": str(args.weight_manifest),
        "policy": {
            "ln1": "f32 formula replay with f32 gamma/beta",
            "qkv": "per-token symmetric int8 activations, rowwise symmetric int8 weights, f32 row scales",
            "attention": "causal f32 softmax over replayed q/k/v; out projection uses int8 activation/weight replay plus f32 bias",
            "attention_residual": "block input plus replayed attention output, followed by f32 ln_2 formula",
            "attention_threshold_note": "raw attention output has small signal RMS; residual ln2 remains the stricter downstream boundary",
        },
        "thresholds": {
            "ln1_normalized_rmse": args.ln1_nrmse_threshold,
            "qkv_normalized_rmse": args.qkv_nrmse_threshold,
            "attention_normalized_rmse": args.attention_nrmse_threshold,
            "ln2_normalized_rmse": args.ln2_nrmse_threshold,
        },
        "aggregate": aggregate,
        "steps": step_results,
        "next_stage": (
            "promote attention/residual fixed-point replay"
            if verdict
            else "tighten attention/out-projection scale policy before RTL generation"
        ),
    }
    args.out_json.parent.mkdir(parents=True, exist_ok=True)
    args.out_json.write_text(json.dumps(artifact, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(args.out_json)
    return 0 if verdict else 1


if __name__ == "__main__":
    raise SystemExit(main())
