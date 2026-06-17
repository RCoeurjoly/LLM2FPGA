#!/usr/bin/env python3
"""Quantize an M2 one-block f32 weight pack into deterministic fixed-point packs.

The script supports three concrete serialization contracts:

  - ``int8``: row-wise signed symmetric 8-bit quantization (legacy path).
  - ``int4``: row-wise signed symmetric 4-bit quantization packed into nibbles.
  - ``ternary2``: row-wise signed ternary ({-1,0,+1}) packed into 2-bit lanes.
"""

from __future__ import annotations

import argparse
from array import array
import datetime as dt
import hashlib
import json
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_IN = ROOT / "artifacts" / "task6" / "weights_pack" / "tiny-stories-1m-m2-block0" / "manifest.json"
DEFAULT_OUT_ROOT = ROOT / "artifacts" / "task6" / "weights_pack"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-manifest", type=Path, default=DEFAULT_IN)
    parser.add_argument(
        "--quantization",
        choices=("int8", "int4", "ternary2"),
        default="int8",
        help="Weight quantization contract: int8, int4, or ternary2.",
    )
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=None,
        help=(
            "Output directory for the contract. If omitted, defaults to a quantization-"
            "specific path under tiny-stories-1m-m2-block0-*"
        ),
    )
    parser.add_argument(
        "--ternary-threshold-factor",
        type=float,
        default=0.25,
        help="Threshold factor for ternary quantization (factor * row mean_abs).",
    )
    parser.add_argument(
        "--ternary-scale-mode",
        choices=("least_squares", "mean_abs"),
        default="least_squares",
        help="Scale mode for ternary row-wise reconstruction.",
    )
    return parser.parse_args()


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def sha256_floats(values: list[float]) -> str:
    return hashlib.sha256(array("f", values).tobytes()).hexdigest()


def safe_filename(name: str, suffix: str) -> str:
    return name.replace(".", "__") + suffix


def read_f32(path: Path) -> array:
    values = array("f")
    values.frombytes(path.read_bytes())
    if values.itemsize != 4:
        raise SystemExit("platform float array is not 32-bit")
    return values


def write_i8(path: Path, values: list[int]) -> None:
    arr = array("b", values)
    path.write_bytes(arr.tobytes())


def write_u8(path: Path, values: list[int]) -> None:
    arr = array("B", values)
    path.write_bytes(arr.tobytes())


def write_f32(path: Path, values: array | list[float]) -> None:
    arr = values if isinstance(values, array) else array("f", values)
    path.write_bytes(arr.tobytes())


def quantize_rowwise_symmetric(
    values: array,
    rows: int,
    cols: int,
    bits: int,
) -> tuple[list[int], list[float]]:
    if bits not in {4, 8}:
        raise SystemExit(f"unsupported symmetric quantization bit-width: {bits}")
    if len(values) != rows * cols:
        raise SystemExit(f"tensor length {len(values)} does not match shape [{rows}, {cols}]")
    qmax = (1 << (bits - 1)) - 1
    q_values: list[int] = []
    scales: list[float] = []
    for row in range(rows):
        start = row * cols
        chunk = values[start : start + cols]
        max_abs = max(abs(float(item)) for item in chunk)
        if max_abs == 0.0:
            scale = 0.0
            q_values.extend([0] * cols)
        else:
            scale = max_abs / qmax
            for item in chunk:
                q = int(round(float(item) / scale))
                q_values.append(max(-qmax, min(qmax, q)))
        scales.append(scale)
    return q_values, scales


def quantize_rowwise_ternary(
    values: array,
    rows: int,
    cols: int,
    threshold_factor: float,
    scale_mode: str,
) -> tuple[list[int], list[float], list[float]]:
    if len(values) != rows * cols:
        raise SystemExit(f"tensor length {len(values)} does not match shape [{rows}, {cols}]")
    if scale_mode not in {"least_squares", "mean_abs"}:
        raise SystemExit(f"unsupported ternary scale mode: {scale_mode}")
    if threshold_factor < 0.0:
        raise SystemExit("--ternary-threshold-factor must be non-negative")

    q_values: list[int] = []
    scales: list[float] = []
    thresholds: list[float] = []

    for row in range(rows):
        start = row * cols
        chunk = [float(item) for item in values[start : start + cols]]
        mean_abs = sum(abs(value) for value in chunk) / cols
        threshold = threshold_factor * mean_abs

        row_q: list[int] = [
            1 if value >= threshold else -1 if value <= -threshold else 0
            for value in chunk
        ]

        if scale_mode == "mean_abs":
            row_scale = mean_abs
        else:
            numerator = sum(value * code for value, code in zip(chunk, row_q))
            denominator = sum(code * code for code in row_q)
            row_scale = numerator / denominator if denominator else 1.0

        q_values.extend(row_q)
        scales.append(row_scale)
        thresholds.append(threshold)

    return q_values, scales, thresholds


