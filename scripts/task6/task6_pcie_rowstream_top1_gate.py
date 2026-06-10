#!/usr/bin/env python3
"""Run the Task 6 DDR3 rowstream top1 compute gate through PCIe BAR regs."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import importlib.util
import json
import mmap
import os
from pathlib import Path
import struct
import subprocess
import time
from typing import Any

TASK6_MAGIC = 0x54365043
TASK6_VERSION = 3
COMMAND_MAGIC = 0x33445244
BAR_SIZE = 4096
ALL_ONES = 0xFFFFFFFF

CONTRACT_VERSION = "task6-host-assisted-rowstream-top1-v1"
CONTRACT_STAGE = "M0-host-assisted-rowstream-top1"
CONTRACT_RESP_HOST = [
    "prompt handling and tokenizer/detokenizer flow",
    "contract/replay/model artifact loading",
    "PCIe lifecycle/recovery orchestration",
    "transformer hidden-state generation from host reference (`--reference-json` or `--model-path`)",
]
CONTRACT_RESP_FPGA = [
    "rowstream load/read sequencing",
    "DDR3 transport and storage",
    "output-head top1 compute scan for fixed-size rowstream rows",
    "status/result/MMIO debug readback",
]

OP_READ_DENSE_BEAT = 0x06
OP_LOAD_PACKET_BEAT = 0x0F
OP_RUN_HOST_PACKET = 0x10
OP_LOAD_PACKET_PAIR = 0x11

REG_MAGIC = 0x000
REG_VERSION = 0x004
REG_STATUS = 0x008
REG_ACCEPTED_COUNT = 0x00C
REG_CMD_MAGIC = 0x010
REG_CMD_OPCODE = 0x014
REG_CMD_ADDR = 0x018
REG_CMD_DATA0 = 0x020
REG_DOORBELL = 0x030
REG_LOADER_STATUS = 0x034
REG_READ_LOW = 0x044

REG_TOP1_STATUS = 0x060
REG_TOP1_START_COUNT = 0x064
REG_TOP1_TOKEN = 0x068
REG_TOP1_SCORE_Q024 = 0x06C
REG_TOP1_ROWS_SCANNED = 0x070
REG_TOP1_CYCLE_COUNT = 0x074
REG_TOP1_HIDDEN = 0x080
REG_DEBUG_TOP1_STATUS = 0x21C
REG_DEBUG_TOP1_READER_ADDR = 0x220
REG_DEBUG_TOP1_WB_ACK_OR_FAULT_TOKEN = 0x224
REG_DEBUG_TOP1_WB_ERR_OR_FAULT_SIDECAR = 0x228
REG_TOP1_PACKET_WB_WRITE_ACK_COUNT = 0x22C
REG_TOP1_PACKET_WB_READ_ACK_COUNT = 0x230

STATUS_RST_N = 1 << 0
STATUS_DONE = 1 << 2
STATUS_ERROR = 1 << 3
STATUS_DOORBELL_ERROR = 1 << 4
STATUS_BOOT_DONE = 1 << 5

LOADER_CALIB_COMPLETE = 1 << 0
LOADER_BOOT_DONE = 1 << 1
LOADER_DONE = 1 << 2
LOADER_ERROR = 1 << 3
LOADER_MAGIC_OK = 1 << 4
LOADER_ACCEPTED = 1 << 5

TOP1_RST_N = 1 << 0
TOP1_BUSY = 1 << 1
TOP1_DONE = 1 << 2
TOP1_ERROR = 1 << 3

TOP1_DEBUG_BITS = (
    (0, "rst_n"),
    (1, "ddr_debug_ok"),
    (2, "calib_complete"),
    (3, "read_probe_done"),
    (4, "start_accepted"),
    (5, "start_rejected"),
    (6, "reader_busy"),
    (7, "reader_done"),
    (8, "reader_error"),
    (9, "reader_wb_cyc"),
    (10, "reader_wb_stb"),
    (11, "reader_wb_we"),
    (12, "wb_stall"),
    (13, "reader_wb_ack"),
    (14, "reader_wb_err"),
    (15, "cutout_valid"),
    (16, "cutout_done"),
    (17, "cutout_busy"),
    (18, "cutout_reserved_error"),
    (19, "row_valid"),
    (20, "row_ready"),
    (21, "row_last"),
    (22, "row0_sidecar_decode_mismatch"),
)

SCRIPT_ROOT = Path(__file__).resolve().parents[2]
ROOT = Path(os.environ.get("TASK6_REPO_ROOT", SCRIPT_ROOT if (SCRIPT_ROOT / "artifacts").exists() else Path.cwd())).resolve()
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
DEFAULT_REFERENCE = (
    ROOT
    / "artifacts"
    / "task6"
    / "parallel-hypotheses"
    / "h2-tinystories-1m-prompt-output-head-q024-reference.json"
)
DEFAULT_OUT = ROOT / "artifacts" / "task6" / "runs" / "rowstream-top1-board-summary.json"


def run(cmd: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, text=True, capture_output=True, check=check)


def command_value(bdf: str) -> int:
    return int(run(["setpci", "-s", bdf, "COMMAND"]).stdout.strip(), 16)


def ensure_mem_enabled(bdf: str, device: Path) -> tuple[int, int]:
    before = command_value(bdf)
    if before & 0x0002:
        return before, before
    if os.geteuid() != 0:
        raise SystemExit(
            f"PCI memory space is disabled for {bdf}. Install/trigger the "
            "Task 6 YPCB PCIe udev rule so it can enable the endpoint and "
            "grant plugdev access to resource0."
        )
    desired = before | 0x0002
    result = run(["setpci", "-s", bdf, f"COMMAND={desired:04x}"], check=False)
    after = command_value(bdf)
    if (after & 0x0002) == 0:
        enable = device / "enable"
        if enable.exists():
            enable.write_text("1\n")
            after = command_value(bdf)
    if (after & 0x0002) == 0:
        stderr = result.stderr.strip()
        raise SystemExit(
            f"PCI memory space did not enable: before=0x{before:04x} "
            f"after=0x{after:04x} {stderr}"
        )
    return before, after


def rd32_raw(mm: mmap.mmap, offset: int) -> int:
    return struct.unpack(">I", bytes(mm[offset : offset + 4]))[0]


def rd32(mm: mmap.mmap, offset: int) -> int:
    value = rd32_raw(mm, offset)
    for _ in range(4):
        if value != ALL_ONES:
            return value
        time.sleep(0.00005)
        value = rd32_raw(mm, offset)
    return value


def wr32(mm: mmap.mmap, offset: int, value: int) -> None:
    mm[offset : offset + 4] = struct.pack(">I", value & 0xFFFFFFFF)
    _ = mm[0:4]


def wait_for(mm: mmap.mmap, offset: int, mask: int, timeout: float, label: str) -> int:
    deadline = time.monotonic() + timeout
    value = rd32(mm, offset)
    while (value & mask) != mask and time.monotonic() < deadline:
        time.sleep(0.001)
        value = rd32(mm, offset)
    if (value & mask) != mask:
        raise TimeoutError(
            f"timeout waiting for {label}: offset=0x{offset:03x} value=0x{value:08x}"
        )
    return value


def wait_clear(mm: mmap.mmap, offset: int, mask: int, timeout: float, label: str) -> int:
    deadline = time.monotonic() + timeout
    value = rd32(mm, offset)
    while (value & mask) != 0 and time.monotonic() < deadline:
        time.sleep(0.001)
        value = rd32(mm, offset)
    if (value & mask) != 0:
        raise TimeoutError(
            f"timeout waiting for {label} to clear: offset=0x{offset:03x} value=0x{value:08x}"
        )
    return value


def read_low_16(mm: mmap.mmap) -> bytes:
    return b"".join(rd32(mm, REG_READ_LOW + index * 4).to_bytes(4, "little") for index in range(4))


def u32_delta(later: int, earlier: int) -> int:
    return (later - earlier) & 0xFFFFFFFF


def wait_for_packet_ack_deltas(
    mm: mmap.mmap,
    before_write_ack: int,
    before_read_ack: int,
    expected_write_ack: int,
    expected_read_ack: int,
    timeout: float,
    label: str,
) -> tuple[int, int]:
    deadline = time.monotonic() + timeout
    write_ack = rd32(mm, REG_TOP1_PACKET_WB_WRITE_ACK_COUNT)
    read_ack = rd32(mm, REG_TOP1_PACKET_WB_READ_ACK_COUNT)
    while (
        u32_delta(write_ack, before_write_ack) < expected_write_ack
        or u32_delta(read_ack, before_read_ack) < expected_read_ack
    ) and time.monotonic() < deadline:
        time.sleep(0.0001)
        write_ack = rd32(mm, REG_TOP1_PACKET_WB_WRITE_ACK_COUNT)
        read_ack = rd32(mm, REG_TOP1_PACKET_WB_READ_ACK_COUNT)

    if u32_delta(write_ack, before_write_ack) < expected_write_ack:
        raise TimeoutError(
            f"timeout waiting for {label}: write ack delta did not reach {expected_write_ack} "
            f"from=0x{before_write_ack:08x} to=0x{write_ack:08x}"
        )
    if u32_delta(read_ack, before_read_ack) < expected_read_ack:
        raise TimeoutError(
            f"timeout waiting for {label}: read ack delta did not reach {expected_read_ack} "
            f"from=0x{before_read_ack:08x} to=0x{read_ack:08x}"
        )
    return write_ack, read_ack


def packet_ack_counters_available(mm: mmap.mmap) -> bool:
    write_ack = rd32(mm, REG_TOP1_PACKET_WB_WRITE_ACK_COUNT)
    read_ack = rd32(mm, REG_TOP1_PACKET_WB_READ_ACK_COUNT)
    return write_ack != ALL_ONES and read_ack != ALL_ONES


def wait_accepted_count(mm: mmap.mmap, before: int, timeout: float, label: str) -> int:
    expected = (before + 1) & 0xFFFFFFFF
    deadline = time.monotonic() + timeout
    value = rd32(mm, REG_ACCEPTED_COUNT)
    while value != expected and time.monotonic() < deadline:
        time.sleep(0.0001)
        value = rd32(mm, REG_ACCEPTED_COUNT)
    if value != expected:
        raise TimeoutError(f"timeout waiting for {label}: before={before} observed={value}")
    return value


def issue_command(
    mm: mmap.mmap,
    opcode: int,
    chunk: int,
    addr: int,
    data: bytes = b"",
    timeout: float = 2.0,
) -> None:
    data = data[:16].ljust(16, b"\0")
    # Break the ingress duplicate-write filter before pulsing the sticky-status
    # clear bit. This matters after failed or interrupted gates where the last
    # accepted BAR write may also have been REG_STATUS=1.
    wr32(mm, REG_STATUS, 0x0)
    wr32(mm, REG_STATUS, 0x1)
    wr32(mm, REG_CMD_MAGIC, COMMAND_MAGIC)
    wr32(mm, REG_CMD_OPCODE, ((chunk & 0x3) << 8) | (opcode & 0xFF))
    wr32(mm, REG_CMD_ADDR, addr)
    for index in range(4):
        wr32(mm, REG_CMD_DATA0 + index * 4, int.from_bytes(data[index * 4 : index * 4 + 4], "little"))
    accepted_before = rd32(mm, REG_ACCEPTED_COUNT)
    wr32(mm, REG_DOORBELL, 0x1)
    wait_for(mm, REG_STATUS, STATUS_DONE, timeout, "ingress done")
    wait_accepted_count(mm, accepted_before, timeout, f"accepted_count opcode=0x{opcode:02x}")
    loader = wait_for(
        mm,
        REG_LOADER_STATUS,
        LOADER_ACCEPTED | LOADER_MAGIC_OK | LOADER_DONE,
        timeout,
        "loader accepted/done",
    )
    status = rd32(mm, REG_STATUS)
    if status & (STATUS_ERROR | STATUS_DOORBELL_ERROR):
        raise RuntimeError(f"ingress error after opcode 0x{opcode:02x}: status=0x{status:08x}")
    if loader & LOADER_ERROR:
        raise RuntimeError(f"loader error after opcode 0x{opcode:02x}: loader=0x{loader:08x}")


def wait_packet_slot_echo(
    mm: mmap.mmap,
    expected: bytes,
    timeout: float,
    label: str,
) -> bytes:
    deadline = time.monotonic() + min(timeout, 0.1)
    observed = read_low_16(mm)[: len(expected)]
    while observed != expected and time.monotonic() < deadline:
        time.sleep(0.0001)
        observed = read_low_16(mm)[: len(expected)]
    if observed != expected:
        raise RuntimeError(
            f"packet slot echo mismatch: {label} expected={expected.hex()} observed={observed.hex()}"
        )
    return observed


def load_rowstream(
    mm: mmap.mmap,
    image: bytes,
    start_beat: int,
    timeout: float,
    progress_every: int,
    beat_bytes: int,
    packet_ack_mode: str,
    packet_settle: float,
    packet_echo_mode: str,
    packet_echo_limit_beats: int | None,
    progress_settle: float,
    packet_beats: int,
    packet_load_mode: str,
) -> dict[str, Any]:
    if len(image) % beat_bytes:
        image += bytes(beat_bytes - (len(image) % beat_bytes))
    total_beats = len(image) // beat_bytes
    ack_supported = packet_ack_counters_available(mm)
    if packet_ack_mode == "require" and not ack_supported:
        raise RuntimeError("packet ACK counters are required but read as unavailable/all-ones")
    ack_fallback_count = 0
    packet_count = 0
    for packet_start in range(0, total_beats, packet_beats):
        packet_count += 1
        packet = image[packet_start * beat_bytes : (packet_start + packet_beats) * beat_bytes]
        beats = len(packet) // beat_bytes
        if beat_bytes == 8 and packet_load_mode == "pair":
            for slot in range(0, beats, 2):
                slot_data = packet[slot * beat_bytes : min((slot + 2) * beat_bytes, len(packet))]
                slot_data = slot_data.ljust(16, b"\0")
                issue_command(mm, OP_LOAD_PACKET_PAIR, 0, slot, slot_data, timeout)
                absolute_beat = packet_start + slot
                echo_enabled = packet_echo_limit_beats is None or absolute_beat < packet_echo_limit_beats
                if packet_echo_mode == "require" and echo_enabled:
                    wait_packet_slot_echo(mm, slot_data[:8], timeout, f"slot_pair={slot}")
                elif packet_echo_mode == "auto" and echo_enabled:
                    try:
                        wait_packet_slot_echo(mm, slot_data[:8], timeout, f"slot_pair={slot}")
                    except RuntimeError:
                        packet_echo_mode = "off"
        else:
            for slot in range(beats):
                slot_data = packet[slot * beat_bytes : (slot + 1) * beat_bytes]
                issue_command(mm, OP_LOAD_PACKET_BEAT, 0, slot, slot_data, timeout)
                absolute_beat = packet_start + slot
                echo_enabled = packet_echo_limit_beats is None or absolute_beat < packet_echo_limit_beats
                if packet_echo_mode == "require" and echo_enabled:
                    wait_packet_slot_echo(mm, slot_data, timeout, f"slot={slot}")
                elif packet_echo_mode == "auto" and echo_enabled:
                    try:
                        wait_packet_slot_echo(mm, slot_data, timeout, f"slot={slot}")
                    except RuntimeError:
                        packet_echo_mode = "off"
        command_addr = ((start_beat + packet_start) & 0x1FFF_FFFF) | ((beats & 0x7) << 29)
        packet_write_ack_before = rd32(mm, REG_TOP1_PACKET_WB_WRITE_ACK_COUNT)
        packet_read_ack_before = rd32(mm, REG_TOP1_PACKET_WB_READ_ACK_COUNT)
        issue_command(mm, OP_RUN_HOST_PACKET, 0, command_addr, b"", timeout)
        if packet_ack_mode != "off" and ack_supported:
            try:
                wait_for_packet_ack_deltas(
                    mm,
                    packet_write_ack_before,
                    packet_read_ack_before,
                    expected_write_ack=beats,
                    expected_read_ack=0,
                    timeout=timeout,
                    label=f"packet beat commit packet_start={packet_start} beats={beats}",
                )
            except TimeoutError:
                if packet_ack_mode == "require":
                    raise
                ack_supported = False
                ack_fallback_count += 1
                if packet_settle > 0:
                    time.sleep(packet_settle)
        else:
            ack_fallback_count += 1
            if packet_settle > 0:
                time.sleep(packet_settle)
        if progress_every and (
            packet_start == 0
            or packet_start + beats == total_beats
            or (packet_start + beats) % progress_every == 0
        ):
            print(f"loaded beats: {packet_start + beats}/{total_beats}")
            if progress_settle > 0:
                time.sleep(progress_settle)
    return {
        "packet_count": packet_count,
        "packet_ack_mode": packet_ack_mode,
        "packet_ack_supported_initial": ack_supported,
        "packet_ack_fallback_count": ack_fallback_count,
        "packet_settle_seconds": packet_settle,
        "packet_echo_mode_final": packet_echo_mode,
        "packet_echo_limit_beats": packet_echo_limit_beats,
        "progress_settle_seconds": progress_settle,
        "packet_beats": packet_beats,
        "packet_load_mode": packet_load_mode,
    }


def verify_loaded_samples(
    mm: mmap.mmap,
    image: bytes,
    start_beat: int,
    timeout: float,
    sample_count: int,
    beat_bytes: int,
    retries: int,
) -> list[dict[str, Any]]:
    if len(image) % beat_bytes:
        image += bytes(beat_bytes - (len(image) % beat_bytes))
    total_beats = len(image) // beat_bytes
    if sample_count <= 0:
        return []
    if sample_count >= total_beats:
        beats = list(range(total_beats))
    else:
        beats = sorted({0, total_beats - 1, *(round(i * (total_beats - 1) / max(sample_count - 1, 1)) for i in range(sample_count))})[:sample_count]
    samples = []
    for beat_index in beats:
        expected = image[beat_index * beat_bytes : (beat_index + 1) * beat_bytes]
        observed = b""
        match = False
        retry_count = 0
        for attempt in range(max(1, retries + 1)):
            # The loader exposes sticky status bits across a PCIe-to-rowstream
            # CDC. After a long packet load, give the read command and BAR
            # shadow a small margin before accepting sampled readback evidence.
            time.sleep(0.001 * (attempt + 1))
            issue_command(mm, OP_READ_DENSE_BEAT, 0, start_beat + beat_index, b"", timeout)
            observed = read_low_16(mm)[:beat_bytes]
            match = observed == expected
            retry_count = attempt
            if match:
                break
        samples.append(
            {
                "beat": start_beat + beat_index,
                "image_beat": beat_index,
                "expected_hex": expected.hex(),
                "observed_hex": observed.hex(),
                "match": match,
                "retry_count": retry_count,
            }
        )
        if not match:
            raise RuntimeError(
                f"verify mismatch at beat {beat_index}: expected={expected.hex()} observed={observed.hex()}"
            )
    return samples


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
    return (token // rows_per_group) * image["group_bytes"] + (token % rows_per_group) * row_bytes


def parse_hidden_q_hex(value: str, hidden_size: int) -> list[int]:
    data = bytes.fromhex(value.strip().replace("_", "").replace(" ", ""))
    if len(data) != hidden_size:
        raise SystemExit(f"--hidden-q-hex decoded to {len(data)} bytes, expected {hidden_size}")
    return [byte_to_signed(byte) for byte in data]


def hidden_to_bytes(hidden_q: list[int], hidden_size: int) -> bytes:
    if len(hidden_q) != hidden_size:
        raise SystemExit(f"hidden vector has {len(hidden_q)} entries, expected {hidden_size}")
    return bytes(value & 0xFF for value in hidden_q)


def scan_rowstream_top1(image: bytes, contract: dict[str, Any], hidden_q: list[int]) -> tuple[int, int, int, int]:
    vocab_size = contract["model"]["vocab_size"]
    hidden_size = contract["model"]["hidden_size"]
    row_bytes = contract["row_format"]["row_bytes"]
    if len(hidden_q) != hidden_size:
        raise SystemExit(f"hidden vector has {len(hidden_q)} entries, expected {hidden_size}")
    best_token = 0xFFFF
    best_score = -(1 << 45)
    rows_scanned = 0
    reserved_nonzero_count = 0
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


def build_sample_hidden_vectors(model_path: Path, adapter_path: Path, sample_count: int) -> list[dict[str, Any]]:
    helper = load_helper_module()
    import torch

    build_model = helper.load_adapter_build_model(adapter_path)
    model = build_model(str(model_path)).eval()
    samples = helper.DEFAULT_SAMPLES[:sample_count]
    payloads = []
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


def build_reference_hidden_vectors(reference: dict[str, Any], hidden_size: int) -> list[dict[str, Any]]:
    steps = reference.get("steps")
    if not isinstance(steps, list) or not steps:
        raise SystemExit("reference JSON does not contain a non-empty steps array")

    generation = reference.get("generation") or {}
    expected_tokens = generation.get("q024_generated_token_ids") or []
    payloads = []
    for index, step in enumerate(steps):
        hidden_q = step.get("hidden_q")
        if not isinstance(hidden_q, list):
            raise SystemExit(f"reference step {index} is missing hidden_q")
        if len(hidden_q) != hidden_size:
            raise SystemExit(
                f"reference step {index} hidden_q has {len(hidden_q)} entries, expected {hidden_size}"
            )
        expected_topk = step.get("q024_topk_token_ids") or []
        expected_token = expected_topk[0] if expected_topk else None
        if index < len(expected_tokens) and expected_token is not None and expected_tokens[index] != expected_token:
            raise SystemExit(
                f"reference step {index} disagrees: generation token {expected_tokens[index]} "
                f"!= q024_topk_token_ids[0] {expected_token}"
            )
        payloads.append(
            {
                "sample_id": f"prompt_step_{index}",
                "reference_step": index,
                "token_ids": step.get("q024_context_token_ids"),
                "hidden_scale": step.get("hidden_scale"),
                "hidden_q": [int(value) for value in hidden_q],
                "reference_expected_top1_token": expected_token,
                "reference_expected_top1_text": (step.get("q024_topk_text") or [None])[0],
                "reference_expected_score_low32": (
                    (step.get("q024_topk_scores_low32") or [None])[0]
                ),
                "reference_tokens_match_f32_top1": step.get("tokens_match_f32_top1"),
            }
        )
    return payloads


def write_hidden(mm: mmap.mmap, hidden_bytes: bytes) -> None:
    if len(hidden_bytes) != 64:
        raise ValueError("top1 hidden vector must be exactly 64 bytes")
    for index in range(16):
        value = int.from_bytes(hidden_bytes[index * 4 : index * 4 + 4], "little")
        wr32(mm, REG_TOP1_HIDDEN + index * 4, value)


def read_hidden(mm: mmap.mmap) -> bytes:
    return b"".join(
        rd32(mm, REG_TOP1_HIDDEN + index * 4).to_bytes(4, "little")
        for index in range(16)
    )


def decode_bit_names(value: int, bits: tuple[tuple[int, str], ...]) -> list[str]:
    return [name for bit, name in bits if value & (1 << bit)]


def read_top1_debug(mm: mmap.mmap) -> dict[str, Any]:
    status = rd32(mm, REG_DEBUG_TOP1_STATUS)
    fault_word = rd32(mm, REG_DEBUG_TOP1_WB_ACK_OR_FAULT_TOKEN)
    fault_sidecar = rd32(mm, REG_DEBUG_TOP1_WB_ERR_OR_FAULT_SIDECAR)
    fault_addr = rd32(mm, REG_DEBUG_TOP1_READER_ADDR)
    return {
        "debug_top1_status": status,
        "debug_top1_status_bits": decode_bit_names(status, TOP1_DEBUG_BITS),
        "debug_top1_reader_addr": fault_addr,
        "debug_top1_fault_seen": bool(fault_word & 0x00010000),
        "debug_top1_fault_token": fault_word & 0xFFFF,
        "debug_top1_fault_sidecar": fault_sidecar,
    }


def clear_top1_status(mm: mmap.mmap, timeout: float) -> None:
    # Break the ingress duplicate-write filter before issuing the clear pulse.
    wr32(mm, REG_TOP1_STATUS, 0x0)
    wr32(mm, REG_TOP1_STATUS, 0x2)
    wait_for(mm, REG_TOP1_STATUS, TOP1_RST_N, timeout, "top1 reset released")
    try:
        wait_clear(
            mm,
            REG_TOP1_STATUS,
            TOP1_BUSY | TOP1_DONE,
            timeout,
            "top1 busy/done",
        )
    except TimeoutError:
        wr32(mm, REG_TOP1_STATUS, 0x0)
        wr32(mm, REG_TOP1_STATUS, 0x2)
        wait_clear(
            mm,
            REG_TOP1_STATUS,
            TOP1_BUSY | TOP1_DONE,
            min(timeout, 5.0),
            "top1 busy/done after retry",
        )
    # The board RTL stretches clear into a short reader/cutout reset window in
    # the rowstream clock domain. TOP1_RST_N reflects the global reset, not
    # that local clear window, so give the CDC pulse time to retire before the
    # start doorbell.
    time.sleep(0.001)


def run_board_top1(mm: mmap.mmap, hidden_bytes: bytes, timeout: float, retries: int = 0) -> dict[str, int]:
    return run_board_top1_with_retries(mm, hidden_bytes, timeout, retries=retries)


def run_board_top1_with_retries(
    mm: mmap.mmap,
    hidden_bytes: bytes,
    timeout: float,
    *,
    retries: int,
) -> dict[str, int]:
    last: dict[str, int] | None = None
    for retry_count in range(retries + 1):
        write_hidden(mm, hidden_bytes)
        clear_top1_status(mm, timeout)
        start_count_before = rd32(mm, REG_TOP1_START_COUNT)
        wr32(mm, REG_TOP1_STATUS, 0x1)
        deadline = time.monotonic() + timeout
        status = rd32(mm, REG_TOP1_STATUS)
        start_count_after = rd32(mm, REG_TOP1_START_COUNT)
        while time.monotonic() < deadline:
            status = rd32(mm, REG_TOP1_STATUS)
            start_count_after = rd32(mm, REG_TOP1_START_COUNT)
            start_seen = start_count_after != start_count_before
            if start_seen and (status & TOP1_DONE):
                break
            time.sleep(0.001)
        if start_count_after == start_count_before:
            raise TimeoutError(
                f"timeout waiting for top1 start acceptance: status=0x{status:08x} "
                f"start_count={start_count_after}"
            )
        if not (status & (TOP1_DONE | TOP1_ERROR)):
            raise TimeoutError(f"timeout waiting for top1 done: status=0x{status:08x}")
        token = rd32(mm, REG_TOP1_TOKEN)
        score_q024 = rd32(mm, REG_TOP1_SCORE_Q024)
        rows_scanned = rd32(mm, REG_TOP1_ROWS_SCANNED)
        cycle_count = rd32(mm, REG_TOP1_CYCLE_COUNT)
        last = {
            "status_reg": status,
            "start_count_before": start_count_before,
            "start_count_after": start_count_after,
            "top1_token": token,
            "top1_score_q024": score_q024,
            "rows_scanned": rows_scanned,
            "cycle_count": cycle_count,
            "retry_count": retry_count,
        }
        transient_zero_row_error = bool(status & TOP1_ERROR) and rows_scanned == 0 and cycle_count == 0
        if transient_zero_row_error and retry_count < retries:
            time.sleep(0.05)
            continue
        return last
    assert last is not None
    return last


def verify_loaded_rows(
    mm: mmap.mmap,
    image: bytes,
    contract: dict[str, Any],
    tokens: list[int],
    start_beat: int,
    timeout: float,
    beat_bytes: int,
    retries: int,
) -> list[dict[str, Any]]:
    row_bytes = contract["row_format"]["row_bytes"]
    results = []
    for token in sorted(set(tokens)):
        offset = row_offset(token, contract)
        first_beat = offset // beat_bytes
        phase = offset % beat_bytes
        beat_count = (phase + row_bytes + beat_bytes - 1) // beat_bytes
        observed_window = b""
        for beat_delta in range(beat_count):
            observed_beat = b""
            for attempt in range(max(1, retries + 1)):
                time.sleep(0.001 * (attempt + 1))
                issue_command(
                    mm,
                    OP_READ_DENSE_BEAT,
                    0,
                    start_beat + first_beat + beat_delta,
                    b"",
                    timeout,
                )
                observed_beat = read_low_16(mm)[:beat_bytes]
                if len(observed_beat) == beat_bytes:
                    break
            observed_window += observed_beat
        observed = observed_window[phase : phase + row_bytes]
        expected = image[offset : offset + row_bytes]
        results.append(
            {
                "token": token,
                "offset": offset,
                "first_beat": start_beat + first_beat,
                "phase": phase,
                "beat_count": beat_count,
                "expected_sha256": hashlib.sha256(expected).hexdigest(),
                "observed_sha256": hashlib.sha256(observed).hexdigest(),
                "match": observed == expected,
                "expected_sidecar_hex": expected[-4:].hex(),
                "observed_sidecar_hex": observed[-4:].hex(),
                "expected_first16_hex": expected[:16].hex(),
                "observed_first16_hex": observed[:16].hex(),
            }
        )
    return results


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bdf", help="PCI BDF, for example 0000:42:00.0")
    parser.add_argument("--image", type=Path, default=DEFAULT_ROWSTREAM, help="packed rowstream image")
    parser.add_argument("--contract-json", type=Path, default=DEFAULT_CONTRACT)
    parser.add_argument("--replay-json", type=Path, default=DEFAULT_REPLAY)
    parser.add_argument(
        "--reference-json",
        type=Path,
        help=(
            "Prompt-level generation reference JSON. Replays each step's hidden_q "
            "and compares board top1 against q024_topk_token_ids[0]."
        ),
    )
    parser.add_argument("--model-path", type=Path)
    parser.add_argument("--adapter-path", type=Path, default=ROOT / "TinyStories" / "model_adapter.py")
    parser.add_argument("--sample-count", type=int, default=1)
    parser.add_argument("--hidden-q-hex", help="Single 64-byte int8 hidden vector as hex")
    parser.add_argument("--start-beat", type=lambda text: int(text, 0), default=0)
    parser.add_argument("--beat-bytes", type=int, choices=(8, 16), default=8, help="DDR Wishbone beat size in bytes; one-lane UberDDR3 uses 8, two-lane uses 16")
    parser.add_argument("--load-image", action=argparse.BooleanOptionalAction, default=True)
    parser.add_argument("--verify-samples", type=int, default=8)
    parser.add_argument("--verify-retries", type=int, default=3)
    parser.add_argument(
        "--verify-token-rows",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Read back exact DDR rows for expected/observed top1 tokens.",
    )
    parser.add_argument("--poll-timeout", type=float, default=2.0)
    parser.add_argument("--boot-timeout", type=float, default=5.0)
    parser.add_argument("--top1-timeout", type=float, default=20.0)
    parser.add_argument(
        "--top1-retries",
        type=int,
        default=8,
        help="bounded retries for transient zero-row top1 errors immediately after loader completion",
    )
    parser.add_argument("--progress-every", type=int, default=16384)
    parser.add_argument(
        "--packet-beats",
        type=int,
        choices=(4,),
        default=4,
        help="DDR beats per committed host packet. The current reduced-BAR path keeps the proven 4-beat commit.",
    )
    parser.add_argument(
        "--packet-load-mode",
        choices=("single", "pair"),
        default="pair",
        help="Use pair mode with new RTL to load two 8-byte slots per BAR command.",
    )
    parser.add_argument(
        "--packet-ack-mode",
        choices=("auto", "require", "off"),
        default="auto",
        help="Packet commit wait policy. auto uses ACK counters when live and falls back to --packet-settle.",
    )
    parser.add_argument(
        "--packet-settle",
        type=float,
        default=0.001,
        help="Seconds to wait after OP_RUN_HOST_PACKET when packet ACK counters are unavailable or inactive.",
    )
    parser.add_argument(
        "--packet-echo-mode",
        choices=("auto", "require", "off"),
        default="require",
        help="Packet slot echo policy before packet commit. Default require preserves the strict acceptance gate.",
    )
    parser.add_argument(
        "--packet-echo-limit-beats",
        type=int,
        default=-1,
        help="Only echo-check the first N rowstream beats; -1 keeps checking every beat.",
    )
    parser.add_argument(
        "--progress-settle",
        type=float,
        default=0.0,
        help="Seconds to sleep after each progress checkpoint during rowstream load.",
    )
    parser.add_argument("--json-out", type=Path, default=DEFAULT_OUT)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    contract = read_json(args.contract_json)
    replay = read_json(args.replay_json)
    image = args.image.read_bytes()
    expected_size = contract["ddr3_linear_image"]["padded_stream_bytes"]
    if len(image) != expected_size:
        raise SystemExit(f"rowstream has {len(image)} bytes, expected {expected_size}")

    hidden_size = contract["model"]["hidden_size"]
    if hidden_size != 64:
        raise SystemExit(f"this BAR gate expects 64-byte hidden vectors, got hidden_size={hidden_size}")
    sample_sources = sum(
        1
        for enabled in (
            bool(args.reference_json),
            bool(args.hidden_q_hex),
            bool(args.model_path),
        )
        if enabled
    )
    if sample_sources != 1:
        raise SystemExit("specify exactly one of --reference-json, --hidden-q-hex, or --model-path")

    reference_metadata: dict[str, Any] | None = None
    if args.reference_json:
        reference = read_json(args.reference_json)
        reference_metadata = {
            "path": str(args.reference_json),
            "artifact_name": reference.get("artifact_name"),
            "status": reference.get("status"),
            "prompt": reference.get("prompt"),
            "generation": reference.get("generation"),
        }
        sample_payloads = build_reference_hidden_vectors(reference, hidden_size)
    elif args.hidden_q_hex:
        sample_payloads = [
            {
                "sample_id": "host_hidden_q_hex",
                "token_ids": None,
                "hidden_scale": None,
                "hidden_q": parse_hidden_q_hex(args.hidden_q_hex, hidden_size),
            }
        ]
    else:
        sample_payloads = build_sample_hidden_vectors(args.model_path, args.adapter_path, args.sample_count)

    replay_by_sample = {entry["sample_id"]: entry for entry in replay.get("samples", [])}
    expected_by_sample = {}
    reserved_nonzero_count = 0
    for payload in sample_payloads:
        token, score, rows_scanned, sample_reserved = scan_rowstream_top1(image, contract, payload["hidden_q"])
        reserved_nonzero_count += sample_reserved
        replay_expected = None
        if payload["sample_id"] in replay_by_sample:
            replay_expected = replay_by_sample[payload["sample_id"]]["rowwise_q024_top5"][0]
        expected_by_sample[payload["sample_id"]] = {
            "expected_top1_token": token,
            "expected_top1_score_q024_signed": score,
            "expected_top1_score_q024_low32": score & 0xFFFFFFFF,
            "expected_rows_scanned": rows_scanned,
            "expected_replay_top1_token": replay_expected,
            "expected_reference_top1_token": payload.get("reference_expected_top1_token"),
            "expected_reference_top1_text": payload.get("reference_expected_top1_text"),
            "expected_reference_score_low32": payload.get("reference_expected_score_low32"),
        }

    device = Path("/sys/bus/pci/devices") / args.bdf
    resource0 = device / "resource0"
    if not resource0.exists():
        raise SystemExit(f"missing BAR0 sysfs resource: {resource0}")

    print(run(["lspci", "-s", args.bdf]).stdout.strip())
    before, after = ensure_mem_enabled(args.bdf, device)
    print(f"COMMAND before: 0x{before:04x}")
    print(f"COMMAND after:  0x{after:04x}")

    started = time.monotonic()
    load_verify_samples: list[dict[str, Any]] = []
    token_row_verify_samples: list[dict[str, Any]] = []
    load_metadata: dict[str, Any] | None = None
    board_samples = []
    fd = os.open(resource0, os.O_RDWR | os.O_SYNC)
    try:
        with mmap.mmap(fd, BAR_SIZE, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE) as mm:
            magic = rd32(mm, REG_MAGIC)
            version = rd32(mm, REG_VERSION)
            status = rd32(mm, REG_STATUS)
            loader = rd32(mm, REG_LOADER_STATUS)
            top1_status = rd32(mm, REG_TOP1_STATUS)
            print(f"magic:       0x{magic:08x}")
            print(f"version:     {version}")
            print(f"status:      0x{status:08x}")
            print(f"loader:      0x{loader:08x}")
            print(f"top1_status: 0x{top1_status:08x}")
            if magic == ALL_ONES and version == ALL_ONES:
                raise SystemExit("BAR0 returned all ones; endpoint may be stale")
            if magic != TASK6_MAGIC:
                raise SystemExit(f"bad magic: expected 0x{TASK6_MAGIC:08x}, got 0x{magic:08x}")
            if version != TASK6_VERSION:
                raise SystemExit(f"bad version: expected {TASK6_VERSION}, got {version}")
            wait_for(mm, REG_STATUS, STATUS_RST_N | STATUS_BOOT_DONE, args.boot_timeout, "DDR boot_done")

            if args.load_image:
                load_metadata = load_rowstream(
                    mm,
                    image,
                    args.start_beat,
                    args.poll_timeout,
                    args.progress_every,
                    args.beat_bytes,
                    args.packet_ack_mode,
                    args.packet_settle,
                    args.packet_echo_mode,
                    None if args.packet_echo_limit_beats < 0 else args.packet_echo_limit_beats,
                    args.progress_settle,
                    args.packet_beats,
                    args.packet_load_mode,
                )
                load_verify_samples = verify_loaded_samples(
                    mm,
                    image,
                    args.start_beat,
                    args.poll_timeout,
                    args.verify_samples,
                    args.beat_bytes,
                    args.verify_retries,
                )

            for payload in sample_payloads:
                expected = expected_by_sample[payload["sample_id"]]
                hidden_bytes = hidden_to_bytes(payload["hidden_q"], hidden_size)
                write_hidden(mm, hidden_bytes)
                hidden_readback = read_hidden(mm)
                top1_debug_before = read_top1_debug(mm)
                observed = run_board_top1(
                    mm,
                    hidden_bytes,
                    args.top1_timeout,
                    args.top1_retries,
                )
                top1_debug_after = read_top1_debug(mm)
                matches_token = observed["top1_token"] == expected["expected_top1_token"]
                matches_score = observed["top1_score_q024"] == expected["expected_top1_score_q024_low32"]
                matches_rows = observed["rows_scanned"] == expected["expected_rows_scanned"]
                no_error = (observed["status_reg"] & TOP1_ERROR) == 0
                board_samples.append(
                    {
                        "sample_id": payload["sample_id"],
                        "reference_step": payload.get("reference_step"),
                        "token_ids": payload["token_ids"],
                        "hidden_scale": payload["hidden_scale"],
                        "reference_tokens_match_f32_top1": payload.get("reference_tokens_match_f32_top1"),
                        **expected,
                        **observed,
                        "hidden_mmio_readback_match": hidden_readback == hidden_bytes,
                        "hidden_mmio_readback_sha256": hashlib.sha256(hidden_readback).hexdigest(),
                        "top1_debug_before": top1_debug_before,
                        "top1_debug_after": top1_debug_after,
                        "matches_token": matches_token,
                        "matches_score_low32": matches_score,
                        "matches_rows_scanned": matches_rows,
                        "no_top1_error": no_error,
                        "matches_expected_replay_top1": (
                            observed["top1_token"] == expected["expected_replay_top1_token"]
                            if expected["expected_replay_top1_token"] is not None
                            else None
                        ),
                        "matches_expected_reference_top1": (
                            observed["top1_token"] == expected["expected_reference_top1_token"]
                            if expected["expected_reference_top1_token"] is not None
                            else None
                        ),
                        "matches_expected_reference_score_low32": (
                            observed["top1_score_q024"] == expected["expected_reference_score_low32"]
                            if expected["expected_reference_score_low32"] is not None
                            else None
                        ),
                    }
                )
                if args.verify_token_rows:
                    token_row_verify_samples.extend(
                        verify_loaded_rows(
                            mm,
                            image,
                            contract,
                            [
                                int(expected["expected_top1_token"]),
                                int(observed["top1_token"]),
                            ],
                            args.start_beat,
                            args.poll_timeout,
                            args.beat_bytes,
                            args.verify_retries,
                        )
                    )
    finally:
        os.close(fd)

    mismatch_count = sum(
        1
        for sample in board_samples
        if not (
            sample["matches_token"]
            and sample["matches_score_low32"]
            and sample["matches_rows_scanned"]
            and sample["no_top1_error"]
        )
    )
    status = "PASS" if mismatch_count == 0 and reserved_nonzero_count == 0 else "FAIL"
    elapsed = time.monotonic() - started
    result = {
        "artifact_name": "task6-pcie-rowstream-top1-board-gate",
        "status": status,
        "date": dt.date.today().isoformat(),
        "contract": {
            "version": CONTRACT_VERSION,
            "stage": CONTRACT_STAGE,
            "responsibilities": {
                "host": CONTRACT_RESP_HOST,
                "fpga": CONTRACT_RESP_FPGA,
            },
            "notes": "Host-assisted transformer hidden-state generation; board performs output-head top1 over rowstream.",
        },
        "bdf": args.bdf,
        "image": str(args.image),
        "image_sha256": hashlib.sha256(image).hexdigest(),
        "reference": reference_metadata,
        "load_image": args.load_image,
        "load_metadata": load_metadata,
        "start_beat": args.start_beat,
        "beat_bytes": args.beat_bytes,
        "elapsed_seconds": elapsed,
        "model": {
            "model_label": contract["model"].get("model_label"),
            "vocab_size": contract["model"]["vocab_size"],
            "hidden_size": hidden_size,
            "sample_count": len(board_samples),
        },
        "validation": {
            "mismatch_count": mismatch_count,
            "reserved_nonzero_count": reserved_nonzero_count,
            "hardware_top1_used": True,
            "score_compare": "low32 of signed Q0.24 product, matching current BAR result width",
        },
        "load_verify_samples": load_verify_samples,
        "token_row_verify_samples": token_row_verify_samples,
        "samples": board_samples,
    }
    if args.json_out is not None:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if status == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
