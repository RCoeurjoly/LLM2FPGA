#!/usr/bin/env python3
from __future__ import annotations

"""Export a deterministic input/output contract for the selected L1 TinyStories site."""

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
        help="Fully-qualified module name to capture",
    )
    parser.add_argument("--candidate-json", type=Path)
    parser.add_argument("--vocab-size", type=int, required=True)
    parser.add_argument("--num-layers", type=int, required=True)
    parser.add_argument("--max-position-embeddings", type=int, required=True)
    parser.add_argument("--window-size", type=int, required=True)
    parser.add_argument("--hidden-size", type=int, required=True)
    parser.add_argument("--num-heads", type=int, required=True)
    parser.add_argument("--token-id", type=int, default=0)
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
    captured: dict[str, torch.Tensor] = {}

    def hook(_module: torch.nn.Module, inputs: tuple[torch.Tensor, ...], output: Any) -> None:
        if len(inputs) != 1:
            raise RuntimeError(
                f"expected exactly one activation input, got {len(inputs)} inputs"
            )
        if not isinstance(output, torch.Tensor):
            raise RuntimeError(f"expected tensor output, got {type(output)!r}")
        captured["activation_in"] = inputs[0].detach().cpu().contiguous()
        captured["activation_out"] = output.detach().cpu().contiguous()

    handle = module.register_forward_hook(hook)
    try:
        sample_input_ids = torch.tensor([[args.token_id]], dtype=torch.long)
        with torch.no_grad():
            model(sample_input_ids)
    finally:
        handle.remove()

    if "activation_in" not in captured or "activation_out" not in captured:
        raise SystemExit(f"hook on {args.module_name!r} did not capture activations")

    args.output_dir.mkdir(parents=True, exist_ok=True)
    activation_in_path = args.output_dir / "activation_in.bin"
    activation_out_path = args.output_dir / "activation_out.bin"
    write_tensor(activation_in_path, captured["activation_in"])
    write_tensor(activation_out_path, captured["activation_out"])

    manifest: dict[str, Any] = {
        "model_label": args.model_label,
        "module_name": args.module_name,
        "representation_level": "pytorch-module-hook",
        "capture_kind": "representative-core-single-token",
        "sample_input_ids": sample_input_ids.tolist(),
        "config": {
            "vocab_size": args.vocab_size,
            "num_layers": args.num_layers,
            "max_position_embeddings": args.max_position_embeddings,
            "window_size": args.window_size,
            "hidden_size": args.hidden_size,
            "num_heads": args.num_heads,
        },
        "tensors": [
            to_tensor_meta("activation_in", captured["activation_in"], activation_in_path.name),
            to_tensor_meta(
                "activation_out", captured["activation_out"], activation_out_path.name
            ),
        ],
    }

    if args.candidate_json is not None:
        candidate_doc = json.loads(args.candidate_json.read_text(encoding="utf-8"))
        selected = candidate_doc["selected_candidate"]
        manifest["selected_site"] = {
            "candidate_json": str(args.candidate_json),
            "line_number": selected["line_number"],
            "result_value": selected["result_value"],
            "shape_contract": selected["shape_contract"],
        }

    (args.output_dir / "manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
