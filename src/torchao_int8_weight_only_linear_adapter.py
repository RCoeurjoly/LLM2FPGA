from __future__ import annotations

"""Minimal TorchAO int8 weight-only Linear reproducer."""

import torch
from torchao.quantization import Int8WeightOnlyConfig, quantize_


EXPORT_STRICT = False


class QuantLinear(torch.nn.Module):
    def __init__(self) -> None:
        super().__init__()
        self.linear = torch.nn.Linear(5, 10)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.linear(x)


def example_inputs() -> tuple[torch.Tensor, ...]:
    return (torch.randn(2, 5),)


def export_program(model_path: str | None) -> torch.export.ExportedProgram:
    del model_path
    model = QuantLinear().eval()
    inputs = tuple(example_inputs())
    quantize_(model, Int8WeightOnlyConfig())
    return torch.export.export(
        model,
        inputs,
        strict=EXPORT_STRICT,
    )
