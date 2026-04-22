#!/usr/bin/env python3
from __future__ import annotations

"""Replay the selected L1 contract from packed weights and compare outputs."""

import argparse
import json
from pathlib import Path
from typing import Any

import torch


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--contract-manifest", required=True, type=Path)
    parser.add_argument("--weight-pack-manifest", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--atol", type=float, default=1e-6)
    parser.add_argument("--rtol", type=float, default=1e-6)
    return parser.parse_args()


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def load_f32_tensor(path: Path, shape: list[int]) -> torch.Tensor:
    raw = path.read_bytes()
    tensor = torch.frombuffer(memoryview(bytearray(raw)), dtype=torch.float32).clone()
    expected_numel = 1
    for dim in shape:
        expected_numel *= dim
    if tensor.numel() != expected_numel:
        raise SystemExit(
            f"tensor size mismatch for {path}: expected {expected_numel} values, got {tensor.numel()}"
        )
    return tensor.reshape(shape)


def tensor_map(manifest: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {tensor["name"]: tensor for tensor in manifest["tensors"]}


def main() -> None:
    args = parse_args()
    contract = load_json(args.contract_manifest)
    weight_pack = load_json(args.weight_pack_manifest)

    contract_tensors = tensor_map(contract)
    weight_tensors = tensor_map(weight_pack)

    contract_dir = args.contract_manifest.parent
    weight_pack_dir = args.weight_pack_manifest.parent

    activation_in = load_f32_tensor(
        contract_dir / contract_tensors["activation_in"]["filename"],
        contract_tensors["activation_in"]["shape"],
    )
    expected_out = load_f32_tensor(
        contract_dir / contract_tensors["activation_out"]["filename"],
        contract_tensors["activation_out"]["shape"],
    )
    weight = load_f32_tensor(
        weight_pack_dir / weight_tensors["weight"]["filename"],
        weight_tensors["weight"]["shape"],
    )
    bias = load_f32_tensor(
        weight_pack_dir / weight_tensors["bias"]["filename"],
        weight_tensors["bias"]["shape"],
    )

    replay_out = torch.matmul(
        activation_in.reshape(-1, activation_in.shape[-1]),
        weight.transpose(0, 1),
    ) + bias
    replay_out = replay_out.reshape(expected_out.shape)

    abs_error = torch.abs(replay_out - expected_out)
    max_abs_error = float(abs_error.max().item())
    mean_abs_error = float(abs_error.mean().item())
    passed = bool(torch.allclose(replay_out, expected_out, atol=args.atol, rtol=args.rtol))

    result = {
        "verification_kind": "packed-gemv-replay",
        "contract_manifest": str(args.contract_manifest),
        "weight_pack_manifest": str(args.weight_pack_manifest),
        "formula": "activation_in @ weight.T + bias",
        "tolerances": {
            "atol": args.atol,
            "rtol": args.rtol,
        },
        "metrics": {
            "max_abs_error": max_abs_error,
            "mean_abs_error": mean_abs_error,
        },
        "shapes": {
            "activation_in": list(activation_in.shape),
            "weight": list(weight.shape),
            "bias": list(bias.shape),
            "activation_out": list(expected_out.shape),
        },
        "verdict": "pass" if passed else "fail",
    }

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")

    if not passed:
        raise SystemExit(
            f"contract replay failed: max_abs_error={max_abs_error:.6g}, mean_abs_error={mean_abs_error:.6g}"
        )


if __name__ == "__main__":
    main()
