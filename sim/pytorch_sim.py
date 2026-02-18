import json
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

    payload = {
        "a": [int(x) for x in a.tolist()],
        "b": [int(x) for x in b.tolist()],
        "expected": expected,
        "note": "1D matmul (dot) of a and b with deterministic vectors.",
    }
    print(json.dumps(payload, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
