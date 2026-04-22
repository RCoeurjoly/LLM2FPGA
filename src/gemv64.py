from __future__ import annotations

import torch


class Gemv64Module(torch.nn.Module):
    """Minimal external-weight GEMV kernel for StreamTensor-lite L0."""

    def forward(self, activation: torch.Tensor, weight: torch.Tensor) -> torch.Tensor:
        return torch.matmul(activation, weight)
