#!/usr/bin/env python3
"""Summarize decoded LiteDRAM DDR3 bring-up evidence against the gate ladder."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


MAGIC = 0x54364A44
DFII_ADDRWALK_COLUMNS = [
    0x0000,
    0x0008,
    0x0010,
    0x0018,
    0x0040,
    0x0048,
    0x0050,
    0x0058,
    0x0100,
    0x0108,
    0x0110,
    0x0118,
    0x0200,
    0x0208,
    0x0210,
    0x0218,
]
EXPECTED_NATIVE_COUNT = 16
EXPECTED_NATIVE_CHUNKS = 9
GATE_ORDER = ["G0", "G1", "G2", "G3", "G4", "G5", "G6", "G7"]


def gate_index(name: str) -> int:
    return GATE_ORDER.index(name)


def highest_gate(*gates: str | None) -> str:
    highest = "G0"
    for gate in gates:
        if gate is None:
            continue
        if gate_index(gate) > gate_index(highest):
            highest = gate
    return highest


def evaluate_gate_pass(
    payload: dict[str, object],
    *,
    expected_version: int | None = None,
    expected_state: str | None = None,
    expected_bits: int | None = None,
    max_gate: str | None = None,
) -> tuple[str, list[str], dict[str, bool]]:
    fields = payload.get("fields", {})
    decoded = payload.get("decoded", {})
    status = decoded.get("status", {})
    extended_status = decoded.get("extended_status", {})
    version = fields.get("version")
    state = decoded.get("state")
    native = decoded.get("native_address_classifier") or {}
    addr_matrix = decoded.get("dfii_addr_matrix") or []

    reason: list[str] = []
    gate_pass: dict[str, bool] = {
        "G0": False,
        "G1": False,
        "G2": False,
        "G3": False,
        "G4": False,
        "G5": False,
        "G6": False,
        "G7": False,
    }
    max_gate_index = gate_index(max_gate) if max_gate else None

    magic_ok = fields.get("magic") == MAGIC
    if expected_bits is not None:
        raw_hex = payload.get("raw_hex")
        if not isinstance(raw_hex, str) or not raw_hex.startswith("0x"):
            reason.append("payload_length_unknown")
            return "G0", reason, gate_pass
        payload_bits = (len(raw_hex) - 2) * 4
        if payload_bits != expected_bits:
            reason.append("payload_length_mismatch")
            return "G0", reason, gate_pass

    if expected_version is not None and version != expected_version:
        reason.append("version_mismatch")
        return "G0", reason, gate_pass

    if not isinstance(fields.get("pll_locked"), int):
        pll_locked = bool(status.get("pll_locked", False))
    else:
        pll_locked = bool(fields.get("pll_locked"))

    if not magic_ok:
        reason.append("missing_or_bad_magic")
        return "G0", reason, gate_pass

    if expected_state is not None and state != expected_state:
        reason.append("state_mismatch")
        return "G0", reason, gate_pass

    gate_pass["G0"] = True
    if max_gate_index is not None and gate_index("G0") >= max_gate_index:
        return highest_gate(*[g for g, p in gate_pass.items() if p]), reason, gate_pass

    if not bool(status.get("init_done", False)):
        reason.append("init_not_done")
        return highest_gate(*[g for g, p in gate_pass.items() if p]), reason, gate_pass
    if bool(status.get("init_error", False)):
        reason.append("init_error")
        return highest_gate(*[g for g, p in gate_pass.items() if p]), reason, gate_pass
    if bool(status.get("wb_error_seen", False)) or bool(status.get("wb_timeout_seen", False)):
        reason.append("wishbone_error_or_timeout")
        return highest_gate(*[g for g, p in gate_pass.items() if p]), reason, gate_pass
    if not pll_locked or bool(status.get("user_rst", True)):
        reason.append("clock_or_reset_not_stable")
        return highest_gate(*[g for g, p in gate_pass.items() if p]), reason, gate_pass

    gate_pass["G1"] = True
    if max_gate_index is not None and gate_index("G1") >= max_gate_index:
        return highest_gate(*[g for g, p in gate_pass.items() if p]), reason, gate_pass

    if not isinstance(fields.get("dfii_wb_ack_count"), int):
        reason.append("dfii_data_metrics_unavailable")
        return highest_gate(*[g for g, p in gate_pass.items() if p]), reason, gate_pass

    if not bool(decoded.get("dfii_data_pass", False)):
        if isinstance(fields.get("mismatch_count"), int) and fields.get("mismatch_count"):
            reason.append("dfii_one_beat_mismatch_count")
        elif isinstance(fields.get("dfii_word_mismatch_mask"), int) and fields.get("dfii_word_mismatch_mask"):
            reason.append("dfii_one_beat_word_mismatch")
        else:
            reason.append("dfii_one_beat_data_not_complete")
        return highest_gate(*[g for g, p in gate_pass.items() if p]), reason, gate_pass

    if int(fields.get("dfii_wb_ack_count", 0)) < 1:
        reason.append("dfii_one_beat_missing_ack")
        return highest_gate(*[g for g, p in gate_pass.items() if p]), reason, gate_pass

    gate_pass["G2"] = True
    if max_gate_index is not None and gate_index("G2") >= max_gate_index:
        return highest_gate(*[g for g, p in gate_pass.items() if p]), reason, gate_pass

    command_count = int(fields.get("command_count", 0))
    response_count = int(fields.get("response_count", 0))
    if command_count != EXPECTED_NATIVE_COUNT or response_count != EXPECTED_NATIVE_COUNT:
        reason.append("dfii_addrwalk_count_not_16")
        return highest_gate(*[g for g, p in gate_pass.items() if p]), reason, gate_pass

    addr_flags = int(fields.get("dfii_addr_flags", 0))
    if not (addr_flags & 0x4):
        reason.append("dfii_addrwalk_not_enabled")
        return highest_gate(*[g for g, p in gate_pass.items() if p]), reason, gate_pass

    if len(addr_matrix) < 4:
        reason.append("dfii_addr_matrix_incomplete")
        return highest_gate(*[g for g, p in gate_pass.items() if p]), reason, gate_pass

    address_columns = [entry.get("column", 0) for entry in addr_matrix]
    if len(set(address_columns)) < 4:
        reason.append("dfii_addr_matrix_has_no_column_coverage")
        return highest_gate(*[g for g, p in gate_pass.items() if p]), reason, gate_pass
    if any((entry.get("mismatch_mask", 0) or 0) for entry in addr_matrix):
        reason.append("dfii_addrwalk_matrix_mismatch")
        return highest_gate(*[g for g, p in gate_pass.items() if p]), reason, gate_pass
    if not set(DFII_ADDRWALK_COLUMNS[:16]).issuperset(set(address_columns)):
        reason.append("dfii_addrwalk_matrix_columns_unexpected")
        return highest_gate(*[g for g, p in gate_pass.items() if p]), reason, gate_pass

    gate_pass["G3"] = True
    if max_gate_index is not None and gate_index("G3") >= max_gate_index:
        return highest_gate(*[g for g, p in gate_pass.items() if p]), reason, gate_pass

    if not native:
        return highest_gate(*[g for g, p in gate_pass.items() if p]), reason, gate_pass

    native_valid = int(native.get("valid_count", 0))
    native_samples = native.get("samples", [])
    if native_valid != EXPECTED_NATIVE_COUNT:
        reason.append("native_classifier_incomplete")
        return highest_gate(*[g for g, p in gate_pass.items() if p]), reason, gate_pass

    if int(native.get("cmdaddr_accepted_valid_count", 0)) != EXPECTED_NATIVE_COUNT:
        reason.append("native_command_acceptance_mismatch")
        return highest_gate(*[g for g, p in gate_pass.items() if p]), reason, gate_pass

    exact_chunks = 0
    if not native_samples:
        reason.append("native_samples_empty")
        return highest_gate(*[g for g, p in gate_pass.items() if p]), reason, gate_pass

    beat_signatures: set[tuple[int, ...]] = set()
    mismatch_slots: list[int] = []
    for sample in native_samples:
        chunks = [chunk.get("actual") for chunk in sample.get("chunks", [])]
        beat_signatures.add(tuple(chunks))
        exact_chunks += int(sample.get("exact_chunk_count", 0) or 0)
        requested = sample.get("requested_addr_index")
        best_same = sample.get("best_same_chunk_dfii_addr_index")
        if requested is not None and best_same is not None and requested != best_same:
            mismatch_slots.append(sample.get("sample", len(mismatch_slots)))

    if len(beat_signatures) == 1:
        reason.append("native_read_data_collapsed_to_one_beat")
        return highest_gate(*[g for g, p in gate_pass.items() if p]), reason, gate_pass

    if mismatch_slots:
        reason.append("native_read_address_mapping_mismatch")
        return highest_gate(*[g for g, p in gate_pass.items() if p]), reason, gate_pass

    if exact_chunks != EXPECTED_NATIVE_COUNT * EXPECTED_NATIVE_CHUNKS:
        reason.append("native_read_exact_chunks_incomplete")
        return highest_gate(*[g for g, p in gate_pass.items() if p]), reason, gate_pass

    gate_pass["G4"] = True
    if max_gate_index is not None and gate_index("G4") >= max_gate_index:
        return highest_gate(*[g for g, p in gate_pass.items() if p]), reason, gate_pass

    if int(fields.get("write_command_count", 0)) != EXPECTED_NATIVE_COUNT:
        reason.append("native_write_command_count_not_16")
        return highest_gate(*[g for g, p in gate_pass.items() if p]), reason, gate_pass

    if int(fields.get("write_data_count", 0)) != EXPECTED_NATIVE_COUNT:
        reason.append("native_write_data_count_not_16")
        return highest_gate(*[g for g, p in gate_pass.items() if p]), reason, gate_pass

    if not bool(extended_status.get("write_command_target_seen", False)):
        reason.append("native_write_command_target_not_seen")
        return highest_gate(*[g for g, p in gate_pass.items() if p]), reason, gate_pass

    if not bool(extended_status.get("write_data_target_seen", False)):
        reason.append("native_write_data_target_not_seen")
        return highest_gate(*[g for g, p in gate_pass.items() if p]), reason, gate_pass

    gate_pass["G5"] = True

    return highest_gate(*[g for g, p in gate_pass.items() if p]), reason, gate_pass


def summarize_one_gates(
    payload: dict[str, Any],
    *,
    expected_version: int | None = None,
    expected_state: str | None = None,
    expected_bits: int | None = None,
    max_gate: str | None = None,
) -> tuple[str, list[str], dict[str, bool]]:
    return evaluate_gate_pass(
        payload,
        expected_version=expected_version,
        expected_state=expected_state,
        expected_bits=expected_bits,
        max_gate=max_gate,
    )


def merge_gate_state(gate_pass: dict[str, bool]) -> str:
    passed = [gate for gate in GATE_ORDER if gate_pass.get(gate)]
    return passed[-1] if passed else "G0"


def gate_pass_signature(gate_pass: dict[str, bool]) -> tuple[bool, ...]:
    return tuple(bool(gate_pass.get(gate, False)) for gate in GATE_ORDER)


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def native_signature(decoded: dict[str, Any]) -> dict[str, Any] | None:
    classifier = decoded.get("native_address_classifier")
    if not classifier:
        return None

    samples = classifier.get("samples", [])
    actual_beats = []
    best_any_indices = []
    best_same_indices = []
    exact_chunk_counts = []
    for sample in samples:
        chunks = sample.get("chunks", [])
        actual_beats.append(tuple(chunk.get("actual") for chunk in chunks))
        best_any_indices.append(sample.get("best_any_chunk_dfii_addr_index"))
        best_same_indices.append(sample.get("best_same_chunk_dfii_addr_index"))
        exact_chunk_counts.append(sample.get("exact_chunk_count", 0))

    return {
        "valid_count": classifier.get("valid_count", 0),
        "first_mismatch_addr": classifier.get("first_mismatch_addr"),
        "first_chunk_mismatch_mask": classifier.get("first_chunk_mismatch_mask"),
        "nonzero_count": classifier.get("nonzero_count"),
        "unique_native_beats": len(set(actual_beats)),
        "best_any_indices": sorted(
            index for index in set(best_any_indices) if index is not None
        ),
        "best_same_indices": sorted(
            index for index in set(best_same_indices) if index is not None
        ),
        "total_exact_chunks": sum(exact_chunk_counts),
        "cmdaddr_presented_valid_count": classifier.get(
            "cmdaddr_presented_valid_count", 0
        ),
        "cmdaddr_accepted_valid_count": classifier.get(
            "cmdaddr_accepted_valid_count", 0
        ),
        "cmdaddr_trace": classifier.get("cmdaddr_trace", []),
    }


def summarize_one(
    path: Path,
    *,
    expected_version: int | None = None,
    expected_state: str | None = None,
    expected_bits: int | None = None,
    max_gate: str | None = None,
) -> dict[str, Any]:
    payload = read_json(path)
    fields = payload.get("fields", {})
    decoded = payload.get("decoded", {})
    highest_gate, stop_reasons, gate_pass = summarize_one_gates(
        payload,
        expected_version=expected_version,
        expected_state=expected_state,
        expected_bits=expected_bits,
        max_gate=max_gate,
    )
    status = decoded.get("status", {})
    extended = decoded.get("extended_status", {})
    native = native_signature(decoded)

    stop_reason: str | None = None
    magic_ok = fields.get("magic") == MAGIC
    version = fields.get("version")
    state = decoded.get("state")
    if stop_reasons:
        stop_reason = stop_reasons[0]

    gate = highest_gate

    return {
        "path": str(path),
        "magic_ok": magic_ok,
        "version": version,
        "state": state,
        "attempts": payload.get("attempts"),
        "command_count": fields.get("command_count"),
        "response_count": fields.get("response_count"),
        "mismatch_count": fields.get("mismatch_count"),
        "highest_gate_with_evidence": gate,
        "stop_reasons": stop_reasons,
        "stop_reason": stop_reason,
        "stop_gate": merge_gate_state(gate_pass),
        "gate_pass": gate_pass,
        "status": {
            "pll_locked": status.get("pll_locked"),
            "user_rst": status.get("user_rst"),
            "init_done": status.get("init_done"),
            "init_error": status.get("init_error"),
            "wb_error_seen": status.get("wb_error_seen"),
            "wb_timeout_seen": status.get("wb_timeout_seen"),
            "probe_done": extended.get("probe_done"),
            "probe_error": extended.get("probe_error"),
            "probe_timeout": extended.get("probe_timeout"),
        },
        "native": native,
    }


def stable_signature(summary: dict[str, Any]) -> tuple[Any, ...]:
    native = summary.get("native") or {}
    return (
        summary.get("magic_ok"),
        summary.get("version"),
        summary.get("state"),
        summary.get("command_count"),
        summary.get("response_count"),
        summary.get("mismatch_count"),
        summary.get("highest_gate_with_evidence"),
        summary.get("stop_reason"),
        tuple(summary.get("stop_reasons") or ()),
        gate_pass_signature(summary.get("gate_pass") or {}),
        native.get("valid_count"),
        native.get("unique_native_beats"),
        tuple(native.get("best_any_indices") or []),
        tuple(native.get("best_same_indices") or []),
        native.get("total_exact_chunks"),
    )


def summarize(
    paths: list[Path],
    *,
    expected_version: int | None = None,
    expected_state: str | None = None,
    expected_bits: int | None = None,
) -> dict[str, Any]:
    readbacks = [
        summarize_one(
            path,
            expected_version=expected_version,
            expected_state=expected_state,
            expected_bits=expected_bits,
        )
        for path in paths
    ]
    signatures = [stable_signature(item) for item in readbacks]
    stable = len(set(signatures)) <= 1 if signatures else False
    gate_order = ["G0", "G1", "G2", "G3", "G4", "G5", "G6", "G7"]
    highest = "G0"
    gate_pass_counts = {gate: 0 for gate in gate_order}
    for item in readbacks:
        gate = item["highest_gate_with_evidence"]
        if gate_order.index(gate) > gate_order.index(highest):
            highest = gate
        for gate_name, passed in (item.get("gate_pass") or {}).items():
            if gate_name in gate_pass_counts and passed:
                gate_pass_counts[gate_name] += 1

    any_fail = any(item.get("stop_reasons") for item in readbacks)
    all_gate = all(item.get("gate_pass", {}).get(highest, False) for item in readbacks)

    return {
        "schema": "task6-litedram-ddr3-bringup-summary-v1",
        "readback_count": len(readbacks),
        "stable_signature": stable,
        "highest_gate_with_evidence": highest,
        "all_readbacks_gate_consistent": not any_fail,
        "all_readbacks_reached_highest_gate": all_gate,
        "readbacks_reached_gate_counts": gate_pass_counts,
        "readbacks": readbacks,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("readback_json", nargs="+", type=Path)
    parser.add_argument("--expected-version", type=int, help="Optional expected payload version for G0 checks.")
    parser.add_argument("--expected-state", type=str, help="Optional expected top-level state for G0 checks.")
    parser.add_argument("--expected-bits", type=int, help="Optional expected payload bit width for G0 checks.")
    parser.add_argument("--output", type=Path)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    result = summarize(
        args.readback_json,
        expected_version=args.expected_version,
        expected_state=args.expected_state,
        expected_bits=args.expected_bits,
    )
    text = json.dumps(result, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text, encoding="utf-8")
    else:
        print(text, end="")


if __name__ == "__main__":
    main()
