from __future__ import annotations

import torch

from gemv64_int16 import Gemv64Int16Module


def build_model(_model_path: str | None) -> torch.nn.Module:
    return Gemv64Int16Module().eval()


def example_inputs() -> tuple[torch.Tensor, ...]:
    return (
        torch.zeros((1, 64), dtype=torch.int16),
        torch.zeros((64, 64), dtype=torch.int16),
    )