def pack_int4(values: list[int]) -> list[int]:
    packed: list[int] = []
    for index in range(0, len(values), 2):
        lo = values[index]
        if lo < -8 or lo > 7:
            raise SystemExit(f"int4 out of range: {lo}")
        lo_nibble = lo & 0xF

        hi = values[index + 1] if index + 1 < len(values) else 0
        if hi < -8 or hi > 7:
            raise SystemExit(f"int4 out of range: {hi}")
        hi_nibble = hi & 0xF

        packed.append((hi_nibble << 4) | lo_nibble)
    return packed


def pack_ternary2(values: list[int]) -> list[int]:
    def code(value: int) -> int:
        if value == 0:
            return 0b00
        if value == 1:
            return 0b01
        if value == -1:
            return 0b10
        raise SystemExit(f"ternary code out of range: {value}")

    packed: list[int] = []
    current = 0
    used_bits = 0
    for value in values:
        if value < -1 or value > 1:
            raise SystemExit(f"ternary out of range: {value}")
        current |= code(value) << used_bits
        used_bits += 2
        if used_bits == 8:
            packed.append(current)
            current = 0
            used_bits = 0
    if used_bits:
        packed.append(current)
    return packed


def quantization_profile(quantization: str, *, args: argparse.Namespace) -> dict[str, Any]:
    if quantization == "int8":
        return {
            "artifact_suffix": "int8",
            "q_dtype": "int8",
            "q_bits": 8,
            "q_pack": "i8",
            "q_pack_bits": 8,
            "q_signed": True,
            "q_suffix": "__rowwise_i8.bin",
            "tensor_quantization": "rowwise-symmetric-int8",
            "rank2_tensors": "rowwise-symmetric-int8-with-f32-row-scales",
            "write_payload": write_i8,
        }

    if quantization == "int4":
        return {
            "artifact_suffix": "int4",
            "q_dtype": "int4-packed",
            "q_bits": 4,
            "q_pack": "two-nibbles-per-byte",
            "q_pack_bits": 8,
            "q_signed": True,
            "q_suffix": "__rowwise_i4_packed.bin",
            "tensor_quantization": "rowwise-symmetric-int4-packed",
            "rank2_tensors": "rowwise-symmetric-int4-with-f32-row-scales",
            "write_payload": write_u8,
            "pack_fn": pack_int4,
        }

    if quantization == "ternary2":
        return {
            "artifact_suffix": "ternary2",
            "q_dtype": "ternary2-packed",
            "q_bits": 2,
            "q_pack": "four-entries-per-byte",
            "q_pack_bits": 8,
            "q_signed": False,
            "q_suffix": "__rowwise_ternary2_packed.bin",
            "tensor_quantization": (
                f"rowwise-ternary2-threshold-{args.ternary_threshold_factor:g}-"
                f"{args.ternary_scale_mode}"
            ),
            "rank2_tensors": "rowwise-ternary2-packed-2bit-with-f32-row-scales",
            "write_payload": write_u8,
            "pack_fn": pack_ternary2,
            "ternary_threshold_factor": args.ternary_threshold_factor,
            "ternary_scale_mode": args.ternary_scale_mode,
        }

    raise SystemExit(f"unsupported quantization mode: {quantization}")


def default_output_dir(quantization: str) -> Path:
    return DEFAULT_OUT_ROOT / f"tiny-stories-1m-m2-block0-{quantization}"


