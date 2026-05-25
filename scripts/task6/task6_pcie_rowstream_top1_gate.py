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

OP_READ_DENSE_BEAT = 0x06
OP_LOAD_PACKET_BEAT = 0x0F
OP_RUN_HOST_PACKET = 0x10

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
DEFAULT_OUT = ROOT / "artifacts" / "task6" / "runs" / "rowstream-top1-board-summary.json"


def run(cmd: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, text=True, capture_output=True, check=check)


def command_value(bdf: str) -> int:
    return int(run(["setpci", "-s", bdf, "COMMAND"]).stdout.strip(), 16)


def ensure_mem_enabled(bdf: str, device: Path) -> tuple[int, int]:
    before = command_value(bdf)
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


def rd32(mm: mmap.mmap, offset: int) -> int:
    return struct.unpack(">I", bytes(mm[offset : offset + 4]))[0]


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


def read_low_16(mm: mmap.mmap) -> bytes:
    return b"".join(rd32(mm, REG_READ_LOW + index * 4).to_bytes(4, "little") for index in range(4))


def issue_command(
    mm: mmap.mmap,
    opcode: int,
    chunk: int,
    addr: int,
    data: bytes = b"",
    timeout: float = 2.0,
) -> None:
    data = data[:16].ljust(16, b"\0")
    wr32(mm, REG_STATUS, 0x1)
    wr32(mm, REG_CMD_MAGIC, COMMAND_MAGIC)
    wr32(mm, REG_CMD_OPCODE, ((chunk & 0x3) << 8) | (opcode & 0xFF))
    wr32(mm, REG_CMD_ADDR, addr)
    for index in range(4):
        wr32(mm, REG_CMD_DATA0 + index * 4, int.from_bytes(data[index * 4 : index * 4 + 4], "little"))
    accepted_before = rd32(mm, REG_ACCEPTED_COUNT)
    wr32(mm, REG_DOORBELL, 0x1)
    wait_for(mm, REG_STATUS, STATUS_DONE, timeout, "ingress done")
    loader = wait_for(
        mm,
        REG_LOADER_STATUS,
        LOADER_ACCEPTED | LOADER_MAGIC_OK | LOADER_DONE,
        timeout,
        "loader accepted/done",
    )
    status = rd32(mm, REG_STATUS)
    accepted_after = rd32(mm, REG_ACCEPTED_COUNT)
    if status & (STATUS_ERROR | STATUS_DOORBELL_ERROR):
        raise RuntimeError(f"ingress error after opcode 0x{opcode:02x}: status=0x{status:08x}")
    if loader & LOADER_ERROR:
        raise RuntimeError(f"loader error after opcode 0x{opcode:02x}: loader=0x{loader:08x}")
    if accepted_after != ((accepted_before + 1) & 0xFFFFFFFF):
        raise RuntimeError(f"accepted_count did not increment: before={accepted_before} after={accepted_after}")


def load_rowstream(mm: mmap.mmap, image: bytes, start_beat: int, timeout: float, progress_every: int) -> None:
    if len(image) % 16:
        image += bytes(16 - (len(image) % 16))
    total_beats = len(image) // 16
    for packet_start in range(0, total_beats, 4):
        packet = image[packet_start * 16 : (packet_start + 4) * 16]
        beats = len(packet) // 16
        for slot in range(beats):
            slot_data = packet[slot * 16 : (slot + 1) * 16]
            issue_command(mm, OP_LOAD_PACKET_BEAT, 0, slot, slot_data, timeout)
            echoed = read_low_16(mm)
            if echoed != slot_data:
                raise RuntimeError(
                    f"packet slot echo mismatch: slot={slot} expected={slot_data.hex()} observed={echoed.hex()}"
                )
        command_addr = ((start_beat + packet_start) & 0x1FFF_FFFF) | ((beats & 0x7) << 29)
        issue_command(mm, OP_RUN_HOST_PACKET, 0, command_addr, b"", timeout)
        if progress_every and (
            packet_start == 0
            or packet_start + beats == total_beats
            or (packet_start + beats) % progress_every == 0
        ):
            print(f"loaded beats: {packet_start + beats}/{total_beats}")


