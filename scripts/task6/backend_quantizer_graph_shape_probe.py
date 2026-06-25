#!/usr/bin/env python3
from __future__ import annotations

import argparse
import importlib
import json
from pathlib import Path
from typing import Any

from scripts.task6.executorch_backend_survey import BACKEND_CANDIDATES, backend_quantizer_entrypoints
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


def load_pt2e_quantize_api() -> tuple[object, object]:
    module_names = [
        "torch.ao.quantization.quantize_pt2e",
        "torchao.quantization.pt2e.quantize_pt2e",
    ]
    last_error: Exception | None = None
    for module_name in module_names:
        try:
            module = importlib.import_module(module_name)
            return module.prepare_pt2e, module.convert_pt2e
        except Exception as exc:
            last_error = exc
    if last_error is None:
        raise ModuleNotFoundError("no PT2E quantize API candidates configured")
    raise last_error


def configure_quantizer_if_supported(quantizer_obj: object, quantizer: str) -> object:
    module_name, _, _object_name = quantizer.rpartition(".")
    if not module_name:
        return quantizer_obj
    try:
        module = importlib.import_module(module_name)
        get_config = getattr(module, "get_symmetric_quantization_config")
        set_global = getattr(quantizer_obj, "set_global")
    except Exception:
        return quantizer_obj
    set_global(get_config())
    return quantizer_obj


def choose_quantizer(backend: str, explicit_quantizer: str | None) -> str | None:
    if explicit_quantizer is not None:
        return explicit_quantizer
    candidates = backend_quantizer_entrypoints(backend)
    return candidates[0] if candidates else None


def run_tiny_pt2e_probe(*, backend: str, quantizer: str) -> dict[str, Any]:
    try:
        import torch
        from torch import nn
        prepare_pt2e, convert_pt2e = load_pt2e_quantize_api()
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
        quantizer_obj = configure_quantizer_if_supported(quantizer_cls(), quantizer)
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


def run_probe_matrix(backends: list[str]) -> dict[str, Any]:
    probes = []
    status_counts: dict[str, int] = {}
    for backend in backends:
        for quantizer in backend_quantizer_entrypoints(backend):
            report = run_tiny_pt2e_probe(backend=backend, quantizer=quantizer)
            probes.append(report)
            status = str(report["status"])
            status_counts[status] = status_counts.get(status, 0) + 1
    return {
        "schema_version": 1,
        "status_counts": status_counts,
        "probes": probes,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--backend", action="append")
    parser.add_argument("--all-backends", action="store_true")
    parser.add_argument("--quantizer")
    parser.add_argument("--existing-graph", type=Path)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()

    if args.all_backends and (args.quantizer is not None or args.existing_graph is not None):
        parser.error("--all-backends cannot be combined with --quantizer or --existing-graph")

    if args.all_backends:
        report = run_probe_matrix(BACKEND_CANDIDATES)
    elif len(args.backend or []) != 1:
        parser.error("provide exactly one --backend unless --all-backends is set")
    else:
        backend = args.backend[0]
        quantizer = choose_quantizer(backend, args.quantizer)
        if quantizer is None:
            report = make_skip_report(
                backend=backend,
                quantizer="",
                reason="no_quantizer_candidates",
                detail=f"no quantizer candidates configured for backend {backend!r}",
            )
        elif args.existing_graph is not None:
            report = audit_existing_graph(
                args.existing_graph.read_text(encoding="utf-8"),
                backend=backend,
                quantizer=quantizer,
            )
        else:
            report = run_tiny_pt2e_probe(backend=backend, quantizer=quantizer)

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
