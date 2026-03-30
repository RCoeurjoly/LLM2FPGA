from __future__ import annotations

"""Helpers for local native-FX quantized reproducers."""

from typing import Iterable, Sequence

import torch
import torch.fx as torch_fx
from torch.ao.quantization import QConfig, QConfigMapping, default_qconfig
from torch.ao.quantization.observer import MinMaxObserver
from torch.ao.quantization.quantize_fx import convert_fx, prepare_fx
from torch.fx.graph_module import GraphModule
from torch.fx.passes.shape_prop import _extract_tensor_metadata
from torch_mlir._mlir_libs._torchMlir import register_dialect
from torch_mlir.extras.fx_importer import FxImporter
from torch_mlir.ir import Context


_RAW_ONLY_ERROR = (
    "native-FX reproducers currently support only --output-type raw; "
    "use scripts/dev/build-linalg-local-from-adapter.sh for the local "
    "raw -> linalg loop"
)


def make_true_per_tensor_qconfig_mapping() -> QConfigMapping:
    qconfig = QConfig(
        activation=default_qconfig.activation,
        weight=MinMaxObserver.with_args(
            dtype=torch.qint8,
            qscheme=torch.per_tensor_symmetric,
        ),
    )
    return QConfigMapping().set_global(qconfig)


def quantize_fx_graph_module(
    model: torch.nn.Module,
    example_inputs: Sequence[torch.Tensor],
    *,
    qconfig_mapping: QConfigMapping | None = None,
) -> GraphModule:
    inputs = tuple(example_inputs)
    prepared = prepare_fx(
        model.eval(),
        qconfig_mapping or make_true_per_tensor_qconfig_mapping(),
        inputs,
    )
    with torch.no_grad():
        prepared(*inputs)
    return convert_fx(prepared)


def _set_node_tensor_metadata(node: torch_fx.Node, value: torch.Tensor) -> None:
    node.meta["tensor_meta"] = _extract_tensor_metadata(value)
    node.meta["val"] = value


def annotate_graph_module_io(
    graph_module: GraphModule,
    example_inputs: Sequence[torch.Tensor],
) -> None:
    inputs = tuple(example_inputs)
    with torch.no_grad():
        output = graph_module(*inputs)

    placeholders = [node for node in graph_module.graph.nodes if node.op == "placeholder"]
    if len(placeholders) != len(inputs):
        raise RuntimeError(
            "native-FX metadata annotation expects placeholder count to match "
            "example_inputs"
        )
    for node, value in zip(placeholders, inputs):
        _set_node_tensor_metadata(node, value)

    output_node = next(
        (node for node in graph_module.graph.nodes if node.op == "output"),
        None,
    )
    if output_node is None:
        raise RuntimeError("native-FX metadata annotation could not find graph output")

    returned = output_node.args[0]
    if isinstance(returned, torch_fx.Node):
        _set_node_tensor_metadata(returned, output)
        return
    if isinstance(returned, (list, tuple)) and isinstance(output, (list, tuple)):
        if len(returned) != len(output):
            raise RuntimeError("native-FX metadata annotation saw mismatched tuple output")
        for node, value in zip(returned, output):
            if not isinstance(node, torch_fx.Node):
                raise RuntimeError("native-FX metadata annotation expected FX nodes in tuple output")
            _set_node_tensor_metadata(node, value)
        return
    raise RuntimeError("native-FX metadata annotation only supports tensor outputs")


def import_graph_module_to_raw_mlir(graph_module: GraphModule) -> str:
    with Context() as context:
        register_dialect(context)
        fx_importer = FxImporter(context=context)
        fx_importer.import_graph_module(graph_module)
        return str(fx_importer.module)


def build_native_fx_raw_mlir(
    model: torch.nn.Module,
    example_inputs: Iterable[torch.Tensor],
    *,
    output_type: str,
    qconfig_mapping: QConfigMapping | None = None,
) -> str:
    if output_type != "raw":
        raise SystemExit(_RAW_ONLY_ERROR)
    inputs = tuple(example_inputs)
    graph_module = quantize_fx_graph_module(
        model,
        inputs,
        qconfig_mapping=qconfig_mapping,
    )
    annotate_graph_module_io(graph_module, inputs)
    return import_graph_module_to_raw_mlir(graph_module)
