#!/usr/bin/env python3
"""Classify native 576-bit LiteDRAM beats against the DFII addrwalk pattern."""

from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import json
from pathlib import Path
import sys
from typing import Any

from read_litedram_probe_jtag_xvc import (
    DFII_ADDRWALK_COLUMNS,
    NATIVE_ADDRESS_CLASSIFIER_SAMPLE_COUNT,
    NATIVE_CHUNK_COUNT,
    native_address_classifier_addr,
    native_dfii_addrwalk_expected_chunks,
)


ROOT = Path(__file__).resolve().parents[2]


def load_json_from_log(path: Path) -> dict[str, Any]:
    text = path.read_text(encoding="utf-8")
    start = text.find("{")
    if start < 0:
        raise SystemExit(f"no JSON object found in {path}")
    return json.loads(text[start:])


def chunk_bytes_le(value: int) -> list[int]:
    return [(value >> (8 * byte)) & 0xFF for byte in range(8)]


def build_byte_dictionary() -> dict[int, list[dict[str, int]]]:
    byte_to_sources: dict[int, list[dict[str, int]]] = defaultdict(list)
    for addr_index in range(16):
        chunks = native_dfii_addrwalk_expected_chunks(addr_index)
        for chunk_index, chunk in enumerate(chunks):
            for byte_index, value in enumerate(chunk_bytes_le(chunk)):
                byte_to_sources[value].append(
                    {
                        "dfii_addr_index": addr_index,
                        "dfii_column": DFII_ADDRWALK_COLUMNS[addr_index],
                        "chunk": chunk_index,
                        "byte": byte_index,
                    }
                )
    return dict(byte_to_sources)


def build_chunk_dictionary() -> dict[int, list[dict[str, int]]]:
    chunk_to_sources: dict[int, list[dict[str, int]]] = defaultdict(list)
    for addr_index in range(16):
        chunks = native_dfii_addrwalk_expected_chunks(addr_index)
        for chunk_index, chunk in enumerate(chunks):
            chunk_to_sources[chunk].append(
                {
                    "dfii_addr_index": addr_index,
                    "dfii_column": DFII_ADDRWALK_COLUMNS[addr_index],
                    "chunk": chunk_index,
                }
            )
    return dict(chunk_to_sources)


def beat_key(chunks: list[int]) -> str:
    return " ".join(f"{chunk:016x}" for chunk in chunks)


def classify_sample(
    fields: dict[str, int],
    sample: int,
    start_index: int,
    chunk_dict: dict[int, list[dict[str, int]]],
    byte_dict: dict[int, list[dict[str, int]]],
) -> dict[str, Any]:
    actual_chunks = [
        fields.get(f"native_address_classifier_actual_{sample}_{chunk}", 0)
        for chunk in range(NATIVE_CHUNK_COUNT)
    ]
    requested_index = (start_index + sample) % NATIVE_ADDRESS_CLASSIFIER_SAMPLE_COUNT
    requested_addr = native_address_classifier_addr(requested_index)
    requested_addr_index = requested_addr & 0xF
    expected_chunks = native_dfii_addrwalk_expected_chunks(requested_addr)

    exact_chunk_matches = []
    any_position_chunk_matches = []
    byte_addr_votes: Counter[int] = Counter()
    byte_lane_votes: Counter[int] = Counter()
    byte_exact_position_matches = 0
    byte_known_count = 0

    for chunk_index, actual in enumerate(actual_chunks):
        if actual == expected_chunks[chunk_index]:
            exact_chunk_matches.append(chunk_index)
        if actual in chunk_dict:
            any_position_chunk_matches.append(
                {
                    "actual_chunk": chunk_index,
                    "matches": chunk_dict[actual],
                }
            )

        expected_bytes = chunk_bytes_le(expected_chunks[chunk_index])
        for byte_index, actual_byte in enumerate(chunk_bytes_le(actual)):
            if actual_byte == expected_bytes[byte_index]:
                byte_exact_position_matches += 1
            matches = byte_dict.get(actual_byte, [])
            if matches:
                byte_known_count += 1
            for match in matches:
                byte_addr_votes[match["dfii_addr_index"]] += 1
                # The low nibble of the addrwalk tag encodes the source lane.
                byte_lane_votes[(match["dfii_addr_index"], match["byte"])] += 1

    best_same_addr = None
    best_same_count = -1
    best_any_addr = None
    best_any_count = -1
    for addr_index in range(16):
        candidate_chunks = native_dfii_addrwalk_expected_chunks(addr_index)
        same_count = sum(
            1
            for chunk_index, actual in enumerate(actual_chunks)
            if actual == candidate_chunks[chunk_index]
        )
        any_count = sum(1 for actual in actual_chunks if actual in candidate_chunks)
        if same_count > best_same_count:
            best_same_addr = addr_index
            best_same_count = same_count
        if any_count > best_any_count:
            best_any_addr = addr_index
            best_any_count = any_count

    return {
        "sample": sample,
        "requested_index": requested_index,
        "requested_native_addr": requested_addr,
        "requested_dfii_addr_index": requested_addr_index,
        "requested_dfii_column": DFII_ADDRWALK_COLUMNS[requested_addr_index],
        "beat_key": beat_key(actual_chunks),
        "exact_same_position_chunk_count": len(exact_chunk_matches),
        "exact_same_position_chunks": exact_chunk_matches,
        "any_position_chunk_match_count": len(any_position_chunk_matches),
        "any_position_chunk_matches": any_position_chunk_matches,
        "byte_exact_same_position_count": byte_exact_position_matches,
        "byte_known_count": byte_known_count,
        "best_same_position_dfii_addr_index": best_same_addr,
        "best_same_position_chunk_count": best_same_count,
        "best_any_position_dfii_addr_index": best_any_addr,
        "best_any_position_chunk_count": best_any_count,
        "top_byte_addr_votes": [
            {"dfii_addr_index": addr, "count": count}
            for addr, count in byte_addr_votes.most_common(6)
        ],
        "actual_chunks_hex": [f"0x{chunk:016x}" for chunk in actual_chunks],
    }


