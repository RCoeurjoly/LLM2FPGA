#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


COUNT_PATTERNS = {
    "aten.linear": "aten.linear",
    "aten.matmul": "aten.matmul",
    "aten.mm": "aten.mm",
    "quantized_decomposed.quantize_per_tensor": "quantize_per_tensor",
    "quantized_decomposed.dequantize_per_tensor": "dequantize_per_tensor",
    "aten.to.dtype": "aten.to.dtype",
    "aten.clamp": "aten.clamp",
}


def audit_graph_text(graph_text: str) -> dict[str, Any]:
    op_counts = {
        name: graph_text.count(pattern)
        for name, pattern in COUNT_PATTERNS.items()
    }
    qdq_count = (
        op_counts["quantized_decomposed.quantize_per_tensor"]
        + op_counts["quantized_decomposed.dequantize_per_tensor"]
    )
    failure_reasons: list[str] = []

    if op_counts["aten.linear"] and op_counts["quantized_decomposed.dequantize_per_tensor"]:
        failure_reasons.append("float_linear_after_dequant")
    elif op_counts["aten.linear"] and qdq_count == 0:
        failure_reasons.append("float_linear_unquantized")

    if op_counts["aten.matmul"] and op_counts["quantized_decomposed.dequantize_per_tensor"]:
        failure_reasons.append("float_matmul_after_dequant")
    elif op_counts["aten.matmul"] and qdq_count == 0:
        failure_reasons.append("float_matmul_unquantized")

    if op_counts["aten.mm"] and op_counts["quantized_decomposed.dequantize_per_tensor"]:
        failure_reasons.append("float_mm_after_dequant")
    elif op_counts["aten.mm"] and qdq_count == 0:
        failure_reasons.append("float_mm_unquantized")

    return {
        "schema_version": 1,
        "status": "fail" if failure_reasons else "pass",
        "failure_reasons": failure_reasons,
        "op_counts": op_counts,
        "line_count": len(graph_text.splitlines()),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Audit a dumped PT2E graph for float linear/matmul compute.")
    parser.add_argument("graph", type=Path)
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()

    report = audit_graph_text(args.graph.read_text(encoding="utf-8"))
    payload = json.dumps(report, indent=2, sort_keys=True)
    if args.out:
        args.out.write_text(payload + "\n", encoding="utf-8")
    else:
        print(payload)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
