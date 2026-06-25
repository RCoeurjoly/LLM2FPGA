from __future__ import annotations

import json
from pathlib import Path
from typing import Any


BACKEND_ID = "llm2fpga.executorch"
SCHEMA_VERSION = 1
SUPPORTED_FAMILIES = {
    "fpga.quantized_matmul",
    "fpga.layer_norm",
    "fpga.softmax_or_attention",
    "fpga.gelu",
}
REQUIRED_FIELDS = (
    "schema_version",
    "backend_id",
    "model_label",
    "representative_core_dimensions",
    "ops",
    "quant_params",
    "tensor_metadata",
    "tiling_hints",
    "kernel_ids",
    "unmatched_core_ops",
)
DEFAULT_KERNEL_IDS = {
    "fpga.quantized_matmul": "qmatmul.v1",
    "fpga.layer_norm": "layer_norm.v1",
    "fpga.softmax_or_attention": "attention.v1",
    "fpga.gelu": "gelu.v1",
}
DEFAULT_REPRESENTATIVE_CORE_DIMS = {
    "vocab_size": 32,
    "num_layers": 2,
    "hidden_size": 2,
    "num_heads": 1,
    "max_position_embeddings": 4,
    "window_size": 2,
}


class ManifestError(ValueError):
    """Raised when an FPGA backend manifest is structurally invalid."""


def validate_manifest(manifest: dict[str, Any]) -> None:
    for field in REQUIRED_FIELDS:
        if field not in manifest:
            raise ManifestError(f"manifest missing required field: {field}")
    if manifest["schema_version"] != SCHEMA_VERSION:
        raise ManifestError(f"unsupported schema_version: {manifest['schema_version']!r}")
    if manifest["backend_id"] != BACKEND_ID:
        raise ManifestError(f"unsupported backend_id: {manifest['backend_id']!r}")
    if not isinstance(manifest["ops"], list):
        raise ManifestError("manifest field ops must be a list")
    for op in manifest["ops"]:
        family = op.get("family") if isinstance(op, dict) else None
        if family not in SUPPORTED_FAMILIES:
            raise ManifestError(f"unsupported FPGA op family: {family}")
    if not isinstance(manifest["unmatched_core_ops"], list):
        raise ManifestError("manifest field unmatched_core_ops must be a list")


def build_manifest(
    *,
    model_label: str,
    ops: list[dict[str, Any]],
    unmatched_core_ops: list[dict[str, Any]],
    representative_core_dimensions: dict[str, Any] | None = None,
    quant_params: dict[str, Any] | None = None,
    tensor_metadata: list[dict[str, Any]] | None = None,
    tiling_hints: dict[str, Any] | None = None,
) -> dict[str, Any]:
    manifest = {
        "schema_version": SCHEMA_VERSION,
        "backend_id": BACKEND_ID,
        "model_label": model_label,
        "representative_core_dimensions": representative_core_dimensions
        or dict(DEFAULT_REPRESENTATIVE_CORE_DIMS),
        "ops": ops,
        "quant_params": quant_params or {"activation_bits": 2, "weight_bits": 2},
        "tensor_metadata": tensor_metadata or [],
        "tiling_hints": tiling_hints or {"target": "representative-core-min"},
        "kernel_ids": dict(DEFAULT_KERNEL_IDS),
        "unmatched_core_ops": unmatched_core_ops,
    }
    validate_manifest(manifest)
    return manifest


def write_manifest(path: Path, manifest: dict[str, Any]) -> None:
    validate_manifest(manifest)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