def analyze(payload: dict[str, Any], source: str, start_index: int) -> dict[str, Any]:
    fields = payload["fields"]
    decoded = payload.get("decoded", {})
    classifier = decoded.get("native_address_classifier") or {}
    valid_count = min(
        int(fields.get("native_address_classifier_valid_count", 0)),
        NATIVE_ADDRESS_CLASSIFIER_SAMPLE_COUNT,
    )
    chunk_dict = build_chunk_dictionary()
    byte_dict = build_byte_dictionary()
    samples = [
        classify_sample(fields, sample, start_index, chunk_dict, byte_dict)
        for sample in range(valid_count)
    ]
    beat_counts = Counter(sample["beat_key"] for sample in samples)
    return {
        "schema": "task6-litedram-native-beat-mapping-analysis-v1",
        "source": source,
        "magic_ok": payload.get("magic_ok"),
        "state": decoded.get("state"),
        "version": fields.get("version"),
        "command_count": fields.get("command_count"),
        "response_count": fields.get("response_count"),
        "mismatch_count": fields.get("mismatch_count"),
        "valid_count": valid_count,
        "start_index": start_index,
        "cmdaddr_trace": classifier.get("cmdaddr_trace", []),
        "unique_beat_count": len(beat_counts),
        "unique_beats": [
            {"beat_key": key, "count": count}
            for key, count in beat_counts.most_common()
        ],
        "samples": samples,
    }


def write_markdown(path: Path, result: dict[str, Any]) -> None:
    lines = [
        "# LiteDRAM native beat mapping analysis",
        "",
        f"- Source: `{result['source']}`",
        f"- State: `{result['state']}`",
        f"- Version: `{result['version']}`",
        f"- Command/response count: `{result['command_count']}` / `{result['response_count']}`",
        f"- Valid samples: `{result['valid_count']}`",
        f"- Start index override: `{result['start_index']}`",
        f"- Mismatches: `{result['mismatch_count']}`",
        f"- Unique native beats: `{result['unique_beat_count']}`",
        "",
    ]
    if result["cmdaddr_trace"]:
        trace = result["cmdaddr_trace"][0]
        lines += [
            "## Command Address Trace",
            "",
            "| command index | scheduled | presented | accepted | accepted=requested |",
            "| ---: | ---: | ---: | ---: | --- |",
            (
                f"| {trace['command_index']} | {trace['scheduled_read_addr']} | "
                f"{trace['presented_cmd_addr']} | {trace['accepted_cmd_addr']} | "
                f"{trace['accepted_matches_requested']} |"
            ),
            "",
        ]
    lines += [
        "## Sample Summary",
        "",
        (
            "| sample | requested native addr | best same-position addr | "
            "same chunks | best any-position addr | any chunks | byte exact | top byte votes |"
        ),
        "| ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |",
    ]
    for sample in result["samples"]:
        top_votes = ", ".join(
            f"{vote['dfii_addr_index']}:{vote['count']}"
            for vote in sample["top_byte_addr_votes"][:3]
        )
        lines.append(
            f"| {sample['sample']} | {sample['requested_native_addr']} | "
            f"{sample['best_same_position_dfii_addr_index']} | "
            f"{sample['best_same_position_chunk_count']} | "
            f"{sample['best_any_position_dfii_addr_index']} | "
            f"{sample['best_any_position_chunk_count']} | "
            f"{sample['byte_exact_same_position_count']} | {top_votes} |"
        )
    lines += [
        "",
        "## Interpretation",
        "",
        "- `same chunks` counts 64-bit chunks matching the same chunk position.",
        "- `any chunks` counts 64-bit chunks matching any expected chunk position for one DFII address index.",
        "- `byte exact` counts byte matches at the requested address and exact byte position.",
        "- If all samples share one beat but command addresses differ, the failure is below native command acceptance.",
        "",
    ]
    path.write_text("\n".join(lines), encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    parser.add_argument("--start-index", type=int, default=0)
    parser.add_argument("--json-out", type=Path, required=True)
    parser.add_argument("--markdown-out", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    payload = load_json_from_log(args.log)
    result = analyze(payload, str(args.log), args.start_index)
    args.json_out.parent.mkdir(parents=True, exist_ok=True)
    args.markdown_out.parent.mkdir(parents=True, exist_ok=True)
    args.json_out.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    write_markdown(args.markdown_out, result)
    print(args.json_out)
    print(args.markdown_out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
