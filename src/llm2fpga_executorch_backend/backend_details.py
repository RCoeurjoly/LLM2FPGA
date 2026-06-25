from __future__ import annotations

import json
from typing import Any

from .manifest import build_manifest
from .partitioner import Llm2FpgaPartitioner


class Llm2FpgaBackendDetails:
    """ExecuTorch BackendDetails-shaped serializer for FPGA manifests."""

    backend_id = "llm2fpga.executorch"

    def __init__(self, model_label: str = "unknown") -> None:
        self.model_label = model_label
        self.partitioner = Llm2FpgaPartitioner()

    def preprocess(self, exported_program: Any) -> bytes:
        ops, unmatched = self.partitioner.partition(exported_program)
        manifest = build_manifest(
            model_label=self.model_label,
            ops=ops,
            unmatched_core_ops=unmatched,
        )
        return json.dumps(manifest, sort_keys=True).encode("utf-8")
