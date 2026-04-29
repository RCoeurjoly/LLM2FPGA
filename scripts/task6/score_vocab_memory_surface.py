#!/usr/bin/env python3
"""Score TinyStories vocab-dependent embedding and output-head memory surfaces."""

from __future__ import annotations

import argparse
import csv
import importlib.util
import json
import math
import os
from pathlib import Path
import sys
from typing import Any


BRAM36_BITS = 36 * 1024
F32_BYTES = 4
SCALE_BYTES = 4


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-path", required=True, type=Path)
    parser.add_argument("--out-json", required=True, type=Path)
    parser.add_argument("--out-csv", type=Path)
    parser.add_argument(
        "--artifact-name",
        default="h2-vocab-memory-surface-score",
    )
    parser.add_argument(
        "--lane",
        action="append",
        required=True,
        help=(
            "Colon-separated lane config: "
            "label:vocab_size:num_layers:max_position_embeddings:"
            "window_size:hidden_size:num_heads"
        ),
    )
    parser.add_argument("--dsp-lanes", type=int, default=4)
    parser.add_argument("--bram36-capacity", type=int, default=955)
    parser.add_argument("--baseline-utilization-json", type=Path)
    parser.add_argument(
        "--include-four-full-vocab-table-baseline",
        action="store_true",
        help=(
            "Add the previously observed all-memory baseline shape: four "
            "full-vocab f32 tables."
        ),
    )
    return parser.parse_args()


def parse_lane(value: str) -> dict[str, Any]:
    parts = value.split(":")
    if len(parts) != 7:
        raise SystemExit(f"bad --lane value {value!r}")
    label, vocab, layers, pos, window, hidden, heads = parts
    return {
        "label": label,
        "vocab_size": int(vocab),
        "num_layers": int(layers),
        "max_position_embeddings": int(pos),
        "window_size": int(window),
        "hidden_size": int(hidden),
        "num_heads": int(heads),
    }


def load_representative_core_builder() -> Any:
    repo_root = Path(__file__).resolve().parents[2]
    adapter_path = repo_root / "TinyStories" / "model_adapter_representative_core.py"
    sys.path.insert(0, str(adapter_path.parent))
    spec = importlib.util.spec_from_file_location(
        "model_adapter_representative_core", adapter_path
    )
    if spec is None or spec.loader is None:
        raise SystemExit(f"unable to load adapter from {adapter_path}")
    module = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(module)
    finally:
        try:
            sys.path.remove(str(adapter_path.parent))
        except ValueError:
            pass
    return module.build_model


def set_lane_env(lane: dict[str, Any]) -> None:
    os.environ["TINYSTORIES_CORE_VOCAB_SIZE"] = str(lane["vocab_size"])
    os.environ["TINYSTORIES_CORE_NUM_LAYERS"] = str(lane["num_layers"])
    os.environ["TINYSTORIES_CORE_MAX_POSITION_EMBEDDINGS"] = str(
        lane["max_position_embeddings"]
    )
    os.environ["TINYSTORIES_CORE_WINDOW_SIZE"] = str(lane["window_size"])
    os.environ["TINYSTORIES_CORE_HIDDEN_SIZE"] = str(lane["hidden_size"])
    os.environ["TINYSTORIES_CORE_NUM_HEADS"] = str(lane["num_heads"])


def bram36_exact(bits: int) -> float:
    return bits / BRAM36_BITS


def bram36_ceil(bits: int) -> int:
    return math.ceil(bram36_exact(bits))


def bram36_summary(bytes_value: int, bram36_capacity: int) -> dict[str, Any]:
    bits = bytes_value * 8
    exact = bram36_exact(bits)
    used = bram36_ceil(bits)
    return {
        "bytes": bytes_value,
        "bits": bits,
        "bram36_exact": exact,
        "bram36_ceiling": used,
        "bram36_capacity": bram36_capacity,
        "bram36_capacity_pct_ceiling": (used / bram36_capacity) * 100.0,
        "fits_bram36_capacity_by_ceiling": used <= bram36_capacity,
    }


def rowwise_int_bytes(rows: int, cols: int, bits: int) -> dict[str, int]:
    numel = rows * cols
    if bits == 8:
        data_bytes = numel
    elif bits == 4:
        data_bytes = (numel + 1) // 2
    else:
        raise ValueError(bits)
    scale_bytes = rows * SCALE_BYTES
    return {
        "data_bytes": data_bytes,
        "scale_sidecar_bytes": scale_bytes,
        "total_bytes": data_bytes + scale_bytes,
    }


