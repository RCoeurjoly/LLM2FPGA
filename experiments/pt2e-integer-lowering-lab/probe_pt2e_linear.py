#!/usr/bin/env python3
from __future__ import annotations

import argparse
import importlib
import json
from pathlib import Path
from typing import Any

from audit import audit_graph_text


DEFAULT_QUANTIZER = "executorch.backends.xnnpack.quantizer.xnnpack_quantizer.XNNPACKQuantizer"


def load_pt2e_api() -> tuple[Any, Any]:
    try:
        module = importlib.import_module("torch.ao.quantization.quantize_pt2e")
    except Exception:
        module = importlib.import_module("torchao.quantization.pt2e.quantize_pt2e")
    return module.prepare_pt2e, module.convert_pt2e


def load_object(dotted_name: str) -> Any:
    module_name, _, object_name = dotted_name.rpartition(".")
    if not module_name or not object_name:
        raise ValueError(f"expected dotted object path, got {dotted_name!r}")
    module = importlib.import_module(module_name)
    return getattr(module, object_name)


def configure_quantizer(quantizer: Any, dotted_name: str) -> Any:
    module_name, _, _ = dotted_name.rpartition(".")
    module = importlib.import_module(module_name)
    get_config = getattr(module, "get_symmetric_quantization_config", None)
    set_global = getattr(quantizer, "set_global", None)
    if get_config is not None and set_global is not None:
        set_global(get_config())
    return quantizer


def run_probe(quantizer_name: str) -> dict[str, Any]:
    import torch
    from torch import nn

    prepare_pt2e, convert_pt2e = load_pt2e_api()

    class TinyLinear(nn.Module):
        def __init__(self) -> None:
            super().__init__()
            self.linear = nn.Linear(4, 3)

        def forward(self, x: torch.Tensor) -> torch.Tensor:
            return self.linear(x)

    example = (torch.randn(2, 4),)
    exported = torch.export.export(TinyLinear().eval(), example).module()
    quantizer_type = load_object(quantizer_name)
    quantizer = configure_quantizer(quantizer_type(), quantizer_name)
    prepared = prepare_pt2e(exported, quantizer)
    prepared(*example)
    converted = convert_pt2e(prepared)

    graph_text = str(converted.graph)
    return {
        "schema_version": 1,
        "quantizer": quantizer_name,
        "graph_text": graph_text,
        "audit": audit_graph_text(graph_text),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Probe PT2E quantization shape for a tiny nn.Linear.")
    parser.add_argument("--quantizer", default=DEFAULT_QUANTIZER)
    parser.add_argument("--out-dir", type=Path, default=Path("out"))
    args = parser.parse_args()

    result = run_probe(args.quantizer)
    args.out_dir.mkdir(parents=True, exist_ok=True)
    (args.out_dir / "converted_graph.txt").write_text(result["graph_text"], encoding="utf-8")
    report = {
        "schema_version": result["schema_version"],
        "quantizer": result["quantizer"],
        "audit": result["audit"],
    }
    (args.out_dir / "report.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
