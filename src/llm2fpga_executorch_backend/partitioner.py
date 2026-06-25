from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from .manifest import SUPPORTED_FAMILIES
from .patterns import capture_backend_ops


@dataclass(frozen=True)
class DelegatedSubgraph:
    family: str
    source_ops: tuple[str, ...]
    kernel_id: str


class Llm2FpgaPartitioner:
    """Small ExecuTorch-style partitioner facade for Task 6 backend capture."""

    backend_id = "llm2fpga.executorch"

    def partition_text(self, graph_text: str) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
        return capture_backend_ops(graph_text)

    def partition(self, exported_program: Any) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
        graph_text = str(getattr(exported_program, "graph", exported_program))
        return self.partition_text(graph_text)

    def supported_families(self) -> set[str]:
        return set(SUPPORTED_FAMILIES)
