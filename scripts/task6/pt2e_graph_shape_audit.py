#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import sys
from typing import Any


OP_PATTERNS = {
    "aten.matmul": re.compile(r"(?:torch\.ops\.)?aten\.matmul(?:\.default)?"),
    "aten.mm": re.compile(r"(?:torch\.ops\.)?aten\.mm(?:\.default)?"),
    "aten.layer_norm": re.compile(r"(?:torch\.ops\.)?aten\.layer_norm(?:\.default)?"),
    "aten.tanh": re.compile(r"(?:torch\.ops\.)?aten\.tanh(?:\.default)?"),
    "aten.pow": re.compile(r"(?:torch\.ops\.)?aten\.pow(?:\.|\b)"),
    "aten.rsqrt": re.compile(r"(?:torch\.ops\.)?aten\.rsqrt(?:\.default)?"),
    "aten.softmax": re.compile(r"(?:torch\.ops\.)?aten\.softmax(?:\.|\b)"),
    "aten.to.dtype": re.compile(r"(?:torch\.ops\.)?aten\.to\.dtype"),
    "aten.clamp": re.compile(r"(?:torch\.ops\.)?aten\.clamp(?:\.|\b)"),
    "quantized_decomposed.quantize_per_tensor": re.compile(
        r"(?:torch\.ops\.)?quantized_decomposed\.quantize_per_tensor"
    ),
    "quantized_decomposed.dequantize_per_tensor": re.compile(
        r"(?:torch\.ops\.)?quantized_decomposed\.dequantize_per_tensor"
    ),
    "torch.aten.quantize_per_tensor": re.compile(r"torch\.aten\.quantize_per_tensor"),
    "torch.aten.dequantize": re.compile(r"torch\.aten\.dequantize"),
}


def count_ops(graph_text: str) -> dict[str, int]:
    return {name: len(pattern.findall(graph_text)) for name, pattern in OP_PATTERNS.items()}


def _has_dequant_before_matmul(lines: list[str]) -> bool:
    seen_dequant = False
    for line in lines:
        if "dequantize" in line:
            seen_dequant = True
        if "aten.matmul" in line and seen_dequant:
            return True
    return False


def audit_graph_text(graph_text: str, *, model_label: str) -> dict[str, Any]:
    lines = [line.strip() for line in graph_text.splitlines() if line.strip()]
    op_counts = count_ops(graph_text)
    critical_float_ops: list[dict[str, Any]] = []
    failure_reasons: list[str] = []

    if _has_dequant_before_matmul(lines):
        failure_reasons.append("float_matmul_after_dequant")
        critical_float_ops.append(
            {
                "family": "matmul",
                "reason": "aten.matmul appears after a dequantize marker",
                "count": op_counts["aten.matmul"],
            }
        )

    if op_counts["aten.layer_norm"]:
        failure_reasons.append("float_layer_norm")
        critical_float_ops.append(
            {
                "family": "layer_norm",
                "reason": "aten.layer_norm remains in the post-PT2E graph",
                "count": op_counts["aten.layer_norm"],
            }
        )

    if op_counts["aten.tanh"] or op_counts["aten.pow"]:
        failure_reasons.append("float_gelu_or_tanh")
        critical_float_ops.append(
            {
                "family": "gelu_or_tanh",
                "reason": "tanh/pow GELU-style math remains in the post-PT2E graph",
                "count": op_counts["aten.tanh"] + op_counts["aten.pow"],
            }
        )

    if op_counts["aten.rsqrt"]:
        failure_reasons.append("float_rsqrt")
        critical_float_ops.append(
            {
                "family": "rsqrt",
                "reason": "rsqrt remains in the post-PT2E graph",
                "count": op_counts["aten.rsqrt"],
            }
        )

    status = "fail" if failure_reasons else "pass"
    return {
        "schema_version": 1,
        "model_label": model_label,
        "status": status,
        "failure_reasons": failure_reasons,
        "op_counts": op_counts,
        "critical_float_ops": critical_float_ops,
        "line_count": len(lines),
        "recommendation": recommendation_for_status(status, failure_reasons),
    }


def recommendation_for_status(status: str, failure_reasons: list[str]) -> str:
    if status == "pass":
        return "Proceed to Torch-MLIR size gates; this audit found no critical float/QDQ blockers."
    reasons = ", ".join(failure_reasons)
    return (
        "Do not treat this graph as structurally integer/fixed-point before Torch-MLIR. "
        f"Fix or isolate: {reasons}."
    )


def write_markdown(report: dict[str, Any]) -> str:
    lines = [
        "# PT2E Graph Shape Audit",
        "",
        f"- model: `{report['model_label']}`",
        f"- status: `{report['status']}`",
        f"- line_count: `{report['line_count']}`",
        f"- recommendation: {report['recommendation']}",
        "",
        "## Failure Reasons",
        "",
    ]
    reasons = report["failure_reasons"]
    if reasons:
        lines.extend(f"- `{reason}`" for reason in reasons)
    else:
        lines.append("- none")
    lines.extend(["", "## Operation Counts", ""])
    for name, count in sorted(report["op_counts"].items()):
        lines.append(f"- `{name}`: `{count}`")
    lines.extend(["", "## Critical Float Ops", ""])
    critical = report["critical_float_ops"]
    if critical:
        for item in critical:
            lines.append(f"- `{item['family']}`: {item['reason']} (`count={item['count']}`)")
    else:
        lines.append("- none")
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--graph", required=True, type=Path)
    parser.add_argument("--json-out", required=True, type=Path)
    parser.add_argument("--markdown-out", type=Path)
    parser.add_argument("--model-label", required=True)
    parser.add_argument("--fail-on-nonstructural", action="store_true")
    args = parser.parse_args()

    graph_text = args.graph.read_text(encoding="utf-8")
    report = audit_graph_text(graph_text, model_label=args.model_label)
    args.json_out.parent.mkdir(parents=True, exist_ok=True)
    args.json_out.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    if args.markdown_out is not None:
        args.markdown_out.parent.mkdir(parents=True, exist_ok=True)
        args.markdown_out.write_text(write_markdown(report), encoding="utf-8")
    if args.fail_on_nonstructural and report["status"] != "pass":
        print(f"non-structural PT2E graph: {', '.join(report['failure_reasons'])}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
