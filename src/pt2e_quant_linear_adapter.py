from __future__ import annotations

"""Minimal PT2E dynamic-quantized Linear reproducer for torch-mlir."""

import torch
from torch.ao.quantization import move_exported_model_to_eval
from torch.ao.quantization.quantize_pt2e import convert_pt2e, prepare_pt2e
from torch.ao.quantization.quantizer.xnnpack_quantizer import (
    XNNPACKQuantizer,
    get_symmetric_quantization_config,
)


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
    exported = torch.export.export(
        model,
        inputs,
        strict=EXPORT_STRICT,
    )
    quantizer = XNNPACKQuantizer().set_global(
        get_symmetric_quantization_config(is_dynamic=True)
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
