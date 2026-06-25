from __future__ import annotations

"""Representative-core TinyStories adapter lowered through the LLM2FPGA backend."""

import json
import os
from pathlib import Path
import sys

import torch
from torch_mlir.fx import export_and_import

import model_adapter_representative_core_pt2e_static_quant as xnnpack_pt2e


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from src.llm2fpga_executorch_backend.backend_details import Llm2FpgaBackendDetails
from src.llm2fpga_executorch_backend.torch_mlir_surrogate import (
    build_torch_surrogate_module,
)


EXPORT_STRICT = False


def _write_manifest(manifest: dict[str, object]) -> None:
    path = os.environ.get("TINYSTORIES_EXECUTORCH_FPGA_BACKEND_MANIFEST")
    if path is None:
        return
    out_path = Path(path)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def build_mlir_module(model_path: str | None, output_type: str):
    exported = xnnpack_pt2e.export_program(model_path)
    manifest_bytes = Llm2FpgaBackendDetails(
        "tiny-stories-1m-representative-core-pt2e-static-w2a2-executorch-fpga-backend-nolsq"
    ).preprocess(exported)
    manifest = json.loads(manifest_bytes.decode("utf-8"))
    _write_manifest(manifest)

    surrogate = build_torch_surrogate_module(manifest)
    exported_surrogate = torch.export.export(
        surrogate,
        xnnpack_pt2e.example_inputs(),
        strict=EXPORT_STRICT,
    )
    return export_and_import(exported_surrogate, output_type=output_type)
