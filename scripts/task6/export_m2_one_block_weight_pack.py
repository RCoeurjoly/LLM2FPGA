#!/usr/bin/env python3
"""Export the M2 one-block TinyStories weight pack."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_ADAPTER = ROOT / "TinyStories" / "model_adapter.py"
DEFAULT_OUT = (
    ROOT
    / "artifacts"
    / "task6"
    / "weights_pack"
    / "tiny-stories-1m-m2-block0"
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model-path", required=True, type=Path)
    parser.add_argument("--adapter-path", type=Path, default=DEFAULT_ADAPTER)
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--block-index", type=int, default=0)
    parser.add_argument("--model-label", default="tiny-stories-1m")
    return parser.parse_args()


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def load_adapter_build_model(adapter_path: Path) -> Any:
    sys.path.insert(0, str(adapter_path.parent))
    spec = importlib.util.spec_from_file_location("task6_m2_weight_adapter", adapter_path)
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
    if not hasattr(module, "build_model"):
        raise SystemExit(f"adapter has no build_model function: {adapter_path}")
    return module.build_model


def selected_parameter_names(block_index: int) -> list[str]:
    block = f"transformer.h.{block_index}."
    prefixes = [
        "transformer.wte.",
        "transformer.wpe.",
        block,
    ]
    return prefixes


def safe_filename(name: str) -> str:
    return name.replace(".", "__") + ".bin"


def tensor_to_file(out_dir: Path, name: str, tensor: Any) -> dict[str, Any]:
    detached = tensor.detach().cpu().contiguous()
    raw = detached.numpy().tobytes(order="C")
    filename = safe_filename(name)
    (out_dir / filename).write_bytes(raw)
    return {
        "name": name,
        "filename": filename,
        "dtype": str(detached.dtype).replace("torch.", ""),
        "shape": [int(dim) for dim in detached.shape],
        "numel": int(detached.numel()),
        "byte_length": len(raw),
        "sha256": sha256_bytes(raw),
    }


def main() -> int:
    args = parse_args()
    if args.block_index < 0:
        raise SystemExit("--block-index must be non-negative")

    build_model = load_adapter_build_model(args.adapter_path)
    model = build_model(str(args.model_path))
    model.eval()
    prefixes = selected_parameter_names(args.block_index)
    args.out_dir.mkdir(parents=True, exist_ok=True)

    tensors: list[dict[str, Any]] = []
    for name, tensor in model.named_parameters():
        if any(name.startswith(prefix) for prefix in prefixes):
            tensors.append(tensor_to_file(args.out_dir, name, tensor))
    if not tensors:
        raise SystemExit(f"no tensors selected for block index {args.block_index}")

    by_region = {
        "embeddings": sum(item["byte_length"] for item in tensors if item["name"].startswith("transformer.w")),
        "block": sum(item["byte_length"] for item in tensors if item["name"].startswith(f"transformer.h.{args.block_index}.")),
    }
    manifest = {
        "schema_version": 1,
        "artifact_name": "h2-tinystories-1m-m2-one-block-weight-pack",
        "status": "PASS",
        "date": dt.datetime.now(dt.timezone.utc).isoformat(),
        "stage": "M2-one-full-block-weight-pack",
        "milestone_target": "M2-one-full-block",
        "live_compute": False,
        "artifact_role": "offline-weight-pack-prerequisite",
        "model_label": args.model_label,
        "model_path": str(args.model_path),
        "adapter_path": str(args.adapter_path),
        "block_index": args.block_index,
        "format": "raw-f32-le",
        "selected_prefixes": prefixes,
        "total_tensors": len(tensors),
        "total_bytes": sum(item["byte_length"] for item in tensors),
        "bytes_by_region": by_region,
        "tensors": tensors,
        "next_stage": "quantize selected tensors into the M2 fixed-point block format",
    }
    manifest_path = args.out_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(manifest_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
