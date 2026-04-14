from __future__ import annotations

"""TinyStories adapter using PT2E static quantization with standard quantizers."""

import copy
import torch
from torch.ao.quantization import move_exported_model_to_eval
from torch.ao.quantization.quantize_pt2e import convert_pt2e, prepare_pt2e
from torch.ao.quantization.quantizer.xnnpack_quantizer import (
    XNNPACKQuantizer,
    get_symmetric_quantization_config,
)
from torch.export.graph_signature import TensorArgument
from transformers import AutoModelForCausalLM


EXPORT_STRICT = False


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
        raise RuntimeError("expected trailing dequantize_per_tensor at model output")

    quantized = dequant.args[0]
    if not isinstance(quantized, torch.fx.Node):
        raise RuntimeError("expected quantized tensor node before output dequantize")
    if quantized.target != torch.ops.quantized_decomposed.quantize_per_tensor.default:
        raise RuntimeError("expected output dequantize to consume quantize_per_tensor")

    output_node.args = ((quantized,),)
    graph.lint()

    graph_signature = copy.deepcopy(exported.graph_signature)
    if len(graph_signature.output_specs) != 1:
        raise RuntimeError("expected a single output spec for TinyStories export")
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
        get_symmetric_quantization_config(is_dynamic=False)
    )
    prepared = prepare_pt2e(exported.module(), quantizer)
    with torch.no_grad():
        prepared(*inputs)
    quantized = convert_pt2e(prepared)
    move_exported_model_to_eval(quantized)
    return _strip_trailing_output_dequantize(torch.export.export(
        quantized,
        inputs,
        strict=EXPORT_STRICT,
    ))
