from __future__ import annotations

"""TorchAO single-projection reproducer for rank-3 dynamic activation qparams."""

import torch
from torchao.quantization import Int8DynamicActivationInt8WeightConfig, quantize_


EXPORT_STRICT = False


class QuantProjection(torch.nn.Module):
    def __init__(self, hidden_size: int = 64) -> None:
        super().__init__()
        self.proj = torch.nn.Linear(hidden_size, hidden_size, bias=False)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.proj(x)


def example_inputs() -> tuple[torch.Tensor, ...]:
    return (torch.randn(1, 4, 64),)


def _is_linear(module: torch.nn.Module, fqn: str) -> bool:
    del fqn
    return isinstance(module, torch.nn.Linear)


def export_program(model_path: str | None) -> torch.export.ExportedProgram:
    del model_path
    model = QuantProjection().eval()
    quantize_(
        model,
        Int8DynamicActivationInt8WeightConfig(),
        filter_fn=_is_linear,
    )
    return torch.export.export(
        model,
        tuple(example_inputs()),
        strict=EXPORT_STRICT,
    )
