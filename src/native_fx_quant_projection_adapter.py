from __future__ import annotations

"""Native-FX quantized single-projection reproducer."""

from native_fx_quant_attention_models import (
    QuantProjection,
    projection_example_inputs,
)
from native_fx_quant_utils import build_native_fx_raw_mlir


def build_mlir_module(model_path: str | None, output_type: str) -> str:
    del model_path
    return build_native_fx_raw_mlir(
        QuantProjection().eval(),
        projection_example_inputs(),
        output_type=output_type,
    )
