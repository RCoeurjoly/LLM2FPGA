#!/usr/bin/env python3
from __future__ import annotations

"""Export a deterministic residual-add contract for the L2 TinyStories MLP site."""

import argparse
import importlib.util
import json
import math
import os
from pathlib import Path
import sys
from typing import Any

import torch


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-path", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--adapter-path", type=Path)
    parser.add_argument("--c-fc-contract-manifest", required=True, type=Path)
    parser.add_argument("--c-proj-contract-manifest", required=True, type=Path)
    parser.add_argument("--vocab-size", type=int, required=True)
    parser.add_argument("--num-layers", type=int, required=True)
    parser.add_argument("--max-position-embeddings", type=int, required=True)
    parser.add_argument("--window-size", type=int, required=True)
    parser.add_argument("--hidden-size", type=int, required=True)
    parser.add_argument("--num-heads", type=int, required=True)
    parser.add_argument("--token-id", type=int, default=0)
    parser.add_argument("--model-label", default="tiny-stories-v1k-h64-l1")
    parser.add_argument("--error-threshold", type=float, default=1e-6)
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


def load_representative_core_builder(adapter_path: Path | None) -> Any:
    if adapter_path is None:
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


def first_tensor(value: Any) -> torch.Tensor:
    if isinstance(value, torch.Tensor):
        return value
    if isinstance(value, (tuple, list)):
        for item in value:
            if isinstance(item, torch.Tensor):
                return item
    raise RuntimeError(f"expected tensor or tuple/list containing a tensor, got {type(value)!r}")


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


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def tensor_by_name(manifest: dict[str, Any], name: str) -> dict[str, Any]:
    for tensor in manifest["tensors"]:
        if tensor["name"] == name:
            return tensor
    raise SystemExit(f"{manifest.get('module_name', '<unknown>')} has no {name} tensor")


def load_contract_tensor(manifest_path: Path, tensor_name: str) -> torch.Tensor:
    manifest = load_json(manifest_path)
    meta = tensor_by_name(manifest, tensor_name)
    path = manifest_path.parent / meta["filename"]
    raw = path.read_bytes()
    expected_bytes = int(meta["numel"]) * 4
    if len(raw) != expected_bytes:
        raise SystemExit(f"{path}: expected {expected_bytes} bytes, got {len(raw)}")
    return torch.frombuffer(bytearray(raw), dtype=torch.float32).reshape(meta["shape"])


def score_error(actual: torch.Tensor, expected: torch.Tensor) -> dict[str, float]:
    actual_flat = actual.detach().cpu().to(torch.float64).reshape(-1)
    expected_flat = expected.detach().cpu().to(torch.float64).reshape(-1)
    if actual_flat.numel() != expected_flat.numel():
        raise SystemExit(
            f"length mismatch: actual={actual_flat.numel()} expected={expected_flat.numel()}"
        )
    errors = actual_flat - expected_flat
    abs_errors = errors.abs()
    mse = float((errors * errors).mean().item())
    signal_mse = float((expected_flat * expected_flat).mean().item())
    rmse = math.sqrt(mse)
    signal_rms = math.sqrt(signal_mse)
    signal_abs = expected_flat.abs()
    return {
        "max_abs_error": float(abs_errors.max().item()),
        "mean_abs_error": float(abs_errors.mean().item()),
        "rmse": rmse,
        "normalized_rmse": 0.0 if signal_rms == 0.0 else rmse / signal_rms,
        "signal_max_abs": float(signal_abs.max().item()),
        "signal_mean_abs": float(signal_abs.mean().item()),
    }


def metric_passes(metric: dict[str, float], threshold: float) -> bool:
    return metric["max_abs_error"] <= threshold


