#!/usr/bin/env python3
"""Pack and replay the Task 6 DDR3 rowstream output-head image."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
from typing import Any

import torch


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-path", required=True, type=Path)
    parser.add_argument("--model-artifact-label")
    parser.add_argument("--adapter-path", required=True, type=Path)
    parser.add_argument("--adapter-artifact-label")
    parser.add_argument("--contract-json", required=True, type=Path)
    parser.add_argument("--replay-json", required=True, type=Path)
    parser.add_argument("--out-dir", required=True, type=Path)
    parser.add_argument("--artifact-name", default="h2-ddr3-row-stream-pack-replay")
    parser.add_argument("--date", default=dt.date.today().isoformat())
    parser.add_argument("--sample-count", type=int, default=8)
    parser.add_argument("--top-k", type=int, default=5)
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


def signed_byte(value: int) -> int:
    if value < 0:
        value += 256
    return value


def byte_to_signed(value: int) -> int:
    return value - 256 if value >= 128 else value


def pack_rowstream(
    rowwise_q: torch.Tensor,
    q024_scales: torch.Tensor,
    contract: dict[str, Any],
) -> bytes:
    image_contract = contract["ddr3_linear_image"]
    row_format = contract["row_format"]
    vocab_size = contract["model"]["vocab_size"]
    hidden_size = contract["model"]["hidden_size"]
    rows_per_group = image_contract["rows_per_group"]
    row_bytes = row_format["row_bytes"]
    padded_stream_bytes = image_contract["padded_stream_bytes"]
    image = bytearray(padded_stream_bytes)

    for token in range(vocab_size):
        group = token // rows_per_group
        row_in_group = token % rows_per_group
        offset = group * image_contract["group_bytes"] + row_in_group * row_bytes
        row_values = rowwise_q[token].detach().cpu().tolist()
        image[offset : offset + hidden_size] = bytes(
            signed_byte(int(value)) for value in row_values
        )
        scale_q024 = int(q024_scales[token].item())
        if scale_q024 < 0 or scale_q024 > 0x00FF_FFFF:
            raise SystemExit(f"token {token} Q0.24 scale out of range")
        image[offset + hidden_size : offset + hidden_size + 3] = (
            scale_q024.to_bytes(3, "little")
        )
        image[offset + hidden_size + 3] = 0

    return bytes(image)


def unpack_rowstream(
    image: bytes,
    contract: dict[str, Any],
) -> tuple[torch.Tensor, torch.Tensor, dict[str, int]]:
    image_contract = contract["ddr3_linear_image"]
    row_format = contract["row_format"]
    vocab_size = contract["model"]["vocab_size"]
    hidden_size = contract["model"]["hidden_size"]
    rows_per_group = image_contract["rows_per_group"]
    row_bytes = row_format["row_bytes"]
    padded_rows = image_contract["group_count"] * rows_per_group
    q = torch.empty((vocab_size, hidden_size), dtype=torch.int16)
    scales = torch.empty(vocab_size, dtype=torch.int64)
    reserved_nonzero_count = 0

    for token in range(vocab_size):
        group = token // rows_per_group
        row_in_group = token % rows_per_group
        offset = group * image_contract["group_bytes"] + row_in_group * row_bytes
        q[token] = torch.tensor(
            [
                byte_to_signed(byte)
                for byte in image[offset : offset + hidden_size]
            ],
            dtype=torch.int16,
        )
        scales[token] = int.from_bytes(
            image[offset + hidden_size : offset + hidden_size + 3],
            "little",
        )
        if image[offset + hidden_size + 3] != 0:
            reserved_nonzero_count += 1

    tail_padding_nonzero_bytes = 0
    for token in range(vocab_size, padded_rows):
        group = token // rows_per_group
        row_in_group = token % rows_per_group
        offset = group * image_contract["group_bytes"] + row_in_group * row_bytes
        tail_padding_nonzero_bytes += sum(
            1 for byte in image[offset : offset + row_bytes] if byte != 0
        )

    return q, scales, {
        "reserved_nonzero_count": reserved_nonzero_count,
        "tail_padding_nonzero_bytes": tail_padding_nonzero_bytes,
    }


def replay_unpacked_stream(
    *,
    helper: Any,
    model: torch.nn.Module,
    weight: torch.Tensor,
    unpacked_q: torch.Tensor,
    unpacked_scales: torch.Tensor,
    replay: dict[str, Any],
    sample_count: int,
    top_k: int,
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    samples = helper.DEFAULT_SAMPLES[:sample_count]
    replay_by_sample = {entry["sample_id"]: entry for entry in replay["samples"]}
    sample_results: list[dict[str, Any]] = []
    top1_match_count = 0
    replay_topk_mismatch_count = 0
    top5_overlaps: list[int] = []
    rowwise_errors: list[dict[str, float]] = []

    with torch.no_grad():
        for sample_id, token_ids in samples:
            input_ids = torch.tensor([token_ids], dtype=torch.long)
            transformer_out = model.transformer(input_ids=input_ids, use_cache=False)
            hidden = transformer_out.last_hidden_state[0, -1].detach().cpu().to(
                torch.float64
            )
            f32_logits = weight.matmul(hidden)
            hidden_q, hidden_scale = helper.quantize_symmetric_tensor(hidden)
            hidden_i64 = hidden_q.to(torch.int64)
            rowwise_acc = torch.sum(unpacked_q.to(torch.int64) * hidden_i64, dim=1)
            rowwise_score_q024 = rowwise_acc * unpacked_scales
            rowwise_logits = (
                rowwise_score_q024.to(torch.float64)
                * float(hidden_scale)
                / helper.Q024_SCALE
            )
            f32_top5 = helper.deterministic_topk(f32_logits, top_k)
            unpacked_top5 = helper.deterministic_topk_int(rowwise_score_q024, top_k)
            expected_top5 = replay_by_sample[sample_id]["rowwise_q024_top5"]
            top5_overlap = len(set(f32_top5) & set(unpacked_top5))
            top5_overlaps.append(top5_overlap)
            if unpacked_top5[0] == f32_top5[0]:
                top1_match_count += 1
            if unpacked_top5 != expected_top5:
                replay_topk_mismatch_count += 1
            rowwise_error = helper.score_error(rowwise_logits, f32_logits)
            rowwise_errors.append(rowwise_error)
            sample_results.append(
                {
                    "sample_id": sample_id,
                    "token_ids": token_ids,
                    "f32_top5": f32_top5,
                    "unpacked_rowstream_top5": unpacked_top5,
                    "expected_replay_rowwise_q024_top5": expected_top5,
                    "matches_expected_replay_top5": unpacked_top5 == expected_top5,
                    "top5_overlap_vs_f32": top5_overlap,
                    "rowwise_error": rowwise_error,
                }
            )

    sample_total = len(samples)
    summary = helper.summarize_errors(rowwise_errors)
    summary.update(
        {
            "sample_count": sample_total,
            "top1_match_count_vs_f32": top1_match_count,
            "top1_match_rate_vs_f32": (
                top1_match_count / sample_total if sample_total else 0.0
            ),
            "top5_overlap_min_vs_f32": min(top5_overlaps, default=0),
            "top5_overlap_mean_vs_f32": (
                sum(top5_overlaps) / sample_total if sample_total else 0.0
            ),
            "replay_topk_mismatch_count": replay_topk_mismatch_count,
        }
    )
    return sample_results, summary


def main() -> None:
    args = parse_args()
    helper = load_helper_module()
    contract = read_json(args.contract_json)
    replay = read_json(args.replay_json)
    build_model = helper.load_adapter_build_model(args.adapter_path)
    model = build_model(str(args.model_path)).eval()
    weight = model.lm_head.weight.detach().cpu().to(torch.float64).contiguous()
    vocab_size, hidden_size = list(weight.shape)
    if vocab_size != contract["model"]["vocab_size"]:
        raise SystemExit("contract vocab size does not match model")
    if hidden_size != contract["model"]["hidden_size"]:
        raise SystemExit("contract hidden size does not match model")

    rowwise_q, rowwise_scales = helper.quantize_rowwise_symmetric(weight)
    q024_scales = torch.round(rowwise_scales * helper.Q024_SCALE).to(torch.int64)
    q024_reserved_nonzero_count = int(torch.sum(q024_scales > helper.Q024_MAX).item())
    if q024_reserved_nonzero_count:
        raise SystemExit("rowstream pack cannot encode nonzero reserved scale bits")

    image = pack_rowstream(rowwise_q, q024_scales, contract)
    unpacked_q, unpacked_scales, unpack_info = unpack_rowstream(image, contract)
    q_mismatch_count = int(torch.sum(unpacked_q != rowwise_q).item())
    scale_mismatch_count = int(torch.sum(unpacked_scales != q024_scales).item())
    sample_results, replay_summary = replay_unpacked_stream(
        helper=helper,
        model=model,
        weight=weight,
        unpacked_q=unpacked_q,
        unpacked_scales=unpacked_scales,
        replay=replay,
        sample_count=args.sample_count,
        top_k=args.top_k,
    )

    rowstream_sha256 = hashlib.sha256(image).hexdigest()
    args.out_dir.mkdir(parents=True, exist_ok=True)
    image_path = args.out_dir / "rowstream.bin"
    image_path.write_bytes(image)

    status_pass = (
        replay.get("status") == "PASS"
        and contract.get("status") == "PASS"
        and q_mismatch_count == 0
        and scale_mismatch_count == 0
        and unpack_info["reserved_nonzero_count"] == 0
        and unpack_info["tail_padding_nonzero_bytes"] == 0
        and replay_summary["top1_match_rate_vs_f32"] == 1.0
        and replay_summary["top5_overlap_min_vs_f32"] >= 4
        and replay_summary["replay_topk_mismatch_count"] == 0
    )
    payload = {
        "artifact_name": args.artifact_name,
        "status": "PASS" if status_pass else "FAIL",
        "date": args.date,
        "hypothesis": (
            "The generated DDR3 rowstream image can be unpacked into the same "
            "rowwise int8/Q0.24 scores that passed the full-vocab replay."
        ),
        "source_artifacts": {
            "model_path": args.model_artifact_label or str(args.model_path),
            "adapter_path": args.adapter_artifact_label or str(args.adapter_path),
            "ddr3_row_stream_interface_contract": (
                "artifacts/task6/parallel-hypotheses/"
                "h2-ddr3-row-stream-interface-contract.json"
            ),
            "full_vocab_rowwise_topk_replay": (
                "artifacts/task6/parallel-hypotheses/"
                "h2-full-vocab-rowwise-topk-replay.json"
            ),
        },
        "rowstream_image": {
            "path": "rowstream.bin",
            "bytes": len(image),
            "sha256": rowstream_sha256,
            "row_format": contract["row_format"]["name"],
            "rows_per_group": contract["ddr3_linear_image"]["rows_per_group"],
            "group_count": contract["ddr3_linear_image"]["group_count"],
        },
        "pack_unpack_validation": {
            "q_mismatch_count": q_mismatch_count,
            "scale_q024_mismatch_count": scale_mismatch_count,
            **unpack_info,
        },
        "replay_summary": replay_summary,
        "samples": sample_results,
        "validation": {
            "python_run": True,
            "simulation_run": False,
            "synthesis_run": False,
            "hardware_run": False,
            "validation_kind": "rowstream-pack-unpack-replay",
        },
        "decision": {
            "verdict": (
                "promote-rowstream-pack-format"
                if status_pass
                else "do-not-promote-rowstream-pack-format"
            ),
            "next_gate": (
                "Build a DDR-free RTL rowstream cutout that consumes this "
                "packed image through a synthetic source before integrating "
                "a DDR3 controller."
                if status_pass
                else "Fix pack/unpack or replay mismatches before RTL work."
            ),
        },
    }
    (args.out_dir / "summary.json").write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n"
    )


if __name__ == "__main__":
    main()
