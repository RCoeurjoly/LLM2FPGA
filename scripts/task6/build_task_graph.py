#!/usr/bin/env python3
from __future__ import annotations

"""Build a minimal task-graph artifact around the selected L1 GEMV site."""

import argparse
import json
from pathlib import Path
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--candidate-json", required=True, type=Path)
    parser.add_argument("--weight-pack-manifest", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    return parser.parse_args()


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def main() -> None:
    args = parse_args()
    candidate_doc = load_json(args.candidate_json)
    weight_pack = load_json(args.weight_pack_manifest)

    selected = candidate_doc["selected_candidate"]
    lhs_shape = selected["shape_contract"]["lhs"]
    rhs_shape = selected["shape_contract"]["rhs"]
    out_shape = selected["shape_contract"]["out"]

    tensors = {tensor["name"]: tensor for tensor in weight_pack["tensors"]}
    weight_shape = tensors["weight"]["shape"]
    bias_shape = tensors["bias"]["shape"]

    expected_weight_shape = [16, 4]
    expected_bias_shape = [16]
    if weight_shape != expected_weight_shape:
        raise SystemExit(
            f"weight pack shape mismatch: expected {expected_weight_shape}, got {weight_shape}"
        )
    if bias_shape != expected_bias_shape:
        raise SystemExit(
            f"bias pack shape mismatch: expected {expected_bias_shape}, got {bias_shape}"
        )

    graph = {
        "graph_name": "task6-l1-c-fc-minimal-task-graph",
        "graph_kind": "streamtensor-lite-minimal-proof",
        "representation_level": selected["representation_level"],
        "source_artifacts": {
            "candidate_json": str(args.candidate_json),
            "weight_pack_manifest": str(args.weight_pack_manifest),
            "linalg_artifact": candidate_doc["artifact"],
        },
        "selected_site": {
            "module_name": weight_pack["module_name"],
            "line_number": selected["line_number"],
            "result_value": selected["result_value"],
            "lhs_value": selected["lhs_value"],
            "rhs_value": selected["rhs_value"],
            "out_value": selected["out_value"],
        },
        "interfaces": {
            "inputs": [
                {
                    "name": "activation_in",
                    "dtype": "float32",
                    "shape": lhs_shape,
                    "role": "single-token activation vector",
                }
            ],
            "outputs": [
                {
                    "name": "activation_out",
                    "dtype": "float32",
                    "shape": out_shape,
                    "role": "post-bias GEMV output",
                }
            ],
        },
        "buffers": [
            {
                "name": "weight_pack",
                "kind": "external-pack",
                "tensor": tensors["weight"],
            },
            {
                "name": "bias_pack",
                "kind": "external-pack",
                "tensor": tensors["bias"],
            },
        ],
        "nodes": [
            {
                "name": "activation_source",
                "kind": "input",
                "outputs": ["activation_in"],
            },
            {
                "name": "weight_fetch",
                "kind": "weight-pack-read",
                "source": "weight_pack",
                "outputs": ["fc_weight"],
                "shape": rhs_shape,
            },
            {
                "name": "bias_fetch",
                "kind": "weight-pack-read",
                "source": "bias_pack",
                "outputs": ["fc_bias"],
                "shape": "tensor<16xf32>",
            },
            {
                "name": "c_fc_gemv",
                "kind": "gemv",
                "inputs": ["activation_in", "fc_weight"],
                "outputs": ["gemv_out"],
                "lhs_shape": lhs_shape,
                "rhs_shape": rhs_shape,
                "out_shape": out_shape,
            },
            {
                "name": "c_fc_bias_add",
                "kind": "bias-add",
                "inputs": ["gemv_out", "fc_bias"],
                "outputs": ["activation_out"],
                "shape": out_shape,
            },
        ],
        "edges": [
            {"from": "activation_source", "to": "c_fc_gemv", "tensor": "activation_in"},
            {"from": "weight_fetch", "to": "c_fc_gemv", "tensor": "fc_weight"},
            {"from": "c_fc_gemv", "to": "c_fc_bias_add", "tensor": "gemv_out"},
            {"from": "bias_fetch", "to": "c_fc_bias_add", "tensor": "fc_bias"},
        ],
    }

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(graph, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
