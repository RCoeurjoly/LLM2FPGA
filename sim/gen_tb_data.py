import os
from pathlib import Path

import torch
from sim_utils import load_matmul_module, load_vectors


def main() -> None:
    vectors_path = Path(os.environ.get("TEST_VECTORS_PATH", str(Path(__file__).parent / "test_vectors.json")))
    a, b = load_vectors(vectors_path)

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
