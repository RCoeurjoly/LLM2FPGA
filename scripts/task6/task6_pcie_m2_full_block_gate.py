#!/usr/bin/env python3
"""Task 6 PCIe-visible M2 one-full-block replay accelerator gate."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import mmap
import os
from pathlib import Path
import re
import struct
import subprocess
import time
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUT = ROOT / "artifacts" / "task6" / "runs" / "m2-full-block-board-summary.json"
BAR_SIZE = 4096
ALL_ONES = 0xFFFFFFFF
TASK6_MAGIC = 0x54365043
TASK6_VERSION = 3
M2_MAGIC = 0x54364D32
M2_VERSION = 1

REG_MAGIC = 0x000
REG_VERSION = 0x004
REG_STATUS = 0x008
REG_M2_MAGIC = 0x500
REG_M2_VERSION = 0x504
REG_M2_PRESENT = 0x508
REG_M2_CONTROL_STATUS = 0x50C
REG_M2_START_COUNT = 0x510
REG_M2_CYCLE_COUNT = 0x514
REG_M2_OUTPUT_CHECKSUM = 0x518
REG_M2_OUTPUT_COUNT = 0x51C
REG_M2_INPUT = 0x540
REG_M2_RESIDUAL = 0x580
REG_M2_OUTPUT_SAMPLE0 = 0x5C0
REG_M2_OUTPUT_SAMPLE1 = 0x5C4
REG_M2_DEBUG = 0x5C8
REG_M2_DEBUG1 = 0x5CC
REG_M2_DEBUG2 = 0x5D0
REG_M2_PROVENANCE = 0x5D4
REG_M2_DEBUG3 = 0x5D8
REG_M2_OUTPUT_VECTOR = 0x600

M2_READY_BIT = 0
M2_BUSY_BIT = 1
M2_ERROR_BIT = 2
M2_OUTPUT_VALID_BIT = 3
M2_STATE_SHIFT = 4
M2_STATE_MASK = 0x7
M2_STATE_DONE = 0x5
M2_STATE_ERROR = 0x6

STATUS_SCHEMA = {
    "ready": M2_READY_BIT,
    "busy": M2_BUSY_BIT,
    "error": M2_ERROR_BIT,
    "output_valid": M2_OUTPUT_VALID_BIT,
    "state_lsb": M2_STATE_SHIFT,
    "state_width": 3,
    "magic_lsb": 16,
    "magic_value": 0x4D32,
}

CONTRACT = {
    "version": "task6-m2-full-block-pcie-wrapper-v4",
    "stage": "M2-full-block-pcie-wrapper",
    "milestone_target": "M2-one-full-block",
    "live_compute": False,
    "artifact_role": "pcie-bar-full-block-candidate-gate",
    "responsibilities": {
        "host": [
            "prompt/model artifact orchestration",
            "PCIe lifecycle/recovery orchestration",
            "M2 contract selection, input-boundary selection, and final vector comparison",
        ],
        "fpga": [
            "host-started fixture or token-ID selected M2 one-block candidate",
            "token-mode RTL embedding/position add, live K/V attention context, attention out projection, LN2, MLP, and final residual lane",
            "BAR-visible status/checksum/sample/full 64-byte final output",
            "debug/provenance words for stale-bitstream and full-block failure triage",
        ],
    },
    "notes": (
        "This gate validates a BAR-visible M2 one-block wrapper. With only "
        "--tb-data-sv it validates the legacy fixture-selected wrapper; with "
        "--embedding-tb-data-sv it validates the token-ID embedding/position-add "
        "wrapper and requires matching provenance."
    ),
}

CONTRACT_TOKEN_LIVE = {
    "version": "task6-m2-token-id-live-full-block-v1",
    "stage": "M2-one-full-block",
    "milestone_target": "M2-one-full-block",
    "live_compute": True,
    "artifact_role": "m2-live-full-block-board-gate",
    "responsibilities": {
        "host": [
            "prompt token/control input",
            "PCIe lifecycle orchestration",
            "final vector comparison against fixed-point TinyStories block reference",
        ],
        "fpga": [
            "token-ID selected embedding and position add",
            "live K/V attention context for one complete TinyStories transformer block",
            "attention out projection, LN2, MLP, and final residual",
            "BAR-visible status/checksum/sample/full 64-byte final output",
        ],
    },
    "notes": (
        "Board executes one complete TinyStories transformer block from "
        "host-supplied token IDs and block_index=0 control input."
    ),
}

SV_ASSIGN_RE = re.compile(
    r"^\s*(?P<name>[A-Za-z0-9_]+)\[(?P<index>\d+)\]\s*=\s*"
    r"(?P<sign>-?)(?P<bits>\d+)'sd(?P<value>\d+)\s*;"
)
SV_LOCALPARAM_HEX_RE = re.compile(
    r"^\s*localparam\s+logic\s+\[31:0\]\s+"
    r"(?P<name>[A-Za-z0-9_]+)\s*=\s*32'h(?P<value>[0-9a-fA-F]+)\s*;"
)
SV_LOCALPARAM_INT_RE = re.compile(
    r"^\s*localparam\s+int\s+(?P<name>[A-Za-z0-9_]+)\s*=\s*(?P<value>\d+)\s*;"
)
SV_TOKEN_ID_RE = re.compile(
    r"^\s*embed_block_expected_token_ids\[(?P<index>\d+)\]\s*=\s*16'd(?P<value>\d+)\s*;"
)
SV_EMBED_LN_INPUT_RE = re.compile(
    r"^\s*embed_block_expected_ln_input_q12_by_token"
    r"\[(?P<token>\d+)\]\[(?P<dim>\d+)\]\s*=\s*"
    r"(?P<sign>-?)(?P<bits>\d+)'sd(?P<value>\d+)\s*;"
)


def run(cmd: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, check=check, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def rd32(mm: mmap.mmap, offset: int) -> int:
    return struct.unpack(">I", bytes(mm[offset : offset + 4]))[0]


def rd32_window(mm: mmap.mmap, offset: int) -> int:
    window_base = offset & ~0x3F
    word_offset = offset - window_base
    window = bytes(mm[window_base : window_base + 64])
    return struct.unpack(">I", window[word_offset : word_offset + 4])[0]


def sample_registers(
    read32,
    offsets: dict[str, int],
    *,
    samples: int,
    interval: float,
) -> tuple[dict[str, int], dict[str, list[int]], dict[str, bool]]:
    if samples < 1:
        raise SystemExit("--preflight-samples must be at least 1")
    observed_samples: dict[str, list[int]] = {name: [] for name in offsets}
    for sample_index in range(samples):
        for name, offset in offsets.items():
            observed_samples[name].append(read32(offset))
        if sample_index + 1 < samples and interval > 0:
            time.sleep(interval)
    stable = {
        name: all(value == values[0] for value in values)
        for name, values in observed_samples.items()
    }
    values = {name: values[-1] for name, values in observed_samples.items()}
    return values, observed_samples, stable


def wr32(mm: mmap.mmap, offset: int, value: int) -> None:
    mm[offset : offset + 4] = struct.pack(">I", value & 0xFFFFFFFF)
    _ = mm[0:4]


def pcie7x_rotate64_compensate_bar_vector_words(words: list[int]) -> list[int]:
    if len(words) != 16:
        raise SystemExit(f"vector must contain 16 words, got {len(words)}")
    compensated: list[int] = []
    for index in range(0, len(words), 2):
        pair = ((words[index + 1] & 0xFFFFFFFF) << 32) | (words[index] & 0xFFFFFFFF)
        rotated = ((pair << 1) | (pair >> 63)) & 0xFFFFFFFFFFFFFFFF
        compensated.append(rotated & 0xFFFFFFFF)
        compensated.append((rotated >> 32) & 0xFFFFFFFF)
    return compensated


def write_vector(mm: mmap.mmap, base: int, data: bytes, *, mode: str) -> tuple[list[int], list[int]]:
    if len(data) != 64:
        raise SystemExit(f"vector must be exactly 64 bytes, got {len(data)}")
    words = []
    for index in range(16):
        word = int.from_bytes(data[index * 4 : index * 4 + 4], "little")
        words.append(word)
    if mode in ("direct", "raw-internal"):
        write_words = words
    elif mode in ("legacy-rotated", "readback-compensated"):
        write_words = pcie7x_rotate64_compensate_bar_vector_words(words)
    else:
        raise SystemExit(f"unknown vector write mode: {mode}")
    for index, word in enumerate(write_words):
        wr32(mm, base + index * 4, word)
    return words, write_words


def read_vector(mm: mmap.mmap, base: int) -> bytes:
    return b"".join(rd32_window(mm, base + index * 4).to_bytes(4, "little") for index in range(16))


def wait_vector_readback(
    mm: mmap.mmap,
    base: int,
    expected: bytes,
    *,
    timeout: float,
    poll_interval: float,
) -> bytes:
    deadline = time.monotonic() + timeout
    observed = read_vector(mm, base)
    while observed != expected and time.monotonic() < deadline:
        time.sleep(poll_interval)
        observed = read_vector(mm, base)
    return observed


def decode_debug(debug: int, debug1: int = 0, debug2: int = 0) -> dict[str, Any]:
    stage = (debug >> 24) & 0xFF
    detail = debug & 0x00FF_FFFF
    decoded: dict[str, Any] = {
        "stage": f"0x{stage:02x}",
        "detail": f"0x{detail:06x}",
    }
    if stage == 0x01:
        decoded["meaning"] = "embedding token-id mismatch"
        decoded["token_index"] = (debug >> 16) & 0xF
        decoded["observed_token_id"] = f"0x{debug & 0xFFFF:04x}"
    elif stage == 0x02:
        decoded["meaning"] = "embedding ln-input mismatch"
        decoded["token_index"] = (debug >> 20) & 0xF
        decoded["dim_index"] = (debug >> 8) & 0xFF
    elif stage == 0x03:
        decoded["meaning"] = "embedding block-input mismatch"
        decoded["dim_index"] = (debug >> 8) & 0xFF
        decoded["observed_q"] = f"0x{debug & 0xFF:02x}"
    elif stage in (0xE0, 0xE1):
        substage = (detail >> 16) & 0xFF
        decoded["substage"] = f"0x{substage:02x}"
    elif 0xC0 <= stage <= 0xCF:
        context_stage = stage & 0x0F
        decoded["meaning"] = "live-context context substage mismatch"
        decoded["context_stage"] = f"0x{context_stage:02x}"
        if context_stage == 0x01:
            decoded["context_meaning"] = "LN output mismatch"
            decoded["ln_index"] = (debug >> 18) & 0x3F
            decoded["expected_q"] = f"0x{(debug >> 10) & 0xFF:02x}"
            decoded["observed_q"] = f"0x{debug & 0xFF:02x}"
            ln_debug_words = [
                (debug1 >> 16) & 0xFFFF,
                debug1 & 0xFFFF,
                (debug2 >> 16) & 0xFFFF,
                debug2 & 0xFFFF,
            ]
            ln_debug_signed = [
                word - 0x10000 if word & 0x8000 else word for word in ln_debug_words
            ]
            decoded["ln_intermediate_hex"] = {
                "mean_q12": f"0x{ln_debug_words[0]:04x}",
                "centered_q12": f"0x{ln_debug_words[1]:04x}",
                "norm_q12": f"0x{ln_debug_words[2]:04x}",
                "affine_q12": f"0x{ln_debug_words[3]:04x}",
            }
            decoded["ln_intermediate_signed"] = {
                "mean_q12": ln_debug_signed[0],
                "centered_q12": ln_debug_signed[1],
                "norm_q12": ln_debug_signed[2],
                "affine_q12": ln_debug_signed[3],
            }
        elif context_stage in (0x02, 0x03, 0x04, 0x09):
            context_names = {
                0x02: "K projection mismatch",
                0x03: "V projection mismatch",
                0x04: "Q projection mismatch",
                0x09: "context output mismatch",
            }
            decoded["context_meaning"] = context_names[context_stage]
            decoded["head_index"] = (debug >> 20) & 0xF
            decoded["dim_index"] = (debug >> 16) & 0xF
            decoded["observed_q"] = f"0x{debug & 0xFF:02x}"
        elif context_stage in (0x05, 0x06, 0x07, 0x08):
            context_names = {
                0x05: "attention score mismatch",
                0x06: "attention value mismatch",
                0x07: "softmax weight mismatch",
                0x08: "softmax probability mismatch",
            }
            decoded["context_meaning"] = context_names[context_stage]
            decoded["head_index"] = (debug >> 20) & 0xF
            decoded["index"] = (debug >> 16) & 0xF
            decoded["observed_value"] = f"0x{debug & 0xFFFF:04x}"
    elif 0xA0 <= stage <= 0xAF:
        decoded["meaning"] = "attention out-projection substage mismatch"
        decoded["attention_stage"] = f"0x{stage & 0x0F:02x}"
    elif 0xB0 <= stage <= 0xBF:
        decoded["meaning"] = "MLP substage mismatch"
        decoded["mlp_stage"] = f"0x{stage & 0x0F:02x}"
    if debug1 or debug2:
        decoded["debug1"] = f"0x{debug1:08x}"
        decoded["debug2"] = f"0x{debug2:08x}"
        decoded["error_core_status"] = f"0x{debug1:08x}"
        decoded["error_core_cycle_count"] = debug2
    return decoded


def decode_done_stage_checksums(debug1: int, debug2: int) -> dict[str, Any]:
    return {
        "block_input_checksum_low16": f"0x{(debug1 >> 16) & 0xFFFF:04x}",
        "context_checksum_low16": f"0x{debug1 & 0xFFFF:04x}",
        "attn_out_checksum_low8": f"0x{(debug2 >> 24) & 0xFF:02x}",
        "attn_residual_checksum_low8": f"0x{(debug2 >> 16) & 0xFF:02x}",
        "ln2_checksum_low8": f"0x{(debug2 >> 8) & 0xFF:02x}",
        "c_proj_checksum_low8": f"0x{debug2 & 0xFF:02x}",
    }


def compare_done_stage_checksums(
    observed_debug1: int,
    observed_debug2: int,
    expected_debug1: int,
    expected_debug2: int,
) -> dict[str, Any]:
    observed = decode_done_stage_checksums(observed_debug1, observed_debug2)
    expected = decode_done_stage_checksums(expected_debug1, expected_debug2)
    matches = {key: observed[key] == expected[key] for key in observed}
    first_mismatch = next((key for key, ok in matches.items() if not ok), None)
    return {
        "observed": observed,
        "expected": expected,
        "matches": matches,
        "first_mismatch": first_mismatch,
        "all_match": first_mismatch is None,
    }


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path | None) -> str | None:
    if path is None:
        return None
    return sha256_bytes(path.read_bytes())


def parse_hex_vector(text: str, *, name: str) -> bytes:
    cleaned = text.strip().removeprefix("0x").replace("_", "").replace(" ", "")
    try:
        data = bytes.fromhex(cleaned)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(f"{name} is not valid hex: {exc}") from exc
    if len(data) != 64:
        raise argparse.ArgumentTypeError(f"{name} must encode exactly 64 bytes, got {len(data)}")
    return data


def parse_expected_json(path: Path) -> dict[str, int | bytes]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    expected: dict[str, int | bytes] = {}
    for json_key, out_key in (
        ("expected_checksum", "checksum"),
        ("expected_sample0", "sample0"),
        ("expected_sample1", "sample1"),
        ("output_count", "output_count"),
    ):
        value = payload.get(json_key)
        if value is not None:
            expected[out_key] = int(value)
    first_64_hex = payload.get("first_64_output_hex")
    if first_64_hex is not None:
        first_64 = bytes.fromhex(str(first_64_hex))
        if len(first_64) != 64:
            raise SystemExit(f"{path} first_64_output_hex must encode 64 bytes")
        expected["first_64_output"] = first_64
    return expected


def parse_signed_sv_literal(sign: str, value: str) -> int:
    parsed = int(value)
    return -parsed if sign == "-" else parsed


def parse_expected_tb_data_sv(path: Path) -> dict[str, int | bytes | list[int]]:
    localparams: dict[str, int] = {}
    int_params: dict[str, int] = {}
    final_q: dict[int, int] = {}
    block_input_q: dict[int, int] = {}
    context_q: dict[int, int] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        int_match = SV_LOCALPARAM_INT_RE.match(line)
        if int_match is not None:
            int_params[int_match.group("name")] = int(int_match.group("value"))
            continue
        param_match = SV_LOCALPARAM_HEX_RE.match(line)
        if param_match is not None:
            localparams[param_match.group("name")] = int(param_match.group("value"), 16)
            continue
        assign_match = SV_ASSIGN_RE.match(line)
        if assign_match is None:
            continue
        if assign_match.group("name") == "mlp_final_expected_q":
            final_q[int(assign_match.group("index"))] = parse_signed_sv_literal(
                assign_match.group("sign"),
                assign_match.group("value"),
            )
        elif assign_match.group("name") == "out_proj_block_input_q":
            block_input_q[int(assign_match.group("index"))] = parse_signed_sv_literal(
                assign_match.group("sign"),
                assign_match.group("value"),
            )
        elif assign_match.group("name") == "out_proj_context_q":
            context_q[int(assign_match.group("index"))] = parse_signed_sv_literal(
                assign_match.group("sign"),
                assign_match.group("value"),
            )

    missing_params = [
        name
        for name in (
            "MLP_FINAL_EXPECTED_CHECKSUM",
            "MLP_FINAL_EXPECTED_SAMPLE0",
            "MLP_FINAL_EXPECTED_SAMPLE1",
        )
        if name not in localparams
    ]
    if missing_params:
        raise SystemExit(f"{path} missing localparam(s): {', '.join(missing_params)}")
    missing_final = [index for index in range(64) if index not in final_q]
    if missing_final:
        raise SystemExit(f"{path} missing mlp_final_expected_q index(es): {missing_final[:8]}")
    missing_block_input = [index for index in range(64) if index not in block_input_q]
    if missing_block_input:
        raise SystemExit(f"{path} missing out_proj_block_input_q index(es): {missing_block_input[:8]}")
    missing_context = [index for index in range(64) if index not in context_q]
    if missing_context:
        raise SystemExit(f"{path} missing out_proj_context_q index(es): {missing_context[:8]}")

    first_64_output = bytes(final_q[index] & 0xFF for index in range(64))
    fixture_block_input = bytes(block_input_q[index] & 0xFF for index in range(64))
    fixture_context = bytes(context_q[index] & 0xFF for index in range(64))
    return {
        "checksum": localparams["MLP_FINAL_EXPECTED_CHECKSUM"],
        "sample0": localparams["MLP_FINAL_EXPECTED_SAMPLE0"],
        "sample1": localparams["MLP_FINAL_EXPECTED_SAMPLE1"],
        "output_count": 64,
        "first_64_output": first_64_output,
        "fixture_block_input": fixture_block_input,
        "fixture_context": fixture_context,
        "token_index": int_params.get("M2_FULL_BLOCK_TOKEN_INDEX", 0),
        "provenance_mode": 0x2000,
    }


def parse_embedding_tb_data_sv(path: Path) -> dict[str, int | bytes | list[int]]:
    token_ids: dict[int, int] = {}
    ln_input_q12: dict[tuple[int, int], int] = {}
    embed_block_seq = 6
    embed_block_dim = 64
    for line in path.read_text(encoding="utf-8").splitlines():
        int_match = SV_LOCALPARAM_INT_RE.match(line)
        if int_match is not None:
            if int_match.group("name") == "EMBED_BLOCK_SEQ":
                embed_block_seq = int(int_match.group("value"))
            elif int_match.group("name") == "EMBED_BLOCK_DIM":
                embed_block_dim = int(int_match.group("value"))
            continue
        token_match = SV_TOKEN_ID_RE.match(line)
        if token_match:
            token_ids[int(token_match.group("index"))] = int(token_match.group("value"))
            continue
        ln_match = SV_EMBED_LN_INPUT_RE.match(line)
        if ln_match:
            ln_input_q12[
                (int(ln_match.group("token")), int(ln_match.group("dim")))
            ] = parse_signed_sv_literal(ln_match.group("sign"), ln_match.group("value"))
            continue
        assign_match = SV_ASSIGN_RE.match(line)
        if assign_match and assign_match.group("name") == "embed_block_expected_token_ids":
            token_ids[int(assign_match.group("index"))] = parse_signed_sv_literal(
                assign_match.group("sign"),
                assign_match.group("value"),
            )
    missing = [index for index in range(embed_block_seq) if index not in token_ids]
    if missing:
        raise SystemExit(f"{path} missing embed_block_expected_token_ids index(es): {missing[:8]}")
    missing_ln_input = [
        (token, dim)
        for token in range(embed_block_seq)
        for dim in range(embed_block_dim)
        if (token, dim) not in ln_input_q12
    ]
    if missing_ln_input:
        raise SystemExit(
            f"{path} missing embed_block_expected_ln_input_q12_by_token index(es): {missing_ln_input[:8]}"
        )
    token_id_list = [token_ids[index] for index in range(embed_block_seq)]
    token_input = bytearray(64)
    for index, token_id in enumerate(token_id_list):
        if token_id < 0 or token_id > 0xFFFF:
            raise SystemExit(f"{path} token id {token_id} does not fit 16 bits")
        token_input[index * 2 : index * 2 + 2] = int(token_id).to_bytes(2, "little")
    ln_input_checksum = 0
    for token in range(embed_block_seq):
        for dim in range(embed_block_dim):
            flat_index = token * embed_block_dim + dim
            ln_input_checksum = (
                ln_input_checksum + ((ln_input_q12[(token, dim)] & 0xFFFF) * (flat_index + 1))
            ) & 0xFFFFFFFF
    return {
        "token_input": bytes(token_input),
        "reserved_input": bytes(64),
        "token_ids": token_id_list,
        "ln_input_checksum": ln_input_checksum,
        "provenance_mode": 0x3000,
    }


def validate_expected(expected: dict[str, int | bytes | list[int]], path: Path) -> None:
    missing = [
        key
        for key in ("checksum", "sample0", "sample1", "output_count", "first_64_output")
        if key not in expected
    ]
    if missing:
        raise SystemExit(f"{path} missing expected field(s): {', '.join(missing)}")


def decode_status(status: int) -> dict[str, Any]:
    state = (status >> M2_STATE_SHIFT) & M2_STATE_MASK
    magic = (status >> STATUS_SCHEMA["magic_lsb"]) & 0xFFFF
    names = {
        0x0: "IDLE",
        0x1: "M2_START",
        0x2: "M2_ARM",
        0x3: "M2_RUN",
        0x4: "M2_LATCH",
        0x5: "DONE",
        0x6: "ERROR",
    }
    return {
        "state": state,
        "state_name": names.get(state, "UNKNOWN"),
        "ready": bool(status & (1 << M2_READY_BIT)),
        "busy": bool(status & (1 << M2_BUSY_BIT)),
        "error": bool(status & (1 << M2_ERROR_BIT)) or state == M2_STATE_ERROR,
        "output_valid": bool(status & (1 << M2_OUTPUT_VALID_BIT)),
        "done": state == M2_STATE_DONE,
        "magic": magic,
        "schema": STATUS_SCHEMA,
        "schema_consistent": magic == STATUS_SCHEMA["magic_value"]
        and not (state == M2_STATE_DONE and bool(status & (1 << M2_BUSY_BIT)))
        and not (state == M2_STATE_DONE and not bool(status & (1 << M2_READY_BIT)))
        and not (state == M2_STATE_DONE and not bool(status & (1 << M2_OUTPUT_VALID_BIT))),
    }


def expected_provenance(expected: dict[str, int | bytes | list[int]]) -> int:
    token_index = int(expected.get("token_index", 0))
    provenance_mode = int(expected.get("provenance_mode", 0x2000))
    return 0x4D32_0000 | (provenance_mode & 0xFF00) | (token_index & 0xFF)


def is_token_live_mode(expected: dict[str, int | bytes | list[int]]) -> bool:
    return int(expected.get("provenance_mode", 0)) == 0x3000 and isinstance(expected.get("token_ids"), list)


def contract_for_expected(expected: dict[str, int | bytes | list[int]]) -> dict[str, Any]:
    return CONTRACT_TOKEN_LIVE if is_token_live_mode(expected) else CONTRACT


def compute_path_for_expected(expected: dict[str, int | bytes | list[int]]) -> str:
    return "live-full-block" if is_token_live_mode(expected) else "fixture-full-block-wrapper"


def select_host_vectors(
    expected: dict[str, int | bytes | list[int]],
    *,
    input_hex: str | None,
    residual_hex: str | None,
) -> tuple[bytes, bytes, str, str]:
    if is_token_live_mode(expected):
        if input_hex is not None or residual_hex is not None:
            raise SystemExit(
                "token-live mode from --embedding-tb-data-sv does not allow "
                "--input-hex or --residual-hex overrides"
            )
        token_input = expected.get("token_input")
        reserved_input = expected.get("reserved_input")
        if not isinstance(token_input, bytes) or len(token_input) != 64:
            raise SystemExit("token-live mode missing 64-byte token_input")
        if not isinstance(reserved_input, bytes) or len(reserved_input) != 64:
            raise SystemExit("token-live mode missing 64-byte reserved_input")
        return (
            token_input,
            reserved_input,
            "embedding_tb_data_sv token_ids",
            "embedding_tb_data_sv reserved token-control vector",
        )

    if input_hex is not None:
        block_input = parse_hex_vector(input_hex, name="input")
        block_input_source = "explicit --input-hex"
    elif "fixture_block_input" in expected:
        fixture_block_input = expected["fixture_block_input"]
        if not isinstance(fixture_block_input, bytes):
            raise SystemExit("fixture mode fixture_block_input must be bytes")
        block_input = fixture_block_input
        block_input_source = "tb_data_sv out_proj_block_input_q"
    else:
        block_input = bytes(64)
        block_input_source = "zero default"

    if residual_hex is not None:
        residual = parse_hex_vector(residual_hex, name="residual")
        residual_source = "explicit --residual-hex"
    elif "fixture_context" in expected:
        fixture_context = expected["fixture_context"]
        if not isinstance(fixture_context, bytes):
            raise SystemExit("fixture mode fixture_context must be bytes")
        residual = fixture_context
        residual_source = "tb_data_sv out_proj_context_q"
    else:
        residual = bytes(64)
        residual_source = "zero default"

    return block_input, residual, block_input_source, residual_source


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bdf", help="PCI BDF, for example 0000:42:00.0")
    parser.add_argument("--json-out", type=Path, default=DEFAULT_OUT)
    parser.add_argument(
        "--expected-json",
        type=Path,
        help="Generated M2 full-block replay summary JSON matching the bitstream",
    )
    parser.add_argument(
        "--tb-data-sv",
        type=Path,
        help="Generated first-token full-block tb_data.sv matching the bitstream",
    )
    parser.add_argument(
        "--embedding-tb-data-sv",
        type=Path,
        help=(
            "Generated embedding block-input constants matching a token-ID "
            "M2 bitstream. Requires --tb-data-sv for final-vector expectations "
            "and switches the BAR input aperture to six little-endian uint16 "
            "token IDs."
        ),
    )
    parser.add_argument("--expect-checksum", type=lambda text: int(text, 0))
    parser.add_argument("--expect-sample0", type=lambda text: int(text, 0))
    parser.add_argument("--expect-sample1", type=lambda text: int(text, 0))
    parser.add_argument("--expect-output-count", type=lambda text: int(text, 0))
    parser.add_argument(
        "--expect-debug1",
        type=lambda text: int(text, 0),
        help="Expected DONE-state M2 debug1 word, usually from a matching sim log",
    )
    parser.add_argument(
        "--expect-debug2",
        type=lambda text: int(text, 0),
        help="Expected DONE-state M2 debug2 word, usually from a matching sim log",
    )
    parser.add_argument(
        "--input-hex",
        help=(
            "64-byte block input vector as hex. With --tb-data-sv, defaults to "
            "the fixture out_proj_block_input_q vector so the host-visible input "
            "matches the bitstream contract."
        ),
    )
    parser.add_argument(
        "--residual-hex",
        help=(
            "64-byte external attention context vector as hex. With --tb-data-sv, "
            "defaults to the fixture out_proj_context_q vector so the host-visible "
            "context input matches the bitstream contract."
        ),
    )
    parser.add_argument("--timeout", type=float, default=2.0)
    parser.add_argument("--poll-interval", type=float, default=0.001)
    parser.add_argument(
        "--vector-write-mode",
        choices=("direct", "legacy-rotated", "raw-internal", "readback-compensated"),
        default="direct",
        help=(
            "M2 vector BAR write strategy. direct is the normal acceptance "
            "contract and requires write/readback identity. raw-internal is a "
            "deprecated alias for direct. legacy-rotated/readback-compensated "
            "apply the measured pcie_7x 64-bit lane-rotate compensation and "
            "are diagnostic only."
        ),
    )
    parser.add_argument(
        "--preflight-samples",
        type=int,
        default=3,
        help=(
            "Number of pre-start register samples required to be stable before "
            "issuing M2 clear/start. This catches transient all-ones BAR reads "
            "without starting the accelerator."
        ),
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if (args.expected_json is None) == (args.tb_data_sv is None):
        raise SystemExit("provide exactly one of --expected-json or --tb-data-sv")
    if args.embedding_tb_data_sv is not None and args.tb_data_sv is None:
        raise SystemExit("--embedding-tb-data-sv requires --tb-data-sv")
    expected_source = args.expected_json if args.expected_json is not None else args.tb_data_sv
    assert expected_source is not None
    expected = (
        parse_expected_json(args.expected_json)
        if args.expected_json is not None
        else parse_expected_tb_data_sv(args.tb_data_sv)
    )
    if args.embedding_tb_data_sv is not None:
        expected.update(parse_embedding_tb_data_sv(args.embedding_tb_data_sv))
    if args.expect_checksum is not None:
        expected["checksum"] = args.expect_checksum
    if args.expect_sample0 is not None:
        expected["sample0"] = args.expect_sample0
    if args.expect_sample1 is not None:
        expected["sample1"] = args.expect_sample1
    if args.expect_output_count is not None:
        expected["output_count"] = args.expect_output_count
    if (args.expect_debug1 is None) != (args.expect_debug2 is None):
        raise SystemExit("--expect-debug1 and --expect-debug2 must be provided together")
    validate_expected(expected, expected_source)

    block_input, residual, block_input_source, residual_source = select_host_vectors(
        expected,
        input_hex=args.input_hex,
        residual_hex=args.residual_hex,
    )
    result_contract = contract_for_expected(expected)
    compute_path = compute_path_for_expected(expected)

    device = Path("/sys/bus/pci/devices") / args.bdf
    resource0 = device / "resource0"
    if not resource0.exists():
        raise SystemExit(f"missing BAR0 sysfs resource: {resource0}")

    lspci = run(["lspci", "-s", args.bdf]).stdout.strip()
    command = run(["setpci", "-s", args.bdf, "COMMAND"]).stdout.strip()
    started = time.monotonic()

    fd = os.open(resource0, os.O_RDWR | os.O_SYNC)
    try:
        with mmap.mmap(fd, BAR_SIZE, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE) as mm:
            preflight_offsets = {
                "magic": REG_MAGIC,
                "version": REG_VERSION,
                "status": REG_STATUS,
                "m2_magic": REG_M2_MAGIC,
                "m2_version": REG_M2_VERSION,
                "m2_present": REG_M2_PRESENT,
                "m2_provenance": REG_M2_PROVENANCE,
            }
            preflight_values, preflight_samples, preflight_stable = sample_registers(
                lambda offset: rd32_window(mm, offset),
                preflight_offsets,
                samples=args.preflight_samples,
                interval=args.poll_interval,
            )
            magic = preflight_values["magic"]
            version = preflight_values["version"]
            status = preflight_values["status"]
            m2_magic = preflight_values["m2_magic"]
            m2_version = preflight_values["m2_version"]
            m2_present = preflight_values["m2_present"]
            m2_provenance = preflight_values["m2_provenance"]
            expected_m2_provenance = expected_provenance(expected)
            preflight_all_stable = all(preflight_stable.values())

            preflight_checks = {
                "preflight_registers_stable": preflight_all_stable,
                "task6_magic": magic == TASK6_MAGIC,
                "task6_version": version == TASK6_VERSION,
                "not_all_ones": all(
                    value != ALL_ONES
                    for value in (magic, version, status, m2_magic, m2_version, m2_present, m2_provenance)
                ),
                "m2_magic": m2_magic == M2_MAGIC,
                "m2_version": m2_version == M2_VERSION,
                "m2_present": m2_present == 1,
                "m2_provenance": m2_provenance == expected_m2_provenance,
            }
            if not all(preflight_checks.values()):
                result = {
                    "artifact_name": "task6-pcie-m2-full-block-board-gate",
                    "status": "FAIL",
                    "date": dt.date.today().isoformat(),
                    "contract": result_contract,
                    "bdf": args.bdf,
                    "lspci": lspci,
                    "command": command,
                    "board": {
                        "status": "FAIL",
                        "bdf": args.bdf,
                        "lspci": lspci,
                        "pcie_command": command,
                    },
                    "elapsed_seconds": time.monotonic() - started,
                    "registers": {
                        "magic": f"0x{magic:08x}",
                        "version": version,
                        "status": f"0x{status:08x}",
                        "m2_magic": f"0x{m2_magic:08x}",
                        "m2_version": m2_version,
                        "m2_present": m2_present,
                        "m2_provenance": f"0x{m2_provenance:08x}",
                        "expected_m2_provenance": f"0x{expected_m2_provenance:08x}",
                    },
                    "preflight_samples": {
                        name: [f"0x{value:08x}" for value in values]
                        for name, values in preflight_samples.items()
                    },
                    "preflight_stable": preflight_stable,
                    "fingerprints": {
                        "gate_script_sha256": sha256_file(Path(__file__)),
                        "expected_json": str(args.expected_json) if args.expected_json else None,
                        "expected_json_sha256": sha256_file(args.expected_json),
                        "tb_data_sv": str(args.tb_data_sv) if args.tb_data_sv else None,
                        "tb_data_sv_sha256": sha256_file(args.tb_data_sv),
                        "embedding_tb_data_sv": str(args.embedding_tb_data_sv) if args.embedding_tb_data_sv else None,
                        "embedding_tb_data_sv_sha256": sha256_file(args.embedding_tb_data_sv),
                        "tb_data_token_index": expected.get("token_index") if args.tb_data_sv else None,
                        "token_ids": expected.get("token_ids"),
                    },
                    "checks": preflight_checks,
                    "failure": (
                        "preflight register/provenance check failed before issuing "
                        "M2 clear/start or vector writes"
                    ),
                }
                args.json_out.parent.mkdir(parents=True, exist_ok=True)
                args.json_out.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
                print(json.dumps(result, indent=2, sort_keys=True))
                return 1

            wr32(mm, REG_M2_CONTROL_STATUS, 0)
            wr32(mm, REG_M2_CONTROL_STATUS, 2)
            input_words, input_write_words = write_vector(
                mm,
                REG_M2_INPUT,
                block_input,
                mode=args.vector_write_mode,
            )
            residual_words, residual_write_words = write_vector(
                mm,
                REG_M2_RESIDUAL,
                residual,
                mode=args.vector_write_mode,
            )
            input_readback = wait_vector_readback(
                mm,
                REG_M2_INPUT,
                block_input,
                timeout=min(args.timeout, 0.25),
                poll_interval=args.poll_interval,
            )
            residual_readback = wait_vector_readback(
                mm,
                REG_M2_RESIDUAL,
                residual,
                timeout=min(args.timeout, 0.25),
                poll_interval=args.poll_interval,
            )
            failure = None
            strict_readback = args.vector_write_mode in ("direct", "raw-internal")
            if strict_readback and (input_readback != block_input or residual_readback != residual):
                failure = "M2 input/residual BAR readback did not match before start"
                m2_status = rd32_window(mm, REG_M2_CONTROL_STATUS)
                decoded = decode_status(m2_status)
                observed = {
                    "start_count_before": rd32_window(mm, REG_M2_START_COUNT),
                    "start_count_after": rd32_window(mm, REG_M2_START_COUNT),
                    "status": m2_status,
                    "cycle_count": rd32_window(mm, REG_M2_CYCLE_COUNT),
                    "checksum": rd32_window(mm, REG_M2_OUTPUT_CHECKSUM),
                    "output_count": rd32_window(mm, REG_M2_OUTPUT_COUNT),
                    "sample0": rd32_window(mm, REG_M2_OUTPUT_SAMPLE0),
                    "sample1": rd32_window(mm, REG_M2_OUTPUT_SAMPLE1),
                    "debug": rd32_window(mm, REG_M2_DEBUG),
                    "debug1": rd32_window(mm, REG_M2_DEBUG1),
                    "debug2": rd32_window(mm, REG_M2_DEBUG2),
                    "debug3": rd32_window(mm, REG_M2_DEBUG3),
                    "provenance": m2_provenance,
                    "expected_provenance": expected_m2_provenance,
                    "output_vector": read_vector(mm, REG_M2_OUTPUT_VECTOR),
                    "input_readback": input_readback,
                    "residual_readback": residual_readback,
                }
            else:
                wr32(mm, REG_M2_CONTROL_STATUS, 0)
                start_count_before = rd32_window(mm, REG_M2_START_COUNT)
                wr32(mm, REG_M2_CONTROL_STATUS, 1)

                deadline = time.monotonic() + args.timeout
                m2_status = rd32_window(mm, REG_M2_CONTROL_STATUS)
                decoded = decode_status(m2_status)
                while time.monotonic() < deadline:
                    m2_status = rd32_window(mm, REG_M2_CONTROL_STATUS)
                    decoded = decode_status(m2_status)
                    if decoded["done"] or decoded["error"]:
                        break
                    time.sleep(args.poll_interval)

                observed = {
                    "start_count_before": start_count_before,
                    "start_count_after": rd32_window(mm, REG_M2_START_COUNT),
                    "status": m2_status,
                    "cycle_count": rd32_window(mm, REG_M2_CYCLE_COUNT),
                    "checksum": rd32_window(mm, REG_M2_OUTPUT_CHECKSUM),
                    "output_count": rd32_window(mm, REG_M2_OUTPUT_COUNT),
                    "sample0": rd32_window(mm, REG_M2_OUTPUT_SAMPLE0),
                    "sample1": rd32_window(mm, REG_M2_OUTPUT_SAMPLE1),
                    "debug": rd32_window(mm, REG_M2_DEBUG),
                    "debug1": rd32_window(mm, REG_M2_DEBUG1),
                    "debug2": rd32_window(mm, REG_M2_DEBUG2),
                    "debug3": rd32_window(mm, REG_M2_DEBUG3),
                    "provenance": m2_provenance,
                    "expected_provenance": expected_m2_provenance,
                    "output_vector": read_vector(mm, REG_M2_OUTPUT_VECTOR),
                    "input_readback": input_readback,
                    "residual_readback": residual_readback,
                }
    finally:
        os.close(fd)

    checks = {
        "preflight_registers_stable": preflight_all_stable,
        "task6_magic": magic == TASK6_MAGIC,
        "task6_version": version == TASK6_VERSION,
        "not_all_ones": all(
            value != ALL_ONES
            for value in (magic, version, status, m2_magic, m2_version, m2_present, observed["status"])
        ),
        "m2_magic": m2_magic == M2_MAGIC,
        "m2_version": m2_version == M2_VERSION,
        "m2_present": m2_present == 1,
        "m2_provenance": observed["provenance"] == observed["expected_provenance"],
        "input_readback": args.vector_write_mode not in ("direct", "raw-internal")
        or observed["input_readback"] == block_input,
        "residual_readback": args.vector_write_mode not in ("direct", "raw-internal")
        or observed["residual_readback"] == residual,
        "status_schema": bool(decoded["schema_consistent"]),
        "start_count_incremented": observed["start_count_after"] == ((observed["start_count_before"] + 1) & 0xFFFFFFFF),
        "state_done": bool(decoded["done"]),
        "no_error": not bool(decoded["error"]),
        "output_valid": bool(decoded["output_valid"]),
        "output_count_live": observed["output_count"] != 0,
    }
    if "checksum" in expected:
        checks["checksum"] = observed["checksum"] == expected["checksum"]
    if "sample0" in expected:
        checks["sample0"] = observed["sample0"] == expected["sample0"]
    if "sample1" in expected:
        checks["sample1"] = observed["sample1"] == expected["sample1"]
    if "output_count" in expected:
        checks["output_count"] = observed["output_count"] == expected["output_count"]
    if "ln_input_checksum" in expected:
        checks["ln_input_checksum"] = observed["debug"] == expected["ln_input_checksum"]
    checks["first_64_output"] = observed["output_vector"] == expected["first_64_output"]

    result_status = "PASS" if all(checks.values()) else "FAIL"
    result: dict[str, Any] = {
        "artifact_name": "task6-pcie-m2-full-block-board-gate",
        "status": result_status,
        "date": dt.date.today().isoformat(),
        "contract": result_contract,
        "bdf": args.bdf,
        "lspci": lspci,
        "command": command,
        "board": {
            "status": result_status,
            "bdf": args.bdf,
            "lspci": lspci,
            "pcie_command": command,
        },
        "elapsed_seconds": time.monotonic() - started,
        "registers": {
            "magic": f"0x{magic:08x}",
            "version": version,
            "status": f"0x{status:08x}",
            "m2_magic": f"0x{m2_magic:08x}",
            "m2_version": m2_version,
            "m2_present": m2_present,
        },
        "preflight_samples": {
            name: [f"0x{value:08x}" for value in values]
            for name, values in preflight_samples.items()
        },
        "preflight_stable": preflight_stable,
        "fingerprints": {
            "gate_script_sha256": sha256_file(Path(__file__)),
            "expected_json": str(args.expected_json) if args.expected_json else None,
            "expected_json_sha256": sha256_file(args.expected_json),
            "tb_data_sv": str(args.tb_data_sv) if args.tb_data_sv else None,
            "tb_data_sv_sha256": sha256_file(args.tb_data_sv),
            "embedding_tb_data_sv": str(args.embedding_tb_data_sv) if args.embedding_tb_data_sv else None,
            "embedding_tb_data_sv_sha256": sha256_file(args.embedding_tb_data_sv),
            "tb_data_token_index": expected.get("token_index") if args.tb_data_sv else None,
            "token_ids": expected.get("token_ids"),
            "block_input_sha256": sha256_bytes(block_input),
            "residual_after_attention_sha256": sha256_bytes(residual),
            "block_input_source": block_input_source,
            "residual_after_attention_source": residual_source,
            "expected_params_sha256": sha256_bytes(
                json.dumps(
                    {
                        key: value.hex() if isinstance(value, bytes) else value
                        for key, value in expected.items()
                    },
                    sort_keys=True,
                    separators=(",", ":"),
                ).encode("utf-8")
            ),
        },
        "input": {
            "block_input_hex": block_input.hex(),
            "block_index": 0 if is_token_live_mode(expected) else None,
            "token_ids": expected.get("token_ids"),
            "residual_after_attention_hex": residual.hex(),
            "block_input_words_little_packed": [f"0x{word:08x}" for word in input_words],
            "residual_words_little_packed": [f"0x{word:08x}" for word in residual_words],
            "vector_write_mode": args.vector_write_mode,
            "block_input_words_written": [f"0x{word:08x}" for word in input_write_words],
            "residual_words_written": [f"0x{word:08x}" for word in residual_write_words],
            "readback_is_contract_check": args.vector_write_mode in ("direct", "raw-internal"),
        },
        "expected": {
            "checksum": f"0x{int(expected['checksum']):08x}",
            "sample0": f"0x{int(expected['sample0']):08x}",
            "sample1": f"0x{int(expected['sample1']):08x}",
            "output_count": int(expected["output_count"]),
            "first_64_output_hex": expected["first_64_output"].hex(),
            "token_index": expected.get("token_index"),
            "ln_input_checksum": (
                f"0x{int(expected['ln_input_checksum']):08x}"
                if "ln_input_checksum" in expected
                else None
            ),
        },
        "observed": {
            "compute_path": compute_path,
            "token_index": expected.get("token_index") if args.tb_data_sv is not None else None,
            "status": f"0x{observed['status']:08x}",
            "decoded_status": decoded,
            "start_count_before": observed["start_count_before"],
            "start_count_after": observed["start_count_after"],
            "cycle_count": observed["cycle_count"],
            "checksum": f"0x{observed['checksum']:08x}",
            "sample0": f"0x{observed['sample0']:08x}",
            "sample1": f"0x{observed['sample1']:08x}",
            "debug": f"0x{observed['debug']:08x}",
            "ln_input_checksum": (
                f"0x{observed['debug']:08x}" if "ln_input_checksum" in expected else None
            ),
            "debug1": f"0x{observed['debug1']:08x}",
            "debug2": f"0x{observed['debug2']:08x}",
            "debug3": f"0x{observed['debug3']:08x}",
            "decoded_debug": decode_debug(observed["debug"], observed["debug1"], observed["debug2"]),
            "done_stage_checksums": decode_done_stage_checksums(
                observed["debug1"],
                observed["debug2"],
            ),
            "provenance": f"0x{observed['provenance']:08x}",
            "expected_provenance": f"0x{observed['expected_provenance']:08x}",
            "output_count": observed["output_count"],
            "first_64_output_hex": observed["output_vector"].hex(),
            "input_readback_hex": observed["input_readback"].hex(),
            "residual_readback_hex": observed["residual_readback"].hex(),
            "input_readback_matches_requested": observed["input_readback"] == block_input,
            "residual_readback_matches_requested": observed["residual_readback"] == residual,
        },
        "checks": checks,
    }
    if args.expect_debug1 is not None and args.expect_debug2 is not None:
        result["observed"]["done_stage_checksum_comparison"] = compare_done_stage_checksums(
            observed["debug1"],
            observed["debug2"],
            args.expect_debug1,
            args.expect_debug2,
        )
    if failure is not None:
        result["failure"] = failure

    args.json_out.parent.mkdir(parents=True, exist_ok=True)
    args.json_out.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if result["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
