#!/usr/bin/env python3
"""Emit int8 RTL replay data for the captured Task 6 L2 c_fc contract."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import struct
import hashlib
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--contract-manifest", required=True, type=Path)
    parser.add_argument("--weight-pack-manifest", required=True, type=Path)
    parser.add_argument("--artifact-name", default="h2-int8-l2-c-fc-local-io-contract-replay")
    parser.add_argument("--out-sv", type=Path)
    parser.add_argument("--out-json", type=Path)
    parser.add_argument("--sim-result-json", type=Path)
    parser.add_argument("--yosys-stat-json", type=Path)
    parser.add_argument("--mapped-utilization-summary-json", type=Path)
    parser.add_argument("--normalized-rmse-threshold", type=float, default=0.02)
    return parser.parse_args()


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def tensor_by_name(manifest: dict[str, Any], name: str) -> dict[str, Any]:
    for tensor in manifest["tensors"]:
        if tensor["name"] == name:
            return tensor
    raise SystemExit(f"{manifest.get('module_name', '<unknown>')} has no {name} tensor")


def product(values: list[int]) -> int:
    out = 1
    for value in values:
        out *= int(value)
    return out


def load_f32(path: Path, numel: int) -> list[float]:
    raw = path.read_bytes()
    expected_bytes = numel * 4
    if len(raw) != expected_bytes:
        raise SystemExit(f"{path}: expected {expected_bytes} bytes, got {len(raw)}")
    return list(struct.unpack(f"<{numel}f", raw))


def quantize_symmetric(values: list[float], bits: int) -> tuple[list[int], float]:
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


def error_metrics(actual: list[float], expected: list[float]) -> dict[str, float]:
    if len(actual) != len(expected):
        raise SystemExit(
            f"output length mismatch: actual {len(actual)}, expected {len(expected)}"
        )
    errors = [
        actual_value - expected_value
        for actual_value, expected_value in zip(actual, expected)
    ]
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


def signed_hex(value: int, bits: int) -> str:
    mask = (1 << bits) - 1
    digits = (bits + 3) // 4
    return f"{value & mask:0{digits}x}"


def signed_byte_blob(values: list[int]) -> bytes:
    return bytes((value & 0xFF) for value in values)


def signed_i32_blob(values: list[int]) -> bytes:
    return b"".join(struct.pack("<i", value) for value in values)


def pack_weight_words(
    weight_q: list[int],
    in_features: int,
    out_features: int,
    lanes: int,
) -> list[int]:
    if out_features % lanes != 0:
        raise SystemExit(f"out_features {out_features} is not divisible by lanes {lanes}")
    words: list[int] = []
    for output_group_index in range(out_features // lanes):
        for in_index in range(in_features):
            packed_word = 0
            for lane_index in range(lanes):
                out_index = output_group_index * lanes + lane_index
                weight = weight_q[out_index * in_features + in_index]
                packed_word |= (weight & 0xFF) << (lane_index * 8)
            words.append(packed_word)
    return words


def compute_accumulators(
    activation_q: list[int],
    weight_q: list[int],
    in_features: int,
    out_features: int,
) -> list[int]:
    accs: list[int] = []
    for out_index in range(out_features):
        weight_offset = out_index * in_features
        acc = 0
        for in_index in range(in_features):
            acc += activation_q[in_index] * weight_q[weight_offset + in_index]
        accs.append(acc)
    return accs


def dequantized_outputs(
    accs: list[int],
    activation_scale: float,
    weight_scales: list[float],
    bias: list[float],
) -> list[float]:
    return [
        bias[out_index] + acc * activation_scale * weight_scales[out_index]
        for out_index, acc in enumerate(accs)
    ]


def load_design_stats(path: Path | None) -> dict[str, Any] | None:
    if path is None:
        return None
    data = load_json(path)
    design = data.get("design", {})
    cells = design.get("num_cells_by_type", {})
    lut_cells = sum(int(cells.get(f"LUT{i}", 0)) for i in range(1, 7))
    return {
        "path": str(path),
        "top_name": "task6_int8_gemv64x256_lanes4_packed_sync_mem_local_io_kernel",
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


def build_payload(args: argparse.Namespace) -> tuple[dict[str, Any], str]:
    contract = load_json(args.contract_manifest)
    weight_pack = load_json(args.weight_pack_manifest)
    activation_meta = tensor_by_name(contract, "activation_in")
    expected_meta = tensor_by_name(contract, "activation_out")
    weight_meta = tensor_by_name(weight_pack, "weight")
    bias_meta = tensor_by_name(weight_pack, "bias")

    contract_dir = args.contract_manifest.parent
    weight_dir = args.weight_pack_manifest.parent
    activation = load_f32(
        contract_dir / activation_meta["filename"],
        product(activation_meta["shape"]),
    )
    expected = load_f32(
        contract_dir / expected_meta["filename"],
        product(expected_meta["shape"]),
    )
    weight = load_f32(
        weight_dir / weight_meta["filename"],
        product(weight_meta["shape"]),
    )
    bias = load_f32(
        weight_dir / bias_meta["filename"],
        product(bias_meta["shape"]),
    )

    out_features, in_features = [int(value) for value in weight_meta["shape"]]
    if len(activation) != in_features:
        raise SystemExit(
            f"activation length {len(activation)} does not match in_features {in_features}"
        )
    if len(expected) != out_features:
        raise SystemExit(
            f"expected length {len(expected)} does not match out_features {out_features}"
        )

    lanes = 4
    activation_q, activation_scale = quantize_symmetric(activation, 8)
    weight_q, weight_scales = quantize_per_output_symmetric(
        weight,
        8,
        in_features,
        out_features,
    )
    packed_words = pack_weight_words(weight_q, in_features, out_features, lanes)
    expected_acc = compute_accumulators(
        activation_q,
        weight_q,
        in_features,
        out_features,
    )
    actual = dequantized_outputs(
        expected_acc,
        activation_scale,
        weight_scales,
        bias,
    )
    metrics = error_metrics(actual, expected)

    activation_blob = signed_byte_blob(activation_q)
    weight_blob = signed_byte_blob(weight_q)
    packed_blob = b"".join(struct.pack("<I", word) for word in packed_words)
    expected_acc_blob = signed_i32_blob(expected_acc)

    sim_result = load_json(args.sim_result_json) if args.sim_result_json else None
    status = "PASS" if metrics["normalized_rmse"] <= args.normalized_rmse_threshold else "FAIL"
    if sim_result is None or sim_result.get("status") != "PASS":
        status = "partial" if status == "PASS" else status

    payload: dict[str, Any] = {
        "artifact_name": args.artifact_name,
        "status": status,
        "source_contract": {
            "contract_manifest": str(args.contract_manifest),
            "weight_pack_manifest": str(args.weight_pack_manifest),
            "model_label": contract["model_label"],
            "module_name": contract["module_name"],
            "selected_site": contract.get("selected_site"),
        },
        "rtl_contract": {
            "in_dim": in_features,
            "out_dim": out_features,
            "lane_count": lanes,
            "packed_weight_words": len(packed_words),
            "activation_dtype": "int8",
            "weight_dtype": "int8",
            "accumulator_dtype": "int32",
            "activation_quantization": "int8-per-tensor-symmetric",
            "weight_quantization": "int8-per-output-symmetric",
            "bias_handling": "f32 bias added during dequantized contract scoring, not inside RTL",
            "local_activation_memory": True,
            "local_packed_weight_memory": True,
            "local_output_memory": True,
        },
        "quantization": {
            "normalized_rmse_threshold": args.normalized_rmse_threshold,
            "activation_scale": activation_scale,
            "weight_scale_min": min(weight_scales),
            "weight_scale_max": max(weight_scales),
            "weight_scale_count": len(weight_scales),
            "activation_q_min": min(activation_q),
            "activation_q_max": max(activation_q),
            "weight_q_min": min(weight_q),
            "weight_q_max": max(weight_q),
            "expected_acc_min": min(expected_acc),
            "expected_acc_max": max(expected_acc),
            "activation_q_sha256": hashlib.sha256(activation_blob).hexdigest(),
            "weight_q_sha256": hashlib.sha256(weight_blob).hexdigest(),
            "packed_weight_sha256": hashlib.sha256(packed_blob).hexdigest(),
            "expected_acc_sha256": hashlib.sha256(expected_acc_blob).hexdigest(),
            **metrics,
            "verdict": (
                "pass"
                if metrics["normalized_rmse"] <= args.normalized_rmse_threshold
                else "fail"
            ),
        },
        "sim_result": sim_result,
        "yosys_result": load_design_stats(args.yosys_stat_json),
        "mapped_utilization": load_utilization(args.mapped_utilization_summary_json),
        "interpretation": [
            "This replays the captured L2 c_fc contract through the fixed-point int8 local-memory RTL shape.",
            "Verilator checks the raw int32 accumulators produced by quantized activation and per-output quantized weights.",
            "The JSON error metrics dequantize those accumulators with f32 bias added outside the RTL boundary.",
        ],
    }

    sv_lines = [
        f"localparam int IN_DIM = {in_features};",
        "localparam int TILE_OUT_DIM = 64;",
        f"localparam int OUT_DIM = {out_features};",
        f"localparam int LANES = {lanes};",
        f"localparam int PACKED_WEIGHT_WORDS = {len(packed_words)};",
        "localparam int PACKED_WEIGHT_ADDR_WIDTH = 12;",
        "localparam int ACTIVATION_ADDR_WIDTH = 6;",
        "localparam int OUT_ADDR_WIDTH = 8;",
        "logic signed [7:0] activation_values [0:IN_DIM - 1];",
        "logic [LANES * 8 - 1:0] packed_weight_values [0:PACKED_WEIGHT_WORDS - 1];",
        "logic signed [31:0] expected_acc_values [0:OUT_DIM - 1];",
        "initial begin",
    ]
    for index, value in enumerate(activation_q):
        sv_lines.append(f"  activation_values[{index}] = 8'sh{signed_hex(value, 8)};")
    for index, value in enumerate(packed_words):
        sv_lines.append(f"  packed_weight_values[{index}] = 32'h{value:08x};")
    for index, value in enumerate(expected_acc):
        sv_lines.append(
            f"  expected_acc_values[{index}] = 32'sh{signed_hex(value, 32)};"
        )
    sv_lines.append("end")
    sv_text = "\n".join(sv_lines) + "\n"
    return payload, sv_text


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
