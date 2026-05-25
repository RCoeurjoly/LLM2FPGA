#!/usr/bin/env python3
"""Run the Task 6 rowstream top1 gate against a rowstream image.

This is the host-side mirror of the board top1 contract: a 64-byte int8 hidden
vector is matched against packed rowstream rows containing 64 int8 weights plus
a 3-byte little-endian Q0.24 scale sidecar and one reserved byte.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_ROWSTREAM = (
    ROOT
    / "artifacts"
    / "task6"
    / "parallel-hypotheses"
    / "h2-ddr3-row-stream-pack-replay"
    / "rowstream.bin"
)
DEFAULT_CONTRACT = (
    ROOT
    / "artifacts"
    / "task6"
    / "parallel-hypotheses"
    / "h2-ddr3-row-stream-interface-contract.json"
)
DEFAULT_REPLAY = (
    ROOT
    / "artifacts"
    / "task6"
    / "parallel-hypotheses"
    / "h2-full-vocab-rowwise-topk-replay.json"
)
DEFAULT_OUT = ROOT / "artifacts" / "task6" / "runs" / "rowstream-top1-summary.json"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rowstream-bin", type=Path, default=DEFAULT_ROWSTREAM)
    parser.add_argument(
        "--readback-bin",
        type=Path,
        help="Optional DDR3 readback image. When supplied, top1 is computed from this image and its hash is compared to --rowstream-bin.",
    )
    parser.add_argument("--contract-json", type=Path, default=DEFAULT_CONTRACT)
    parser.add_argument("--replay-json", type=Path, default=DEFAULT_REPLAY)
    parser.add_argument("--model-path", type=Path)
    parser.add_argument("--adapter-path", type=Path, default=ROOT / "TinyStories" / "model_adapter.py")
    parser.add_argument("--sample-count", type=int, default=1)
    parser.add_argument(
        "--hidden-q-hex",
        help="Single 64-byte int8 hidden vector as hex. Bypasses model loading and replay samples.",
    )
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--json-only", action="store_true")
    return parser.parse_args()


def read_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def load_helper_module() -> Any:
    helper_path = ROOT / "scripts" / "task6" / "check_full_vocab_rowwise_topk_contract.py"
    spec = importlib.util.spec_from_file_location("task6_topk_helper", helper_path)
    if spec is None or spec.loader is None:
        raise SystemExit(f"unable to load helper from {helper_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def byte_to_signed(value: int) -> int:
    return value - 256 if value >= 128 else value


def row_offset(token: int, contract: dict[str, Any]) -> int:
    image = contract["ddr3_linear_image"]
    row_bytes = contract["row_format"]["row_bytes"]
    rows_per_group = image["rows_per_group"]
    group = token // rows_per_group
    row_in_group = token % rows_per_group
    return group * image["group_bytes"] + row_in_group * row_bytes


def parse_hidden_q_hex(value: str, hidden_size: int) -> list[int]:
    data = bytes.fromhex(value.strip().replace("_", "").replace(" ", ""))
    if len(data) != hidden_size:
        raise SystemExit(f"--hidden-q-hex decoded to {len(data)} bytes, expected {hidden_size}")
    return [byte_to_signed(byte) for byte in data]


def scan_rowstream_top1(
    image: bytes,
    contract: dict[str, Any],
    hidden_q: list[int],
) -> tuple[int, int, int, int]:
    vocab_size = contract["model"]["vocab_size"]
    hidden_size = contract["model"]["hidden_size"]
    row_bytes = contract["row_format"]["row_bytes"]
    if len(hidden_q) != hidden_size:
        raise SystemExit(f"hidden vector has {len(hidden_q)} entries, expected {hidden_size}")

    best_token = 0xFFFF
    best_score = -(1 << 45)
    reserved_nonzero_count = 0
    rows_scanned = 0

    for token in range(vocab_size):
        offset = row_offset(token, contract)
        row = image[offset : offset + row_bytes]
        if len(row) != row_bytes:
            raise SystemExit(f"short row {token} at offset {offset}: got {len(row)} bytes")
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
        rows_scanned += 1

    return best_token, best_score, rows_scanned, reserved_nonzero_count


def build_sample_hidden_vectors(
    *,
    model_path: Path,
    adapter_path: Path,
    sample_count: int,
) -> list[dict[str, Any]]:
    helper = load_helper_module()
    import torch

    build_model = helper.load_adapter_build_model(adapter_path)
    model = build_model(str(model_path)).eval()
    samples = helper.DEFAULT_SAMPLES[:sample_count]
    payloads: list[dict[str, Any]] = []

    with torch.no_grad():
        for sample_id, token_ids in samples:
            input_ids = torch.tensor([token_ids], dtype=torch.long)
            transformer_out = model.transformer(input_ids=input_ids, use_cache=False)
            hidden = transformer_out.last_hidden_state[0, -1].detach().cpu().to(torch.float64)
            hidden_q_tensor, hidden_scale = helper.quantize_symmetric_tensor(hidden)
            payloads.append(
                {
                    "sample_id": sample_id,
                    "token_ids": token_ids,
                    "hidden_scale": hidden_scale,
                    "hidden_q": [int(value) for value in hidden_q_tensor.cpu().tolist()],
                }
            )
    return payloads


def main() -> int:
    args = parse_args()
    contract = read_json(args.contract_json)
    replay = read_json(args.replay_json)
    expected_size = contract["ddr3_linear_image"]["padded_stream_bytes"]
    source_image = args.rowstream_bin.read_bytes()
    image_path = args.readback_bin or args.rowstream_bin
    image = image_path.read_bytes()
    if len(source_image) != expected_size:
        raise SystemExit(f"source rowstream has {len(source_image)} bytes, expected {expected_size}")
    if len(image) != expected_size:
        raise SystemExit(f"top1 image has {len(image)} bytes, expected {expected_size}")

    hidden_size = contract["model"]["hidden_size"]
    if args.hidden_q_hex:
        sample_payloads = [
            {
                "sample_id": "host_hidden_q_hex",
                "token_ids": None,
                "hidden_scale": None,
                "hidden_q": parse_hidden_q_hex(args.hidden_q_hex, hidden_size),
            }
        ]
    else:
        if args.model_path is None:
            raise SystemExit("--model-path is required unless --hidden-q-hex is supplied")
        sample_payloads = build_sample_hidden_vectors(
            model_path=args.model_path,
            adapter_path=args.adapter_path,
            sample_count=args.sample_count,
        )

    replay_by_sample = {entry["sample_id"]: entry for entry in replay.get("samples", [])}
    samples = []
    mismatch_count = 0
    reserved_nonzero_count = 0
    for payload in sample_payloads:
        token, score, rows_scanned, sample_reserved = scan_rowstream_top1(
            image, contract, payload["hidden_q"]
        )
        reserved_nonzero_count += sample_reserved
        expected = None
        matches_expected = None
        if payload["sample_id"] in replay_by_sample:
            expected = replay_by_sample[payload["sample_id"]]["rowwise_q024_top5"][0]
            matches_expected = token == expected
            mismatch_count += int(not matches_expected)
        samples.append(
            {
                "sample_id": payload["sample_id"],
                "token_ids": payload["token_ids"],
                "hidden_scale": payload["hidden_scale"],
                "top1_token": token,
                "top1_score_q024": score,
                "rows_scanned": rows_scanned,
                "reserved_nonzero_count": sample_reserved,
                "expected_replay_top1_token": expected,
                "matches_expected_replay_top1": matches_expected,
            }
        )

    source_sha = hashlib.sha256(source_image).hexdigest()
    image_sha = hashlib.sha256(image).hexdigest()
    hash_match = image_sha == source_sha
    status = "PASS" if mismatch_count == 0 and reserved_nonzero_count == 0 and hash_match else "FAIL"
    result = {
        "artifact_name": "task6-rowstream-top1-host-gate",
        "status": status,
        "date": dt.date.today().isoformat(),
        "rowstream": {
            "source_path": str(args.rowstream_bin),
            "top1_image_path": str(image_path),
            "bytes": len(image),
            "source_sha256": source_sha,
            "top1_image_sha256": image_sha,
            "source_matches_top1_image": hash_match,
        },
        "model": {
            "model_label": contract["model"].get("model_label"),
            "vocab_size": contract["model"]["vocab_size"],
            "hidden_size": hidden_size,
            "sample_count": len(samples),
        },
        "validation": {
            "mismatch_count": mismatch_count,
            "reserved_nonzero_count": reserved_nonzero_count,
            "board_readback_used": args.readback_bin is not None,
            "hardware_top1_used": False,
        },
        "samples": samples,
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    if args.json_only:
        print(json.dumps(result, sort_keys=True))
    else:
        print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if status == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