def inspect_lane(
    build_model: Any,
    model_path: Path,
    lane: dict[str, Any],
    dsp_lanes: int,
    bram36_capacity: int,
) -> dict[str, Any]:
    set_lane_env(lane)
    model = build_model(str(model_path))
    wte = model.transformer.wte
    wpe = model.transformer.wpe
    lm_head = model.lm_head

    vocab_size = int(lane["vocab_size"])
    hidden_size = int(lane["hidden_size"])
    max_position_embeddings = int(lane["max_position_embeddings"])
    token_numel = vocab_size * hidden_size
    pos_numel = max_position_embeddings * hidden_size
    lm_head_numel = vocab_size * hidden_size

    token_embedding_f32_bytes = token_numel * F32_BYTES
    position_embedding_f32_bytes = pos_numel * F32_BYTES
    lm_head_f32_bytes = lm_head_numel * F32_BYTES
    lm_head_tied_to_token_embedding = (
        lm_head.weight.detach().data_ptr() == wte.weight.detach().data_ptr()
    )
    physical_lm_head_f32_bytes = (
        0 if lm_head_tied_to_token_embedding else lm_head_f32_bytes
    )
    unique_persistent_f32_bytes = (
        token_embedding_f32_bytes
        + position_embedding_f32_bytes
        + physical_lm_head_f32_bytes
    )
    logical_persistent_f32_bytes = (
        token_embedding_f32_bytes
        + position_embedding_f32_bytes
        + lm_head_f32_bytes
    )

    token_int8 = rowwise_int_bytes(vocab_size, hidden_size, 8)
    position_int8 = rowwise_int_bytes(max_position_embeddings, hidden_size, 8)
    lm_head_int8 = rowwise_int_bytes(vocab_size, hidden_size, 8)
    token_int4 = rowwise_int_bytes(vocab_size, hidden_size, 4)
    position_int4 = rowwise_int_bytes(max_position_embeddings, hidden_size, 4)
    lm_head_int4 = rowwise_int_bytes(vocab_size, hidden_size, 4)
    unique_int8_bytes = token_int8["total_bytes"] + position_int8["total_bytes"]
    unique_int4_bytes = token_int4["total_bytes"] + position_int4["total_bytes"]
    if not lm_head_tied_to_token_embedding:
        unique_int8_bytes += lm_head_int8["total_bytes"]
        unique_int4_bytes += lm_head_int4["total_bytes"]

    output_macs = vocab_size * hidden_size
    output_cycles = math.ceil(output_macs / dsp_lanes)
    embedding_f32_read_bytes = hidden_size * F32_BYTES
    embedding_int8_read_bytes = hidden_size + SCALE_BYTES
    output_f32_weight_stream_bytes = lm_head_f32_bytes
    output_f32_logits_bytes = vocab_size * F32_BYTES
    output_int8_weight_stream_bytes = lm_head_int8["total_bytes"]
    output_int8_logits_bytes = vocab_size

    return {
        "label": lane["label"],
        "config": dict(lane),
        "inspection": {
            "token_embedding_module": "transformer.wte",
            "position_embedding_module": "transformer.wpe",
            "lm_head_module": "lm_head",
            "token_embedding_shape": list(wte.weight.shape),
            "position_embedding_shape": list(wpe.weight.shape),
            "lm_head_shape": list(lm_head.weight.shape),
            "token_embedding_dtype": str(wte.weight.dtype).replace("torch.", ""),
            "position_embedding_dtype": str(wpe.weight.dtype).replace("torch.", ""),
            "lm_head_dtype": str(lm_head.weight.dtype).replace("torch.", ""),
            "lm_head_tied_to_token_embedding": lm_head_tied_to_token_embedding,
        },
        "persistent_storage": {
            "token_embedding_f32_bytes": token_embedding_f32_bytes,
            "position_embedding_f32_bytes": position_embedding_f32_bytes,
            "lm_head_logical_f32_bytes": lm_head_f32_bytes,
            "lm_head_physical_f32_bytes": physical_lm_head_f32_bytes,
            "unique_persistent_f32": bram36_summary(
                unique_persistent_f32_bytes,
                bram36_capacity,
            ),
            "logical_persistent_f32_if_lm_head_materialized": bram36_summary(
                logical_persistent_f32_bytes,
                bram36_capacity,
            ),
            "unique_rowwise_int8": bram36_summary(unique_int8_bytes, bram36_capacity),
            "unique_rowwise_int4": bram36_summary(unique_int4_bytes, bram36_capacity),
        },
        "per_token_access": {
            "embedding_lookup": {
                "f32_read_bytes": embedding_f32_read_bytes,
                "rowwise_int8_read_bytes": embedding_int8_read_bytes,
                "scales_with_vocab_per_token": False,
            },
            "output_projection": {
                "macs": output_macs,
                "dsp_lanes": dsp_lanes,
                "min_compute_cycles": output_cycles,
                "f32_weight_stream_bytes": output_f32_weight_stream_bytes,
                "f32_logits_output_bytes": output_f32_logits_bytes,
                "f32_input_vector_bytes": hidden_size * F32_BYTES,
                "f32_total_weight_input_logits_bytes": (
                    output_f32_weight_stream_bytes
                    + output_f32_logits_bytes
                    + hidden_size * F32_BYTES
                ),
                "rowwise_int8_weight_stream_bytes": output_int8_weight_stream_bytes,
                "rowwise_int8_input_vector_bytes": hidden_size,
                "rowwise_int8_logits_output_bytes": output_int8_logits_bytes,
                "rowwise_int8_total_with_int8_logits_bytes": (
                    output_int8_weight_stream_bytes
                    + output_int8_logits_bytes
                    + hidden_size
                ),
                "rowwise_int8_total_topk_stream_no_full_logits_bytes": (
                    output_int8_weight_stream_bytes + hidden_size
                ),
                "f32_bytes_per_min_compute_cycle": (
                    (
                        output_f32_weight_stream_bytes
                        + output_f32_logits_bytes
                        + hidden_size * F32_BYTES
                    )
                    / output_cycles
                ),
                "rowwise_int8_topk_bytes_per_min_compute_cycle": (
                    (output_int8_weight_stream_bytes + hidden_size)
                    / output_cycles
                ),
            },
        },
    }


