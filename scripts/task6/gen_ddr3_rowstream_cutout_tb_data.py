#!/usr/bin/env python3
"""Emit test data for the DDR-free rowstream RTL cutout proof."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import importlib.util
import json
from pathlib import Path
from typing import Any

import torch


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-path", required=True, type=Path)
    parser.add_argument("--model-artifact-label")
    parser.add_argument("--adapter-path", required=True, type=Path)
    parser.add_argument("--adapter-artifact-label")
    parser.add_argument("--contract-json", required=True, type=Path)
    parser.add_argument("--contract-artifact-label")
    parser.add_argument("--replay-json", required=True, type=Path)
    parser.add_argument("--replay-artifact-label")
    parser.add_argument("--rowstream-bin", required=True, type=Path)
    parser.add_argument("--rowstream-artifact-label")
    parser.add_argument("--out-dir", required=True, type=Path)
    parser.add_argument("--artifact-name", default="h2-ddr3-row-stream-cutout-tb-data")
    parser.add_argument("--date", default=dt.date.today().isoformat())
    parser.add_argument("--sample-count", type=int, default=8)
    return parser.parse_args()


def load_helper_module() -> Any:
    helper_path = Path(__file__).with_name(
        "check_full_vocab_rowwise_topk_contract.py"
    )
    spec = importlib.util.spec_from_file_location("task6_topk_helper", helper_path)
    if spec is None or spec.loader is None:
        raise SystemExit(f"unable to load helper from {helper_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def read_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def byte_to_signed(value: int) -> int:
    return value - 256 if value >= 128 else value


def signed_hex(value: int, bits: int) -> str:
    mask = (1 << bits) - 1
    return f"{value & mask:0{(bits + 3) // 4}x}"


def sv_string(value: str) -> str:
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def row_offset(token: int, contract: dict[str, Any]) -> int:
    image = contract["ddr3_linear_image"]
    row_bytes = contract["row_format"]["row_bytes"]
    rows_per_group = image["rows_per_group"]
    group = token // rows_per_group
    row_in_group = token % rows_per_group
    return group * image["group_bytes"] + row_in_group * row_bytes


def scan_rowstream_top1(
    image: bytes,
    contract: dict[str, Any],
    hidden_q: list[int],
) -> tuple[int, int, int]:
    vocab_size = contract["model"]["vocab_size"]
    hidden_size = contract["model"]["hidden_size"]
    row_bytes = contract["row_format"]["row_bytes"]
    best_token = 0xFFFF
    best_score = -(1 << 45)
    reserved_nonzero_count = 0

    for token in range(vocab_size):
        offset = row_offset(token, contract)
        row = image[offset : offset + row_bytes]
        acc = 0
        for index in range(hidden_size):
            acc += byte_to_signed(row[index]) * hidden_q[index]
        scale_q024 = int.from_bytes(row[hidden_size : hidden_size + 3], "little")
        if row[hidden_size + 3] != 0:
            reserved_nonzero_count += 1
        score = acc * scale_q024
        if score > best_score or (score == best_score and token < best_token):
            best_score = score
            best_token = token

    return best_token, best_score, reserved_nonzero_count


def write_rowstream_mem(
    *,
    image: bytes,
    contract: dict[str, Any],
    out_mem: Path,
) -> str:
    row_bytes = contract["row_format"]["row_bytes"]
    padded_rows = (
        contract["ddr3_linear_image"]["group_count"]
        * contract["ddr3_linear_image"]["rows_per_group"]
    )
    hex_digits = row_bytes * 2
    with out_mem.open("w", encoding="utf-8") as handle:
        for row_index in range(padded_rows):
            offset = row_offset(row_index, contract)
            row = image[offset : offset + row_bytes]
            value = int.from_bytes(row, "little")
            handle.write(f"{value:0{hex_digits}x}\n")
    return hashlib.sha256(out_mem.read_bytes()).hexdigest()


def emit_sv(
    *,
    contract: dict[str, Any],
    rowstream_mem_file: Path,
    hidden_vectors: list[list[int]],
    expected_tokens: list[int],
    expected_scores: list[int],
) -> str:
    hidden_size = contract["model"]["hidden_size"]
    vocab_size = contract["model"]["vocab_size"]
    row_bytes = contract["row_format"]["row_bytes"]
    padded_rows = (
        contract["ddr3_linear_image"]["group_count"]
        * contract["ddr3_linear_image"]["rows_per_group"]
    )
    lines = [
        f"localparam int HIDDEN_SIZE = {hidden_size};",
        f"localparam int VOCAB_SIZE = {vocab_size};",
        f"localparam int PADDED_ROWS = {padded_rows};",
        f"localparam int ROW_BYTES = {row_bytes};",
        f"localparam int SAMPLE_COUNT = {len(hidden_vectors)};",
        f"localparam string ROWSTREAM_MEM_FILE = {sv_string(str(rowstream_mem_file))};",
        "logic signed [7:0] hidden_q_values [0:SAMPLE_COUNT * HIDDEN_SIZE - 1];",
        "logic [15:0] expected_top_token [0:SAMPLE_COUNT - 1];",
        "logic signed [45:0] expected_top_score_q024 [0:SAMPLE_COUNT - 1];",
        "initial begin",
    ]
    for sample_index, hidden_q in enumerate(hidden_vectors):
        for hidden_index, value in enumerate(hidden_q):
            flat_index = sample_index * hidden_size + hidden_index
            lines.append(
                f"  hidden_q_values[{flat_index}] = 8'sh{signed_hex(value, 8)};"
            )
    for sample_index, token in enumerate(expected_tokens):
        lines.append(f"  expected_top_token[{sample_index}] = 16'd{token};")
    for sample_index, score in enumerate(expected_scores):
        lines.append(
            "  expected_top_score_q024"
            f"[{sample_index}] = 46'sh{signed_hex(score, 46)};"
        )
    lines.append("end")
    return "\n".join(lines) + "\n"


def main() -> None:
    args = parse_args()
    helper = load_helper_module()
    contract = read_json(args.contract_json)
    replay = read_json(args.replay_json)
    image = args.rowstream_bin.read_bytes()
    expected_image_bytes = contract["ddr3_linear_image"]["padded_stream_bytes"]
    if len(image) != expected_image_bytes:
        raise SystemExit(
            f"rowstream image has {len(image)} bytes, expected {expected_image_bytes}"
        )

    samples = helper.DEFAULT_SAMPLES[: args.sample_count]
    build_model = helper.load_adapter_build_model(args.adapter_path)
    model = build_model(str(args.model_path)).eval()
    replay_by_sample = {entry["sample_id"]: entry for entry in replay["samples"]}

    hidden_vectors: list[list[int]] = []
    expected_tokens: list[int] = []
    expected_scores: list[int] = []
    sample_payloads: list[dict[str, Any]] = []
    reserved_nonzero_count = 0
    replay_top1_mismatch_count = 0

    with torch.no_grad():
        for sample_id, token_ids in samples:
            input_ids = torch.tensor([token_ids], dtype=torch.long)
            transformer_out = model.transformer(input_ids=input_ids, use_cache=False)
            hidden = transformer_out.last_hidden_state[0, -1].detach().cpu().to(
                torch.float64
            )
            hidden_q_tensor, hidden_scale = helper.quantize_symmetric_tensor(hidden)
            hidden_q = [int(value) for value in hidden_q_tensor.cpu().tolist()]
            top_token, top_score, sample_reserved_count = scan_rowstream_top1(
                image,
                contract,
                hidden_q,
            )
            expected_replay_top1 = replay_by_sample[sample_id]["rowwise_q024_top5"][0]
            if top_token != expected_replay_top1:
                replay_top1_mismatch_count += 1
            reserved_nonzero_count += sample_reserved_count
            hidden_vectors.append(hidden_q)
            expected_tokens.append(top_token)
            expected_scores.append(top_score)
            sample_payloads.append(
                {
                    "sample_id": sample_id,
                    "token_ids": token_ids,
                    "hidden_scale": hidden_scale,
                    "rowstream_top1_token": top_token,
                    "rowstream_top1_score_q024": top_score,
                    "expected_replay_top1_token": expected_replay_top1,
                    "matches_expected_replay_top1": top_token == expected_replay_top1,
                }
            )

    args.out_dir.mkdir(parents=True, exist_ok=True)
    out_mem = args.out_dir / "rowstream_rows.mem"
    out_sv = args.out_dir / "tb_data.sv"
    out_json = args.out_dir / "summary.json"
    rowstream_sha256 = hashlib.sha256(image).hexdigest()
    rowstream_mem_sha256 = write_rowstream_mem(
        image=image,
        contract=contract,
        out_mem=out_mem,
    )
    out_sv.write_text(
        emit_sv(
            contract=contract,
            rowstream_mem_file=out_mem,
            hidden_vectors=hidden_vectors,
            expected_tokens=expected_tokens,
            expected_scores=expected_scores,
        ),
        encoding="utf-8",
    )

    status = (
        "PASS"
        if reserved_nonzero_count == 0 and replay_top1_mismatch_count == 0
        else "FAIL"
    )
    payload = {
        "artifact_name": args.artifact_name,
        "status": status,
        "date": args.date,
        "hypothesis": (
            "A DDR-free RTL cutout can replay the packed full-vocab rowstream "
            "through a synthetic source and match the rowwise Q0.24 top1 result."
        ),
        "source_artifacts": {
            "model_path": args.model_artifact_label or str(args.model_path),
            "adapter_path": args.adapter_artifact_label or str(args.adapter_path),
            "ddr3_row_stream_interface_contract": (
                args.contract_artifact_label or str(args.contract_json)
            ),
            "full_vocab_rowwise_topk_replay": (
                args.replay_artifact_label or str(args.replay_json)
            ),
            "rowstream_bin": args.rowstream_artifact_label or str(args.rowstream_bin),
            "baseline_bundle": (
                "artifacts/task6/baselines/"
                "tiny-stories-1m-baseline-float-selftest-all-memory-utilization"
            ),
        },
        "model": {
            "model_label": contract["model"]["model_label"],
            "vocab_size": contract["model"]["vocab_size"],
            "hidden_size": contract["model"]["hidden_size"],
            "sample_count": len(samples),
        },
        "rowstream_image": {
            "bytes": len(image),
            "sha256": rowstream_sha256,
            "rowstream_mem_sha256": rowstream_mem_sha256,
            "rowstream_mem_file": "rowstream_rows.mem",
            "row_bytes": contract["row_format"]["row_bytes"],
            "padded_rows": (
                contract["ddr3_linear_image"]["group_count"]
                * contract["ddr3_linear_image"]["rows_per_group"]
            ),
        },
        "validation": {
            "python_run": True,
            "simulation_run": False,
            "synthesis_run": False,
            "hardware_run": False,
            "validation_kind": "rowstream-cutout-test-vector-generation",
            "reserved_nonzero_count": reserved_nonzero_count,
            "replay_top1_mismatch_count": replay_top1_mismatch_count,
        },
        "samples": sample_payloads,
        "decision": {
            "verdict": "generate-rtl-cutout-sim"
            if status == "PASS"
            else "do-not-run-rtl-cutout-sim",
            "next_gate": (
                "Run the Verilator DDR-free rowstream cutout proof, then use "
                "that pass as the gate for DDR3 controller integration."
            ),
        },
    }
    out_json.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    if status != "PASS":
        raise SystemExit("DDR3 rowstream cutout TB data validation failed")


if __name__ == "__main__":
    main()
