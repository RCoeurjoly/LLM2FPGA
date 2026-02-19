import os
from pathlib import Path

import torch
from sim_utils import load_matmul_module

def load_vectors(path: Path) -> tuple[torch.Tensor, torch.Tensor]:
    import json

    with path.open("r", encoding="utf-8") as f:
        payload = json.load(f)
    if payload.get("dtype") != "int32":
        raise ValueError(f"Expected dtype 'int32', got {payload.get('dtype')!r}")
    if payload.get("shape") != [16]:
        raise ValueError(f"Expected shape [16], got {payload.get('shape')!r}")
    a = torch.tensor(payload["a"], dtype=torch.int32)
    b = torch.tensor(payload["b"], dtype=torch.int32)
    if a.numel() != 16 or b.numel() != 16:
        raise ValueError("Expected exactly 16 elements in both 'a' and 'b'")
    return a, b

def main() -> None:
    a, b = load_vectors(Path(__file__).parent / "test_vectors.json")

    MatmulModule = load_matmul_module()
    m = MatmulModule().eval()
    with torch.no_grad():
        expected = int(m(a, b).item())

    print("logic [31:0] a_mem [0:15];")
    print("logic [31:0] b_mem [0:15];")
    print(f"logic [31:0] expected = 32'd{expected};")
    print("initial begin")
    for i in range(16):
        print(f"  a_mem[{i}] = 32'd{int(a[i])};")
    for i in range(16):
        print(f"  b_mem[{i}] = 32'd{int(b[i])};")
    print("end")


if __name__ == "__main__":
    main()
