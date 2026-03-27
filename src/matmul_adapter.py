from __future__ import annotations

import torch

from sim_utils import load_matmul_module


MatmulModule = load_matmul_module()


def build_model(_model_path: str | None) -> torch.nn.Module:
    return MatmulModule().eval()


def example_inputs() -> tuple[torch.Tensor, ...]:
    return (
        torch.zeros((16,), dtype=torch.int32),
        torch.zeros((16,), dtype=torch.int32),
    )
