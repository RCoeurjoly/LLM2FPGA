from __future__ import annotations

"""PT2E static-quantized Embedding reproducer using ComposableQuantizer."""

import torch
from torch.ao.quantization import move_exported_model_to_eval
from torch.ao.quantization.quantize_pt2e import convert_pt2e, prepare_pt2e
from torch.ao.quantization.quantizer.composable_quantizer import ComposableQuantizer
from torch.ao.quantization.quantizer.embedding_quantizer import EmbeddingQuantizer
from torch.ao.quantization.quantizer.xnnpack_quantizer import (
    XNNPACKQuantizer,
    get_symmetric_quantization_config,
)


EXPORT_STRICT = False


class QuantEmbedding(torch.nn.Module):
    def __init__(self) -> None:
        super().__init__()
        self.embedding = torch.nn.Embedding(16, 8)

    def forward(self, token_ids: torch.Tensor) -> torch.Tensor:
        return self.embedding(token_ids)


def example_inputs() -> tuple[torch.Tensor, ...]:
    return (torch.tensor([[0, 1, 2, 3], [4, 5, 6, 7]], dtype=torch.int64),)


def export_program(model_path: str | None) -> torch.export.ExportedProgram:
    del model_path
    model = QuantEmbedding().eval()
    inputs = tuple(example_inputs())
    exported = torch.export.export(
        model,
        inputs,
        strict=EXPORT_STRICT,
    )
    quantizer = ComposableQuantizer(
        [
            EmbeddingQuantizer(),
            XNNPACKQuantizer().set_global(
                get_symmetric_quantization_config(is_dynamic=False)
            ),
        ]
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
