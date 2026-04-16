from __future__ import annotations

"""TinyStories adapter using export-friendly PT2E dynamic quantization."""

import torch
from torch.ao.quantization import move_exported_model_to_eval
from torch.ao.quantization.quantize_pt2e import convert_pt2e, prepare_pt2e
from torch.ao.quantization.quantizer.xnnpack_quantizer import (
    XNNPACKQuantizer,
    get_symmetric_quantization_config,
)
from transformers import AutoModelForCausalLM


EXPORT_STRICT = False


def build_model(model_path: str | None) -> torch.nn.Module:
    if model_path is None:
        raise RuntimeError("TinyStories adapter requires --model-path")
    return AutoModelForCausalLM.from_pretrained(
        model_path,
        use_cache=False,
        attn_implementation="eager",
        local_files_only=True,
    ).eval()


def example_inputs() -> tuple[torch.Tensor, ...]:
    return (torch.zeros((1, 1), dtype=torch.long),)


def export_program(model_path: str | None) -> torch.export.ExportedProgram:
    model = build_model(model_path)
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
