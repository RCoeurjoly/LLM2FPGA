import importlib.util
import os
from pathlib import Path

import torch


def load_module_class(default_path: Path, env_var: str, class_name: str):
    module_path = Path(os.environ.get(env_var, str(default_path)))
    spec = importlib.util.spec_from_file_location(f"{class_name}_module", module_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Failed to load module spec from {module_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return getattr(module, class_name)


def load_matmul_module():
    return load_module_class(
        Path(__file__).parent.parent / "src" / "matmul.py",
        "MATMUL_PY",
        "MatmulModule",
    )


def load_gemv64_module():
    return load_module_class(
        Path(__file__).parent.parent / "src" / "gemv64.py",
        "GEMV64_PY",
        "Gemv64Module",
    )