def add_lane_deltas(lanes: list[dict[str, Any]]) -> None:
    previous: dict[str, Any] | None = None
    for lane in lanes:
        if previous is None:
            lane["delta_vs_previous_lane"] = None
        else:
            current_storage = lane["persistent_storage"]["unique_persistent_f32"][
                "bytes"
            ]
            previous_storage = previous["persistent_storage"]["unique_persistent_f32"][
                "bytes"
            ]
            current_cycles = lane["per_token_access"]["output_projection"][
                "min_compute_cycles"
            ]
            previous_cycles = previous["per_token_access"]["output_projection"][
                "min_compute_cycles"
            ]
            current_stream = lane["per_token_access"]["output_projection"][
                "rowwise_int8_total_topk_stream_no_full_logits_bytes"
            ]
            previous_stream = previous["per_token_access"]["output_projection"][
                "rowwise_int8_total_topk_stream_no_full_logits_bytes"
            ]
            lane["delta_vs_previous_lane"] = {
                "previous_label": previous["label"],
                "unique_persistent_f32_bytes_delta": (
                    current_storage - previous_storage
                ),
                "unique_persistent_f32_bytes_ratio": (
                    current_storage / previous_storage
                    if previous_storage
                    else None
                ),
                "output_projection_min_compute_cycles_delta": (
                    current_cycles - previous_cycles
                ),
                "output_projection_min_compute_cycles_ratio": (
                    current_cycles / previous_cycles if previous_cycles else None
                ),
                "rowwise_int8_topk_stream_bytes_per_token_delta": (
                    current_stream - previous_stream
                ),
                "rowwise_int8_topk_stream_bytes_per_token_ratio": (
                    current_stream / previous_stream if previous_stream else None
                ),
            }
        previous = lane


