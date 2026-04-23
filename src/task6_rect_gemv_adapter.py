from __future__ import annotations

import os

import torch

from task6_rect_gemv import Task6RectGemvModule


def env_int(name: str) -> int:
    value = os.environ.get(name)
    if value is None:
        raise RuntimeError(f"missing required environment variable: {name}")
    return int(value)


def build_model(_model_path: str | None) -> torch.nn.Module:
    return Task6RectGemvModule().eval()


def example_inputs() -> tuple[torch.Tensor, ...]:
    input_dim = env_int("TASK6_RECT_GEMV_IN_DIM")
    output_dim = env_int("TASK6_RECT_GEMV_OUT_DIM")
    return (
        torch.zeros((1, input_dim), dtype=torch.float32),
        torch.zeros((input_dim, output_dim), dtype=torch.float32),
    )
