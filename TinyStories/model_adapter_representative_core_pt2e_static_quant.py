from __future__ import annotations

"""Representative-core TinyStories adapter using PT2E static quantization."""

import copy
import os
from pathlib import Path

import torch
from torch.ao.quantization import move_exported_model_to_eval
from torch.ao.quantization.quantize_pt2e import convert_pt2e, prepare_pt2e
from torch.ao.quantization.pt2e.representation.rewrite import (
    reference_representation_rewrite,
)
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


def _qrange(bits: int) -> tuple[int, int]:
    if bits < 2:
        raise ValueError(f"PT2E static quant bits must be >= 2; got {bits}")
    qmax = (1 << (bits - 1)) - 1
    return -(qmax + 1), qmax


def _maybe_dump_quantized_graph(model: torch.nn.Module) -> None:
    dump_path = os.environ.get("TINYSTORIES_DUMP_PT2E_QUANTIZED_GRAPH")
    if dump_path is None:
        return

    graph_text = str(model.graph)
    if dump_path == "-":
        print(graph_text)
        return

    Path(dump_path).write_text(graph_text, encoding="utf-8")


def _maybe_reference_representation_rewrite(
    model: torch.fx.GraphModule,
) -> torch.fx.GraphModule:
    value = os.environ.get("TINYSTORIES_PT2E_REFERENCE_REPRESENTATION_REWRITE")
    if value is None or value in {"", "0", "false", "False"}:
        return model
    return reference_representation_rewrite(model)


def _reference_representation_rewrite_enabled() -> bool:
    value = os.environ.get("TINYSTORIES_PT2E_REFERENCE_REPRESENTATION_REWRITE")
    return value is not None and value not in {"", "0", "false", "False"}


def _materialize_missing_linear_biases(model: torch.nn.Module) -> None:
    for module in model.modules():
        if isinstance(module, torch.nn.Linear) and module.bias is None:
            module.bias = torch.nn.Parameter(torch.zeros(module.out_features))


def _decompose_out_dtype(model: torch.fx.GraphModule) -> torch.fx.GraphModule:
    graph = model.graph
    for node in list(graph.nodes):
        if node.op != "call_function" or node.target != torch.ops.higher_order.out_dtype:
            continue
        op, output_dtype, *op_args = node.args
        with graph.inserting_before(node):
            op_node = graph.call_function(op, args=tuple(op_args))
            to_node = graph.call_function(
                torch.ops.aten.to.dtype,
                args=(op_node, output_dtype),
            )
        node.replace_all_uses_with(to_node)
        graph.erase_node(node)
    graph.lint()
    model.recompile()
    return model


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
    use_reference_rewrite = _reference_representation_rewrite_enabled()
    if use_reference_rewrite:
        _materialize_missing_linear_biases(model)
    inputs = tuple(example_inputs())
    exported = torch.export.export(
        model,
        inputs,
        strict=EXPORT_STRICT,
    )
    activation_bits = env_int("TINYSTORIES_PYTORCHAO_ACTIVATION_BITS", 8)
    weight_bits = env_int("TINYSTORIES_PYTORCHAO_WEIGHT_BITS", 8)
    activation_qmin, activation_qmax = _qrange(activation_bits)
    weight_qmin, weight_qmax = _qrange(weight_bits)
    quantizer = XNNPACKQuantizer().set_global(
        get_symmetric_quantization_config(
            is_dynamic=False,
            act_qmin=activation_qmin,
            act_qmax=activation_qmax,
            weight_qmin=weight_qmin,
            weight_qmax=weight_qmax,
        )
    )
    prepared = prepare_pt2e(exported.module(), quantizer)
    with torch.no_grad():
        prepared(*inputs)
    quantized = convert_pt2e(prepared)
    _maybe_dump_quantized_graph(quantized)
    quantized = _maybe_reference_representation_rewrite(quantized)
    if use_reference_rewrite:
        quantized = _decompose_out_dtype(quantized)
    move_exported_model_to_eval(quantized)
    exported = torch.export.export(
        quantized,
        inputs,
        strict=EXPORT_STRICT,
    )
    if use_reference_rewrite:
        return exported
    return _strip_trailing_output_dequantize(exported)