def build_csv_rows(lanes: list[dict[str, Any]]) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for lane in lanes:
        output = lane["per_token_access"]["output_projection"]
        rows.append(
            {
                "label": lane["label"],
                "vocab_size": lane["config"]["vocab_size"],
                "hidden_size": lane["config"]["hidden_size"],
                "max_position_embeddings": lane["config"][
                    "max_position_embeddings"
                ],
                "lm_head_tied": lane["inspection"][
                    "lm_head_tied_to_token_embedding"
                ],
                "unique_persistent_f32_bytes": lane["persistent_storage"][
                    "unique_persistent_f32"
                ]["bytes"],
                "unique_persistent_f32_bram36_ceiling": lane["persistent_storage"][
                    "unique_persistent_f32"
                ]["bram36_ceiling"],
                "unique_rowwise_int8_bytes": lane["persistent_storage"][
                    "unique_rowwise_int8"
                ]["bytes"],
                "unique_rowwise_int4_bytes": lane["persistent_storage"][
                    "unique_rowwise_int4"
                ]["bytes"],
                "output_projection_macs": output["macs"],
                "output_projection_min_compute_cycles": output[
                    "min_compute_cycles"
                ],
                "output_projection_f32_bytes_per_token": output[
                    "f32_total_weight_input_logits_bytes"
                ],
                "output_projection_int8_topk_stream_bytes_per_token": output[
                    "rowwise_int8_total_topk_stream_no_full_logits_bytes"
                ],
            }
        )
    return rows


def main() -> None:
    args = parse_args()
    build_model = load_representative_core_builder()
    lanes = [
        inspect_lane(
            build_model,
            args.model_path,
            parse_lane(value),
            args.dsp_lanes,
            args.bram36_capacity,
        )
        for value in args.lane
    ]
    add_lane_deltas(lanes)

    baseline_utilization = None
    if args.baseline_utilization_json is not None:
        baseline_utilization = json.loads(
            args.baseline_utilization_json.read_text(encoding="utf-8")
        )

    four_table_baseline = None
    if args.include_four_full_vocab_table_baseline:
        full_lane = lanes[-1]
        vocab_size = int(full_lane["config"]["vocab_size"])
        hidden_size = int(full_lane["config"]["hidden_size"])
        bytes_value = 4 * vocab_size * hidden_size * F32_BYTES
        four_table_baseline = {
            "description": "four f32 full-vocab tables observed in the copied all-memory baseline notes",
            "table_count": 4,
            "table_shape": [vocab_size, hidden_size],
            "storage": bram36_summary(bytes_value, args.bram36_capacity),
        }

    v4k_lane = next(
        (lane for lane in lanes if lane["config"]["vocab_size"] == 4096),
        None,
    )
    full_lane = lanes[-1]
    decision = {
        "verdict": "promote-v4k-on-chip-vocab-prototype-and-full-vocab-ddr3-plan",
        "v4k_storage_gate": None,
        "full_model_storage_gate": None,
        "next_gate": (
            "Keep the next board-facing v4k prototype on-chip for tied vocab "
            "storage, but plan the full TinyStories vocab/output surface as an "
            "external-memory or streamed-output-head problem."
        ),
    }
    if v4k_lane is not None:
        decision["v4k_storage_gate"] = (
            "fits-on-chip"
            if v4k_lane["persistent_storage"]["unique_persistent_f32"][
                "fits_bram36_capacity_by_ceiling"
            ]
            else "requires-external-memory"
        )
    decision["full_model_storage_gate"] = (
        "fits-on-chip"
        if full_lane["persistent_storage"]["unique_persistent_f32"][
            "fits_bram36_capacity_by_ceiling"
        ]
        else "requires-external-memory-or-compression"
    )

    payload = {
        "artifact_name": args.artifact_name,
        "status": "PASS",
        "source_artifacts": {
            "model_path": str(args.model_path),
            "baseline_utilization_json": (
                str(args.baseline_utilization_json)
                if args.baseline_utilization_json is not None
                else None
            ),
        },
        "assumptions": {
            "bram36_bits": BRAM36_BITS,
            "bram36_capacity": args.bram36_capacity,
            "dsp_lanes_for_output_projection": args.dsp_lanes,
            "rowwise_quantization_sidecar_bytes_per_row": SCALE_BYTES,
            "lm_head_tying_checked_from_model": True,
        },
        "lanes": lanes,
        "copied_baseline_utilization": baseline_utilization,
        "four_full_vocab_table_baseline": four_table_baseline,
        "decision": decision,
    }

    args.out_json.parent.mkdir(parents=True, exist_ok=True)
    args.out_json.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")

    if args.out_csv is not None:
        rows = build_csv_rows(lanes)
        args.out_csv.parent.mkdir(parents=True, exist_ok=True)
        with args.out_csv.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
            writer.writeheader()
            writer.writerows(rows)


if __name__ == "__main__":
    main()
