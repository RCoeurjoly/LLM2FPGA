from __future__ import annotations

import struct

import torch

from sim_utils import load_gemv64_module

VECTOR_LEN = 64


def f32_bits(value: float) -> int:
    return struct.unpack("<I", struct.pack("<f", float(value)))[0]


def build_activation() -> torch.Tensor:
    values = [((index % 8) - 4) / 8.0 for index in range(VECTOR_LEN)]
    return torch.tensor([values], dtype=torch.float32)


def build_weight() -> torch.Tensor:
    rows = []
    for row_index in range(VECTOR_LEN):
        row = [
            (((row_index * 3) + (col_index * 5)) % 17 - 8) / 16.0
            for col_index in range(VECTOR_LEN)
        ]
        rows.append(row)
    return torch.tensor(rows, dtype=torch.float32)


def main() -> None:
    activation = build_activation()
    weight = build_weight()

    Gemv64Module = load_gemv64_module()
    model = Gemv64Module().eval()
    with torch.no_grad():
        expected = model(activation, weight).reshape(-1)

    activation_words = activation.reshape(-1)
    weight_words = weight.reshape(-1)

    print("logic [31:0] activation_mem [0:63];")
    print("logic [31:0] weight_mem [0:4095];")
    print("logic [31:0] expected_mem [0:63];")
    print("localparam int EXPECTED_STORE_COUNT = 64;")
    print("initial begin")
    for index, value in enumerate(activation_words):
        print(f"  activation_mem[{index}] = 32'h{f32_bits(value.item()):08x};")
    for index, value in enumerate(weight_words):
        print(f"  weight_mem[{index}] = 32'h{f32_bits(value.item()):08x};")
    for index, value in enumerate(expected):
        print(f"  expected_mem[{index}] = 32'h{f32_bits(value.item()):08x};")
    print("end")


if __name__ == "__main__":
    main()