def verify_loaded_samples(
    mm: mmap.mmap,
    image: bytes,
    start_beat: int,
    timeout: float,
    sample_count: int,
) -> list[dict[str, Any]]:
    if len(image) % 16:
        image += bytes(16 - (len(image) % 16))
    total_beats = len(image) // 16
    if sample_count <= 0:
        return []
    if sample_count >= total_beats:
        beats = list(range(total_beats))
    else:
        beats = sorted({0, total_beats - 1, *(round(i * (total_beats - 1) / max(sample_count - 1, 1)) for i in range(sample_count))})[:sample_count]
    samples = []
    for beat_index in beats:
        issue_command(mm, OP_READ_DENSE_BEAT, 0, start_beat + beat_index, b"", timeout)
        observed = read_low_16(mm)
        expected = image[beat_index * 16 : (beat_index + 1) * 16]
        match = observed == expected
        samples.append(
            {
                "beat": start_beat + beat_index,
                "image_beat": beat_index,
                "expected_hex": expected.hex(),
                "observed_hex": observed.hex(),
                "match": match,
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


def write_hidden(mm: mmap.mmap, hidden_bytes: bytes) -> None:
    if len(hidden_bytes) != 64:
        raise ValueError("top1 hidden vector must be exactly 64 bytes")
    for index in range(16):
        value = int.from_bytes(hidden_bytes[index * 4 : index * 4 + 4], "little")
        wr32(mm, REG_TOP1_HIDDEN + index * 4, value)


def run_board_top1(mm: mmap.mmap, hidden_bytes: bytes, timeout: float) -> dict[str, int]:
    write_hidden(mm, hidden_bytes)
    wr32(mm, REG_TOP1_STATUS, 0x2)
    wait_for(mm, REG_TOP1_STATUS, TOP1_RST_N, timeout, "top1 reset released")
    start_count_before = rd32(mm, REG_TOP1_START_COUNT)
    wr32(mm, REG_TOP1_STATUS, 0x1)
    deadline = time.monotonic() + timeout
    status = rd32(mm, REG_TOP1_STATUS)
    while time.monotonic() < deadline:
        status = rd32(mm, REG_TOP1_STATUS)
        if status & TOP1_ERROR:
            break
        if status & TOP1_DONE:
            break
        time.sleep(0.001)
    if not (status & (TOP1_DONE | TOP1_ERROR)):
        raise TimeoutError(f"timeout waiting for top1 done: status=0x{status:08x}")
    token = rd32(mm, REG_TOP1_TOKEN)
    score_q024 = rd32(mm, REG_TOP1_SCORE_Q024)
    rows_scanned = rd32(mm, REG_TOP1_ROWS_SCANNED)
    cycle_count = rd32(mm, REG_TOP1_CYCLE_COUNT)
    start_count_after = rd32(mm, REG_TOP1_START_COUNT)
    return {
        "status_reg": status,
        "start_count_before": start_count_before,
        "start_count_after": start_count_after,
        "top1_token": token,
        "top1_score_q024": score_q024,
        "rows_scanned": rows_scanned,
        "cycle_count": cycle_count,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bdf", help="PCI BDF, for example 0000:42:00.0")
    parser.add_argument("--image", type=Path, default=DEFAULT_ROWSTREAM, help="packed rowstream image")
    parser.add_argument("--contract-json", type=Path, default=DEFAULT_CONTRACT)
    parser.add_argument("--replay-json", type=Path, default=DEFAULT_REPLAY)
    parser.add_argument("--model-path", type=Path)
    parser.add_argument("--adapter-path", type=Path, default=ROOT / "TinyStories" / "model_adapter.py")
    parser.add_argument("--sample-count", type=int, default=1)
    parser.add_argument("--hidden-q-hex", help="Single 64-byte int8 hidden vector as hex")
    parser.add_argument("--start-beat", type=lambda text: int(text, 0), default=0)
    parser.add_argument("--load-image", action=argparse.BooleanOptionalAction, default=True)
    parser.add_argument("--verify-samples", type=int, default=8)
    parser.add_argument("--poll-timeout", type=float, default=2.0)
    parser.add_argument("--boot-timeout", type=float, default=5.0)
    parser.add_argument("--top1-timeout", type=float, default=20.0)
    parser.add_argument("--progress-every", type=int, default=16384)
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
                load_rowstream(mm, image, args.start_beat, args.poll_timeout, args.progress_every)
                load_verify_samples = verify_loaded_samples(
                    mm,
                    image,
                    args.start_beat,
                    args.poll_timeout,
                    args.verify_samples,
                )

            for payload in sample_payloads:
                expected = expected_by_sample[payload["sample_id"]]
                observed = run_board_top1(
                    mm,
                    hidden_to_bytes(payload["hidden_q"], hidden_size),
                    args.top1_timeout,
                )
                matches_token = observed["top1_token"] == expected["expected_top1_token"]
                matches_score = observed["top1_score_q024"] == expected["expected_top1_score_q024_low32"]
                matches_rows = observed["rows_scanned"] == expected["expected_rows_scanned"]
                no_error = (observed["status_reg"] & TOP1_ERROR) == 0
                board_samples.append(
                    {
                        "sample_id": payload["sample_id"],
                        "token_ids": payload["token_ids"],
                        "hidden_scale": payload["hidden_scale"],
                        **expected,
                        **observed,
                        "matches_token": matches_token,
                        "matches_score_low32": matches_score,
                        "matches_rows_scanned": matches_rows,
                        "no_top1_error": no_error,
                        "matches_expected_replay_top1": (
                            observed["top1_token"] == expected["expected_replay_top1_token"]
                            if expected["expected_replay_top1_token"] is not None
                            else None
                        ),
                    }
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
        "bdf": args.bdf,
        "image": str(args.image),
        "image_sha256": hashlib.sha256(image).hexdigest(),
        "load_image": args.load_image,
        "start_beat": args.start_beat,
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
        "samples": board_samples,
    }
    if args.json_out is not None:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if status == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
