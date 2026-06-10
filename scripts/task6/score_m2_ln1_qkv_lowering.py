#!/usr/bin/env python3
"""Score the first M2 fixed-point lowering slice: ln_1 plus q/k/v projections."""

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
    / "h2-tinystories-1m-m2-ln1-qkv-lowering-score.json"
)
QMAX = 127
EPS = 1e-5


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--contract-manifest", type=Path, default=DEFAULT_CONTRACT)
    parser.add_argument("--weight-manifest", type=Path, default=DEFAULT_WEIGHTS)
    parser.add_argument("--out-json", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--ln1-nrmse-threshold", type=float, default=1e-6)
    parser.add_argument("--qkv-nrmse-threshold", type=float, default=0.02)
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


def flatten(rows: list[list[float]]) -> list[float]:
    return [item for row in rows for item in row]


def tensor_path(base: Path, tensor_meta: dict) -> Path:
    return base / tensor_meta["filename"]


def weight_tensor(weight_manifest: dict, name: str) -> dict:
    for tensor in weight_manifest["tensors"]:
        if tensor["name"] == name:
            return tensor
    raise SystemExit(f"missing weight tensor {name}")


def score_projection(
    weight_base: Path,
    weight_manifest: dict,
    projection_name: str,
    ln1_rows: list[list[float]],
    expected_rows: list[list[float]],
) -> dict:
    tensor = weight_tensor(weight_manifest, f"transformer.h.0.attn.attention.{projection_name}_proj.weight")
    shape = [int(dim) for dim in tensor["shape"]]
    out_features, in_features = shape
    weight_q = read_i8(weight_base / tensor["q_filename"])
    row_scales = read_f32(weight_base / tensor["scale_filename"])
    actual_rows = project_rows_i8(ln1_rows, weight_q, row_scales, out_features, in_features)
    result = metrics(flatten(actual_rows), flatten(expected_rows))
    result["projection"] = projection_name
    result["activation_quantization"] = "per-token symmetric int8"
    result["weight_quantization"] = tensor["quantization"]
    return result


def main() -> int:
    args = parse_args()
    contract = load_json(args.contract_manifest)
    weights = load_json(args.weight_manifest)
    contract_base = args.contract_manifest.parent
    weight_base = args.weight_manifest.parent

    ln_gamma = read_f32(weight_base / weight_tensor(weights, "transformer.h.0.ln_1.weight")["filename"])
    ln_beta = read_f32(weight_base / weight_tensor(weights, "transformer.h.0.ln_1.bias")["filename"])

    step_results: list[dict] = []
    all_ln_actual: list[float] = []
    all_ln_expected: list[float] = []
    all_proj_results: dict[str, list[dict]] = {"q": [], "k": [], "v": []}

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
        for name in ("q", "k", "v"):
            expected = reshape2(
                read_f32(tensor_path(contract_base, step["tensors"][f"{name}_proj_output_f32"])),
                seq_len,
                hidden,
            )
            scored = score_projection(weight_base, weights, name, ln_actual, expected)
            projections[name] = scored
            all_proj_results[name].append(scored)

        step_results.append(
            {
                "step": step_index,
                "sequence_length": seq_len,
                "ln1_f32_replay": ln_metrics,
                "qkv_int8_replay": projections,
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
    }
    verdict = (
        aggregate["ln1_f32_replay"]["normalized_rmse"] <= args.ln1_nrmse_threshold
        and all(item["max_normalized_rmse"] <= args.qkv_nrmse_threshold for item in aggregate_proj.values())
    )
    artifact = {
        "schema_version": 1,
        "artifact_name": "h2-tinystories-1m-m2-ln1-qkv-lowering-score",
        "status": "PASS" if verdict else "FAIL",
        "date": dt.datetime.now(dt.timezone.utc).isoformat(),
        "stage": "M2-one-full-block",
        "contract_manifest": str(args.contract_manifest),
        "weight_manifest": str(args.weight_manifest),
        "policy": {
            "ln1": "f32 formula replay with f32 gamma/beta",
            "qkv": "per-token symmetric int8 activations, rowwise symmetric int8 weights, f32 row scales",
        },
        "thresholds": {
            "ln1_normalized_rmse": args.ln1_nrmse_threshold,
            "qkv_normalized_rmse": args.qkv_nrmse_threshold,
        },
        "aggregate": aggregate,
        "steps": step_results,
        "next_stage": (
            "promote q/k/v projection fixed-point replay"
            if verdict
            else "tighten activation/weight scale policy before RTL generation"
        ),
    }
    args.out_json.parent.mkdir(parents=True, exist_ok=True)
    args.out_json.write_text(json.dumps(artifact, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(args.out_json)
    return 0 if verdict else 1


if __name__ == "__main__":
    raise SystemExit(main())
