from __future__ import annotations

"""Minimal PT2E static-quantized matmul reproducer using X86InductorQuantizer."""

import torch
from torch.ao.quantization import move_exported_model_to_eval
from torch.ao.quantization.quantize_pt2e import convert_pt2e, prepare_pt2e
from torch.ao.quantization.quantizer.x86_inductor_quantizer import (
    X86InductorQuantizer,
    get_default_x86_inductor_quantization_config,
)


EXPORT_STRICT = False


class QuantMatmul(torch.nn.Module):
    def forward(self, lhs: torch.Tensor, rhs: torch.Tensor) -> torch.Tensor:
        return torch.matmul(lhs, rhs)


def example_inputs() -> tuple[torch.Tensor, ...]:
    return (
        torch.randn(2, 4, 8),
        torch.randn(2, 8, 4),
    )


def export_program(model_path: str | None) -> torch.export.ExportedProgram:
    del model_path
    model = QuantMatmul().eval()
    inputs = tuple(example_inputs())
    exported = torch.export.export(
        model,
        inputs,
        strict=EXPORT_STRICT,
    )
    quantizer = X86InductorQuantizer().set_global(
        get_default_x86_inductor_quantization_config()
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
