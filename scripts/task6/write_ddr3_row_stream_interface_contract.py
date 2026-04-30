#!/usr/bin/env python3
"""Generate the Task 6 DDR3 row-stream interface contract."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import math
from pathlib import Path
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--replay-json", required=True, type=Path)
    parser.add_argument("--replay-artifact-label")
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument(
        "--artifact-name",
        default="h2-ddr3-row-stream-interface-contract",
    )
    parser.add_argument("--date", default=dt.date.today().isoformat())
    parser.add_argument("--vocab-size", type=int, default=50257)
    parser.add_argument("--hidden-size", type=int, default=64)
    parser.add_argument("--rows-per-group", type=int, default=32)
    parser.add_argument("--beat-bytes", type=int, default=16)
    parser.add_argument("--kernel-clock-mhz", type=float, default=50.0)
    parser.add_argument("--dsp-lanes", action="append", type=int)
    return parser.parse_args()


def ceil_div(numerator: int, denominator: int) -> int:
    return (numerator + denominator - 1) // denominator


def read_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def lane_budget(
    *,
    dsp_lanes: list[int],
    hidden_size: int,
    vocab_size: int,
    row_bytes: int,
    padded_stream_bytes: int,
    beat_bytes: int,
    kernel_clock_mhz: float,
) -> list[dict[str, Any]]:
    rows = []
    stream_cycles_at_beat = ceil_div(padded_stream_bytes, beat_bytes)
    for lanes in dsp_lanes:
        row_compute_cycles = ceil_div(hidden_size, lanes)
        compute_cycles = vocab_size * row_compute_cycles
        bytes_per_compute_cycle_required = row_bytes / row_compute_cycles
        useful_bandwidth_mb_s = (
            bytes_per_compute_cycle_required * kernel_clock_mhz
        )
        total_cycles_if_beat_per_cycle = max(compute_cycles, stream_cycles_at_beat)
        rows.append(
            {
                "dsp_lanes": lanes,
                "row_compute_cycles": row_compute_cycles,
                "compute_cycles": compute_cycles,
                "stream_cycles_at_one_beat_per_cycle": stream_cycles_at_beat,
                "total_cycles_if_one_beat_per_cycle": total_cycles_if_beat_per_cycle,
                "limiter_if_one_beat_per_cycle": (
                    "ddr3_bandwidth"
                    if stream_cycles_at_beat > compute_cycles
                    else "compute"
                ),
                "bytes_per_compute_cycle_required": (
                    bytes_per_compute_cycle_required
                ),
                "minimum_useful_bandwidth_mb_s": useful_bandwidth_mb_s,
            }
        )
    return rows


def main() -> None:
    args = parse_args()
    lanes = args.dsp_lanes or [4, 8, 16]
    if args.hidden_size <= 0 or args.vocab_size <= 0:
        raise SystemExit("vocab-size and hidden-size must be positive")
    if args.rows_per_group <= 0 or args.beat_bytes <= 0:
        raise SystemExit("rows-per-group and beat-bytes must be positive")

    replay = read_json(args.replay_json)
    rowwise_metrics = replay["metrics"]["profile_b_rowwise_q024"]
    q024_reserved_nonzero_count = int(
        replay["quantization"]["profile_b"]["reserved_nonzero_count"]
    )
    replay_pass = (
        replay.get("status") == "PASS"
        and q024_reserved_nonzero_count == 0
        and rowwise_metrics["top1_match_rate_vs_f32"] == 1.0
        and rowwise_metrics["top5_overlap_min"] >= 4
    )

    weight_bytes_per_row = args.hidden_size
    sidecar_bytes_per_row = 4
    row_bytes = weight_bytes_per_row + sidecar_bytes_per_row
    group_count = ceil_div(args.vocab_size, args.rows_per_group)
    padded_rows = group_count * args.rows_per_group
    tail_valid_rows = args.vocab_size % args.rows_per_group
    if tail_valid_rows == 0:
        tail_valid_rows = args.rows_per_group
    tail_padding_rows = padded_rows - args.vocab_size
    logical_stream_bytes = args.vocab_size * row_bytes
    padded_stream_bytes = padded_rows * row_bytes
    group_bytes = args.rows_per_group * row_bytes
    beats_per_group = ceil_div(group_bytes, args.beat_bytes)
    if beats_per_group * args.beat_bytes != group_bytes:
        raise SystemExit(
            "row group is not an integer number of memory-stream beats"
        )

    payload = {
        "artifact_name": args.artifact_name,
        "status": "PASS" if replay_pass else "FAIL",
        "date": args.date,
        "hypothesis": (
            "The full TinyStories output head can be fed from DDR3 as a "
            "linear row stream of rowwise int8 payloads plus Q0.24 sidecars, "
            "with the existing fixed-point comparator as the row-score unit."
        ),
        "source_artifacts": {
            "full_vocab_rowwise_topk_replay": (
                args.replay_artifact_label or str(args.replay_json)
            ),
            "full_vocab_rowwise_topk_contract": (
                "artifacts/task6/parallel-hypotheses/"
                "h2-full-vocab-rowwise-topk-contract.json"
            ),
            "fixed_point_topk_budget": (
                "artifacts/task6/parallel-hypotheses/"
                "h2-full-vocab-rowwise-fixed-point-topk-budget.json"
            ),
            "q024_comparator_cutout_result": (
                "artifacts/task6/parallel-hypotheses/"
                "h2-q024-topk-comparator-cutout-result.json"
            ),
            "baseline_bundle": (
                "artifacts/task6/baselines/"
                "tiny-stories-1m-baseline-float-selftest-all-memory-utilization"
            ),
        },
        "model": {
            "model_label": replay["model"]["model_label"],
            "vocab_size": args.vocab_size,
            "hidden_size": args.hidden_size,
            "lm_head_tied_to_token_embedding": replay["model"][
                "lm_head_tied_to_token_embedding"
            ],
        },
        "row_format": {
            "name": "rowwise-int8-q024-inline-row",
            "row_bytes": row_bytes,
            "weight_bytes": weight_bytes_per_row,
            "sidecar_bytes": sidecar_bytes_per_row,
            "byte_layout": [
                {
                    "offset": 0,
                    "bytes": weight_bytes_per_row,
                    "field": "weight_q_i8[0:hidden_size]",
                    "endianness": "dimension order",
                },
                {
                    "offset": weight_bytes_per_row,
                    "bytes": 3,
                    "field": "scale_q0_24_low24",
                    "endianness": "little",
                },
                {
                    "offset": weight_bytes_per_row + 3,
                    "bytes": 1,
                    "field": "reserved_upper_byte",
                    "required_value": 0,
                },
            ],
            "score_formula": "signed_accumulator * scale_q0_24_low24",
            "score_bits": 46,
            "tie_break": "lower token id wins exact fixed-point score ties",
        },
        "ddr3_linear_image": {
            "base_symbol": "output_head_rowstream_base",
            "beat_bytes": args.beat_bytes,
            "rows_per_group": args.rows_per_group,
            "group_bytes": group_bytes,
            "beats_per_group": beats_per_group,
            "group_count": group_count,
            "logical_stream_bytes": logical_stream_bytes,
            "padded_stream_bytes": padded_stream_bytes,
            "tail_valid_rows": tail_valid_rows,
            "tail_padding_rows": tail_padding_rows,
            "tail_padding_bytes": tail_padding_rows * row_bytes,
            "row_address_rule": (
                f"group_base + row_in_group * {row_bytes}; group_base is "
                "output_head_rowstream_base + group_index * "
                f"{group_bytes}"
            ),
            "padding_rule": (
                "Rows with token_id >= vocab_size are invalid and must not "
                "update top-k state."
            ),
        },
        "kernel_side_interface": {
            "clock_domain": "kernel clock",
            "flow_control": "ready/valid at decoded row granularity",
            "signals": [
                {"name": "row_valid", "direction": "source_to_kernel", "bits": 1},
                {"name": "row_ready", "direction": "kernel_to_source", "bits": 1},
                {
                    "name": "row_token_id",
                    "direction": "source_to_kernel",
                    "bits": 16,
                },
                {
                    "name": "row_weight_q_i8",
                    "direction": "source_to_kernel",
                    "bits": args.hidden_size * 8,
                },
                {
                    "name": "row_scale_q0_24",
                    "direction": "source_to_kernel",
                    "bits": 24,
                },
                {
                    "name": "row_reserved_valid",
                    "direction": "source_to_kernel",
                    "bits": 1,
                },
                {"name": "row_last", "direction": "source_to_kernel", "bits": 1},
            ],
            "consumer": (
                "dot-product row engine followed by the existing Q0.24 "
                "fixed-point score comparator"
            ),
            "backpressure_rule": (
                "The source may pause between rows. A presented row is consumed "
                "only when row_valid and row_ready are both high."
            ),
        },
        "lane_budget": lane_budget(
            dsp_lanes=lanes,
            hidden_size=args.hidden_size,
            vocab_size=args.vocab_size,
            row_bytes=row_bytes,
            padded_stream_bytes=padded_stream_bytes,
            beat_bytes=args.beat_bytes,
            kernel_clock_mhz=args.kernel_clock_mhz,
        ),
        "replay_summary": {
            "status": replay["status"],
            "sample_count": replay["model"]["sample_count"],
            "top1_match_count": rowwise_metrics["top1_match_count"],
            "top1_match_rate_vs_f32": rowwise_metrics[
                "top1_match_rate_vs_f32"
            ],
            "top5_overlap_min": rowwise_metrics["top5_overlap_min"],
            "top5_overlap_mean": rowwise_metrics["top5_overlap_mean"],
            "max_normalized_rmse": rowwise_metrics["max_normalized_rmse"],
            "reserved_nonzero_count": q024_reserved_nonzero_count,
        },
        "acceptance_gates": [
            {
                "gate": "pack-unpack-replay",
                "requirement": (
                    "A generated rowstream image must unpack back to the same "
                    "rowwise Q0.24 top1/top5 results recorded by the full-vocab "
                    "replay artifact."
                ),
            },
            {
                "gate": "rtl-rowstream-cutout",
                "requirement": (
                    "A Verilator cutout must feed decoded rows through the dot "
                    "engine and Q0.24 comparator without a DDR3 controller."
                ),
            },
            {
                "gate": "ddr3-linear-read-bandwidth",
                "requirement": (
                    "Board DDR3 bring-up must demonstrate sustained linear read "
                    "bandwidth for the 4-lane target, with margin above "
                    "212.5 MB/s useful row payload at 50 MHz."
                ),
            },
        ],
        "validation": {
            "python_run": True,
            "simulation_run": False,
            "synthesis_run": False,
            "hardware_run": False,
            "validation_kind": "interface-contract-generation",
        },
        "decision": {
            "verdict": (
                "promote-ddr3-row-stream-contract"
                if replay_pass
                else "do-not-promote-ddr3-row-stream-contract"
            ),
            "rationale": (
                "The full-vocab replay passed with zero Q0.24 reserved-byte "
                "violations, so the DDR3 work can target this row stream "
                "instead of debating row format."
                if replay_pass
                else "The prerequisite full-vocab replay did not pass, so the "
                "DDR3 row stream should not be implemented yet."
            ),
            "next_gate": (
                "Generate and validate a pack/unpack rowstream image, then build "
                "a DDR-free RTL rowstream cutout before integrating a DDR3 "
                "controller."
                if replay_pass
                else "Fix the replay/profile before defining a hardware memory "
                "interface."
            ),
        },
    }

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()
