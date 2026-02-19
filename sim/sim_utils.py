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
