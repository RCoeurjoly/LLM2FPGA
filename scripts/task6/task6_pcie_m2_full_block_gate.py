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
M2_VERSION_ABI_MASK = 0x0000_FFFF

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
REG_M2_OUTPUT_HASH = 0x640

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

CLEAR_ONLY_CONTRACT = {
    "version": "task6-m2-clear-only-v1",
    "stage": "M2-clear",
    "milestone_target": "M2-one-full-block",
    "live_compute": False,
    "artifact_role": "m2-clear-only-board-action",
    "responsibilities": {
        "host": [
            "PCIe lifecycle orchestration",
            "M2 clear sequencing",
            "post-clear status/debug register capture",
        ],
        "fpga": [
            "BAR-visible M2 clear handling",
            "idle status and debug/provenance reporting",
        ],
    },
    "notes": "Issues M2 clear without writing vectors or starting compute.",
}

BAR_CONTRACT = {
    "version": "task6-m2-direct-bar-contract-v1",
    "stage": "M2.1-direct-pcie-bar-contract",
    "milestone_target": "M2.1-PCIe-BAR-contract",
    "live_compute": False,
    "artifact_role": "m2-direct-bar-contract-board-gate",
    "responsibilities": {
        "host": [
            "PCIe lifecycle orchestration",
            "direct-mode input/residual/control writes",
            "BAR readback identity checks",
            "post-clear idle/status capture",
        ],
        "fpga": [
            "BAR-visible M2 input/residual/control storage",
            "direct write/readback identity without compensated host tricks",
            "idle status and provenance reporting",
        ],
    },
    "notes": (
        "M2.1 acceptance gate. It does not start M2 compute; it proves direct "
        "BAR transport and clear/idle behavior before later M2 submilestones."
    ),
}

START_CLEAR_CONTRACT = {
    "version": "task6-m2-start-clear-lifecycle-v1",
    "stage": "M2.2-start-clear-lifecycle",
    "milestone_target": "M2.2-start-clear-lifecycle",
    "live_compute": False,
    "artifact_role": "m2-start-clear-lifecycle-board-gate",
    "responsibilities": {
        "host": [
            "PCIe lifecycle orchestration",
            "direct-mode input/residual/control writes",
            "single start assertion",
            "post-terminal clear sequencing",
        ],
        "fpga": [
            "BAR-visible M2 lifecycle state machine",
            "start_count increment on accepted start",
            "stable DONE or precise ERROR terminal status",
            "clear back to IDLE without stale/all-ones BAR",
        ],
    },
    "notes": (
        "M2.2 acceptance gate. It proves start/clear lifecycle on the public "
        "BAR contract and does not require final compute-vector correctness."
    ),
}

EMBEDDING_HANDOFF_CONTRACT = {
    "version": "task6-m2-embedding-handoff-v1",
    "stage": "M2.3-embedding-and-block-input-handoff",
    "milestone_target": "M2.3-embedding-and-block-input-handoff",
    "live_compute": True,
    "artifact_role": "m2-embedding-handoff-board-gate",
    "responsibilities": {
        "host": [
            "PCIe lifecycle orchestration",
            "direct token-ID writes",
            "BAR-visible block/LN checksum comparison",
        ],
        "fpga": [
            "token-ID selected embedding and position add",
            "live token-ID selected embedding and position add",
            "handoff of block input and LN input to the live-context block",
            "BAR debug/output exposure of full boundary checksums and block vector",
        ],
    },
    "notes": (
        "M2.3 acceptance gate. It proves token IDs reached the expected "
        "embedding/block-input/LN-input boundary before attention math."
    ),
}

CONTRACT_ATTENTION_SLICE = {
    "version": "task6-m2-live-context-attention-slice-v1",
    "stage": "M2.4-live-context-attention-slice",
    "milestone_target": "M2.4-live-context-attention-slice",
    "live_compute": True,
    "artifact_role": "m2-live-context-attention-slice-board-gate",
    "responsibilities": {
        "host": [
            "PCIe lifecycle orchestration",
            "direct token-ID writes",
            "BAR-visible context vector/checksum comparison",
        ],
        "fpga": [
            "token-ID selected embedding and position add",
            "handoff of live LN input to the live-context attention slice",
            "live LN + QKV + softmax/value/context computation",
            "BAR-visible full 64-byte context vector and boundary checksums",
        ],
    },
    "notes": (
        "M2.4 acceptance gate. It proves the focused live-context attention "
        "slice from host token IDs through the context vector boundary."
    ),
}

