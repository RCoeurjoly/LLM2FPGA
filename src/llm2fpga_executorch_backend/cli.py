#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

if __package__ is None or __package__ == "":
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from src.llm2fpga_executorch_backend.manifest import build_manifest, write_manifest
from src.llm2fpga_executorch_backend.patterns import capture_backend_ops


REQUIRED_REPRESENTATIVE_CORE_FAMILIES = {
    "fpga.quantized_matmul",
    "fpga.layer_norm",
    "fpga.softmax_or_attention",
    "fpga.gelu",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Emit an LLM2FPGA ExecuTorch-style backend manifest from a PT2E graph dump."
    )
    parser.add_argument("--graph", required=True, type=Path)
    parser.add_argument("--out-dir", required=True, type=Path)
    parser.add_argument("--model-label", required=True)
    parser.add_argument("--require-representative-core", action="store_true")
    return parser.parse_args()


def write_json(path: Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def main() -> None:
    args = parse_args()
    graph_text = args.graph.read_text(encoding="utf-8")
    if args.graph.stat().st_size == 0:
        raise SystemExit(f"quantized graph file is empty: {args.graph}")
    ops, unmatched = capture_backend_ops(graph_text)
    manifest = build_manifest(
        model_label=args.model_label,
        ops=ops,
        unmatched_core_ops=unmatched,
    )

    args.out_dir.mkdir(parents=True, exist_ok=True)
    write_manifest(args.out_dir / "manifest.json", manifest)
    write_json(args.out_dir / "backend_ops.json", {"ops": ops})
    write_json(args.out_dir / "unmatched_core_ops.json", {"unmatched_core_ops": unmatched})

    if args.require_representative_core:
        families = {op["family"] for op in ops}
        missing = sorted(REQUIRED_REPRESENTATIVE_CORE_FAMILIES - families)
        if missing or unmatched:
            write_json(
                args.out_dir / "failure.json",
                {
                    "status": "FAIL",
                    "missing_families": missing,
                    "unmatched_core_ops": unmatched,
                },
            )
            raise SystemExit(1)

    write_json(args.out_dir / "summary.json", {"status": "PASS", "op_count": len(ops)})


if __name__ == "__main__":
    main()
