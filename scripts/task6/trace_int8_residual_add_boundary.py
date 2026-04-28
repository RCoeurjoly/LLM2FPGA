#!/usr/bin/env python3
"""Trace the residual-add boundary after the H2 int8 c_proj proof."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any


ADD_LINE_RE = re.compile(
    r"(?P<result>%\d+)\s*=\s*linalg\.generic\b.*\bins\("
    r"(?P<lhs>%\d+),\s*(?P<rhs>%\d+)\s*:"
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--c-fc-contract-manifest", required=True, type=Path)
    parser.add_argument("--c-proj-contract-manifest", required=True, type=Path)
    parser.add_argument("--c-proj-candidate-json", required=True, type=Path)
    parser.add_argument("--c-proj-requant-rtl-proof-json", required=True, type=Path)
    parser.add_argument("--out-json", required=True, type=Path)
    return parser.parse_args()


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def tensor_by_name(manifest: dict[str, Any], name: str) -> dict[str, Any]:
    for tensor in manifest["tensors"]:
        if tensor["name"] == name:
            return tensor
    raise SystemExit(f"{manifest.get('module_name', '<unknown>')} has no {name} tensor")


def find_next_add_site(candidate: dict[str, Any]) -> dict[str, Any]:
    selected = candidate["selected_candidate"]
    selected_line = int(selected["line_number"])
    selected_value = selected["result_value"]
    context = selected.get("context", [])
    for row in context:
        line_number = int(row.get("line_number", -1))
        text = str(row.get("text", ""))
        if line_number <= selected_line:
            continue
        match = ADD_LINE_RE.search(text)
        if match is None:
            continue
        operands = [match.group("lhs"), match.group("rhs")]
        if selected_value in operands or "%95" in operands:
            c_proj_operand = selected_value if selected_value in operands else "%95"
            residual_operand = operands[1] if operands[0] == c_proj_operand else operands[0]
            return {
                "line_number": line_number,
                "text": text,
                "result_value": match.group("result"),
                "operands": operands,
                "residual_operand_value": residual_operand,
                "c_proj_operand_value": c_proj_operand,
            }
    raise SystemExit("could not find residual add site in c_proj candidate context")


def main() -> None:
    args = parse_args()
    c_fc_contract = load_json(args.c_fc_contract_manifest)
    c_proj_contract = load_json(args.c_proj_contract_manifest)
    candidate = load_json(args.c_proj_candidate_json)
    proof = load_json(args.c_proj_requant_rtl_proof_json)

    c_fc_activation = tensor_by_name(c_fc_contract, "activation_in")
    c_proj_output = tensor_by_name(c_proj_contract, "activation_out")
    add_site = find_next_add_site(candidate)
    quantization = proof.get("quantization", {})
    metrics = proof.get("metrics", {})

    upstream_pass = proof.get("status") == "PASS"
    q_matches = bool(quantization.get("c_proj_output_matches_boundary_quantizer"))
    acc_matches = bool(quantization.get("c_proj_accumulator_matches_boundary"))
    ready_for_capture = upstream_pass and q_matches and acc_matches

    payload = {
        "artifact_name": "h2-int8-l2-residual-add-boundary-scout",
        "status": "NEEDS_CAPTURE" if ready_for_capture else "BLOCKED_UPSTREAM",
        "source_artifacts": {
            "c_fc_contract_manifest": str(args.c_fc_contract_manifest),
            "c_proj_contract_manifest": str(args.c_proj_contract_manifest),
            "c_proj_candidate_json": str(args.c_proj_candidate_json),
            "c_proj_requant_rtl_proof_json": str(args.c_proj_requant_rtl_proof_json),
        },
        "upstream_c_proj_requant": {
            "status": proof.get("status"),
            "output_scale": quantization.get("c_proj_output_scale"),
            "output_q_min": quantization.get("c_proj_output_q_min"),
            "output_q_max": quantization.get("c_proj_output_q_max"),
            "output_q_sha256": quantization.get("c_proj_output_q_sha256"),
            "output_matches_boundary_quantizer": q_matches,
            "accumulator_matches_boundary": acc_matches,
            "normalized_rmse": metrics.get(
                "c_proj_int8_output_from_fixed_requant", {}
            ).get("normalized_rmse"),
            "mapped_utilization": proof.get("mapped_utilization", {}),
        },
        "linalg_boundary": {
            "linalg_artifact": candidate.get("artifact"),
            "c_proj_matmul_line": candidate["selected_candidate"]["line_number"],
            "c_proj_matmul_value": candidate["selected_candidate"]["result_value"],
            "post_c_proj_add_site": add_site,
            "interpretation": (
                "The next same-shape add consumes the c_proj bias-add result and "
                "a separate residual tensor. The current c_proj contract captures "
                "only the MLP projection boundary, so the residual operand still "
                "needs a separate activation capture before numeric residual-add "
                "claims are made."
            ),
        },
        "pytorch_capture_plan": {
            "model_family": "GPT-Neo via TinyStories representative-core adapter",
            "sample_input_ids": c_fc_contract.get("sample_input_ids"),
            "residual_operand_hook": {
                "module": "transformer.h.0.ln_2",
                "tensor": "activation_in",
                "reason": (
                    "GPT-Neo block code applies ln_2 to the post-attention hidden "
                    "state, then adds that same pre-ln_2 residual to the MLP output."
                ),
            },
            "normalization_cross_check": {
                "module": "transformer.h.0.ln_2",
                "tensor": "activation_out",
                "expected_match": {
                    "module": c_fc_contract.get("module_name"),
                    "tensor": "activation_in",
                    "shape": c_fc_activation.get("shape"),
                },
            },
            "c_proj_cross_check": {
                "module": c_proj_contract.get("module_name"),
                "tensor": "activation_out",
                "shape": c_proj_output.get("shape"),
            },
            "residual_add_cross_check": {
                "module": "transformer.h.0",
                "tensor": "first output tensor",
                "formula": "block_out = ln_2.activation_in + mlp.c_proj.activation_out",
            },
        },
        "next_numeric_scores": [
            {
                "name": "f32_residual_plus_int8_c_proj_dequant",
                "formula": "residual_f32 + c_proj_output_q * c_proj_output_scale",
                "purpose": "test the promoted int8 c_proj output as a dequantized residual-add input",
            },
            {
                "name": "int8_residual_plus_int8_c_proj_dequant",
                "formula": "residual_q * residual_scale + c_proj_output_q * c_proj_output_scale",
                "purpose": "test whether the residual operand can also cross the add as int8",
            },
            {
                "name": "int8_final_residual_add_output",
                "formula": "quantize(residual_dequant + c_proj_dequant)",
                "purpose": "test whether the residual-add output can remain quantized for the next block boundary",
            },
        ],
        "decision": {
            "verdict": "capture-residual-add-contract" if ready_for_capture else "fix-upstream-first",
            "next_gate": (
                "capture transformer.h.0.ln_2 input plus block output, then score "
                "the residual add against the c_proj int8 output q/scale"
                if ready_for_capture
                else "restore c_proj requant proof consistency before residual scoring"
            ),
        },
    }

    args.out_json.parent.mkdir(parents=True, exist_ok=True)
    args.out_json.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
