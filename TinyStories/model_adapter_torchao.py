from __future__ import annotations

"""TinyStories adapter using the current official TorchAO quantize_ API."""

import torch
from torchao.quantization import (
    Int8DynamicActivationInt8WeightConfig,
    Int8WeightOnlyConfig,
    quantize_,
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


def _is_linear(module: torch.nn.Module, fqn: str) -> bool:
    del fqn
    return isinstance(module, torch.nn.Linear)


def _is_embedding(module: torch.nn.Module, fqn: str) -> bool:
    del fqn
    return isinstance(module, torch.nn.Embedding)


def export_program(model_path: str | None) -> torch.export.ExportedProgram:
    model = build_model(model_path)
    inputs = tuple(example_inputs())
    quantize_(model, Int8WeightOnlyConfig(), filter_fn=_is_embedding)
    quantize_(
        model,
        Int8DynamicActivationInt8WeightConfig(),
        filter_fn=_is_linear,
    )
    return torch.export.export(
        model,
        inputs,
        strict=EXPORT_STRICT,
    )
