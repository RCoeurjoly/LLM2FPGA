from __future__ import annotations

import copy
import os

import torch
from torch.ao.quantization import move_exported_model_to_eval
from torch.ao.quantization.quantize_pt2e import convert_pt2e, prepare_pt2e
from torch.ao.quantization.quantizer.xnnpack_quantizer import (
    XNNPACKQuantizer,
    get_symmetric_quantization_config,
)
from torch.export.graph_signature import TensorArgument

from task6_rect_gemv import Task6RectGemvModule


EXPORT_STRICT = False


def env_int(name: str) -> int:
    value = os.environ.get(name)
    if value is None:
        raise RuntimeError(f"missing required environment variable: {name}")
    return int(value)


def _strip_trailing_output_dequantize(
    exported: torch.export.ExportedProgram,
) -> torch.export.ExportedProgram:
    graph = copy.deepcopy(exported.graph)
    output_node = next(node for node in graph.nodes if node.op == "output")
    returned = output_node.args[0]
    if not (
        isinstance(returned, tuple)
        and len(returned) == 1
        and isinstance(returned[0], torch.fx.Node)
    ):
        raise RuntimeError("expected a single-tensor model output")

    dequant = returned[0]
    if dequant.target != torch.ops.quantized_decomposed.dequantize_per_tensor.default:
        # PT2E-static currently leaves the external-weight GEMV unquantized on
        # this minimal surface, so the output can remain the original float
        # tensor with no trailing dequantize node.
        return exported

    quantized = dequant.args[0]
    if not isinstance(quantized, torch.fx.Node):
        raise RuntimeError("expected quantized tensor node before output dequantize")
    if quantized.target != torch.ops.quantized_decomposed.quantize_per_tensor.default:
        raise RuntimeError("expected output dequantize to consume quantize_per_tensor")

    output_node.args = ((quantized,),)
    graph.lint()

    graph_signature = copy.deepcopy(exported.graph_signature)
    if len(graph_signature.output_specs) != 1:
        raise RuntimeError("expected a single output spec for Task 6 export")
    graph_signature.output_specs[0].arg = TensorArgument(name=quantized.name)

    return torch.export.ExportedProgram(
        exported.graph_module,
        graph,
        graph_signature,
        exported.state_dict,
        exported.range_constraints,
        exported.module_call_graph,
        exported.example_inputs,
        exported.constants,
        verifiers=exported.verifiers,
    )


def build_model(_model_path: str | None) -> torch.nn.Module:
    return Task6RectGemvModule().eval()


def example_inputs() -> tuple[torch.Tensor, ...]:
    input_dim = env_int("TASK6_RECT_GEMV_IN_DIM")
    output_dim = env_int("TASK6_RECT_GEMV_OUT_DIM")
    return (
        torch.zeros((1, input_dim), dtype=torch.float32),
        torch.zeros((input_dim, output_dim), dtype=torch.float32),
    )


def export_program(_model_path: str | None) -> torch.export.ExportedProgram:
    model = build_model(None)
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
    return _strip_trailing_output_dequantize(
        torch.export.export(
            quantized,
            inputs,
            strict=EXPORT_STRICT,
        )
    )
