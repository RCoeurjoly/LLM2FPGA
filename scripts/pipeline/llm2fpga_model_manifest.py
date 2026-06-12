#!/usr/bin/env python3
"""Emit a first-class LLM2FPGA model manifest from a PyTorch adapter.

This is the metadata spine for the GPT/TinyStories-first pipeline. It does not
generate RTL by itself; it records the model shape and tensor inventory that
later artifact stages consume for quantization, DDR3 packing, RTL generation,
resource estimation, and board-run recipes.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
from pathlib import Path
import sys
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_BOARD = "ypcb-00338-1p1"
SUPPORTED_FAMILIES = ("gpt-causal",)
PIPELINE_PROFILE = {
    "style": "contract-driven kernelized stages",
    "frontend": "pytorch via adapter + optional torch-mlir exploration",
    "compute_boundary": "gradual host-to-fpga transformer block migration",
    "reference_scope": "fixed-point replay oracles + stage contracts",
    "target_scope": "gpt-causal decoder families on YPCB first",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model-path", required=True, type=Path)
    parser.add_argument("--adapter-path", required=True, type=Path)
    parser.add_argument("--out-json", required=True, type=Path)
    parser.add_argument("--model-label", required=True)
    parser.add_argument("--family", choices=SUPPORTED_FAMILIES, default="gpt-causal")
    parser.add_argument("--target-board", default=DEFAULT_BOARD)
    return parser.parse_args()


def load_model_builder(adapter_path: Path) -> Any:
    sys.path.insert(0, str(adapter_path.parent))
    spec = importlib.util.spec_from_file_location("llm2fpga_model_adapter", adapter_path)
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


def tensor_meta(name: str, tensor: Any) -> dict[str, Any]:
    detached = tensor.detach().cpu().contiguous()
    return {
        "name": name,
        "dtype": str(detached.dtype).replace("torch.", ""),
        "shape": [int(dim) for dim in detached.shape],
        "numel": int(detached.numel()),
        "byte_length": int(detached.numel() * detached.element_size()),
    }


def module_class_name(module: Any) -> str:
    return f"{module.__class__.__module__}.{module.__class__.__name__}"


def config_dict(model: Any) -> dict[str, Any]:
    cfg = getattr(model, "config", None)
    if cfg is None:
        return {}
    if hasattr(cfg, "to_dict"):
        raw = cfg.to_dict()
    elif isinstance(cfg, dict):
        raw = dict(cfg)
    else:
        raw = {
            key: getattr(cfg, key)
            for key in dir(cfg)
            if not key.startswith("_") and isinstance(getattr(cfg, key), (str, int, float, bool, type(None)))
        }
    return {
        str(key): value
        for key, value in raw.items()
        if isinstance(value, (str, int, float, bool, type(None), list, tuple, dict))
    }


def model_dimensions(config: dict[str, Any], tensors: list[dict[str, Any]]) -> dict[str, Any]:
    dims: dict[str, Any] = {}
    aliases = {
        "vocab_size": ("vocab_size",),
        "hidden_size": ("hidden_size", "n_embd"),
        "num_layers": ("num_hidden_layers", "n_layer"),
        "num_heads": ("num_attention_heads", "n_head"),
        "max_position_embeddings": ("max_position_embeddings", "n_positions", "n_ctx"),
    }
    for out_key, keys in aliases.items():
        for key in keys:
            if key in config:
                dims[out_key] = config[key]
                break

    if "parameter_count" not in dims:
        dims["parameter_count"] = sum(int(item["numel"]) for item in tensors)
    if "parameter_bytes_f32" not in dims:
        dims["parameter_bytes_f32"] = sum(int(item["byte_length"]) for item in tensors)
    return dims


def module_inventory(model: Any) -> list[dict[str, Any]]:
    inventory: list[dict[str, Any]] = []
    for name, module in model.named_modules():
        if not name:
            continue
        direct_params = list(module.named_parameters(recurse=False))
        if not direct_params:
            continue
        inventory.append(
            {
                "name": name,
                "class": module_class_name(module),
                "parameters": [tensor_meta(param_name, param) for param_name, param in direct_params],
            }
        )
    return inventory


def parameter_inventory(model: Any) -> list[dict[str, Any]]:
    return [tensor_meta(name, param) for name, param in model.named_parameters()]


def family_check(family: str, config: dict[str, Any], modules: list[dict[str, Any]]) -> dict[str, Any]:
    if family != "gpt-causal":
        return {"status": "unsupported", "reason": f"unsupported family {family}"}
    names = {module["name"] for module in modules}
    has_transformer_blocks = any(".h." in f".{name}." or name.startswith("transformer.h.") for name in names)
    has_output_head = any(name in names for name in ("lm_head", "score"))
    has_vocab = "vocab_size" in config
    missing = []
    if not has_transformer_blocks:
        missing.append("transformer block modules")
    if not has_output_head:
        missing.append("lm_head/score output module")
    if not has_vocab:
        missing.append("vocab_size config")
    return {
        "status": "supported" if not missing else "diagnostic-only",
        "missing": missing,
    }


def main() -> None:
    args = parse_args()
    build_model = load_model_builder(args.adapter_path)
    model = build_model(str(args.model_path))
    model.eval()

    tensors = parameter_inventory(model)
    modules = module_inventory(model)
    cfg = config_dict(model)
    manifest = {
        "schema_version": 1,
        "artifact_name": "llm2fpga-pytorch-model-manifest",
        "model_label": args.model_label,
        "model_path": str(args.model_path),
        "adapter_path": str(args.adapter_path),
        "input_format": "pytorch",
        "family": args.family,
        "target_board": args.target_board,
        "target_board_contract": {
            "host": [
                "tokenization/detokenization",
                "generation control",
                "PCIe recovery/orchestration",
                "CPU/fixed-point reference",
                "artifact loading and logging",
            ],
            "fpga": [
                "DDR3 model/row movement",
                "embeddings",
                "layernorm",
                "attention/KV",
                "MLP/GELU/residual",
                "output-head top1/top-k",
            ],
            "pcie": [
                "control/status",
                "prompt/token IDs",
                "model artifact loading",
                "generated token/result readback",
            ],
        },
        "config": cfg,
        "dimensions": model_dimensions(cfg, tensors),
        "family_check": family_check(args.family, cfg, modules),
        "parameters": tensors,
        "modules": modules,
        "pipeline_profile": PIPELINE_PROFILE,
        "next_artifact_stages": [
            "quantized-weight-pack",
            "ddr3-rowstream",
            "fixed-point-reference",
            "stage-rtl-generation",
            "resource-estimate",
            "board-run-recipe",
        ],
    }
    args.out_json.parent.mkdir(parents=True, exist_ok=True)
    args.out_json.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