CONTRACT_ATTENTION_LN2 = {
    "version": "task6-m2-live-context-attention-ln2-v1",
    "stage": "M2.5-attention-out-proj-residual-ln2",
    "milestone_target": "M2.5-attention-out-proj-residual-ln2",
    "live_compute": True,
    "artifact_role": "m2-live-context-attention-ln2-board-gate",
    "responsibilities": {
        "host": [
            "PCIe lifecycle orchestration",
            "direct token-ID writes",
            "BAR-visible LN2 vector/checksum comparison",
        ],
        "fpga": [
            "token-ID selected embedding and position add",
            "handoff of live LN input to the live-context attention slice",
            "live attention context computation",
            "attention out projection, attention residual add, and LN2",
            "BAR-visible full 64-byte LN2 vector and boundary checksums",
        ],
    },
    "notes": (
        "M2.5 acceptance gate. It proves the focused live-context attention "
        "out-projection, residual add, and LN2 boundary from host token IDs."
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
SV_CONTEXT_LN_INPUT_RE = re.compile(
    r"^\s*ln_input_q12_by_token"
    r"\[(?P<token>\d+)\]\[(?P<dim>\d+)\]\s*=\s*"
    r"(?P<sign>-?)(?P<bits>\d+)'sd(?P<value>\d+)\s*;"
)
SV_CONTEXT_INV_STD_RE = re.compile(
    r"^\s*ln_inv_std_q16_by_token\[(?P<token>\d+)\]\s*=\s*"
    r"(?P<sign>-?)(?P<bits>\d+)'sd(?P<value>\d+)\s*;"
)
SV_CONTEXT_EXPECTED_Q_RE = re.compile(
    r"^\s*ln_expected_q_by_token"
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


def warmup_register_reads(
    read32,
    offsets: dict[str, int],
    *,
    samples: int,
) -> dict[str, list[int]]:
    if samples < 0:
        raise SystemExit("--preflight-warmup-samples must be non-negative")
    observed_samples: dict[str, list[int]] = {name: [] for name in offsets}
    for _ in range(samples):
        for name, offset in offsets.items():
            observed_samples[name].append(read32(offset))
    return observed_samples


def stable_or_leading_all_ones(values: list[int]) -> bool:
    if not values:
        return False
    if values[-1] == ALL_ONES:
        return False
    if all(value == values[0] for value in values):
        return True
    return (
        len(values) >= 2
        and values[0] == ALL_ONES
        and all(value == values[-1] for value in values[1:])
    )


def m2_version_abi_matches(value: int) -> bool:
    return value != ALL_ONES and (value & M2_VERSION_ABI_MASK) == M2_VERSION


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


def pcie7x_inverse_rotate64_bar_vector_words(words: list[int]) -> list[int]:
    if len(words) != 16:
        raise SystemExit(f"vector must contain 16 words, got {len(words)}")
    transformed: list[int] = []
    for index in range(0, len(words), 2):
        pair = ((words[index + 1] & 0xFFFFFFFF) << 32) | (words[index] & 0xFFFFFFFF)
        rotated = ((pair >> 1) | ((pair & 1) << 63)) & 0xFFFFFFFFFFFFFFFF
        transformed.append(rotated & 0xFFFFFFFF)
        transformed.append((rotated >> 32) & 0xFFFFFFFF)
    return transformed


def vector_words_from_bytes(data: bytes) -> list[int]:
    if len(data) != 64:
        raise SystemExit(f"vector must be exactly 64 bytes, got {len(data)}")
    return [int.from_bytes(data[index * 4 : index * 4 + 4], "little") for index in range(16)]


def vector_bytes_from_words(words: list[int]) -> bytes:
    if len(words) != 16:
        raise SystemExit(f"vector must contain 16 words, got {len(words)}")
    return b"".join((word & 0xFFFFFFFF).to_bytes(4, "little") for word in words)


def vector_hash128(data: bytes) -> bytes:
    if len(data) != 64:
        raise SystemExit(f"vector must be exactly 64 bytes, got {len(data)}")
    h0 = 0x811C9DC5
    h1 = 0x9E3779B9
    h2 = 0x85EBCA6B
    h3 = 0xC2B2AE35
    mask = 0xFFFFFFFF
    for index, byte_value in enumerate(data):
        h0 = ((((h0 << 5) | (h0 >> 27)) & mask) ^ byte_value ^ ((0x9E3779B9 + index) & mask)) & mask
        h1 = (
            (((h1 >> 7) | ((h1 << 25) & mask)) & mask)
            + (((byte_value << 8) & mask) ^ ((0x85EBCA6B + index) & mask))
        ) & mask
        h2 = (
            (((h2 << 3) | (h2 >> 29)) & mask)
            ^ (((byte_value << 16) + 0xC2B2AE35 + index) & mask)
        ) & mask
        h3 = (
            h3
            + (
                byte_value
                ^ (((index & 0xFFFF) << 16) | (index & 0xFFFF))
                ^ ((byte_value << 24) | (byte_value << 16) | (byte_value << 8) | byte_value)
            )
        ) & mask
    return b"".join(word.to_bytes(4, "little") for word in (h0, h1, h2, h3))


def classify_vector_readback_transform(expected: bytes, observed: bytes) -> str:
    if observed == expected:
        return "identity"
    if observed == bytes(64):
        return "all-zero"
    expected_words = vector_words_from_bytes(expected)
    if observed == vector_bytes_from_words(pcie7x_inverse_rotate64_bar_vector_words(expected_words)):
        return "pcie7x-64bit-ror1"
    if observed == vector_bytes_from_words(pcie7x_rotate64_compensate_bar_vector_words(expected_words)):
        return "pcie7x-64bit-rol1"
    return "other"


def vector_write_words_for_mode(words: list[int], mode: str) -> list[int]:
    if mode in ("direct", "raw-internal"):
        return words
    if mode in ("legacy-rotated", "readback-compensated"):
        return pcie7x_rotate64_compensate_bar_vector_words(words)
    if mode == "input-shadow-direct-compensated":
        return pcie7x_inverse_rotate64_bar_vector_words(words)
    raise SystemExit(f"unknown vector write mode: {mode}")


def write_vector(mm: mmap.mmap, base: int, data: bytes, *, mode: str) -> tuple[list[int], list[int]]:
    words = vector_words_from_bytes(data)
    write_words = vector_write_words_for_mode(words, mode)
    for index, word in enumerate(write_words):
        wr32(mm, base + index * 4, word)
    return words, write_words


def read_vector(mm: mmap.mmap, base: int) -> bytes:
    return b"".join(rd32_window(mm, base + index * 4).to_bytes(4, "little") for index in range(16))


def read_vector_hash(mm: mmap.mmap) -> bytes:
    return b"".join(
        rd32_window(mm, REG_M2_OUTPUT_HASH + index * 4).to_bytes(4, "little")
        for index in range(4)
    )


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
            decoded["expected_q_packed"] = f"0x{(debug >> 8) & 0xFF:02x}"
            decoded["token_index_packed"] = (debug >> 8) & 0xF
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
        attention_stage = stage & 0x0F
        decoded["attention_stage"] = f"0x{attention_stage:02x}"
        if attention_stage == 0x01:
            decoded["dim_index"] = (debug >> 20) & 0xF
            observed_acc_low20 = debug & 0xFFFFF
            decoded["observed_acc_low20"] = f"0x{observed_acc_low20:05x}"
            decoded["observed_acc_low8"] = f"0x{observed_acc_low20 & 0xFF:02x}"
            decoded["expected_acc_low16"] = f"0x{(debug1 >> 16) & 0xFFFF:04x}"
            decoded["observed_acc_low16"] = f"0x{debug1 & 0xFFFF:04x}"
            decoded["last_context_q"] = f"0x{(debug2 >> 24) & 0xFF:02x}"
            decoded["last_weight_q"] = f"0x{(debug2 >> 16) & 0xFF:02x}"
            decoded["next_acc_low16"] = f"0x{debug2 & 0xFFFF:04x}"
            decoded["attention_meaning"] = "attention out-projection accumulator mismatch"
        elif attention_stage in (0x02, 0x03):
            decoded["dim_index"] = (debug >> 20) & 0xF
            decoded["expected_q"] = f"0x{(debug >> 8) & 0xFF:02x}"
            decoded["observed_q"] = f"0x{debug & 0xFF:02x}"
            if attention_stage == 0x02:
                decoded["acc_low16"] = f"0x{(debug1 >> 16) & 0xFFFF:04x}"
                decoded["shifted_low16"] = f"0x{debug1 & 0xFFFF:04x}"
                decoded["product_low32"] = f"0x{debug2 & 0xFFFFFFFF:08x}"
            else:
                decoded["output_q"] = f"0x{(debug1 >> 24) & 0xFF:02x}"
                decoded["expected_output_q"] = f"0x{(debug1 >> 16) & 0xFF:02x}"
                decoded["block_input_q"] = f"0x{(debug1 >> 8) & 0xFF:02x}"
                decoded["expected_residual_q_from_debug1"] = f"0x{debug1 & 0xFF:02x}"
                decoded["residual_product_low32"] = f"0x{debug2 & 0xFFFFFFFF:08x}"
            decoded["attention_meaning"] = (
                "attention output mismatch"
                if attention_stage == 0x02
                else "attention residual mismatch"
            )
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


def parse_expected_tb_data_sv(
    path: Path,
    *,
    output_boundary: str = "final",
) -> dict[str, int | bytes | list[int]]:
    if output_boundary not in ("final", "attention-ln2"):
        raise SystemExit(f"unsupported output boundary: {output_boundary}")
    localparams: dict[str, int] = {}
    int_params: dict[str, int] = {}
    final_q: dict[int, int] = {}
    ln2_q: dict[int, int] = {}
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
        elif assign_match.group("name") == "m2_full_block_output_q":
            final_q[int(assign_match.group("index"))] = parse_signed_sv_literal(
                assign_match.group("sign"),
                assign_match.group("value"),
            )
        elif assign_match.group("name") == "ln2_expected_q":
            ln2_q[int(assign_match.group("index"))] = parse_signed_sv_literal(
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

    if output_boundary == "attention-ln2":
        expected_checksum = localparams.get("LN2_EXPECTED_CHECKSUM")
        expected_sample0 = localparams.get("LN2_EXPECTED_SAMPLE0")
        expected_sample1 = localparams.get("LN2_EXPECTED_SAMPLE1")
        output_q = ln2_q
        missing_message = (
            f"{path} missing localparam(s): LN2_EXPECTED_CHECKSUM, "
            "LN2_EXPECTED_SAMPLE0, LN2_EXPECTED_SAMPLE1"
        )
        missing_output_name = "ln2_expected_q"
        provenance_mode = 0x4200
    else:
        expected_checksum = localparams.get("MLP_FINAL_EXPECTED_CHECKSUM")
        if expected_checksum is None:
            expected_checksum = localparams.get("M2_FULL_BLOCK_EXPECTED_CHECKSUM")
        expected_sample0 = localparams.get("MLP_FINAL_EXPECTED_SAMPLE0")
        if expected_sample0 is None:
            expected_sample0 = localparams.get("M2_FULL_BLOCK_EXPECTED_SAMPLE0")
        expected_sample1 = localparams.get("MLP_FINAL_EXPECTED_SAMPLE1")
        if expected_sample1 is None:
            expected_sample1 = localparams.get("M2_FULL_BLOCK_EXPECTED_SAMPLE1")
        output_q = final_q
        missing_message = (
            f"{path} missing localparam(s): MLP_FINAL_EXPECTED_CHECKSUM / M2_FULL_BLOCK_EXPECTED_CHECKSUM, "
            "MLP_FINAL_EXPECTED_SAMPLE0 / M2_FULL_BLOCK_EXPECTED_SAMPLE0, "
            "MLP_FINAL_EXPECTED_SAMPLE1 / M2_FULL_BLOCK_EXPECTED_SAMPLE1"
        )
        missing_output_name = "mlp_final_expected_q"
        provenance_mode = 0x2000

    if expected_checksum is None or expected_sample0 is None or expected_sample1 is None:
        raise SystemExit(missing_message)
    missing_final = [index for index in range(64) if index not in output_q]
    if missing_final:
        raise SystemExit(f"{path} missing {missing_output_name} index(es): {missing_final[:8]}")
    missing_block_input = [index for index in range(64) if index not in block_input_q]
    if missing_block_input:
        block_input_q = {index: output_q.get(index, 0) for index in range(64)}
    missing_context = [index for index in range(64) if index not in context_q]
    if missing_context:
        context_q = {index: output_q.get(index, 0) for index in range(64)}

    first_64_output = bytes(output_q[index] & 0xFF for index in range(64))
    fixture_block_input = bytes(block_input_q[index] & 0xFF for index in range(64))
    fixture_context = bytes(context_q[index] & 0xFF for index in range(64))
    return {
        "checksum": expected_checksum,
        "sample0": expected_sample0,
        "sample1": expected_sample1,
        "output_count": 64,
        "first_64_output": first_64_output,
        "fixture_block_input": fixture_block_input,
        "fixture_context": fixture_context,
        "token_index": int_params.get("M2_FULL_BLOCK_TOKEN_INDEX", 0),
        "provenance_mode": provenance_mode,
    }


def parse_embedding_tb_data_sv(path: Path) -> dict[str, int | bytes | list[int]]:
    token_ids: dict[int, int] = {}
    ln_input_q12: dict[tuple[int, int], int] = {}
    block_input_q: dict[int, int] = {}
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
            continue
        if assign_match and assign_match.group("name") == "embed_block_expected_last_input_q":
            block_input_q[int(assign_match.group("index"))] = parse_signed_sv_literal(
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
    missing_block_input = [
        index for index in range(embed_block_dim) if index not in block_input_q
    ]
    if missing_block_input:
        raise SystemExit(
            f"{path} missing embed_block_expected_last_input_q index(es): {missing_block_input[:8]}"
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
    block_input_checksum = None
    block_input_output = bytes(block_input_q[index] & 0xFF for index in range(embed_block_dim))
    computed_block_input_checksum = sum(
        (block_input_q[index] & 0xFF) * (index + 1) for index in range(embed_block_dim)
    ) & 0xFFFFFFFF
    summary_path = path.with_name("summary.json")
    if summary_path.exists():
        summary = json.loads(summary_path.read_text(encoding="utf-8"))
        if "block_input_checksum" in summary:
            block_input_checksum = int(summary["block_input_checksum"])
    if block_input_checksum is not None and block_input_checksum != computed_block_input_checksum:
        raise SystemExit(
            f"{path} summary block_input_checksum 0x{block_input_checksum:08x} "
            f"does not match parsed vector checksum 0x{computed_block_input_checksum:08x}"
        )
    result: dict[str, int | bytes | list[int]] = {
        "token_input": bytes(token_input),
        "reserved_input": bytes(64),
        "token_ids": token_id_list,
        "ln_input_checksum": ln_input_checksum,
        "embedding_block_input_vector": block_input_output,
        "embedding_block_input_checksum": computed_block_input_checksum,
        "provenance_mode": 0x3000,
    }
    result["block_input_checksum"] = (
        block_input_checksum
        if block_input_checksum is not None
        else computed_block_input_checksum
    )
    return result


def parse_context_tb_data_sv(path: Path) -> dict[str, int]:
    signature_token = 5
    signature_dim = 1
    ln_input_q12: dict[tuple[int, int], int] = {}
    ln_inv_std_q16: dict[int, int] = {}
    ln_expected_q: dict[tuple[int, int], int] = {}
    context_q: dict[int, int] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        ln_input_match = SV_CONTEXT_LN_INPUT_RE.match(line)
        if ln_input_match:
            ln_input_q12[
                (int(ln_input_match.group("token")), int(ln_input_match.group("dim")))
            ] = parse_signed_sv_literal(
                ln_input_match.group("sign"),
                ln_input_match.group("value"),
            )
            continue
        inv_std_match = SV_CONTEXT_INV_STD_RE.match(line)
        if inv_std_match:
            ln_inv_std_q16[int(inv_std_match.group("token"))] = parse_signed_sv_literal(
                inv_std_match.group("sign"),
                inv_std_match.group("value"),
            )
            continue
        expected_match = SV_CONTEXT_EXPECTED_Q_RE.match(line)
        if expected_match:
            ln_expected_q[
                (int(expected_match.group("token")), int(expected_match.group("dim")))
            ] = parse_signed_sv_literal(
                expected_match.group("sign"),
                expected_match.group("value"),
            )
            continue
        assign_match = SV_ASSIGN_RE.match(line)
        if assign_match and assign_match.group("name") == "context_expected_q":
            context_q[int(assign_match.group("index"))] = parse_signed_sv_literal(
                assign_match.group("sign"),
                assign_match.group("value"),
            )
    required = {
        "ln_input_q12": (signature_token, signature_dim) in ln_input_q12,
        "ln_expected_q": (signature_token, signature_dim) in ln_expected_q,
        "ln_inv_std_q16": signature_token in ln_inv_std_q16,
    }
    missing = [name for name, present in required.items() if not present]
    if missing:
        raise SystemExit(f"{path} missing context fixture signature field(s): {', '.join(missing)}")
    signature = (
        (0xC5 << 24)
        | ((ln_expected_q[(signature_token, signature_dim)] & 0xFF) << 16)
        | ((ln_input_q12[(signature_token, signature_dim)] & 0xFF) << 8)
        | (ln_inv_std_q16[signature_token] & 0xFF)
    )
    missing_context = [index for index in range(64) if index not in context_q]
    if missing_context:
        raise SystemExit(f"{path} missing context_expected_q index(es): {missing_context[:8]}")
    context_vector = bytes(context_q[index] & 0xFF for index in range(64))
    context_checksum = sum(
        (context_q[index] & 0xFF) * (index + 1) for index in range(64)
    ) & 0xFFFFFFFF
    context_sample0 = int.from_bytes(context_vector[0:4], "little")
    context_sample1 = int.from_bytes(context_vector[4:8], "little")
    summary_path = path.with_name("summary.json")
    if summary_path.exists():
        summary = json.loads(summary_path.read_text(encoding="utf-8"))
        if int(summary.get("context_checksum", context_checksum)) != context_checksum:
            raise SystemExit(
                f"{path} summary context_checksum 0x{int(summary['context_checksum']):08x} "
                f"does not match parsed vector checksum 0x{context_checksum:08x}"
            )
        if int(str(summary.get("context_sample0", f"{context_sample0:08x}")), 16) != context_sample0:
            raise SystemExit(
                f"{path} summary context_sample0 does not match parsed vector sample0"
            )
        if int(str(summary.get("context_sample1", f"{context_sample1:08x}")), 16) != context_sample1:
            raise SystemExit(
                f"{path} summary context_sample1 does not match parsed vector sample1"
            )
    return {
        "context_fixture_signature": signature,
        "context_fixture_signature_token": signature_token,
        "context_fixture_signature_dim": signature_dim,
        "checksum": context_checksum,
        "sample0": context_sample0,
        "sample1": context_sample1,
        "output_count": 64,
        "first_64_output": context_vector,
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


def bar_contract_checks(
    *,
    status: int,
    provenance: int,
    input_readback: bytes,
    residual_readback: bytes,
    block_input: bytes,
    residual: bytes,
    start_count_before: int,
    start_count_after: int,
) -> dict[str, bool]:
    decoded = decode_status(status)
    return {
        "status_not_all_ones": status != ALL_ONES,
        "provenance_not_all_ones": provenance != ALL_ONES,
        "status_schema_consistent": bool(decoded["schema_consistent"]),
        "provenance_schema_consistent": (provenance >> 16) == 0x4D32,
        "state_idle": decoded["state_name"] == "IDLE" and bool(decoded["ready"]),
        "no_error": not bool(decoded["error"]),
        "start_count_unchanged": start_count_after == start_count_before,
        "input_readback_identity": input_readback == block_input,
        "residual_readback_identity": residual_readback == residual,
    }


def start_clear_contract_checks(
    *,
    run_status: int,
    clear_status: int,
    provenance: int,
    input_readback: bytes,
    residual_readback: bytes,
    block_input: bytes,
    residual: bytes,
    start_count_before: int,
    start_count_after_start: int,
    start_count_after_clear: int,
    allow_error: bool,
) -> dict[str, bool]:
    run_decoded = decode_status(run_status)
    clear_decoded = decode_status(clear_status)
    run_reached_done = bool(run_decoded["done"]) and not bool(run_decoded["error"])
    run_reached_error = bool(run_decoded["error"])
    run_reached_allowed_terminal = run_reached_done or (allow_error and run_reached_error)
    return {
        "run_status_not_all_ones": run_status != ALL_ONES,
        "clear_status_not_all_ones": clear_status != ALL_ONES,
        "provenance_not_all_ones": provenance != ALL_ONES,
        "run_status_schema_consistent": bool(run_decoded["schema_consistent"]),
        "clear_status_schema_consistent": bool(clear_decoded["schema_consistent"]),
        "provenance_schema_consistent": (provenance >> 16) == 0x4D32,
        "start_count_incremented": start_count_after_start == ((start_count_before + 1) & 0xFFFFFFFF),
        "start_count_stable_after_clear": start_count_after_clear == start_count_after_start,
        "run_reached_terminal": bool(run_decoded["done"]) or run_reached_error,
        "run_reached_allowed_terminal": run_reached_allowed_terminal,
        "clear_state_idle": clear_decoded["state_name"] == "IDLE" and bool(clear_decoded["ready"]),
        "clear_no_error": not bool(clear_decoded["error"]),
        "input_readback_identity": input_readback == block_input,
        "residual_readback_identity": residual_readback == residual,
    }


def embedding_handoff_contract_checks(
    *,
    run_decoded: dict[str, Any],
    output_count: int,
    checksum: int,
    debug: int,
    debug1: int,
    debug2: int,
    debug3: int,
    output_vector: bytes,
    output_hash: bytes,
    expected_block_input_checksum: int,
    expected_ln_input_checksum: int,
    expected_block_vector: bytes,
) -> dict[str, bool]:
    expected_block_vector_hash = vector_hash128(expected_block_vector)
    return {
        "embedding_run_done": bool(run_decoded["done"]),
        "embedding_no_error": not bool(run_decoded["error"]),
        "embedding_output_valid": bool(run_decoded["output_valid"]),
        "embedding_output_count": output_count == 64,
        "embedding_output_checksum": checksum == expected_block_input_checksum,
        "embedding_debug_block_checksum": debug1 == expected_block_input_checksum,
        "embedding_debug_ln_checksum": debug == expected_ln_input_checksum,
        "embedding_debug2_ln_checksum": debug2 == expected_ln_input_checksum,
        "embedding_debug3_checksum_lows": debug3
        == (((expected_block_input_checksum & 0xFFFF) << 16) | (expected_ln_input_checksum & 0xFFFF)),
        "embedding_output_vector": output_vector == expected_block_vector,
        "embedding_output_hash": output_hash == expected_block_vector_hash,
    }


def expected_provenance(expected: dict[str, int | bytes | list[int]]) -> int:
    token_index = int(expected.get("token_index", 0))
    provenance_mode = int(expected.get("provenance_mode", 0x2000))
    return 0x4D32_0000 | (provenance_mode & 0xFF00) | (token_index & 0xFF)


def is_token_live_mode(expected: dict[str, int | bytes | list[int]]) -> bool:
    return int(expected.get("provenance_mode", 0)) in (0x3000, 0x3100, 0x4100, 0x4200) and isinstance(expected.get("token_ids"), list)


def contract_for_expected(expected: dict[str, int | bytes | list[int]]) -> dict[str, Any]:
    if int(expected.get("provenance_mode", 0)) == 0x4200:
        return CONTRACT_ATTENTION_LN2
    if int(expected.get("provenance_mode", 0)) == 0x4100:
        return CONTRACT_ATTENTION_SLICE
    return CONTRACT_TOKEN_LIVE if is_token_live_mode(expected) else CONTRACT


def compute_path_for_expected(expected: dict[str, int | bytes | list[int]]) -> str:
    if int(expected.get("provenance_mode", 0)) == 0x4200:
        return "live-context-attention-ln2"
    if int(expected.get("provenance_mode", 0)) == 0x4100:
        return "live-context-attention-slice"
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
    parser.add_argument(
        "--context-tb-data-sv",
        type=Path,
        help=(
            "Generated live-context constants matching a token-ID M2 bitstream. "
            "When provided, preflight requires the board idle DEBUG3 context "
            "fixture signature to match before issuing clear/start."
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
        "--clear-only",
        action="store_true",
        help="Issue M2 clear and report the post-clear status/debug registers without starting compute.",
    )
    parser.add_argument(
        "--bar-contract-only",
        action="store_true",
        help=(
            "Run the M2.1 direct PCIe/BAR contract gate: clear, write input/"
            "residual in direct mode, require readback identity, and do not "
            "start compute."
        ),
    )
    parser.add_argument(
        "--start-clear-only",
        action="store_true",
        help=(
            "Run the M2.2 start/clear lifecycle gate: direct write/readback, "
            "assert start once, require terminal lifecycle status, clear back "
            "to IDLE, and do not check final compute vector correctness."
        ),
    )
    parser.add_argument(
        "--start-clear-disallow-error",
        action="store_true",
        help=(
            "For --start-clear-only, require DONE rather than accepting a "
            "schema-valid ERROR as a precise lifecycle terminal state."
        ),
    )
    parser.add_argument(
        "--require-embedding-handoff",
        action="store_true",
        help=(
            "With --start-clear-only, also require BAR debug3 to expose the "
            "expected block-input and LN-input checksum low16 values. This is "
            "the M2.3 embedding/block-input handoff acceptance check."
        ),
    )
    parser.add_argument(
        "--require-attention-slice",
        action="store_true",
        help=(
            "Require the focused M2.4 live-context attention-slice contract: "
            "direct token-ID writes, matching context fixture signature, DONE/"
            "no-error, and full BAR context vector/checksum comparison."
        ),
    )
    parser.add_argument(
        "--require-attention-ln2",
        action="store_true",
        help=(
            "Require the focused M2.5 attention out-proj/residual/LN2 contract: "
            "direct token-ID writes, matching context fixture signature, DONE/"
            "no-error, and full BAR LN2 vector/checksum comparison."
        ),
    )
    parser.add_argument(
        "--vector-write-mode",
        choices=(
            "direct",
            "legacy-rotated",
            "raw-internal",
            "readback-compensated",
            "input-shadow-direct-compensated",
        ),
        default="direct",
        help=(
            "M2 vector BAR write strategy. direct is the normal acceptance "
            "contract and requires write/readback identity. raw-internal is a "
            "deprecated alias for direct. legacy-rotated/readback-compensated "
            "apply the measured pcie_7x 64-bit lane-rotate compensation for "
            "readback-only RTL. input-shadow-direct-compensated applies the "
            "inverse direction needed by the restored input-shadow-direct RTL. "
            "All compensated modes are diagnostic only."
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
    parser.add_argument(
        "--preflight-warmup-samples",
        type=int,
        default=1,
        help=(
            "Read and discard this many preflight register sample sets before "
            "the strict stability samples. These warm-up reads are reported "
            "in the artifact but never count toward PASS."
        ),
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    special_modes = [args.clear_only, args.bar_contract_only, args.start_clear_only]
    if sum(1 for enabled in special_modes if enabled) > 1:
        raise SystemExit("--clear-only, --bar-contract-only, and --start-clear-only are mutually exclusive")
    if (args.bar_contract_only or args.start_clear_only) and args.vector_write_mode not in ("direct", "raw-internal"):
        raise SystemExit("--bar-contract-only/--start-clear-only require direct/raw-internal vector write mode")
    if args.require_embedding_handoff and not args.start_clear_only:
        raise SystemExit("--require-embedding-handoff requires --start-clear-only")
    if args.require_attention_slice and args.require_attention_ln2:
        raise SystemExit("--require-attention-slice and --require-attention-ln2 are mutually exclusive")
    if (args.require_attention_slice or args.require_attention_ln2) and args.start_clear_only:
        raise SystemExit("--require-attention-slice/--require-attention-ln2 use the normal strict compute-vector gate")
    if (args.require_attention_slice or args.require_attention_ln2) and args.context_tb_data_sv is None:
        raise SystemExit("--require-attention-slice/--require-attention-ln2 require --context-tb-data-sv")
    if (args.require_attention_slice or args.require_attention_ln2) and args.embedding_tb_data_sv is None:
        raise SystemExit("--require-attention-slice/--require-attention-ln2 require --embedding-tb-data-sv")
    if not args.clear_only and (args.expected_json is None) == (args.tb_data_sv is None):
        raise SystemExit("provide exactly one of --expected-json or --tb-data-sv")
    if args.embedding_tb_data_sv is not None and args.tb_data_sv is None:
        raise SystemExit("--embedding-tb-data-sv requires --tb-data-sv")
    expected_source = args.expected_json if args.expected_json is not None else args.tb_data_sv
    expected: dict[str, Any] = {}
    if not args.clear_only:
        assert expected_source is not None
        expected = (
            parse_expected_json(args.expected_json)
            if args.expected_json is not None
            else parse_expected_tb_data_sv(
                args.tb_data_sv,
                output_boundary="attention-ln2" if args.require_attention_ln2 else "final",
            )
        )
        if args.embedding_tb_data_sv is not None:
            expected.update(parse_embedding_tb_data_sv(args.embedding_tb_data_sv))
        if args.context_tb_data_sv is not None:
            expected.update(parse_context_tb_data_sv(args.context_tb_data_sv))
        if args.require_embedding_handoff:
            expected["provenance_mode"] = 0x3100
        if args.require_attention_slice:
            expected["provenance_mode"] = 0x4100
        if args.require_attention_ln2:
            expected["provenance_mode"] = 0x4200
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

    block_input, residual, block_input_source, residual_source = (
        (bytes(64), bytes(64), "clear-only", "clear-only")
        if args.clear_only
        else select_host_vectors(
            expected,
            input_hex=args.input_hex,
            residual_hex=args.residual_hex,
        )
    )
    result_contract = (
        CLEAR_ONLY_CONTRACT
        if args.clear_only
        else BAR_CONTRACT if args.bar_contract_only
        else EMBEDDING_HANDOFF_CONTRACT if args.require_embedding_handoff
        else START_CLEAR_CONTRACT if args.start_clear_only
        else contract_for_expected(expected)
    )
    compute_path = (
        "clear-only"
        if args.clear_only
        else "direct-bar-contract" if args.bar_contract_only
        else "embedding-handoff" if args.require_embedding_handoff
        else "start-clear-lifecycle" if args.start_clear_only
        else compute_path_for_expected(expected)
    )

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
            if args.clear_only:
                wr32(mm, REG_M2_CONTROL_STATUS, 0)
                wr32(mm, REG_M2_CONTROL_STATUS, 2)
                time.sleep(args.poll_interval)
                wr32(mm, REG_M2_CONTROL_STATUS, 0)
                time.sleep(args.poll_interval)
                status = rd32_window(mm, REG_M2_CONTROL_STATUS)
                provenance = rd32_window(mm, REG_M2_PROVENANCE)
                decoded_status = decode_status(status)
                clear_checks = {
                    "status_not_all_ones": status != ALL_ONES,
                    "provenance_not_all_ones": provenance != ALL_ONES,
                    "status_schema_consistent": bool(decoded_status["schema_consistent"]),
                    "provenance_schema_consistent": (provenance >> 16) == 0x4D32,
                }
                clear_pass = all(clear_checks.values())
                result = {
                    "artifact_name": "task6-pcie-m2-full-block-clear-only",
                    "status": "PASS" if clear_pass else "FAIL",
                    "date": dt.date.today().isoformat(),
                    "contract": result_contract,
                    "bdf": args.bdf,
                    "lspci": lspci,
                    "command": command,
                    "elapsed_seconds": time.monotonic() - started,
                    "checks": clear_checks,
                    "observed": {
                        "status": f"0x{status:08x}",
                        "decoded_status": decoded_status,
                        "cycle_count": rd32_window(mm, REG_M2_CYCLE_COUNT),
                        "debug": f"0x{rd32_window(mm, REG_M2_DEBUG):08x}",
                        "debug1": f"0x{rd32_window(mm, REG_M2_DEBUG1):08x}",
                        "debug2": f"0x{rd32_window(mm, REG_M2_DEBUG2):08x}",
                        "debug3": f"0x{rd32_window(mm, REG_M2_DEBUG3):08x}",
                        "provenance": f"0x{provenance:08x}",
                    },
                }
                args.json_out.parent.mkdir(parents=True, exist_ok=True)
                args.json_out.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
                print(json.dumps(result, indent=2, sort_keys=True))
                return 0 if clear_pass else 1

            preflight_offsets = {
                "magic": REG_MAGIC,
                "version": REG_VERSION,
                "status": REG_STATUS,
                "m2_magic": REG_M2_MAGIC,
                "m2_version": REG_M2_VERSION,
                "m2_present": REG_M2_PRESENT,
                "m2_provenance": REG_M2_PROVENANCE,
            }
            if "context_fixture_signature" in expected:
                preflight_offsets["m2_context_fixture_signature"] = REG_M2_DEBUG3
            preflight_warmup_samples = warmup_register_reads(
                lambda offset: rd32_window(mm, offset),
                preflight_offsets,
                samples=args.preflight_warmup_samples,
            )
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
            m2_context_fixture_signature = preflight_values.get("m2_context_fixture_signature")
            expected_context_fixture_signature = expected.get("context_fixture_signature")
            preflight_acceptable = {
                name: stable_or_leading_all_ones(values)
                for name, values in preflight_samples.items()
            }
            preflight_all_stable = all(preflight_acceptable.values())

            preflight_checks = {
                "preflight_registers_stable": preflight_all_stable,
                "task6_magic": magic == TASK6_MAGIC,
                "task6_version": version == TASK6_VERSION,
                "not_all_ones": all(value != ALL_ONES for value in preflight_values.values()),
                "m2_magic": m2_magic == M2_MAGIC,
                "m2_version": m2_version_abi_matches(m2_version),
                "m2_present": m2_present == 1,
                "m2_provenance": m2_provenance == expected_m2_provenance,
            }
            if expected_context_fixture_signature is not None:
                preflight_checks["m2_context_fixture_signature"] = (
                    m2_context_fixture_signature == expected_context_fixture_signature
                )
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
                        "m2_context_fixture_signature": (
                            f"0x{m2_context_fixture_signature:08x}"
                            if m2_context_fixture_signature is not None
                            else None
                        ),
                        "expected_context_fixture_signature": (
                            f"0x{int(expected_context_fixture_signature):08x}"
                            if expected_context_fixture_signature is not None
                            else None
                        ),
                    },
                    "preflight_samples": {
                        name: [f"0x{value:08x}" for value in values]
                        for name, values in preflight_samples.items()
                    },
                    "preflight_warmup_samples": {
                        name: [f"0x{value:08x}" for value in values]
                        for name, values in preflight_warmup_samples.items()
                    },
                    "preflight_stable": preflight_stable,
                    "preflight_acceptable": preflight_acceptable,
                    "fingerprints": {
                        "gate_script_sha256": sha256_file(Path(__file__)),
                        "expected_json": str(args.expected_json) if args.expected_json else None,
                        "expected_json_sha256": sha256_file(args.expected_json),
                        "tb_data_sv": str(args.tb_data_sv) if args.tb_data_sv else None,
                        "tb_data_sv_sha256": sha256_file(args.tb_data_sv),
                        "embedding_tb_data_sv": str(args.embedding_tb_data_sv) if args.embedding_tb_data_sv else None,
                        "embedding_tb_data_sv_sha256": sha256_file(args.embedding_tb_data_sv),
                        "context_tb_data_sv": str(args.context_tb_data_sv) if args.context_tb_data_sv else None,
                        "context_tb_data_sv_sha256": sha256_file(args.context_tb_data_sv),
                        "tb_data_token_index": expected.get("token_index") if args.tb_data_sv else None,
                        "token_ids": expected.get("token_ids"),
                        "context_fixture_signature": (
                            f"0x{int(expected_context_fixture_signature):08x}"
                            if expected_context_fixture_signature is not None
                            else None
                        ),
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

            if args.bar_contract_only:
                start_count_before = rd32_window(mm, REG_M2_START_COUNT)
                wr32(mm, REG_M2_CONTROL_STATUS, 0)
                wr32(mm, REG_M2_CONTROL_STATUS, 2)
                time.sleep(args.poll_interval)
                wr32(mm, REG_M2_CONTROL_STATUS, 0)
                time.sleep(args.poll_interval)
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
                m2_status = rd32_window(mm, REG_M2_CONTROL_STATUS)
                provenance = rd32_window(mm, REG_M2_PROVENANCE)
                start_count_after = rd32_window(mm, REG_M2_START_COUNT)
                decoded = decode_status(m2_status)
                contract_checks = bar_contract_checks(
                    status=m2_status,
                    provenance=provenance,
                    input_readback=input_readback,
                    residual_readback=residual_readback,
                    block_input=block_input,
                    residual=residual,
                    start_count_before=start_count_before,
                    start_count_after=start_count_after,
                )
                checks = {**preflight_checks, **contract_checks}
                result_status = "PASS" if all(checks.values()) else "FAIL"
                result = {
                    "artifact_name": "task6-pcie-m2-direct-bar-contract-gate",
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
                        "m2_provenance": f"0x{m2_provenance:08x}",
                        "expected_m2_provenance": f"0x{expected_m2_provenance:08x}",
                        "m2_context_fixture_signature": (
                            f"0x{m2_context_fixture_signature:08x}"
                            if m2_context_fixture_signature is not None
                            else None
                        ),
                        "expected_context_fixture_signature": (
                            f"0x{int(expected_context_fixture_signature):08x}"
                            if expected_context_fixture_signature is not None
                            else None
                        ),
                    },
                    "preflight_samples": {
                        name: [f"0x{value:08x}" for value in values]
                        for name, values in preflight_samples.items()
                    },
                    "preflight_warmup_samples": {
                        name: [f"0x{value:08x}" for value in values]
                        for name, values in preflight_warmup_samples.items()
                    },
                    "preflight_stable": preflight_stable,
                    "preflight_acceptable": preflight_acceptable,
                    "fingerprints": {
                        "gate_script_sha256": sha256_file(Path(__file__)),
                        "expected_json": str(args.expected_json) if args.expected_json else None,
                        "expected_json_sha256": sha256_file(args.expected_json),
                        "tb_data_sv": str(args.tb_data_sv) if args.tb_data_sv else None,
                        "tb_data_sv_sha256": sha256_file(args.tb_data_sv),
                        "embedding_tb_data_sv": (
                            str(args.embedding_tb_data_sv) if args.embedding_tb_data_sv else None
                        ),
                        "embedding_tb_data_sv_sha256": sha256_file(args.embedding_tb_data_sv),
                        "context_tb_data_sv": (
                            str(args.context_tb_data_sv) if args.context_tb_data_sv else None
                        ),
                        "context_tb_data_sv_sha256": sha256_file(args.context_tb_data_sv),
                        "tb_data_token_index": expected.get("token_index") if args.tb_data_sv else None,
                        "token_ids": expected.get("token_ids"),
                        "context_fixture_signature": (
                            f"0x{int(expected_context_fixture_signature):08x}"
                            if expected_context_fixture_signature is not None
                            else None
                        ),
                        "block_input_sha256": sha256_bytes(block_input),
                        "residual_after_attention_sha256": sha256_bytes(residual),
                        "block_input_source": block_input_source,
                        "residual_after_attention_source": residual_source,
                    },
                    "input": {
                        "block_input_hex": block_input.hex(),
                        "block_index": 0 if is_token_live_mode(expected) else None,
                        "token_ids": expected.get("token_ids"),
                        "residual_after_attention_hex": residual.hex(),
                        "block_input_words_little_packed": [
                            f"0x{word:08x}" for word in input_words
                        ],
                        "residual_words_little_packed": [
                            f"0x{word:08x}" for word in residual_words
                        ],
                        "vector_write_mode": args.vector_write_mode,
                        "block_input_words_written": [
                            f"0x{word:08x}" for word in input_write_words
                        ],
                        "residual_words_written": [
                            f"0x{word:08x}" for word in residual_write_words
                        ],
                        "readback_is_contract_check": True,
                    },
                    "observed": {
                        "compute_path": compute_path,
                        "status": f"0x{m2_status:08x}",
                        "decoded_status": decoded,
                        "start_count_before": start_count_before,
                        "start_count_after": start_count_after,
                        "cycle_count": rd32_window(mm, REG_M2_CYCLE_COUNT),
                        "debug": f"0x{rd32_window(mm, REG_M2_DEBUG):08x}",
                        "debug1": f"0x{rd32_window(mm, REG_M2_DEBUG1):08x}",
                        "debug2": f"0x{rd32_window(mm, REG_M2_DEBUG2):08x}",
                        "debug3": f"0x{rd32_window(mm, REG_M2_DEBUG3):08x}",
                        "provenance": f"0x{provenance:08x}",
                        "expected_provenance": f"0x{expected_m2_provenance:08x}",
                        "input_readback_hex": input_readback.hex(),
                        "residual_readback_hex": residual_readback.hex(),
                        "input_readback_matches_requested": input_readback == block_input,
                        "residual_readback_matches_requested": residual_readback == residual,
                        "input_readback_transform": classify_vector_readback_transform(
                            block_input,
                            input_readback,
                        ),
                        "residual_readback_transform": classify_vector_readback_transform(
                            residual,
                            residual_readback,
                        ),
                    },
                    "checks": checks,
                }
                args.json_out.parent.mkdir(parents=True, exist_ok=True)
                args.json_out.write_text(
                    json.dumps(result, indent=2, sort_keys=True) + "\n",
                    encoding="utf-8",
                )
                print(json.dumps(result, indent=2, sort_keys=True))
                return 0 if result_status == "PASS" else 1

            if args.start_clear_only:
                wr32(mm, REG_M2_CONTROL_STATUS, 0)
                wr32(mm, REG_M2_CONTROL_STATUS, 2)
                time.sleep(args.poll_interval)
                wr32(mm, REG_M2_CONTROL_STATUS, 0)
                time.sleep(args.poll_interval)
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
                start_count_before = rd32_window(mm, REG_M2_START_COUNT)
                wr32(mm, REG_M2_CONTROL_STATUS, 1)

                deadline = time.monotonic() + args.timeout
                run_status = rd32_window(mm, REG_M2_CONTROL_STATUS)
                run_decoded = decode_status(run_status)
                while time.monotonic() < deadline:
                    run_status = rd32_window(mm, REG_M2_CONTROL_STATUS)
                    run_decoded = decode_status(run_status)
                    if run_decoded["done"] or run_decoded["error"]:
                        break
                    time.sleep(args.poll_interval)

                start_count_after_start = rd32_window(mm, REG_M2_START_COUNT)
                cycle_count = rd32_window(mm, REG_M2_CYCLE_COUNT)
                checksum = rd32_window(mm, REG_M2_OUTPUT_CHECKSUM)
                output_count = rd32_window(mm, REG_M2_OUTPUT_COUNT)
                sample0 = rd32_window(mm, REG_M2_OUTPUT_SAMPLE0)
                sample1 = rd32_window(mm, REG_M2_OUTPUT_SAMPLE1)
                debug = rd32_window(mm, REG_M2_DEBUG)
                debug1 = rd32_window(mm, REG_M2_DEBUG1)
                debug2 = rd32_window(mm, REG_M2_DEBUG2)
                debug3 = rd32_window(mm, REG_M2_DEBUG3)
                provenance = rd32_window(mm, REG_M2_PROVENANCE)
                output_vector = read_vector(mm, REG_M2_OUTPUT_VECTOR)
                output_hash = read_vector_hash(mm)

                wr32(mm, REG_M2_CONTROL_STATUS, 0)
                wr32(mm, REG_M2_CONTROL_STATUS, 2)
                time.sleep(args.poll_interval)
                wr32(mm, REG_M2_CONTROL_STATUS, 0)
                time.sleep(args.poll_interval)
                clear_status = rd32_window(mm, REG_M2_CONTROL_STATUS)
                clear_decoded = decode_status(clear_status)
                start_count_after_clear = rd32_window(mm, REG_M2_START_COUNT)
                allow_error = not args.start_clear_disallow_error and not args.require_embedding_handoff
                lifecycle_checks = start_clear_contract_checks(
                    run_status=run_status,
                    clear_status=clear_status,
                    provenance=provenance,
                    input_readback=input_readback,
                    residual_readback=residual_readback,
                    block_input=block_input,
                    residual=residual,
                    start_count_before=start_count_before,
                    start_count_after_start=start_count_after_start,
                    start_count_after_clear=start_count_after_clear,
                    allow_error=allow_error,
                )
                if args.require_embedding_handoff:
                    if "block_input_checksum" not in expected:
                        raise SystemExit(
                            "--require-embedding-handoff requires block_input_checksum "
                            "from embedding summary.json"
                        )
                    if "ln_input_checksum" not in expected:
                        raise SystemExit(
                            "--require-embedding-handoff requires ln_input_checksum "
                            "from --embedding-tb-data-sv"
                        )
                    if "embedding_block_input_vector" not in expected:
                        raise SystemExit(
                            "--require-embedding-handoff requires embedding_block_input_vector "
                            "from --embedding-tb-data-sv"
                        )
                    expected_block_vector = expected["embedding_block_input_vector"]
                    if not isinstance(expected_block_vector, bytes):
                        raise SystemExit("embedding_block_input_vector must be bytes")
                    lifecycle_checks.update(
                        embedding_handoff_contract_checks(
                            run_decoded=run_decoded,
                            output_count=output_count,
                            checksum=checksum,
                            debug=debug,
                            debug1=debug1,
                            debug2=debug2,
                            debug3=debug3,
                            output_vector=output_vector,
                            output_hash=output_hash,
                            expected_block_input_checksum=int(expected["block_input_checksum"]),
                            expected_ln_input_checksum=int(expected["ln_input_checksum"]),
                            expected_block_vector=expected_block_vector,
                        )
                    )
                checks = {**preflight_checks, **lifecycle_checks}
                status_checks = dict(checks)
                status_checks.pop("embedding_output_hash", None)
                result_status = "PASS" if all(status_checks.values()) else "FAIL"
                result = {
                    "artifact_name": "task6-pcie-m2-start-clear-lifecycle-gate",
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
                        "m2_provenance": f"0x{m2_provenance:08x}",
                        "expected_m2_provenance": f"0x{expected_m2_provenance:08x}",
                        "m2_context_fixture_signature": (
                            f"0x{m2_context_fixture_signature:08x}"
                            if m2_context_fixture_signature is not None
                            else None
                        ),
                        "expected_context_fixture_signature": (
                            f"0x{int(expected_context_fixture_signature):08x}"
                            if expected_context_fixture_signature is not None
                            else None
                        ),
                    },
                    "preflight_samples": {
                        name: [f"0x{value:08x}" for value in values]
                        for name, values in preflight_samples.items()
                    },
                    "preflight_warmup_samples": {
                        name: [f"0x{value:08x}" for value in values]
                        for name, values in preflight_warmup_samples.items()
                    },
                    "preflight_stable": preflight_stable,
                    "preflight_acceptable": preflight_acceptable,
                    "fingerprints": {
                        "gate_script_sha256": sha256_file(Path(__file__)),
                        "expected_json": str(args.expected_json) if args.expected_json else None,
                        "expected_json_sha256": sha256_file(args.expected_json),
                        "tb_data_sv": str(args.tb_data_sv) if args.tb_data_sv else None,
                        "tb_data_sv_sha256": sha256_file(args.tb_data_sv),
                        "embedding_tb_data_sv": (
                            str(args.embedding_tb_data_sv) if args.embedding_tb_data_sv else None
                        ),
                        "embedding_tb_data_sv_sha256": sha256_file(args.embedding_tb_data_sv),
                        "context_tb_data_sv": (
                            str(args.context_tb_data_sv) if args.context_tb_data_sv else None
                        ),
                        "context_tb_data_sv_sha256": sha256_file(args.context_tb_data_sv),
                        "tb_data_token_index": expected.get("token_index") if args.tb_data_sv else None,
                        "token_ids": expected.get("token_ids"),
                        "context_fixture_signature": (
                            f"0x{int(expected_context_fixture_signature):08x}"
                            if expected_context_fixture_signature is not None
                            else None
                        ),
                        "block_input_sha256": sha256_bytes(block_input),
                        "residual_after_attention_sha256": sha256_bytes(residual),
                        "block_input_source": block_input_source,
                        "residual_after_attention_source": residual_source,
                    },
                    "input": {
                        "block_input_hex": block_input.hex(),
                        "block_index": 0 if is_token_live_mode(expected) else None,
                        "token_ids": expected.get("token_ids"),
                        "residual_after_attention_hex": residual.hex(),
                        "block_input_words_little_packed": [
                            f"0x{word:08x}" for word in input_words
                        ],
                        "residual_words_little_packed": [
                            f"0x{word:08x}" for word in residual_words
                        ],
                        "vector_write_mode": args.vector_write_mode,
                        "block_input_words_written": [
                            f"0x{word:08x}" for word in input_write_words
                        ],
                        "residual_words_written": [
                            f"0x{word:08x}" for word in residual_write_words
                        ],
                        "readback_is_contract_check": True,
                    },
                    "observed": {
                        "compute_path": compute_path,
                        "allow_terminal_error": allow_error,
                        "run_status": f"0x{run_status:08x}",
                        "run_decoded_status": run_decoded,
                        "clear_status": f"0x{clear_status:08x}",
                        "clear_decoded_status": clear_decoded,
                        "start_count_before": start_count_before,
                        "start_count_after_start": start_count_after_start,
                        "start_count_after_clear": start_count_after_clear,
                        "cycle_count": cycle_count,
                        "checksum": f"0x{checksum:08x}",
                        "output_count": output_count,
                        "sample0": f"0x{sample0:08x}",
                        "sample1": f"0x{sample1:08x}",
                        "debug": f"0x{debug:08x}",
                        "debug1": f"0x{debug1:08x}",
                        "debug2": f"0x{debug2:08x}",
                        "debug3": f"0x{debug3:08x}",
                        "output_vector_hex": output_vector.hex(),
                        "output_hash_hex": output_hash.hex(),
                        "expected_output_hash_hex": (
                            vector_hash128(expected["embedding_block_input_vector"]).hex()
                            if args.require_embedding_handoff
                            and isinstance(
                                expected.get("embedding_block_input_vector"),
                                bytes,
                            )
                            else None
                        ),
                        "expected_block_input_checksum": (
                            f"0x{int(expected['block_input_checksum']):08x}"
                            if "block_input_checksum" in expected
                            else None
                        ),
                        "expected_ln_input_checksum": (
                            f"0x{int(expected['ln_input_checksum']):08x}"
                            if "ln_input_checksum" in expected
                            else None
                        ),
                        "expected_embedding_block_input_vector_hex": (
                            expected["embedding_block_input_vector"].hex()
                            if isinstance(expected.get("embedding_block_input_vector"), bytes)
                            else None
                        ),
                        "decoded_debug": decode_debug(debug, debug1, debug2),
                        "done_stage_checksums": decode_done_stage_checksums(debug1, debug2),
                        "provenance": f"0x{provenance:08x}",
                        "expected_provenance": f"0x{expected_m2_provenance:08x}",
                        "input_readback_hex": input_readback.hex(),
                        "residual_readback_hex": residual_readback.hex(),
                        "input_readback_matches_requested": input_readback == block_input,
                        "residual_readback_matches_requested": residual_readback == residual,
                        "input_readback_transform": classify_vector_readback_transform(
                            block_input,
                            input_readback,
                        ),
                        "residual_readback_transform": classify_vector_readback_transform(
                            residual,
                            residual_readback,
                        ),
                    },
                    "checks": checks,
                }
                args.json_out.parent.mkdir(parents=True, exist_ok=True)
                args.json_out.write_text(
                    json.dumps(result, indent=2, sort_keys=True) + "\n",
                    encoding="utf-8",
                )
                print(json.dumps(result, indent=2, sort_keys=True))
                return 0 if result_status == "PASS" else 1

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
            for value in (*preflight_values.values(), observed["status"])
        ),
        "m2_magic": m2_magic == M2_MAGIC,
        "m2_version": m2_version_abi_matches(m2_version),
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
    if expected_context_fixture_signature is not None:
        checks["m2_context_fixture_signature"] = (
            m2_context_fixture_signature == expected_context_fixture_signature
        )
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
            "m2_context_fixture_signature": (
                f"0x{m2_context_fixture_signature:08x}"
                if m2_context_fixture_signature is not None
                else None
            ),
            "expected_context_fixture_signature": (
                f"0x{int(expected_context_fixture_signature):08x}"
                if expected_context_fixture_signature is not None
                else None
            ),
        },
        "preflight_samples": {
            name: [f"0x{value:08x}" for value in values]
            for name, values in preflight_samples.items()
        },
        "preflight_warmup_samples": {
            name: [f"0x{value:08x}" for value in values]
            for name, values in preflight_warmup_samples.items()
        },
        "preflight_stable": preflight_stable,
        "preflight_acceptable": preflight_acceptable,
        "fingerprints": {
            "gate_script_sha256": sha256_file(Path(__file__)),
            "expected_json": str(args.expected_json) if args.expected_json else None,
            "expected_json_sha256": sha256_file(args.expected_json),
            "tb_data_sv": str(args.tb_data_sv) if args.tb_data_sv else None,
            "tb_data_sv_sha256": sha256_file(args.tb_data_sv),
            "embedding_tb_data_sv": str(args.embedding_tb_data_sv) if args.embedding_tb_data_sv else None,
            "embedding_tb_data_sv_sha256": sha256_file(args.embedding_tb_data_sv),
            "context_tb_data_sv": str(args.context_tb_data_sv) if args.context_tb_data_sv else None,
            "context_tb_data_sv_sha256": sha256_file(args.context_tb_data_sv),
            "tb_data_token_index": expected.get("token_index") if args.tb_data_sv else None,
            "token_ids": expected.get("token_ids"),
            "context_fixture_signature": (
                f"0x{int(expected_context_fixture_signature):08x}"
                if expected_context_fixture_signature is not None
                else None
            ),
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
            "context_fixture_signature": (
                f"0x{int(expected_context_fixture_signature):08x}"
                if expected_context_fixture_signature is not None
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
            "input_readback_transform": classify_vector_readback_transform(
                block_input,
                observed["input_readback"],
            ),
            "residual_readback_transform": classify_vector_readback_transform(
                residual,
                observed["residual_readback"],
            ),
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
