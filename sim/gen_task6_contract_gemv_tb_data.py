from __future__ import annotations

import argparse
import json
from pathlib import Path
import struct
from typing import Any

import torch


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--contract-manifest", required=True, type=Path)
    parser.add_argument("--weight-pack-manifest", required=True, type=Path)
    return parser.parse_args()


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def tensor_map(manifest: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {tensor["name"]: tensor for tensor in manifest["tensors"]}


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


def f32_bits(value: float) -> int:
    return struct.unpack("<I", struct.pack("<f", float(value)))[0]


def addr_width(word_count: int) -> int:
    return max(1, (word_count - 1).bit_length())


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
    ).reshape(-1)
    weight = load_f32_tensor(
        weight_pack_dir / weight_tensors["weight"]["filename"],
        weight_tensors["weight"]["shape"],
    )

    if weight.ndim != 2:
        raise SystemExit(f"expected 2D weight tensor, got {list(weight.shape)}")
    if activation_in.numel() != weight.shape[1]:
        raise SystemExit(
            f"activation length {activation_in.numel()} does not match packed weight input dim {weight.shape[1]}"
        )

    activation_words = activation_in.reshape(1, -1)
    weight_words = weight.transpose(0, 1)
    expected_out = torch.matmul(activation_words, weight_words).reshape(-1)

    activation_flat = activation_words.reshape(-1)
    weight_flat = weight_words.reshape(-1)

    print(f"localparam int ACTIVATION_WORDS = {activation_flat.numel()};")
    print(f"localparam int WEIGHT_WORDS = {weight_flat.numel()};")
    print(f"localparam int EXPECTED_STORE_COUNT = {expected_out.numel()};")
    print(
        f"localparam int ACTIVATION_ADDR_WIDTH = {addr_width(activation_flat.numel())};"
    )
    print(f"localparam int WEIGHT_ADDR_WIDTH = {addr_width(weight_flat.numel())};")
    print(
        f"localparam int OUTPUT_ADDR_WIDTH = {addr_width(expected_out.numel())};"
    )
    print("logic [31:0] activation_mem [0:ACTIVATION_WORDS - 1];")
    print("logic [31:0] weight_mem [0:WEIGHT_WORDS - 1];")
    print("logic [31:0] expected_mem [0:EXPECTED_STORE_COUNT - 1];")
    print("initial begin")
    for index, value in enumerate(activation_flat):
        print(f"  activation_mem[{index}] = 32'h{f32_bits(value.item()):08x};")
    for index, value in enumerate(weight_flat):
        print(f"  weight_mem[{index}] = 32'h{f32_bits(value.item()):08x};")
    for index, value in enumerate(expected_out):
        print(f"  expected_mem[{index}] = 32'h{f32_bits(value.item()):08x};")
    print("end")


if __name__ == "__main__":
    main()
