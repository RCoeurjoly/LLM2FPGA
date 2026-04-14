from __future__ import annotations

"""Native-FX quantized LayerNorm reproducer for the local torch-mlir importer."""

import torch

from native_fx_quant_utils import build_native_fx_raw_mlir


class QuantLayerNorm(torch.nn.Module):
    def __init__(self, hidden_size: int = 8) -> None:
        super().__init__()
        self.layer_norm = torch.nn.LayerNorm(hidden_size)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.layer_norm(x)


def example_inputs() -> tuple[torch.Tensor, ...]:
    return (torch.randn(2, 4, 8),)


def build_mlir_module(model_path: str | None, output_type: str) -> str:
    del model_path
    return build_native_fx_raw_mlir(
        QuantLayerNorm().eval(),
        example_inputs(),
        output_type=output_type,
    )
