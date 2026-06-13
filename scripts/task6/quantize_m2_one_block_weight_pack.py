#!/usr/bin/env python3
"""Quantize an M2 one-block f32 weight pack into a deterministic int8 pack."""

from __future__ import annotations

import argparse
from array import array
import datetime as dt
import hashlib
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_IN = ROOT / "artifacts" / "task6" / "weights_pack" / "tiny-stories-1m-m2-block0" / "manifest.json"
DEFAULT_OUT = ROOT / "artifacts" / "task6" / "weights_pack" / "tiny-stories-1m-m2-block0-int8"
QMAX = 127


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-manifest", type=Path, default=DEFAULT_IN)
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT)
    return parser.parse_args()


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


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


def write_f32(path: Path, values: array | list[float]) -> None:
    arr = values if isinstance(values, array) else array("f", values)
    path.write_bytes(arr.tobytes())


def quantize_rowwise(values: array, rows: int, cols: int) -> tuple[list[int], list[float]]:
    if len(values) != rows * cols:
        raise SystemExit(f"tensor length {len(values)} does not match shape [{rows}, {cols}]")
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
            scale = max_abs / QMAX
            for item in chunk:
                q = int(round(float(item) / scale))
                q_values.append(max(-QMAX, min(QMAX, q)))
        scales.append(scale)
    return q_values, scales


def quantize_tensor(input_dir: Path, out_dir: Path, tensor: dict) -> dict:
    src = input_dir / tensor["filename"]
    shape = [int(dim) for dim in tensor["shape"]]
    dtype = tensor["dtype"]
    if dtype != "float32":
        raise SystemExit(f"expected f32 source tensor, got {dtype}: {tensor['name']}")
    values = read_f32(src)

    if len(shape) == 2:
        rows, cols = shape
        q_values, scales = quantize_rowwise(values, rows, cols)
        q_name = safe_filename(tensor["name"], "__rowwise_i8.bin")
        scale_name = safe_filename(tensor["name"], "__row_scales_f32.bin")
        q_path = out_dir / q_name
        scale_path = out_dir / scale_name
        write_i8(q_path, q_values)
        write_f32(scale_path, scales)
        return {
            "name": tensor["name"],
            "source_filename": tensor["filename"],
            "quantization": "rowwise-symmetric-int8",
            "shape": shape,
            "q_filename": q_name,
            "q_dtype": "int8",
            "q_byte_length": q_path.stat().st_size,
            "q_sha256": sha256_file(q_path),
            "scale_filename": scale_name,
            "scale_dtype": "float32",
            "scale_shape": [rows],
            "scale_byte_length": scale_path.stat().st_size,
            "scale_sha256": sha256_file(scale_path),
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
    input_dir = args.input_manifest.parent
    args.out_dir.mkdir(parents=True, exist_ok=True)
    tensors = [quantize_tensor(input_dir, args.out_dir, tensor) for tensor in source["tensors"]]
    int8_bytes = sum(tensor.get("q_byte_length", 0) for tensor in tensors)
    scale_bytes = sum(tensor.get("scale_byte_length", 0) for tensor in tensors)
    passthrough_bytes = sum(tensor.get("byte_length", 0) for tensor in tensors)
    manifest = {
        "schema_version": 1,
        "artifact_name": "h2-tinystories-1m-m2-one-block-int8-weight-pack",
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
        "policy": {
            "rank2_tensors": "rowwise-symmetric-int8-with-f32-row-scales",
            "rank1_tensors": "f32-passthrough-until-layernorm-bias-fixed-point-contract",
        },
        "total_source_bytes": source.get("total_bytes"),
        "total_quantized_bytes": int8_bytes + scale_bytes + passthrough_bytes,
        "int8_payload_bytes": int8_bytes,
        "scale_bytes": scale_bytes,
        "passthrough_f32_bytes": passthrough_bytes,
        "tensors": tensors,
        "next_stage": "replace f32 passthrough tensors with fixed-point layernorm/bias constants",
    }
    (args.out_dir / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(args.out_dir / "manifest.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
