#!/usr/bin/env python3
"""Replay captured GEMV contracts with simple packed-weight quantization."""

from __future__ import annotations

import argparse
import csv
from dataclasses import dataclass
import json
import math
from pathlib import Path
import struct
from typing import Any


FIELDNAMES = [
    "artifact",
    "model_label",
    "module_name",
    "quantization",
    "weight_numel",
    "weight_value_storage_bytes",
    "scale_storage_bytes",
    "total_weight_storage_bytes",
    "scale",
    "max_abs_error",
    "mean_abs_error",
    "rmse",
    "normalized_rmse",
    "signal_max_abs",
    "signal_mean_abs",
    "verdict",
]


@dataclass(frozen=True)
class ReplayInput:
    artifact: str
    contract_manifest: Path
    weight_pack_manifest: Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--case",
        action="append",
        required=True,
        help=(
            "Replay case as artifact=contract_manifest=weight_pack_manifest. "
            "Repeat for multiple contracts."
        ),
    )
    parser.add_argument("--out-csv", required=True, type=Path)
    parser.add_argument("--out-json", required=True, type=Path)
    parser.add_argument("--normalized-rmse-threshold", type=float, default=0.02)
    return parser.parse_args()


def parse_case(text: str) -> ReplayInput:
    parts = text.split("=", 2)
    if len(parts) != 3:
        raise SystemExit(
            "--case must have the form artifact=contract_manifest=weight_pack_manifest"
        )
    return ReplayInput(parts[0], Path(parts[1]), Path(parts[2]))


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def tensor_by_name(manifest: dict[str, Any], name: str) -> dict[str, Any]:
    for tensor in manifest["tensors"]:
        if tensor["name"] == name:
            return tensor
    raise SystemExit(f"{manifest.get('module_name', '<unknown>')} has no {name} tensor")


def load_f32(path: Path, numel: int) -> list[float]:
    raw = path.read_bytes()
    expected_bytes = numel * 4
    if len(raw) != expected_bytes:
        raise SystemExit(f"{path}: expected {expected_bytes} bytes, got {len(raw)}")
    return list(struct.unpack(f"<{numel}f", raw))


def product(values: list[int]) -> int:
    out = 1
    for value in values:
        out *= int(value)
    return out


def quantize_symmetric(values: list[float], bits: int) -> tuple[list[int], float]:
    if bits not in {4, 8}:
        raise SystemExit(f"unsupported quantization width: {bits}")
    qmax = (1 << (bits - 1)) - 1
    max_abs = max((abs(value) for value in values), default=0.0)
    if max_abs == 0.0:
        return [0 for _ in values], 1.0
    scale = max_abs / qmax
    qmin = -qmax
    quantized = [
        max(qmin, min(qmax, int(round(value / scale))))
        for value in values
    ]
    return quantized, scale


def quantize_per_output_symmetric(
    values: list[float],
    bits: int,
    in_features: int,
    out_features: int,
) -> tuple[list[int], list[float]]:
    quantized: list[int] = []
    scales: list[float] = []
    for out_index in range(out_features):
        row = values[out_index * in_features : (out_index + 1) * in_features]
        row_quantized, row_scale = quantize_symmetric(row, bits)
        quantized.extend(row_quantized)
        scales.append(row_scale)
    return quantized, scales


def replay_linear(
    activation: list[float],
    weight: list[float],
    bias: list[float],
    in_features: int,
    out_features: int,
) -> list[float]:
    output: list[float] = []
    for out_index in range(out_features):
        acc = bias[out_index]
        weight_offset = out_index * in_features
        for in_index in range(in_features):
            acc += activation[in_index] * weight[weight_offset + in_index]
        output.append(acc)
    return output


def error_metrics(actual: list[float], expected: list[float]) -> dict[str, float]:
    if len(actual) != len(expected):
        raise SystemExit(
            f"output length mismatch: actual {len(actual)}, expected {len(expected)}"
        )
    errors = [actual_value - expected_value for actual_value, expected_value in zip(actual, expected)]
    abs_errors = [abs(value) for value in errors]
    signal_abs = [abs(value) for value in expected]
    mse = sum(value * value for value in errors) / len(errors)
    signal_mse = sum(value * value for value in expected) / len(expected)
    rmse = math.sqrt(mse)
    signal_rms = math.sqrt(signal_mse)
    return {
        "max_abs_error": max(abs_errors),
        "mean_abs_error": sum(abs_errors) / len(abs_errors),
        "rmse": rmse,
        "normalized_rmse": 0.0 if signal_rms == 0.0 else rmse / signal_rms,
        "signal_max_abs": max(signal_abs),
        "signal_mean_abs": sum(signal_abs) / len(signal_abs),
    }


