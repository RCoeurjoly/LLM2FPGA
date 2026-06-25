#!/usr/bin/env python3
from __future__ import annotations

import argparse
import importlib
import json
from pathlib import Path
from typing import Any


BACKEND_CANDIDATES = [
    "xnnpack",
    "example",
    "test",
    "vulkan",
    "cadence",
    "arm",
    "cortex_m",
    "openvino",
    "aoti",
    "cuda",
    "webgpu",
    "mlx",
    "apple",
    "mediatek",
    "nxp",
    "qualcomm",
    "samsung",
]

SDK_GATED_BACKENDS = {"apple", "mediatek", "nxp", "qualcomm", "samsung"}
HARDWARE_GATED_BACKENDS = {"apple", "mediatek", "nxp", "qualcomm", "samsung"}

REQUIRED_REPORT_KEYS = {
    "backend",
    "status",
    "skip_reason",
    "requires_sdk",
    "requires_hardware",
    "python_entrypoints",
    "partitioned_ops",
    "unpartitioned_ops",
    "delegate_blob_count",
    "delegate_blob_bytes",
    "graph_transparency",
    "torch_mlir_status",
    "linalg_status",
    "cf_status",
    "hw_status",
    "torch_mlir_bytes",
    "hw_mlir_bytes",
    "hw_mlir_lines",
    "failure_signature",
}


def classify_backend(backend: str) -> dict[str, Any]:
    return {
        "backend": backend,
        "requires_sdk": backend in SDK_GATED_BACKENDS,
        "requires_hardware": backend in HARDWARE_GATED_BACKENDS,
        "python_entrypoints": backend_entrypoints(backend),
    }


def backend_entrypoints(backend: str) -> list[str]:
    mapping = {
        "xnnpack": [
            "executorch.backends.xnnpack.partition.xnnpack_partitioner",
            "executorch.backends.xnnpack.xnnpack_preprocess",
        ],
        "example": ["executorch.backends.example"],
        "test": ["executorch.backends.test"],
        "vulkan": ["executorch.backends.vulkan"],
        "cadence": ["executorch.backends.cadence"],
        "arm": ["executorch.backends.arm"],
        "cortex_m": ["executorch.backends.cortex_m"],
        "openvino": ["executorch.backends.openvino"],
        "aoti": ["executorch.backends.aoti"],
        "cuda": ["executorch.backends.cuda"],
        "webgpu": ["executorch.backends.webgpu"],
        "mlx": ["executorch.backends.mlx"],
        "apple": ["executorch.backends.apple"],
        "mediatek": ["executorch.backends.mediatek"],
        "nxp": ["executorch.backends.nxp"],
        "qualcomm": ["executorch.backends.qualcomm"],
        "samsung": ["executorch.backends.samsung"],
    }
    return mapping.get(backend, [f"executorch.backends.{backend}"])


def module_available(module_name: str) -> bool:
    try:
        importlib.import_module(module_name)
    except Exception:
        return False
    return True


def attempt_backend_imports(module_names: list[str]) -> dict[str, Any]:
    available_modules = [name for name in module_names if module_available(name)]
    return {
        "available": bool(available_modules),
        "available_modules": available_modules,
    }


def make_report_entry(backend: str, *, status: str, skip_reason: str | None = None) -> dict[str, Any]:
    info = classify_backend(backend)
    entry = {
        "backend": backend,
        "status": status,
        "skip_reason": skip_reason,
        "requires_sdk": info["requires_sdk"],
        "requires_hardware": info["requires_hardware"],
        "python_entrypoints": info["python_entrypoints"],
        "partitioned_ops": [],
        "unpartitioned_ops": [],
        "delegate_blob_count": None,
        "delegate_blob_bytes": None,
        "graph_transparency": "unknown",
        "torch_mlir_status": "skip",
        "linalg_status": "skip",
        "cf_status": "skip",
        "hw_status": "skip",
        "torch_mlir_bytes": None,
        "hw_mlir_bytes": None,
        "hw_mlir_lines": None,
        "failure_signature": skip_reason,
    }
    validate_report_entry(entry)
    return entry


def classify_graph_transparency(graph_text: str) -> str:
    lowered = graph_text.lower()
    if "executorch_call_delegate" in lowered or "delegate" in lowered and "blob" in lowered:
        return "opaque"
    if "torch.ops.aten" in graph_text or "call_function" in graph_text:
        return "transparent"
    if "delegate" in lowered:
        return "mixed"
    return "unknown"


def validate_report_entry(entry: dict[str, Any]) -> None:
    missing = REQUIRED_REPORT_KEYS - set(entry)
    if missing:
        raise ValueError(f"report entry missing keys: {sorted(missing)}")
    if entry["status"] not in {"pass", "skip", "fail"}:
        raise ValueError(f"invalid status: {entry['status']!r}")
    if entry["graph_transparency"] not in {"transparent", "mixed", "opaque", "unknown"}:
        raise ValueError(f"invalid graph_transparency: {entry['graph_transparency']!r}")


def probe_xnnpack_lowering() -> dict[str, Any]:
    if not module_available("executorch.backends.xnnpack.partition.xnnpack_partitioner"):
        return make_report_entry("xnnpack", status="skip", skip_reason="executorch_xnnpack_not_importable")
    entry = make_report_entry(
        "xnnpack",
        status="skip",
        skip_reason="xnnpack_probe_requires_executorch_runtime_wiring",
    )
    entry["graph_transparency"] = "unknown"
    validate_report_entry(entry)
    return entry


def probe_backend_by_import_only(backend: str) -> dict[str, Any]:
    info = classify_backend(backend)
    imports = attempt_backend_imports(info["python_entrypoints"])
    if not imports["available"]:
        return make_report_entry(backend, status="skip", skip_reason="executorch_backend_not_importable")

    entry = make_report_entry(backend, status="skip", skip_reason="backend_lowering_probe_not_connected")
    entry["python_entrypoints"] = imports["available_modules"]
    validate_report_entry(entry)
    return entry


def inventory_backends(backends: list[str]) -> list[dict[str, Any]]:
    entries = []
    for backend in backends:
        if backend == "xnnpack":
            entries.append(probe_xnnpack_lowering())
            continue
        entries.append(probe_backend_by_import_only(backend))
    return entries


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--backend", action="append", choices=BACKEND_CANDIDATES)
    args = parser.parse_args()

    backends = args.backend or BACKEND_CANDIDATES
    payload = {"backends": inventory_backends(backends)}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
