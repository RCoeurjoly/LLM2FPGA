#!/usr/bin/env python3
from __future__ import annotations

"""Export a first-class weight pack for a selected TinyStories module."""

import argparse
import importlib.util
import json
import os
from pathlib import Path
import sys
from typing import Any

import torch


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-path", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument(
        "--module-name",
        default="transformer.h.0.mlp.c_fc",
        help="Fully-qualified module name to pack",
    )
    parser.add_argument("--vocab-size", type=int, required=True)
    parser.add_argument("--num-layers", type=int, required=True)
    parser.add_argument("--max-position-embeddings", type=int, required=True)
    parser.add_argument("--window-size", type=int, required=True)
    parser.add_argument("--hidden-size", type=int, required=True)
    parser.add_argument("--num-heads", type=int, required=True)
    parser.add_argument(
        "--model-label",
        default="tiny-stories-1m-representative-core-v64-h4",
    )
    return parser.parse_args()


def set_representative_core_env(args: argparse.Namespace) -> None:
    os.environ["TINYSTORIES_CORE_VOCAB_SIZE"] = str(args.vocab_size)
    os.environ["TINYSTORIES_CORE_NUM_LAYERS"] = str(args.num_layers)
    os.environ["TINYSTORIES_CORE_MAX_POSITION_EMBEDDINGS"] = str(
        args.max_position_embeddings
    )
    os.environ["TINYSTORIES_CORE_WINDOW_SIZE"] = str(args.window_size)
    os.environ["TINYSTORIES_CORE_HIDDEN_SIZE"] = str(args.hidden_size)
    os.environ["TINYSTORIES_CORE_NUM_HEADS"] = str(args.num_heads)


def to_tensor_meta(name: str, tensor: torch.Tensor, filename: str) -> dict[str, Any]:
    detached = tensor.detach().cpu().contiguous()
    return {
        "name": name,
        "filename": filename,
        "dtype": str(detached.dtype).replace("torch.", ""),
        "shape": list(detached.shape),
        "numel": detached.numel(),
        "byte_length": detached.numel() * detached.element_size(),
    }


def write_tensor(path: Path, tensor: torch.Tensor) -> None:
    detached = tensor.detach().cpu().contiguous()
    path.write_bytes(detached.numpy().tobytes(order="C"))


def load_representative_core_builder() -> Any:
    repo_root = Path(__file__).resolve().parents[2]
    adapter_path = repo_root / "TinyStories" / "model_adapter_representative_core.py"
    sys.path.insert(0, str(adapter_path.parent))
    spec = importlib.util.spec_from_file_location(
        "model_adapter_representative_core", adapter_path
    )
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


def main() -> None:
    args = parse_args()
    set_representative_core_env(args)
    build_model = load_representative_core_builder()
    model = build_model(str(args.model_path))
    named_modules = dict(model.named_modules())
    if args.module_name not in named_modules:
        available = ", ".join(sorted(name for name in named_modules if name))
        raise SystemExit(
            f"module {args.module_name!r} not found; available names include: {available}"
        )

    module = named_modules[args.module_name]
    if not hasattr(module, "weight"):
        raise SystemExit(f"module {args.module_name!r} has no weight attribute")
    if not hasattr(module, "bias"):
        raise SystemExit(f"module {args.module_name!r} has no bias attribute")

    args.output_dir.mkdir(parents=True, exist_ok=True)
    weight_path = args.output_dir / "weight.bin"
    bias_path = args.output_dir / "bias.bin"

    write_tensor(weight_path, module.weight)
    write_tensor(bias_path, module.bias)

    manifest = {
        "model_label": args.model_label,
        "module_name": args.module_name,
        "representation_level": "pytorch-state-dict",
        "format": "raw-f32-le",
        "config": {
            "vocab_size": args.vocab_size,
            "num_layers": args.num_layers,
            "max_position_embeddings": args.max_position_embeddings,
            "window_size": args.window_size,
            "hidden_size": args.hidden_size,
            "num_heads": args.num_heads,
        },
        "tensors": [
            to_tensor_meta("weight", module.weight, weight_path.name),
            to_tensor_meta("bias", module.bias, bias_path.name),
        ],
    }
    (args.output_dir / "manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