def main() -> None:
    args = parse_args()
    set_representative_core_env(args)
    build_model = load_representative_core_builder(args.adapter_path)
    model = build_model(str(args.model_path))
    named_modules = dict(model.named_modules())

    required_modules = {
        "ln_2": "transformer.h.0.ln_2",
        "c_proj": "transformer.h.0.mlp.c_proj",
        "block": "transformer.h.0",
    }
    missing = [name for name in required_modules.values() if name not in named_modules]
    if missing:
        available = ", ".join(sorted(name for name in named_modules if name))
        raise SystemExit(f"missing modules {missing}; available names include: {available}")

    captured: dict[str, torch.Tensor] = {}

    def ln_2_hook(
        _module: torch.nn.Module,
        inputs: tuple[torch.Tensor, ...],
        output: Any,
    ) -> None:
        if len(inputs) != 1:
            raise RuntimeError(f"ln_2 expected one input, got {len(inputs)}")
        captured["residual_activation_in"] = inputs[0].detach().cpu().contiguous()
        captured["ln2_activation_out"] = first_tensor(output).detach().cpu().contiguous()

    def c_proj_hook(
        _module: torch.nn.Module,
        inputs: tuple[torch.Tensor, ...],
        output: Any,
    ) -> None:
        if len(inputs) != 1:
            raise RuntimeError(f"c_proj expected one input, got {len(inputs)}")
        captured["c_proj_activation_in"] = inputs[0].detach().cpu().contiguous()
        captured["c_proj_activation_out"] = first_tensor(output).detach().cpu().contiguous()

    def block_hook(
        _module: torch.nn.Module,
        _inputs: tuple[torch.Tensor, ...],
        output: Any,
    ) -> None:
        captured["block_output"] = first_tensor(output).detach().cpu().contiguous()

    handles = [
        named_modules[required_modules["ln_2"]].register_forward_hook(ln_2_hook),
        named_modules[required_modules["c_proj"]].register_forward_hook(c_proj_hook),
        named_modules[required_modules["block"]].register_forward_hook(block_hook),
    ]
    sample_input_ids = torch.tensor([[args.token_id]], dtype=torch.long)
    try:
        with torch.no_grad():
            model(sample_input_ids)
    finally:
        for handle in handles:
            handle.remove()

    required_tensors = {
        "residual_activation_in",
        "ln2_activation_out",
        "c_proj_activation_in",
        "c_proj_activation_out",
        "block_output",
    }
    missing_tensors = sorted(required_tensors.difference(captured))
    if missing_tensors:
        raise SystemExit(f"hooks did not capture tensors: {missing_tensors}")

    residual_add_f32 = (
        captured["residual_activation_in"] + captured["c_proj_activation_out"]
    ).detach().cpu().contiguous()
    captured["residual_add_f32"] = residual_add_f32

    c_fc_contract_in = load_contract_tensor(
        args.c_fc_contract_manifest,
        "activation_in",
    )
    c_proj_contract_in = load_contract_tensor(
        args.c_proj_contract_manifest,
        "activation_in",
    )
    c_proj_contract_out = load_contract_tensor(
        args.c_proj_contract_manifest,
        "activation_out",
    )

    checks = {
        "ln2_activation_out_vs_c_fc_activation_in": score_error(
            captured["ln2_activation_out"],
            c_fc_contract_in,
        ),
        "c_proj_activation_in_vs_contract": score_error(
            captured["c_proj_activation_in"],
            c_proj_contract_in,
        ),
        "c_proj_activation_out_vs_contract": score_error(
            captured["c_proj_activation_out"],
            c_proj_contract_out,
        ),
        "residual_plus_c_proj_vs_block_output": score_error(
            residual_add_f32,
            captured["block_output"],
        ),
    }
    status = (
        "PASS"
        if all(metric_passes(metric, args.error_threshold) for metric in checks.values())
        else "FAIL"
    )

    args.output_dir.mkdir(parents=True, exist_ok=True)
    tensor_files = {
        "residual_activation_in": "residual_activation_in.bin",
        "ln2_activation_out": "ln2_activation_out.bin",
        "c_proj_activation_in": "c_proj_activation_in.bin",
        "c_proj_activation_out": "c_proj_activation_out.bin",
        "block_output": "block_output.bin",
        "residual_add_f32": "residual_add_f32.bin",
    }
    for name, filename in tensor_files.items():
        write_tensor(args.output_dir / filename, captured[name])

    manifest = {
        "artifact_name": "h2-int8-l2-residual-add-contract",
        "status": status,
        "model_label": args.model_label,
        "representation_level": "pytorch-module-hooks",
        "capture_kind": "representative-core-single-token-residual-add",
        "sample_input_ids": sample_input_ids.tolist(),
        "config": {
            "vocab_size": args.vocab_size,
            "num_layers": args.num_layers,
            "max_position_embeddings": args.max_position_embeddings,
            "window_size": args.window_size,
            "hidden_size": args.hidden_size,
            "num_heads": args.num_heads,
        },
        "modules": {
            "residual_operand": required_modules["ln_2"],
            "mlp_projection": required_modules["c_proj"],
            "block": required_modules["block"],
        },
        "source_artifacts": {
            "c_fc_contract_manifest": str(args.c_fc_contract_manifest),
            "c_proj_contract_manifest": str(args.c_proj_contract_manifest),
        },
        "tensors": [
            to_tensor_meta(name, captured[name], filename)
            for name, filename in tensor_files.items()
        ],
        "cross_checks": checks,
        "error_threshold": args.error_threshold,
        "decision": {
            "verdict": "score-residual-add-boundary" if status == "PASS" else "fix-capture",
            "next_gate": (
                "score residual_f32 + int8 c_proj output and quantized residual-add output"
                if status == "PASS"
                else "debug residual capture cross-checks before quantized scoring"
            ),
        },
    }

    (args.output_dir / "manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
