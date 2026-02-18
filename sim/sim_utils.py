import importlib.util
import os
from pathlib import Path

import torch


def load_matmul_module():
    default_matmul_path = Path(__file__).parent.parent / "src" / "matmul.py"
    matmul_path = Path(os.environ.get("MATMUL_PY", str(default_matmul_path)))
    spec = importlib.util.spec_from_file_location("matmul_module", matmul_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Failed to load module spec from {matmul_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.MatmulModule


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