def quantize_tensor(
    input_dir: Path,
    out_dir: Path,
    tensor: dict,
    quantization: str,
    profile: dict[str, Any],
) -> dict:
    src = input_dir / tensor["filename"]
    shape = [int(dim) for dim in tensor["shape"]]
    dtype = tensor["dtype"]
    if dtype != "float32":
        raise SystemExit(f"expected f32 source tensor, got {dtype}: {tensor['name']}")
    values = read_f32(src)

    if len(shape) == 2:
        rows, cols = shape

        if quantization == "int8":
            q_values, scales = quantize_rowwise_symmetric(values, rows, cols, 8)
            q_payload = q_values
            extra_meta: dict[str, Any] = {}
        elif quantization == "int4":
            q_values, scales = quantize_rowwise_symmetric(values, rows, cols, 4)
            q_payload = profile["pack_fn"](q_values)
            extra_meta = {}
        elif quantization == "ternary2":
            q_values, scales, thresholds = quantize_rowwise_ternary(
                values,
                rows,
                cols,
                threshold_factor=profile["ternary_threshold_factor"],
                scale_mode=profile["ternary_scale_mode"],
            )
            q_payload = profile["pack_fn"](q_values)
            extra_meta = {
                "row_thresholds_sha256": sha256_floats(thresholds),
                "ternary_threshold_factor": profile["ternary_threshold_factor"],
                "ternary_scale_mode": profile["ternary_scale_mode"],
                "q_zero_code": 0,
                "q_plus_code": 1,
                "q_minus_code": 2,
            }
        else:
            raise SystemExit(f"unsupported quantization mode: {quantization}")

        q_name = safe_filename(tensor["name"], profile["q_suffix"])
        scale_name = safe_filename(tensor["name"], "__row_scales_f32.bin")
        q_path = out_dir / q_name
        scale_path = out_dir / scale_name

        profile["write_payload"](q_path, q_payload)
        write_f32(scale_path, scales)

        return {
            "name": tensor["name"],
            "source_filename": tensor["filename"],
            "quantization": profile["tensor_quantization"],
            "shape": shape,
            "q_filename": q_name,
            "q_dtype": profile["q_dtype"],
            "q_bits": profile["q_bits"],
            "q_pack": profile["q_pack"],
            "q_pack_bits": profile["q_pack_bits"],
            "q_signed": profile["q_signed"],
            "q_byte_length": q_path.stat().st_size,
            "q_sha256": sha256_file(q_path),
            "scale_filename": scale_name,
            "scale_dtype": "float32",
            "scale_shape": [rows],
            "scale_byte_length": scale_path.stat().st_size,
            "scale_sha256": sha256_file(scale_path),
            **extra_meta,
        }

    passthrough_name = safe_filename(tensor["name"], "__f32.bin")
    passthrough_path = out_dir / passthrough_name
    write_f32(passthrough_path, values)
    return {
        "name": tensor["name"],
        "source_filename": tensor["filename"],
        "quantization": "f32-passthrough",
        "shape": shape,
        "filename": passthrough_name,
        "dtype": "float32",
        "byte_length": passthrough_path.stat().st_size,
        "sha256": sha256_file(passthrough_path),
    }


def main() -> int:
    args = parse_args()
    source = load_json(args.input_manifest)
    profile = quantization_profile(args.quantization, args=args)
    if args.out_dir is None:
        args.out_dir = default_output_dir(profile["artifact_suffix"])
    input_dir = args.input_manifest.parent
    args.out_dir.mkdir(parents=True, exist_ok=True)

    tensors = [
        quantize_tensor(input_dir, args.out_dir, tensor, args.quantization, profile)
        for tensor in source["tensors"]
    ]

    quantized_bytes = sum(tensor.get("q_byte_length", 0) for tensor in tensors)
    scale_bytes = sum(tensor.get("scale_byte_length", 0) for tensor in tensors)
    passthrough_bytes = sum(tensor.get("byte_length", 0) for tensor in tensors)

    manifest = {
        "schema_version": 1,
        "artifact_name": f"h2-tinystories-1m-m2-one-block-{profile['artifact_suffix']}-weight-pack",
        "status": "PASS",
        "date": dt.datetime.now(dt.timezone.utc).isoformat(),
        "source_manifest": str(args.input_manifest),
        "stage": "M2-one-full-block-quantized-weight-pack",
        "milestone_target": source.get("milestone_target", "M2-one-full-block"),
        "source_stage": source.get("stage"),
        "live_compute": False,
        "artifact_role": "offline-quantized-weight-pack-prerequisite",
        "model_label": source.get("model_label"),
        "block_index": source.get("block_index"),
        "quantization": {
            "mode": args.quantization,
            "rank2_tensors": profile["rank2_tensors"],
        },
        "policy": {
            "rank2_tensors": profile["rank2_tensors"],
            "rank1_tensors": "f32-passthrough-until-layernorm-bias-fixed-point-contract",
        },
        "total_source_bytes": source.get("total_bytes"),
        "total_quantized_bytes": quantized_bytes + scale_bytes + passthrough_bytes,
        "weight_payload_bytes": quantized_bytes,
        "quantized_payload_bytes": quantized_bytes,
        "int8_payload_bytes": quantized_bytes if args.quantization == "int8" else 0,
        "scale_bytes": scale_bytes,
        "passthrough_f32_bytes": passthrough_bytes,
        "tensors": tensors,
        "next_stage": "replace f32 passthrough tensors with fixed-point layernorm/bias constants",
    }

    if args.quantization == "ternary2":
        manifest["ternary"] = {
            "threshold_factor": args.ternary_threshold_factor,
            "scale_mode": args.ternary_scale_mode,
        }

    (args.out_dir / "manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(args.out_dir / "manifest.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
