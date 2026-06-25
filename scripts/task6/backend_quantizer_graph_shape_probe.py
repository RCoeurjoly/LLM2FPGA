#!/usr/bin/env python3
from __future__ import annotations

import argparse
import importlib
import json
from pathlib import Path
from typing import Any

from scripts.task6.executorch_backend_survey import backend_quantizer_entrypoints
from scripts.task6.pt2e_graph_shape_audit import audit_graph_text


def make_skip_report(*, backend: str, quantizer: str, reason: str, detail: str) -> dict[str, Any]:
    return {
        "schema_version": 1,
        "backend": backend,
        "quantizer": quantizer,
        "status": "skip",
        "skip_reason": reason,
        "detail": detail,
        "graph_shape_report": None,
    }


def audit_existing_graph(graph_text: str, *, backend: str, quantizer: str) -> dict[str, Any]:
    graph_report = audit_graph_text(graph_text, model_label=f"{backend}:{quantizer}")
    return {
        "schema_version": 1,
        "backend": backend,
        "quantizer": quantizer,
        "status": graph_report["status"],
        "skip_reason": None,
        "detail": "audited existing graph text",
        "graph_shape_report": graph_report,
    }


def import_object(dotted_name: str) -> object:
    module_name, _, object_name = dotted_name.rpartition(".")
    if not module_name or not object_name:
        raise ValueError("quantizer path must be a dotted object path")
    module = importlib.import_module(module_name)
    return getattr(module, object_name)


def choose_quantizer(backend: str, explicit_quantizer: str | None) -> str | None:
    if explicit_quantizer is not None:
        return explicit_quantizer
    candidates = backend_quantizer_entrypoints(backend)
    return candidates[0] if candidates else None


def run_tiny_pt2e_probe(*, backend: str, quantizer: str) -> dict[str, Any]:
    try:
        import torch
        from torch import nn
        from torch.ao.quantization.quantize_pt2e import convert_pt2e, prepare_pt2e
    except Exception as exc:
        return make_skip_report(
            backend=backend,
            quantizer=quantizer,
            reason="torch_pt2e_not_importable",
            detail=f"{type(exc).__name__}: {exc}",
        )

    try:
        quantizer_cls = import_object(quantizer)
    except Exception as exc:
        return make_skip_report(
            backend=backend,
            quantizer=quantizer,
            reason="quantizer_not_importable",
            detail=f"{type(exc).__name__}: {exc}",
        )

    class TinyLinear(nn.Module):
        def __init__(self) -> None:
            super().__init__()
            self.linear = nn.Linear(4, 3)

        def forward(self, x: torch.Tensor) -> torch.Tensor:
            return self.linear(x)

    torch.manual_seed(0)
    model = TinyLinear().eval()
    example_inputs = (torch.randn(2, 4),)

    try:
        quantizer_obj = quantizer_cls()
    except Exception as exc:
        return make_skip_report(
            backend=backend,
            quantizer=quantizer,
            reason="quantizer_constructor_failed",
            detail=f"{type(exc).__name__}: {exc}",
        )

    try:
        exported = torch.export.export(model, example_inputs).module()
        prepared = prepare_pt2e(exported, quantizer_obj)
        prepared(*example_inputs)
        converted = convert_pt2e(prepared)
    except Exception as exc:
        return make_skip_report(
            backend=backend,
            quantizer=quantizer,
            reason="pt2e_probe_failed",
            detail=f"{type(exc).__name__}: {exc}",
        )

    return audit_existing_graph(str(converted.graph), backend=backend, quantizer=quantizer)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--backend", required=True)
    parser.add_argument("--quantizer")
    parser.add_argument("--existing-graph", type=Path)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()

    quantizer = choose_quantizer(args.backend, args.quantizer)
    if quantizer is None:
        report = make_skip_report(
            backend=args.backend,
            quantizer="",
            reason="no_quantizer_candidates",
            detail=f"no quantizer candidates configured for backend {args.backend!r}",
        )
    elif args.existing_graph is not None:
        report = audit_existing_graph(
            args.existing_graph.read_text(encoding="utf-8"),
            backend=args.backend,
            quantizer=quantizer,
        )
    else:
        report = run_tiny_pt2e_probe(backend=args.backend, quantizer=quantizer)

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
