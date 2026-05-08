#!/usr/bin/env python3
"""Summarize a LiteDRAM JTAG readback as a Task 6 linear-read gate."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def mbps(bytes_transferred: int, cycles: int, clock_mhz: float) -> float | None:
    if cycles <= 0:
        return None
    return (bytes_transferred / cycles) * clock_mhz


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--readback-json", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--artifact-name", default="task6-litedram-linear-read-gate")
    parser.add_argument("--native-beat-bytes", type=int, default=72)
    parser.add_argument("--rowstream-useful-bytes", type=int, default=68)
    parser.add_argument("--target-mbps", type=float, default=212.5)
    parser.add_argument("--design-clock-mhz", type=float, default=25.0)
    parser.add_argument("--rowstream-clock-mhz", type=float, default=50.0)
    parser.add_argument(
        "--integrity-mode",
        choices=["expected-data", "readscan-nonzero-only"],
        default="readscan-nonzero-only",
    )
    parser.add_argument("--source-run-dir")
    args = parser.parse_args()

    data = json.loads(args.readback_json.read_text())
    decoded = data.get("decoded", {})
    fields = data.get("fields", {})
    status = decoded.get("status", {})
    extended_status = decoded.get("extended_status", {})

    responses = int(fields.get("response_count", 0))
    target_reads = int(fields.get("target_read_count", 0))
    cycles = int(fields.get("read_cycle_count", 0))
    mismatch_count = int(fields.get("mismatch_count", 0))
    native_nonzero = int(fields.get("native_readscan_nonzero_count", 0))
    write_commands = int(fields.get("write_command_count", 0))
    write_data = int(fields.get("write_data_count", 0))

    raw_bytes = responses * args.native_beat_bytes
    rowstream_useful_bytes = responses * args.rowstream_useful_bytes
    design_mbps = mbps(rowstream_useful_bytes, cycles, args.design_clock_mhz)
    rowstream_mbps = mbps(rowstream_useful_bytes, cycles, args.rowstream_clock_mhz)

    bandwidth_clears_target = (
        rowstream_mbps is not None and rowstream_mbps >= args.target_mbps
    )
    read_count_complete = responses == target_reads and target_reads > 0
    board_read_complete = bool(
        data.get("magic_ok")
        and decoded.get("complete")
        and not decoded.get("failed")
        and status.get("init_done")
        and not status.get("init_error")
        and extended_status.get("probe_done")
        and not extended_status.get("probe_error")
        and not extended_status.get("probe_timeout")
        and read_count_complete
    )

    if args.integrity_mode == "expected-data":
        integrity_verified = board_read_complete and mismatch_count == 0
        integrity_basis = "expected-data compare in RTL"
    else:
        integrity_verified = False
        integrity_basis = (
            "nonzero readscan only; RTL did not compare each response against "
            "the deterministic expected row data"
        )

    result = {
        "artifact_name": args.artifact_name,
        "schema": "task6-linear-read-gate-v1",
        "source": {
            "readback_json": str(args.readback_json),
            "run_dir": args.source_run_dir,
            "backend": data.get("backend"),
            "attempts": data.get("attempts"),
        },
        "probe": {
            "magic_ok": data.get("magic_ok"),
            "version": fields.get("version"),
            "state": decoded.get("state"),
            "complete": decoded.get("complete"),
            "failed": decoded.get("failed"),
            "pll_locked": status.get("pll_locked"),
            "init_done": status.get("init_done"),
            "init_error": status.get("init_error"),
            "probe_done": extended_status.get("probe_done"),
            "probe_error": extended_status.get("probe_error"),
            "probe_timeout": extended_status.get("probe_timeout"),
        },
        "linear_read": {
            "target_read_count": target_reads,
            "command_count": fields.get("command_count"),
            "response_count": responses,
            "read_cycle_count": cycles,
            "native_beat_bytes": args.native_beat_bytes,
            "rowstream_useful_bytes_per_beat": args.rowstream_useful_bytes,
            "raw_bytes": raw_bytes,
            "rowstream_useful_bytes": rowstream_useful_bytes,
            "write_command_count": write_commands,
            "write_data_count": write_data,
            "mismatch_count": mismatch_count,
            "native_readscan_nonzero_count": native_nonzero,
            "native_readscan_nonzero_chunk_seen": fields.get(
                "native_readscan_nonzero_chunk_seen"
            ),
            "native_readscan_first_nonzero_addr": fields.get(
                "native_readscan_first_nonzero_addr"
            ),
            "native_readscan_first_nonzero_data": fields.get(
                "native_readscan_first_nonzero_data"
            ),
        },
        "bandwidth": {
            "design_clock_mhz": args.design_clock_mhz,
            "rowstream_clock_mhz": args.rowstream_clock_mhz,
            "target_mbps": args.target_mbps,
            "design_clock_useful_mbps": design_mbps,
            "rowstream_clock_useful_mbps": rowstream_mbps,
            "clears_target_at_rowstream_clock": bandwidth_clears_target,
        },
        "verdict": {
            "board_read_complete": board_read_complete,
            "read_count_complete": read_count_complete,
            "bandwidth_clears_target": bandwidth_clears_target,
            "integrity_mode": args.integrity_mode,
            "integrity_basis": integrity_basis,
            "integrity_verified": integrity_verified,
            "gate_pass": bool(
                board_read_complete
                and bandwidth_clears_target
                and integrity_verified
            ),
        },
        "next_step": (
            "Keep this as a bandwidth-shaped read visibility result, but build "
            "a deterministic expected-data linear-read probe before connecting "
            "DDR3 to the INT8 rowstream cutout."
        ),
    }

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()
