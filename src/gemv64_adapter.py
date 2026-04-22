from __future__ import annotations

import torch

from gemv64 import Gemv64Module


def build_model(_model_path: str | None) -> torch.nn.Module:
    return Gemv64Module().eval()


def example_inputs() -> tuple[torch.Tensor, ...]:
    return (
        torch.zeros((1, 64), dtype=torch.float32),
        torch.zeros((64, 64), dtype=torch.float32),
    )
