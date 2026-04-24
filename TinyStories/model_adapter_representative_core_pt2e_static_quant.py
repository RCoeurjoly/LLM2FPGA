from __future__ import annotations

"""Representative-core TinyStories adapter using PT2E static quantization."""

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
from transformers import AutoConfig, AutoModelForCausalLM


EXPORT_STRICT = False

DEFAULT_VOCAB_SIZE = 32
DEFAULT_NUM_LAYERS = 2
DEFAULT_MAX_POSITION_EMBEDDINGS = 4
DEFAULT_WINDOW_SIZE = 2
DEFAULT_HIDDEN_SIZE = 2
DEFAULT_NUM_HEADS = 1


def env_int(name: str, default: int) -> int:
    value = os.environ.get(name)
    if value is None:
        return default
    return int(value)


def attention_types_for_layers(num_layers: int) -> list[list[object]]:
    pattern = ["global", "local"]
    full_repeats, remainder = divmod(num_layers, len(pattern))
    attention_types: list[list[object]] = []
    if full_repeats:
        attention_types.append([pattern, full_repeats])
    if remainder:
        attention_types.append([pattern[:remainder], 1])
    return attention_types


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

    config = AutoConfig.from_pretrained(model_path, local_files_only=True)
    config.vocab_size = env_int("TINYSTORIES_CORE_VOCAB_SIZE", DEFAULT_VOCAB_SIZE)
    config.num_layers = env_int("TINYSTORIES_CORE_NUM_LAYERS", DEFAULT_NUM_LAYERS)
    config.max_position_embeddings = env_int(
        "TINYSTORIES_CORE_MAX_POSITION_EMBEDDINGS",
        DEFAULT_MAX_POSITION_EMBEDDINGS,
    )
    config.window_size = env_int("TINYSTORIES_CORE_WINDOW_SIZE", DEFAULT_WINDOW_SIZE)
    config.hidden_size = env_int("TINYSTORIES_CORE_HIDDEN_SIZE", DEFAULT_HIDDEN_SIZE)
    config.num_heads = env_int("TINYSTORIES_CORE_NUM_HEADS", DEFAULT_NUM_HEADS)
    config.attention_types = attention_types_for_layers(config.num_layers)
    config.attention_layers = config.expand_attention_types_params(config.attention_types)
    config.use_cache = False
    config.bos_token_id = config.vocab_size - 1
    config.eos_token_id = config.vocab_size - 1

    torch.manual_seed(0)
    return AutoModelForCausalLM.from_config(config).eval()


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
    return _strip_trailing_output_dequantize(
        torch.export.export(
            quantized,
            inputs,
            strict=EXPORT_STRICT,
        )
    )