def score_case(case: ReplayInput, normalized_rmse_threshold: float) -> list[dict[str, Any]]:
    contract = load_json(case.contract_manifest)
    weight_pack = load_json(case.weight_pack_manifest)
    contract_tensors = {tensor["name"]: tensor for tensor in contract["tensors"]}
    weight_tensors = {tensor["name"]: tensor for tensor in weight_pack["tensors"]}

    activation_meta = contract_tensors["activation_in"]
    expected_meta = contract_tensors["activation_out"]
    weight_meta = weight_tensors["weight"]
    bias_meta = weight_tensors["bias"]

    activation = load_f32(
        case.contract_manifest.parent / activation_meta["filename"],
        product(activation_meta["shape"]),
    )
    expected = load_f32(
        case.contract_manifest.parent / expected_meta["filename"],
        product(expected_meta["shape"]),
    )
    weight = load_f32(
        case.weight_pack_manifest.parent / weight_meta["filename"],
        product(weight_meta["shape"]),
    )
    bias = load_f32(
        case.weight_pack_manifest.parent / bias_meta["filename"],
        product(bias_meta["shape"]),
    )

    out_features, in_features = weight_meta["shape"]
    rows: list[dict[str, Any]] = []
    quantized_variants: list[tuple[str, int, list[int], float | list[float]]] = []
    for bits in (8, 4):
        quantized, scale = quantize_symmetric(weight, bits)
        quantized_variants.append((f"int{bits}-per-tensor-symmetric", bits, quantized, scale))
        per_output_quantized, per_output_scales = quantize_per_output_symmetric(
            weight,
            bits,
            int(in_features),
            int(out_features),
        )
        quantized_variants.append((
            f"int{bits}-per-output-symmetric",
            bits,
            per_output_quantized,
            per_output_scales,
        ))

    for quantization, bits, quantized, scale in quantized_variants:
        if isinstance(scale, list):
            dequantized = []
            for out_index, row_scale in enumerate(scale):
                row_offset = out_index * int(in_features)
                for in_index in range(int(in_features)):
                    dequantized.append(quantized[row_offset + in_index] * row_scale)
            scale_summary: float | str = (
                f"min={min(scale):.9g};max={max(scale):.9g};count={len(scale)}"
            )
            scale_storage_bytes = len(scale) * 4
        else:
            dequantized = [value * scale for value in quantized]
            scale_summary = scale
            scale_storage_bytes = 4

        actual = replay_linear(
            activation,
            dequantized,
            bias,
            int(in_features),
            int(out_features),
        )
        metrics = error_metrics(actual, expected)
        value_storage_bytes = len(quantized) if bits == 8 else math.ceil(len(quantized) / 2)
        rows.append({
            "artifact": case.artifact,
            "model_label": weight_pack["model_label"],
            "module_name": weight_pack["module_name"],
            "quantization": quantization,
            "weight_numel": len(quantized),
            "weight_value_storage_bytes": value_storage_bytes,
            "scale_storage_bytes": scale_storage_bytes,
            "total_weight_storage_bytes": value_storage_bytes + scale_storage_bytes,
            "scale": scale_summary,
            **metrics,
            "verdict": (
                "pass"
                if metrics["normalized_rmse"] <= normalized_rmse_threshold
                else "fail"
            ),
        })
    return rows


def write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDNAMES, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def main() -> None:
    args = parse_args()
    cases = [parse_case(text) for text in args.case]
    rows = [
        row
        for case in cases
        for row in score_case(case, args.normalized_rmse_threshold)
    ]

    write_csv(args.out_csv, rows)
    args.out_json.parent.mkdir(parents=True, exist_ok=True)
    args.out_json.write_text(
        json.dumps(
            {
                "normalized_rmse_threshold": args.normalized_rmse_threshold,
                "rows": rows,
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
