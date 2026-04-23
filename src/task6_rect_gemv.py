from __future__ import annotations

import torch


class Task6RectGemvModule(torch.nn.Module):
    """Minimal rectangular external-weight GEMV kernel for Task 6 redirect proofs."""

    def forward(self, activation: torch.Tensor, weight: torch.Tensor) -> torch.Tensor:
        return torch.matmul(activation, weight)
