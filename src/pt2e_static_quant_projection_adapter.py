from __future__ import annotations

"""PT2E static-quantized rank-3 projection reproducer for torch-mlir."""

import torch
from torch.ao.quantization import move_exported_model_to_eval
from torch.ao.quantization.quantize_pt2e import convert_pt2e, prepare_pt2e
from torch.ao.quantization.quantizer.xnnpack_quantizer import (
    XNNPACKQuantizer,
    get_symmetric_quantization_config,
)


EXPORT_STRICT = False


class QuantProjection(torch.nn.Module):
    def __init__(self, hidden_size: int = 64) -> None:
        super().__init__()
        self.proj = torch.nn.Linear(hidden_size, hidden_size, bias=False)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.proj(x)


def example_inputs() -> tuple[torch.Tensor, ...]:
    return (torch.randn(1, 4, 64),)


def export_program(model_path: str | None) -> torch.export.ExportedProgram:
    del model_path
    model = QuantProjection().eval()
    inputs = tuple(example_inputs())
    exported = torch.export.export(
        model,
        inputs,
        strict=EXPORT_STRICT,
    )
    quantizer = XNNPACKQuantizer().set_global(
        get_symmetric_quantization_config(is_dynamic=False)
    )
    prepared = prepare_pt2e(exported.module(), quantizer)
    with torch.no_grad():
        prepared(*inputs)
    quantized = convert_pt2e(prepared)
    move_exported_model_to_eval(quantized)
    return torch.export.export(
        quantized,
        inputs,
        strict=EXPORT_STRICT,
    )
