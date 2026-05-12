#!/usr/bin/env python3
"""Load and verify the Task 6 rowstream image through the DDR3 JTAG loader."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import time
from typing import Any

from read_jtag_debug_ftdi_bitbang import (
    FTDI_FT232H_PRODUCT,
    FTDI_VENDOR,
    FtdiBitbangJtag,
    FtdiMpsseJtag,
)
from read_jtag_debug_xvc import reset_tap, shift_dr_read, shift_ir
from write_jtag_command_ftdi_bitbang import shift_dr_write


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
DEFAULT_RUN_ROOT = ROOT / "artifacts" / "task6" / "runs"

DEBUG_BITS = 512
DEBUG_MAGIC = 0x54364A44
DEBUG_VERSION = 61
COMMAND_BITS = 192
COMMAND_MAGIC = 0x33445244
OP_WRITE_CHUNK = 0x01
OP_READ_BEAT = 0x02
OP_WRITE_LOWBYTE = 0x03
OP_READ_LOWBYTE = 0x04
OP_WRITE_DENSE_BYTE = 0x05
OP_READ_DENSE_BEAT = 0x06
OP_RUN_AUTOPROBE = 0x07
OP_WRITE_DENSE_FILL = 0x08
OP_RUN_FULLBEAT = 0x09
BEAT_BYTES = 64


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bitstream", type=Path)
    parser.add_argument("--rowstream-bin", type=Path, default=DEFAULT_ROWSTREAM)
    parser.add_argument("--contract-json", type=Path, default=DEFAULT_CONTRACT)
    parser.add_argument("--replay-json", type=Path, default=DEFAULT_REPLAY)
    parser.add_argument("--run-dir", type=Path)
    parser.add_argument("--program", action=argparse.BooleanOptionalAction, default=True)
    parser.add_argument("--jtag-cable", default="digilent_hs3")
    parser.add_argument("--serial", default="210299BF3824")
    parser.add_argument("--vid", type=lambda value: int(value, 0), default=FTDI_VENDOR)
    parser.add_argument("--pid", type=lambda value: int(value, 0), default=FTDI_FT232H_PRODUCT)
    parser.add_argument("--backend", choices=("mpsse", "bitbang"), default="mpsse")
    parser.add_argument("--freq-hz", type=int, default=1_000_000)
    parser.add_argument("--tdo-bit", type=int, choices=(0, 7), default=7)
    parser.add_argument("--bit-delay-us", type=float, default=0.0)
    parser.add_argument("--ir-len", type=int, default=6)
    parser.add_argument("--debug-ir", type=lambda value: int(value, 0), default=0x02)
    parser.add_argument("--command-ir", type=lambda value: int(value, 0), default=0x03)
    parser.add_argument("--command-delay", type=float, default=0.001)
    parser.add_argument(
        "--command-repeats",
        type=int,
        default=2,
        help="send each loader command this many times; v33 accepts every other USER2 event",
    )
    parser.add_argument("--poll-timeout", type=float, default=5.0)
    parser.add_argument("--calib-timeout", type=float, default=20.0)
    parser.add_argument(
        "--storage-mode",
        choices=("lowbyte", "beat"),
        default="lowbyte",
        help=(
            "lowbyte stores one rowstream byte in DDR3 byte lane 0 at one "
            "Wishbone address per stream byte; beat uses dense 64-byte beats"
        ),
    )
    parser.add_argument("--max-beats", type=int, help="debug limit; default loads the full image")
    parser.add_argument(
        "--max-bytes",
        type=int,
        help="debug limit for --storage-mode lowbyte; default loads the full image",
    )
    parser.add_argument("--progress-beats", type=int, default=1024)
    parser.add_argument("--progress-bytes", type=int, default=65536)
    parser.add_argument("--boundary-tokens", default="0,1,31,32,50256")
    parser.add_argument(
        "--load-boundary-rows-only",
        action=argparse.BooleanOptionalAction,
        default=False,
        help=(
            "in lowbyte mode, write only the row byte ranges named by "
            "--boundary-tokens for a fast first/boundary row proof"
        ),
    )
    parser.add_argument("--full-readback", action=argparse.BooleanOptionalAction, default=True)
    parser.add_argument(
        "--boot-only",
        action="store_true",
        help=(
            "program the bitstream, wait for DDR3 calibration, record the "
            "BIST-derived boot status, and exit before any loader commands"
        ),
    )
    parser.add_argument(
        "--diagnostic-lowbyte-count",
        type=int,
        default=0,
        help=(
            "before rowstream loading, write values 0..N-1 to low-byte sparse "
            "addresses 0..N-1, read them back, emit a diagnostic JSON, and exit"
        ),
    )
    parser.add_argument(
        "--diagnostic-dense-count",
        type=int,
        default=0,
        help=(
            "before rowstream loading, write values 0..N-1 through dense byte-lane "
            "commands, read full beat 0, emit a diagnostic JSON, and exit"
        ),
    )
    parser.add_argument(
        "--diagnostic-dense-lane-map-count",
        type=int,
        default=0,
        help=(
            "before rowstream loading, write one nonzero sentinel per dense byte "
            "lane up to N, read beat 0 after each write, emit a lane-map JSON, "
            "and exit"
        ),
    )
    parser.add_argument(
        "--diagnostic-readbeat-addr",
        type=int,
        default=None,
        help=(
            "before rowstream loading, read one 512-bit beat address through the "
            "read-only diagnostic command, capture the lower 16 bytes, emit a "
            "diagnostic JSON, and exit"
        ),
    )
    parser.add_argument(
        "--diagnostic-fillbeat-value",
        type=lambda value: int(value, 0),
        default=None,
        help=(
            "before rowstream loading, write one full 512-bit beat with a repeated "
            "byte through the v35 lowbyte/full-width write path, read the same dense "
            "beat address, emit a diagnostic JSON, and exit"
        ),
    )
    parser.add_argument(
        "--diagnostic-fillbeat-addr",
        type=lambda value: int(value, 0),
        default=0,
        help="beat address for --diagnostic-fillbeat-value; default: 0",
    )
    parser.add_argument(
        "--diagnostic-fullbeat-addr",
        type=lambda value: int(value, 0),
        default=None,
        help=(
            "before rowstream loading, write one 64-byte ramp through the "
            "full-beat chunk protocol, read all four chunks back, emit a "
            "diagnostic JSON, and exit"
        ),
    )
    parser.add_argument(
        "--diagnostic-autoprobe-value",
        type=lambda value: int(value, 0),
        default=None,
        help=(
            "launch one board-side UberDDR3 write/read probe from a single JTAG "
            "command, emit a diagnostic JSON, and exit"
        ),
    )
    parser.add_argument(
        "--diagnostic-autoprobe-addr",
        type=lambda value: int(value, 0),
        default=0,
        help="stream base address for --diagnostic-autoprobe-value; default: 0",
    )
    parser.add_argument(
        "--diagnostic-denseburst-value",
        type=lambda value: int(value, 0),
        default=None,
        help=(
            "launch one board-side full-512-bit DDR3 fill write "
            "from a single JTAG command, emit a diagnostic JSON, and exit"
        ),
    )
    parser.add_argument(
        "--diagnostic-denseburst-addr",
        type=lambda value: int(value, 0),
        default=0,
        help="Wishbone beat address for --diagnostic-denseburst-value; default: 0",
    )
    parser.add_argument(
        "--diagnostic-rtl-fullbeat-base",
        type=lambda value: int(value, 0),
        default=None,
        help=(
            "launch one board-side generated 64-byte ramp write/read/compare "
            "from a single RTL command, emit a diagnostic JSON, and exit"
        ),
    )
    parser.add_argument(
        "--diagnostic-rtl-fullbeat-addr",
        type=lambda value: int(value, 0),
        default=0,
        help="Wishbone beat address for --diagnostic-rtl-fullbeat-base; default: 0",
    )
    parser.add_argument("--top1-from-model", action=argparse.BooleanOptionalAction, default=False)
    parser.add_argument("--model-path", type=Path)
    parser.add_argument("--adapter-path", type=Path)
    parser.add_argument("--sample-count", type=int, default=8)
    parser.add_argument("--json-only", action="store_true")
    return parser.parse_args()


def read_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def json_debug(debug: dict[str, Any]) -> dict[str, Any]:
    return {key: value for key, value in debug.items() if not isinstance(value, bytes)}


def row_offset(token: int, contract: dict[str, Any]) -> int:
    image = contract["ddr3_linear_image"]
    row_bytes = contract["row_format"]["row_bytes"]
    rows_per_group = image["rows_per_group"]
    return (token // rows_per_group) * image["group_bytes"] + (token % rows_per_group) * row_bytes


def byte_to_signed(value: int) -> int:
    return value - 256 if value >= 128 else value


def load_helper_module() -> Any:
    helper_path = ROOT / "scripts" / "task6" / "check_full_vocab_rowwise_topk_contract.py"
    spec = importlib.util.spec_from_file_location("task6_topk_helper", helper_path)
    if spec is None or spec.loader is None:
        raise SystemExit(f"unable to load helper from {helper_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def scan_rowstream_top1(
    image: bytes, contract: dict[str, Any], hidden_q: list[int]
) -> tuple[int, int, int]:
    vocab_size = contract["model"]["vocab_size"]
    hidden_size = contract["model"]["hidden_size"]
    row_bytes = contract["row_format"]["row_bytes"]
    best_token = 0xFFFF
    best_score = -(1 << 45)
    reserved_nonzero_count = 0

    for token in range(vocab_size):
        offset = row_offset(token, contract)
        row = image[offset : offset + row_bytes]
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
    return best_token, best_score, reserved_nonzero_count


def compute_top1_from_image(
    image: bytes,
    contract: dict[str, Any],
    replay: dict[str, Any],
    model_path: Path,
    adapter_path: Path,
    sample_count: int,
) -> dict[str, Any]:
    helper = load_helper_module()
    import torch

    build_model = helper.load_adapter_build_model(adapter_path)
    model = build_model(str(model_path)).eval()
    replay_by_sample = {entry["sample_id"]: entry for entry in replay["samples"]}
    samples = helper.DEFAULT_SAMPLES[:sample_count]
    sample_payloads = []
    mismatch_count = 0
    reserved_nonzero_count = 0

    with torch.no_grad():
        for sample_id, token_ids in samples:
            input_ids = torch.tensor([token_ids], dtype=torch.long)
            transformer_out = model.transformer(input_ids=input_ids, use_cache=False)
            hidden = transformer_out.last_hidden_state[0, -1].detach().cpu().to(torch.float64)
            hidden_q_tensor, _hidden_scale = helper.quantize_symmetric_tensor(hidden)
            hidden_q = [int(value) for value in hidden_q_tensor.cpu().tolist()]
            token, score, sample_reserved = scan_rowstream_top1(image, contract, hidden_q)
            expected = replay_by_sample[sample_id]["rowwise_q024_top5"][0]
            mismatch = token != expected
            mismatch_count += int(mismatch)
            reserved_nonzero_count += sample_reserved
            sample_payloads.append(
                {
                    "sample_id": sample_id,
                    "token_ids": token_ids,
                    "ddr3_readback_top1_token": token,
                    "ddr3_readback_top1_score_q024": score,
                    "expected_rowstream_top1_token": expected,
                    "matches_expected": not mismatch,
                }
            )

    return {
        "sample_count": len(samples),
        "mismatch_count": mismatch_count,
        "reserved_nonzero_count": reserved_nonzero_count,
        "samples": sample_payloads,
        "status": "PASS" if mismatch_count == 0 and reserved_nonzero_count == 0 else "FAIL",
    }


def make_command(opcode: int, chunk: int, addr: int, data: bytes = b"") -> int:
    if len(data) > 16:
        raise ValueError("command chunk data must fit in 16 bytes")
    payload = COMMAND_MAGIC
    payload |= (opcode & 0xFF) << 32
    payload |= (chunk & 0x3) << 40
    payload |= (addr & 0xFFFF_FFFF) << 48
    for index, byte in enumerate(data):
        payload |= (byte & 0xFF) << (64 + index * 8)
    return payload


def decode_debug(raw: int) -> dict[str, Any]:
    status = (raw >> 40) & 0xFF
    command_word = (raw >> 272) & 0xFFFF_FFFF
    loader_word = (raw >> 304) & 0xFFFF_FFFF
    read_data_int = (raw >> 336) & ((1 << 128) - 1)
    read_data_chunk = read_data_int.to_bytes(16, "little")
    return {
        "raw_hex": f"0x{raw:0{DEBUG_BITS // 4}x}",
        "magic": raw & 0xFFFF_FFFF,
        "magic_ok": (raw & 0xFFFF_FFFF) == DEBUG_MAGIC,
        "version": (raw >> 32) & 0xFF,
        "status": status,
        "calib_complete": bool(status & 0x1),
        "calib_seen": bool(status & 0x2),
        "cycle": (raw >> 48) & 0xFFFF_FFFF,
        "calib_seen_cycle": (raw >> 80) & 0xFFFF_FFFF,
        "debug1": (raw >> 112) & 0xFFFF_FFFF,
        "wb_ack_count": (raw >> 144) & 0xFFFF_FFFF,
        "wb_err_count": (raw >> 176) & 0xFFFF_FFFF,
        "wb_stall_count": (raw >> 208) & 0xFFFF_FFFF,
        "rtl_fullbeat_write_echo32": (raw >> 240) & 0xFFFF_FFFF,
        "command_count": (command_word >> 18) & 0xFF,
        "last_opcode": (command_word >> 10) & 0xFF,
        "last_chunk": (command_word >> 2) & 0x3,
        "last_magic_ok": bool(command_word & 0x2),
        "last_accepted": bool(command_word & 0x1),
        "loader_state": loader_word & 0xF,
        "loader_stb": bool(loader_word & (1 << 4)),
        "loader_cyc": bool(loader_word & (1 << 5)),
        "loader_done": bool(loader_word & (1 << 6)),
        "loader_write_ack_seen": bool(loader_word & (1 << 7)),
        "loader_read_ack_seen": bool(loader_word & (1 << 8)),
        "loader_error": bool(loader_word & (1 << 9)),
        "loader_stall_seen": bool(loader_word & (1 << 10)),
        "boot_done": bool(loader_word & (1 << 11)),
        "boot_write_ack_seen": bool(loader_word & (1 << 12)),
        "boot_read_ack_seen": bool(loader_word & (1 << 13)),
        "boot_error": bool(loader_word & (1 << 14)),
        "boot_stall_seen": bool(loader_word & (1 << 15)),
        "boot_mismatch": bool(loader_word & (1 << 16)),
        "loader_wait_cycles": (raw >> 464) & 0xFFFF_FFFF,
        "last_addr_low15": (raw >> 496) & 0x7FFF,
        "dense_write_seen": bool((raw >> 464) & 0x1),
        "dense_write_wb_addr_low16": (raw >> 465) & 0xFFFF,
        "dense_write_lane": (raw >> 481) & 0x3F,
        "dense_write_data": (raw >> 487) & 0xFF,
        "dense_write_sel_low16": (raw >> 496) & 0xFFFF,
        "dense_burst_active": bool((raw >> 464) & 0x1),
        "dense_burst_mismatch_count": (raw >> 465) & 0x7F,
        "dense_burst_addr_low24": (raw >> 472) & 0xFF_FFFF,
        "dense_burst_expected_base": (raw >> 496) & 0xFF,
        "read_data_chunk": read_data_chunk,
        "read_data_beat": read_data_chunk + bytes(BEAT_BYTES - len(read_data_chunk)),
    }


class RowstreamLoader:
    def __init__(self, args: argparse.Namespace):
        self.args = args
        if args.backend == "mpsse":
            self.client = FtdiMpsseJtag(
                serial=args.serial,
                vid=args.vid,
                pid=args.pid,
                freq_hz=args.freq_hz,
                tdo_bit=args.tdo_bit,
            )
        else:
            self.client = FtdiBitbangJtag(
                serial=args.serial,
                vid=args.vid,
                pid=args.pid,
                delay_s=args.bit_delay_us / 1_000_000.0,
            )
        reset_tap(self.client)

    def close(self) -> None:
        self.client.close()

    def read_debug(self) -> dict[str, Any]:
        shift_ir(self.client, self.args.debug_ir, self.args.ir_len)
        return decode_debug(shift_dr_read(self.client, DEBUG_BITS))

    def send_command(self, opcode: int, chunk: int, addr: int, data: bytes = b"") -> None:
        shift_ir(self.client, self.args.command_ir, self.args.ir_len)
        command = make_command(opcode, chunk, addr, data)
        for _repeat in range(self.args.command_repeats):
            shift_dr_write(
                self.client,
                command,
                COMMAND_BITS,
                "idle",
            )
            if self.args.command_delay > 0:
                time.sleep(self.args.command_delay)

    def wait_ready(self, min_ack_count: int | None = None) -> dict[str, Any]:
        deadline = time.monotonic() + self.args.poll_timeout
        last = self.read_debug()
        while time.monotonic() < deadline:
            if (
                last["magic_ok"]
                and last["version"] == DEBUG_VERSION
                and not last["loader_error"]
                and last["loader_state"] == 1
                and (min_ack_count is None or last["wb_ack_count"] >= min_ack_count)
            ):
                return last
            time.sleep(0.01)
            last = self.read_debug()
        raise TimeoutError(f"loader did not become ready: {summarize_debug(last)}")

    def wait_calibration(self) -> dict[str, Any]:
        deadline = time.monotonic() + self.args.calib_timeout
        last = self.read_debug()
        while time.monotonic() < deadline:
            if last["magic_ok"] and last["version"] == DEBUG_VERSION and last["calib_seen"]:
                return self.wait_ready()
            time.sleep(0.1)
            last = self.read_debug()
        raise TimeoutError(f"DDR3 calibration did not complete: {summarize_debug(last)}")

    def write_beat(self, beat_addr: int, data: bytes) -> dict[str, Any]:
        if len(data) != BEAT_BYTES:
            raise ValueError("write_beat requires exactly 64 bytes")
        before = self.read_debug()
        min_ack = before["wb_ack_count"] + 1
        for chunk in range(4):
            self.send_command(
                OP_WRITE_CHUNK,
                chunk,
                beat_addr,
                data[chunk * 16 : (chunk + 1) * 16],
            )
        return self.wait_ready(min_ack_count=min_ack)

    def read_beat(self, beat_addr: int) -> tuple[bytes, dict[str, Any]]:
        chunks = []
        debug = self.read_debug()
        for chunk in range(4):
            before = self.read_debug()
            min_ack = before["wb_ack_count"] + 1
            self.send_command(OP_READ_BEAT, chunk, beat_addr)
            debug = self.wait_ready(min_ack_count=min_ack)
            chunks.append(debug["read_data_chunk"])
        return b"".join(chunks), debug

    def write_lowbyte(self, stream_addr: int, value: int) -> dict[str, Any]:
        before = self.read_debug()
        min_ack = before["wb_ack_count"] + 1
        self.send_command(OP_WRITE_LOWBYTE, 0, stream_addr, bytes([value & 0xFF]))
        return self.wait_ready(min_ack_count=min_ack)

    def read_lowbyte(self, stream_addr: int) -> tuple[int, dict[str, Any]]:
        before = self.read_debug()
        min_ack = before["wb_ack_count"] + 1
        self.send_command(OP_READ_LOWBYTE, 0, stream_addr)
        debug = self.wait_ready(min_ack_count=min_ack)
        return debug["read_data_chunk"][0], debug

    def write_dense_byte(self, stream_addr: int, value: int) -> dict[str, Any]:
        before = self.read_debug()
        min_ack = before["wb_ack_count"] + 1
        self.send_command(OP_WRITE_DENSE_BYTE, 0, stream_addr, bytes([value & 0xFF]))
        return self.wait_ready(min_ack_count=min_ack)

    def read_dense_beat(self, beat_addr: int) -> tuple[bytes, dict[str, Any]]:
        before = self.read_debug()
        min_ack = before["wb_ack_count"] + 1
        self.send_command(OP_READ_DENSE_BEAT, 0, beat_addr)
        debug = self.wait_ready(min_ack_count=min_ack)
        return debug["read_data_beat"], debug

    def run_autoprobe(self, stream_base: int, value: int) -> dict[str, Any]:
        before = self.read_debug()
        min_ack = before["wb_ack_count"] + 1
        self.send_command(OP_RUN_AUTOPROBE, 0, stream_base, bytes([value & 0xFF]))
        return self.wait_ready(min_ack_count=min_ack)

    def run_dense_fill_write(self, beat_addr: int, value: int) -> dict[str, Any]:
        before = self.read_debug()
        min_ack = before["wb_ack_count"] + 1
        self.send_command(OP_WRITE_DENSE_FILL, 0, beat_addr, bytes([value & 0xFF]))
        return self.wait_ready(min_ack_count=min_ack)

    def run_rtl_fullbeat(self, beat_addr: int, base: int) -> dict[str, Any]:
        before = self.read_debug()
        min_ack = before["wb_ack_count"] + 2
        self.send_command(OP_RUN_FULLBEAT, 0, beat_addr, bytes([base & 0xFF]))
        return self.wait_ready(min_ack_count=min_ack)


def summarize_debug(debug: dict[str, Any]) -> str:
    return (
        f"magic_ok={debug.get('magic_ok')} version={debug.get('version')} "
        f"calib_seen={debug.get('calib_seen')} state={debug.get('loader_state')} "
        f"ack={debug.get('wb_ack_count')} err={debug.get('wb_err_count')} "
        f"loader_error={debug.get('loader_error')} debug1=0x{debug.get('debug1', 0):08x}"
    )


def make_run_dir(base: Path | None, label: str) -> Path:
    if base is not None:
        base.mkdir(parents=True, exist_ok=True)
        return base
    stamp = dt.datetime.now().astimezone().strftime("%Y-%m-%dT%H-%M-%S%z")
    safe_label = "".join(char if char.isalnum() or char in "-_" else "-" for char in label)
    run_dir = DEFAULT_RUN_ROOT / f"{stamp}-ypcb-ddr3-rowstream-loader-{safe_label}"
    run_dir.mkdir(parents=True, exist_ok=False)
    return run_dir


def program_bitstream(args: argparse.Namespace, run_dir: Path) -> None:
    if not args.program:
        return
    if args.bitstream is None:
        raise SystemExit("--bitstream is required when --program is enabled")
    log_path = run_dir / "program.log"
    command = [
        "openFPGALoader",
        "-c",
        args.jtag_cable,
        "--ftdi-serial",
        args.serial,
        str(args.bitstream),
    ]
    with log_path.open("w", encoding="utf-8") as log:
        subprocess.run(command, check=True, stdout=log, stderr=subprocess.STDOUT)


def run_lowbyte_diagnostic(
    loader: RowstreamLoader, count: int, run_dir: Path, initial_debug: dict[str, Any]
) -> dict[str, Any]:
    if count <= 0:
        raise ValueError("diagnostic count must be positive")
    writes = []
    readback = []
    for stream_addr in range(count):
        value = stream_addr & 0xFF
        debug = loader.write_lowbyte(stream_addr, value)
        writes.append(
            {
                "stream_addr": stream_addr,
                "value": value,
                "ack_count": debug["wb_ack_count"],
                "err_count": debug["wb_err_count"],
                "loader_error": debug["loader_error"],
            }
        )
    for stream_addr in range(count):
        value, debug = loader.read_lowbyte(stream_addr)
        expected = stream_addr & 0xFF
        readback.append(
            {
                "stream_addr": stream_addr,
                "expected": expected,
                "observed": value,
                "match": value == expected,
                "ack_count": debug["wb_ack_count"],
                "err_count": debug["wb_err_count"],
                "loader_error": debug["loader_error"],
            }
        )
    mismatch_count = sum(1 for row in readback if not row["match"])
    final_debug = loader.read_debug()
    payload = {
        "artifact_name": "task6-ypcb-uberddr3-lowbyte-0n-board-diagnostic",
        "status": "PASS" if mismatch_count == 0 else "FAIL",
        "count": count,
        "mismatch_count": mismatch_count,
        "initial_debug": json_debug(initial_debug),
        "final_debug": json_debug(final_debug),
        "writes": writes,
        "readback": readback,
        "decision": {
            "verdict": (
                "sparse-lowbyte-contract-passes"
                if mismatch_count == 0
                else "sparse-lowbyte-contract-fails"
            ),
            "next_gate": (
                "If this passes, add dense byte-lane write/read commands; if it "
                "fails, debug the current v35 sparse command path before rowstream."
            ),
        },
    }
    write_json(run_dir / "lowbyte-diagnostic.json", payload)
    return payload


def run_dense_diagnostic(
    loader: RowstreamLoader, count: int, run_dir: Path, initial_debug: dict[str, Any]
) -> dict[str, Any]:
    if count <= 0 or count > 16:
        raise ValueError("dense diagnostic count must be in 1..16 for the 512-bit debug build")
    if (
        not bool(initial_debug["boot_done"])
        or bool(initial_debug["boot_error"])
        or bool(initial_debug["boot_mismatch"])
    ):
        final_debug = loader.read_debug()
        payload = {
            "artifact_name": "task6-ypcb-uberddr3-dense-byte-0n-board-diagnostic",
            "status": "FAIL",
            "count": count,
            "mismatch_count": None,
            "initial_debug": json_debug(initial_debug),
            "final_debug": json_debug(final_debug),
            "writes": [],
            "readback": [],
            "decision": {
                "verdict": "dense-byte-diagnostic-blocked-by-unclean-boot",
                "next_gate": (
                    "Do not interpret dense byte-lane readback until the "
                    "BIST-derived boot gate is clean."
                ),
            },
        }
        write_json(run_dir / "dense-diagnostic.json", payload)
        return payload

    writes = []
    for stream_addr in range(count):
        value = stream_addr & 0xFF
        debug = loader.write_dense_byte(stream_addr, value)
        writes.append(
            {
                "stream_addr": stream_addr,
                "wb_addr": stream_addr // BEAT_BYTES,
                "lane": stream_addr % BEAT_BYTES,
                "value": value,
                "ack_count": debug["wb_ack_count"],
                "err_count": debug["wb_err_count"],
                "loader_error": debug["loader_error"],
            }
        )

    beat, read_debug = loader.read_dense_beat(0)
    expected = bytes(range(count))
    observed_prefix = beat[:count]
    readback = [
        {
            "lane": lane,
            "expected": expected[lane],
            "observed": observed_prefix[lane],
            "match": observed_prefix[lane] == expected[lane],
        }
        for lane in range(count)
    ]
    mismatch_count = sum(1 for row in readback if not row["match"])
    final_debug = loader.read_debug()
    payload = {
        "artifact_name": "task6-ypcb-uberddr3-dense-byte-0n-board-diagnostic",
        "status": "PASS" if mismatch_count == 0 else "FAIL",
        "count": count,
        "mismatch_count": mismatch_count,
        "initial_debug": json_debug(initial_debug),
        "read_debug": json_debug(read_debug),
        "final_debug": json_debug(final_debug),
        "writes": writes,
        "beat0_hex": beat.hex(),
        "beat0_prefix_hex": observed_prefix.hex(),
        "expected_prefix_hex": expected.hex(),
        "readback": readback,
        "decision": {
            "verdict": (
                "dense-byte-contract-passes"
                if mismatch_count == 0
                else "dense-byte-contract-fails"
            ),
            "next_gate": (
                "If this passes, convert rowstream loading to dense byte lanes; "
                "if it fails, inspect full beat for lane permutation or stale capture."
            ),
        },
    }
    write_json(run_dir / "dense-diagnostic.json", payload)
    return payload


def run_dense_lane_map_diagnostic(
    loader: RowstreamLoader, count: int, run_dir: Path, initial_debug: dict[str, Any]
) -> dict[str, Any]:
    if count <= 0 or count > 16:
        raise ValueError("dense lane-map count must be in 1..16 for the 512-bit debug build")
    if (
        not bool(initial_debug["boot_done"])
        or bool(initial_debug["boot_error"])
        or bool(initial_debug["boot_mismatch"])
    ):
        final_debug = loader.read_debug()
        payload = {
            "artifact_name": "task6-ypcb-uberddr3-dense-byte-lane-map-board-diagnostic",
            "status": "FAIL",
            "count": count,
            "initial_debug": json_debug(initial_debug),
            "final_debug": json_debug(final_debug),
            "samples": [],
            "decision": {
                "verdict": "dense-lane-map-blocked-by-unclean-boot",
                "next_gate": "Do not interpret lane data until boot_mismatch=false.",
            },
        }
        write_json(run_dir / "dense-lane-map-diagnostic.json", payload)
        return payload

    samples = []
    pass_status = True
    for lane in range(count):
        value = (0x80 + lane) & 0xFF
        write_debug = loader.write_dense_byte(lane, value)
        beat, read_debug = loader.read_dense_beat(0)
        lower128 = beat[:16]
        sample_ok = (
            not bool(write_debug["loader_error"])
            and not bool(read_debug["loader_error"])
            and write_debug["wb_err_count"] == initial_debug["wb_err_count"]
            and read_debug["wb_err_count"] == initial_debug["wb_err_count"]
            and bool(write_debug["loader_write_ack_seen"])
            and bool(read_debug["loader_read_ack_seen"])
        )
        pass_status = pass_status and sample_ok
        samples.append(
            {
                "lane": lane,
                "value": value,
                "lower128_hex": lower128.hex(),
                "observed_at_lane": lower128[lane],
                "target_lane_match": lower128[lane] == value,
                "matching_lanes": [
                    index for index, observed in enumerate(lower128) if observed == value
                ],
                "write_ack_count": write_debug["wb_ack_count"],
                "read_ack_count": read_debug["wb_ack_count"],
                "write_loader_error": write_debug["loader_error"],
                "read_loader_error": read_debug["loader_error"],
            }
        )

    final_debug = loader.read_debug()
    payload = {
        "artifact_name": "task6-ypcb-uberddr3-dense-byte-lane-map-board-diagnostic",
        "status": "PASS" if pass_status else "FAIL",
        "count": count,
        "initial_debug": json_debug(initial_debug),
        "final_debug": json_debug(final_debug),
        "samples": samples,
        "decision": {
            "verdict": (
                "dense-lane-map-captured"
                if pass_status
                else "dense-lane-map-transport-failed"
            ),
            "next_gate": (
                "Use matching_lanes and lower128_hex to determine whether the "
                "dense path needs byte-select remapping, data remapping, or a "
                "controller-native full-beat writer."
            ),
        },
    }
    write_json(run_dir / "dense-lane-map-diagnostic.json", payload)
    return payload


def run_readbeat_diagnostic(
    loader: RowstreamLoader, beat_addr: int, run_dir: Path, initial_debug: dict[str, Any]
) -> dict[str, Any]:
    beat, read_debug = loader.read_dense_beat(beat_addr)
    final_debug = loader.read_debug()
    boot_clean = (
        bool(initial_debug["boot_done"])
        and not bool(initial_debug["boot_error"])
        and not bool(initial_debug["boot_mismatch"])
        and not bool(read_debug["loader_error"])
        and read_debug["wb_err_count"] == initial_debug["wb_err_count"]
    )
    payload = {
        "artifact_name": "task6-ypcb-uberddr3-readbeat-lower128-board-diagnostic",
        "status": "PASS" if boot_clean else "FAIL",
        "beat_addr": beat_addr,
        "lower128_hex": beat[:16].hex(),
        "initial_debug": json_debug(initial_debug),
        "read_debug": json_debug(read_debug),
        "final_debug": json_debug(final_debug),
        "decision": {
            "verdict": (
                "read-only-beat-capture-preserves-boot"
                if boot_clean
                else "read-only-beat-capture-or-boot-gate-fails"
            ),
            "next_gate": (
                "If this passes, add dense write-select generation in a separate "
                "variant; if it fails, return to the exact v35 boot datapath."
            ),
        },
    }
    write_json(run_dir / "readbeat-diagnostic.json", payload)
    return payload


def run_fillbeat_diagnostic(
    loader: RowstreamLoader,
    value: int,
    beat_addr: int,
    run_dir: Path,
    initial_debug: dict[str, Any],
) -> dict[str, Any]:
    if value < 0 or value > 0xFF:
        raise ValueError("fillbeat diagnostic value must fit in one byte")
    if beat_addr < 0:
        raise ValueError("fillbeat diagnostic address must be non-negative")
    if (
        not bool(initial_debug["boot_done"])
        or bool(initial_debug["boot_error"])
        or bool(initial_debug["boot_mismatch"])
    ):
        final_debug = loader.read_debug()
        payload = {
            "artifact_name": "task6-ypcb-uberddr3-fillbeat-board-diagnostic",
            "status": "FAIL",
            "value": value,
            "beat_addr": beat_addr,
            "mismatch_count": None,
            "initial_debug": json_debug(initial_debug),
            "final_debug": json_debug(final_debug),
            "decision": {
                "verdict": "fillbeat-diagnostic-blocked-by-unclean-boot",
                "next_gate": (
                    "Do not interpret write/read diagnostics until the "
                    "BIST-derived boot gate is clean."
                ),
            },
        }
        write_json(run_dir / "fillbeat-diagnostic.json", payload)
        return payload

    write_debug = loader.write_lowbyte(beat_addr, value)
    lowbyte_value, lowbyte_read_debug = loader.read_lowbyte(beat_addr)
    beat, read_debug = loader.read_dense_beat(beat_addr)
    expected = bytes([value & 0xFF]) * BEAT_BYTES
    readback = [
        {
            "lane": lane,
            "expected": expected[lane],
            "observed": beat[lane],
            "match": beat[lane] == expected[lane],
        }
        for lane in range(BEAT_BYTES)
    ]
    mismatch_count = sum(1 for row in readback if not row["match"])
    final_debug = loader.read_debug()
    payload = {
        "artifact_name": "task6-ypcb-uberddr3-fillbeat-board-diagnostic",
        "status": "PASS" if mismatch_count == 0 else "FAIL",
        "value": value,
        "beat_addr": beat_addr,
        "mismatch_count": mismatch_count,
        "initial_debug": json_debug(initial_debug),
        "write_debug": json_debug(write_debug),
        "lowbyte_read_debug": json_debug(lowbyte_read_debug),
        "lowbyte_observed": lowbyte_value,
        "lowbyte_match": lowbyte_value == (value & 0xFF),
        "read_debug": json_debug(read_debug),
        "final_debug": json_debug(final_debug),
        "beat0_hex": beat.hex(),
        "beat0_prefix_hex": beat[:16].hex(),
        "expected_prefix_hex": expected[:16].hex(),
        "readback": readback,
        "decision": {
            "verdict": (
                "fillbeat-write-read-passes"
                if mismatch_count == 0
                else "fillbeat-write-read-fails"
            ),
            "next_gate": (
                "If this passes while dense byte writes fail, debug byte-select "
                "masking/lane mapping; if this fails too, debug write-data or "
                "read-capture before byte-select logic."
            ),
        },
    }
    write_json(run_dir / "fillbeat-diagnostic.json", payload)
    return payload


def run_fullbeat_diagnostic(
    loader: RowstreamLoader,
    beat_addr: int,
    run_dir: Path,
    initial_debug: dict[str, Any],
) -> dict[str, Any]:
    if beat_addr < 0:
        raise ValueError("fullbeat diagnostic address must be non-negative")
    if (
        not bool(initial_debug["boot_done"])
        or bool(initial_debug["boot_error"])
        or bool(initial_debug["boot_mismatch"])
    ):
        final_debug = loader.read_debug()
        payload = {
            "artifact_name": "task6-ypcb-uberddr3-fullbeat-board-diagnostic",
            "status": "FAIL",
            "beat_addr": beat_addr,
            "mismatch_count": None,
            "initial_debug": json_debug(initial_debug),
            "final_debug": json_debug(final_debug),
            "decision": {
                "verdict": "fullbeat-diagnostic-blocked-by-unclean-boot",
                "next_gate": (
                    "Do not interpret full-beat write/read diagnostics until "
                    "the BIST-derived boot gate is clean."
                ),
            },
        }
        write_json(run_dir / "fullbeat-diagnostic.json", payload)
        return payload

    expected = bytes(range(BEAT_BYTES))
    write_debug = loader.write_beat(beat_addr, expected)
    observed, read_debug = loader.read_beat(beat_addr)
    readback = [
        {
            "lane": lane,
            "expected": expected[lane],
            "observed": observed[lane],
            "match": observed[lane] == expected[lane],
        }
        for lane in range(BEAT_BYTES)
    ]
    mismatch_count = sum(1 for row in readback if not row["match"])
    final_debug = loader.read_debug()
    payload = {
        "artifact_name": "task6-ypcb-uberddr3-fullbeat-board-diagnostic",
        "status": "PASS" if mismatch_count == 0 else "FAIL",
        "beat_addr": beat_addr,
        "mismatch_count": mismatch_count,
        "expected_hex": expected.hex(),
        "observed_hex": observed.hex(),
        "initial_debug": json_debug(initial_debug),
        "write_debug": json_debug(write_debug),
        "read_debug": json_debug(read_debug),
        "final_debug": json_debug(final_debug),
        "readback": readback,
        "decision": {
            "verdict": (
                "fullbeat-write-read-passes"
                if mismatch_count == 0
                else "fullbeat-write-read-fails"
            ),
            "next_gate": (
                "If this passes at several beat addresses and patterns, switch "
                "Task 6 rowstream loading to full-beat packed writes."
            ),
        },
    }
    write_json(run_dir / "fullbeat-diagnostic.json", payload)
    return payload


def run_autoprobe_diagnostic(
    loader: RowstreamLoader,
    value: int,
    stream_base: int,
    run_dir: Path,
    initial_debug: dict[str, Any],
) -> dict[str, Any]:
    if value < 0 or value > 0xFF:
        raise ValueError("autoprobe diagnostic value must fit in one byte")
    if stream_base < 0:
        raise ValueError("autoprobe diagnostic address must be non-negative")
    if (
        not bool(initial_debug["boot_done"])
        or bool(initial_debug["boot_error"])
        or bool(initial_debug["boot_mismatch"])
    ):
        final_debug = loader.read_debug()
        payload = {
            "artifact_name": "task6-ypcb-uberddr3-autoprobe-board-diagnostic",
            "status": "FAIL",
            "value": value,
            "stream_base": stream_base,
            "initial_debug": json_debug(initial_debug),
            "final_debug": json_debug(final_debug),
            "decision": {
                "verdict": "autoprobe-blocked-by-unclean-boot",
                "next_gate": (
                    "Do not interpret board-side probe diagnostics until the "
                    "BIST-derived boot gate is clean."
                ),
            },
        }
        write_json(run_dir / "autoprobe-diagnostic.json", payload)
        return payload

    debug = loader.run_autoprobe(stream_base, value)
    pass_status = (
        bool(debug["boot_done"])
        and bool(debug["boot_write_ack_seen"])
        and bool(debug["boot_read_ack_seen"])
        and not bool(debug["boot_error"])
        and not bool(debug["boot_mismatch"])
    )
    payload = {
        "artifact_name": "task6-ypcb-uberddr3-autoprobe-board-diagnostic",
        "status": "PASS" if pass_status else "FAIL",
        "value": value,
        "stream_base": stream_base,
        "initial_debug": json_debug(initial_debug),
        "final_debug": json_debug(debug),
        "decision": {
            "verdict": (
                "board-side-autoprobe-passes"
                if pass_status
                else "board-side-autoprobe-fails"
            ),
            "next_gate": (
                "If this passes while host-decomposed writes fail, move Task 6 "
                "toward a board-side DDR3 burst loader instead of individual "
                "host-issued Wishbone transactions."
            ),
        },
    }
    write_json(run_dir / "autoprobe-diagnostic.json", payload)
    return payload


def run_denseburst_diagnostic(
    loader: RowstreamLoader,
    value: int,
    beat_addr: int,
    run_dir: Path,
    initial_debug: dict[str, Any],
) -> dict[str, Any]:
    if value < 0 or value > 0xFF:
        raise ValueError("denseburst diagnostic value must fit in one byte")
    if beat_addr < 0:
        raise ValueError("denseburst diagnostic address must be non-negative")
    if (
        not bool(initial_debug["boot_done"])
        or bool(initial_debug["boot_error"])
        or bool(initial_debug["boot_mismatch"])
    ):
        final_debug = loader.read_debug()
        payload = {
            "artifact_name": "task6-ypcb-uberddr3-densefill-write-board-diagnostic",
            "status": "FAIL",
            "value": value,
            "beat_addr": beat_addr,
            "mismatch_count": None,
            "initial_debug": json_debug(initial_debug),
            "final_debug": json_debug(final_debug),
            "decision": {
                "verdict": "densefill-write-blocked-by-unclean-boot",
                "next_gate": (
                    "Do not interpret dense data until the BIST-derived boot "
                    "gate is clean."
                ),
            },
        }
        write_json(run_dir / "denseburst-diagnostic.json", payload)
        return payload

    write_debug = loader.run_dense_fill_write(beat_addr, value)
    observed_prefix_first, first_read_debug = loader.read_dense_beat(beat_addr)
    observed_prefix, debug = loader.read_dense_beat(beat_addr)
    expected_prefix = bytes([value & 0xFF]) * 16
    pass_status = (
        bool(debug["boot_done"])
        and bool(debug["boot_write_ack_seen"])
        and not bool(debug["boot_error"])
        and not bool(debug["boot_mismatch"])
        and debug["wb_err_count"] == initial_debug["wb_err_count"]
        and bool(write_debug["loader_write_ack_seen"])
        and bool(debug["loader_read_ack_seen"])
        and not bool(debug["loader_error"])
        and observed_prefix[:16] == expected_prefix
    )
    payload = {
        "artifact_name": "task6-ypcb-uberddr3-densefill-readback-board-diagnostic",
        "status": "PASS" if pass_status else "FAIL",
        "value": value,
        "beat_addr": beat_addr,
        "mismatch_count": 0 if observed_prefix[:16] == expected_prefix else 1,
        "observed_first_prefix_hex": observed_prefix_first[:16].hex(),
        "observed_prefix_hex": observed_prefix[:16].hex(),
        "expected_prefix_hex": expected_prefix.hex(),
        "initial_debug": json_debug(initial_debug),
        "write_debug": json_debug(write_debug),
        "first_read_debug": json_debug(first_read_debug),
        "final_debug": json_debug(debug),
        "decision": {
            "verdict": (
                "board-side-densefill-readback-passes"
                if pass_status
                else "board-side-densefill-readback-fails"
            ),
            "next_gate": (
                "If this passes at several beat addresses and byte patterns, "
                "replace the host-per-byte rowstream loader with buffered "
                "board-side DDR3 burst commits."
            ),
        },
    }
    write_json(run_dir / "denseburst-diagnostic.json", payload)
    return payload


def run_rtl_fullbeat_diagnostic(
    loader: RowstreamLoader,
    base: int,
    beat_addr: int,
    run_dir: Path,
    initial_debug: dict[str, Any],
) -> dict[str, Any]:
    if base < 0 or base > 0xFF:
        raise ValueError("RTL fullbeat base must fit in one byte")
    if beat_addr < 0:
        raise ValueError("RTL fullbeat address must be non-negative")
    if (
        not bool(initial_debug["boot_done"])
        or bool(initial_debug["boot_error"])
        or bool(initial_debug["boot_mismatch"])
    ):
        final_debug = loader.read_debug()
        payload = {
            "artifact_name": "task6-ypcb-uberddr3-rtl-fullbeat-board-diagnostic",
            "status": "FAIL",
            "base": base,
            "beat_addr": beat_addr,
            "mismatch_count": None,
            "initial_debug": json_debug(initial_debug),
            "final_debug": json_debug(final_debug),
            "decision": {
                "verdict": "rtl-fullbeat-blocked-by-unclean-boot",
                "next_gate": (
                    "Do not interpret full-beat data integrity until the "
                    "BIST-derived boot gate is clean."
                ),
            },
        }
        write_json(run_dir / "rtl-fullbeat-diagnostic.json", payload)
        return payload

    debug = loader.run_rtl_fullbeat(beat_addr, base)
    expected_prefix = bytes(((base + lane) & 0xFF) for lane in range(16))
    observed_prefix = debug["read_data_chunk"]
    expected_echo32 = int.from_bytes(expected_prefix[:4], "little")
    write_echo32_match = debug["rtl_fullbeat_write_echo32"] == expected_echo32
    pass_status = (
        bool(debug["boot_done"])
        and not bool(debug["boot_error"])
        and not bool(debug["boot_mismatch"])
        and not bool(debug["loader_error"])
        and bool(debug["loader_write_ack_seen"])
        and bool(debug["loader_read_ack_seen"])
        and bool(debug["dense_burst_active"])
        and debug["dense_burst_mismatch_count"] == 0
        and debug["dense_burst_expected_base"] == (base & 0xFF)
    )
    payload = {
        "artifact_name": "task6-ypcb-uberddr3-rtl-fullbeat-board-diagnostic",
        "status": "PASS" if pass_status else "FAIL",
        "base": base,
        "beat_addr": beat_addr,
        "mismatch_count": debug["dense_burst_mismatch_count"],
        "write_echo32": debug["rtl_fullbeat_write_echo32"],
        "expected_echo32": expected_echo32,
        "write_echo32_match": write_echo32_match,
        "expected_prefix_hex": expected_prefix.hex(),
        "observed_prefix_hex": observed_prefix.hex(),
        "initial_debug": json_debug(initial_debug),
        "final_debug": json_debug(debug),
        "decision": {
            "verdict": (
                "rtl-generated-fullbeat-readback-passes"
                if pass_status
                else "rtl-generated-fullbeat-readback-fails"
            ),
            "next_gate": (
                "If this passes across several addresses and bases, replace "
                "host-provided write chunks with a buffered board-side "
                "full-beat rowstream commit path."
            ),
        },
    }
    write_json(run_dir / "rtl-fullbeat-diagnostic.json", payload)
    return payload


def read_row(loader: RowstreamLoader, token: int, contract: dict[str, Any]) -> bytes:
    row_bytes = contract["row_format"]["row_bytes"]
    start = row_offset(token, contract)
    end = start + row_bytes
    first_beat = start // BEAT_BYTES
    last_beat = (end - 1) // BEAT_BYTES
    data = bytearray()
    for beat in range(first_beat, last_beat + 1):
        beat_data, _debug = loader.read_beat(beat)
        data.extend(beat_data)
    rel = start - first_beat * BEAT_BYTES
    return bytes(data[rel : rel + row_bytes])


def read_row_lowbyte(loader: RowstreamLoader, token: int, contract: dict[str, Any]) -> bytes:
    row_bytes = contract["row_format"]["row_bytes"]
    start = row_offset(token, contract)
    return bytes(loader.read_lowbyte(start + index)[0] for index in range(row_bytes))


def merge_ranges(ranges: list[tuple[int, int]]) -> list[tuple[int, int]]:
    merged: list[tuple[int, int]] = []
    for start, end in sorted(ranges):
        if start >= end:
            continue
        if not merged or start > merged[-1][1]:
            merged.append((start, end))
        else:
            merged[-1] = (merged[-1][0], max(merged[-1][1], end))
    return merged


def range_covered(start: int, end: int, ranges: list[tuple[int, int]]) -> bool:
    return any(start >= range_start and end <= range_end for range_start, range_end in ranges)


def main() -> int:
    args = parse_args()
    run_dir = make_run_dir(args.run_dir, args.bitstream.stem)
    contract = read_json(args.contract_json)
    replay = read_json(args.replay_json)
    image = args.rowstream_bin.read_bytes()
    expected_size = contract["ddr3_linear_image"]["padded_stream_bytes"]
    if len(image) != expected_size:
        raise SystemExit(f"rowstream image has {len(image)} bytes, expected {expected_size}")
    if len(image) % BEAT_BYTES != 0:
        raise SystemExit("rowstream image must be 64-byte aligned")
    total_beats = len(image) // BEAT_BYTES
    boundary_tokens = [int(token_text, 0) for token_text in args.boundary_tokens.split(",")]
    if args.storage_mode == "beat":
        beats_to_load = min(total_beats, args.max_beats) if args.max_beats else total_beats
        bytes_to_load = beats_to_load * BEAT_BYTES
        load_ranges = [(0, bytes_to_load)]
    else:
        bytes_to_load = min(len(image), args.max_bytes) if args.max_bytes else len(image)
        beats_to_load = 0
        if args.load_boundary_rows_only:
            row_bytes = contract["row_format"]["row_bytes"]
            load_ranges = merge_ranges(
                [
                    (row_offset(token, contract), row_offset(token, contract) + row_bytes)
                    for token in boundary_tokens
                ]
            )
        else:
            load_ranges = [(0, bytes_to_load)]
    loaded_byte_count = sum(end - start for start, end in load_ranges)

    program_bitstream(args, run_dir)
    loader = RowstreamLoader(args)
    try:
        initial_debug = loader.wait_calibration()
        if args.boot_only:
            boot_clean = (
                bool(initial_debug["boot_done"])
                and not bool(initial_debug["boot_error"])
                and not bool(initial_debug["boot_mismatch"])
            )
            diagnostic = {
                "artifact_name": "task6-ypcb-uberddr3-boot-clean-board-diagnostic",
                "status": "PASS" if boot_clean else "FAIL",
                "decision": {
                    "verdict": "boot-clean" if boot_clean else "boot-unclean",
                    "next_step": (
                        "May proceed to read-only or dense diagnostics."
                        if boot_clean
                        else "Do not interpret data-path diagnostics until boot is clean."
                    ),
                },
                "debug": json_debug(initial_debug),
            }
            write_json(run_dir / "boot-diagnostic.json", diagnostic)
            write_json(
                run_dir / "summary.json",
                {
                    "status": diagnostic["status"],
                    "run_dir": str(run_dir),
                    "diagnostic_json": str(run_dir / "boot-diagnostic.json"),
                    "verdict": diagnostic["decision"]["verdict"],
                    "boot_done": initial_debug["boot_done"],
                    "boot_error": initial_debug["boot_error"],
                    "boot_mismatch": initial_debug["boot_mismatch"],
                    "calib_seen": initial_debug["calib_seen"],
                },
            )
            if not args.json_only:
                print(
                    "boot diagnostic "
                    f"{diagnostic['status']} verdict={diagnostic['decision']['verdict']} "
                    f"calib_seen={initial_debug['calib_seen']} "
                    f"boot_done={initial_debug['boot_done']} "
                    f"boot_mismatch={initial_debug['boot_mismatch']}"
                )
            return 0 if diagnostic["status"] == "PASS" else 1
        if args.diagnostic_lowbyte_count:
            diagnostic = run_lowbyte_diagnostic(
                loader, args.diagnostic_lowbyte_count, run_dir, initial_debug
            )
            write_json(
                run_dir / "summary.json",
                {
                    "status": diagnostic["status"],
                    "run_dir": str(run_dir),
                    "diagnostic_json": str(run_dir / "lowbyte-diagnostic.json"),
                    "mismatch_count": diagnostic["mismatch_count"],
                    "count": diagnostic["count"],
                },
            )
            if not args.json_only:
                print(
                    "diagnostic "
                    f"{diagnostic['status']} mismatches "
                    f"{diagnostic['mismatch_count']}/{diagnostic['count']}"
                )
            return 0 if diagnostic["status"] == "PASS" else 1
        if args.diagnostic_readbeat_addr is not None:
            diagnostic = run_readbeat_diagnostic(
                loader, args.diagnostic_readbeat_addr, run_dir, initial_debug
            )
            write_json(
                run_dir / "summary.json",
                {
                    "status": diagnostic["status"],
                    "run_dir": str(run_dir),
                    "diagnostic_json": str(run_dir / "readbeat-diagnostic.json"),
                    "beat_addr": diagnostic["beat_addr"],
                    "lower128_hex": diagnostic["lower128_hex"],
                },
            )
            if not args.json_only:
                print(
                    "readbeat diagnostic "
                    f"{diagnostic['status']} beat={diagnostic['beat_addr']} "
                    f"lower128={diagnostic['lower128_hex']}"
                )
            return 0 if diagnostic["status"] == "PASS" else 1
        if args.diagnostic_fillbeat_value is not None:
            diagnostic = run_fillbeat_diagnostic(
                loader,
                args.diagnostic_fillbeat_value,
                args.diagnostic_fillbeat_addr,
                run_dir,
                initial_debug,
            )
            write_json(
                run_dir / "summary.json",
                {
                    "status": diagnostic["status"],
                    "run_dir": str(run_dir),
                    "diagnostic_json": str(run_dir / "fillbeat-diagnostic.json"),
                    "value": diagnostic["value"],
                    "beat_addr": diagnostic["beat_addr"],
                    "mismatch_count": diagnostic["mismatch_count"],
                    "beat_prefix_hex": diagnostic.get("beat0_prefix_hex"),
                    "expected_prefix_hex": diagnostic.get("expected_prefix_hex"),
                    "verdict": diagnostic["decision"]["verdict"],
                },
            )
            if not args.json_only:
                if diagnostic["mismatch_count"] is None:
                    print(
                        "fillbeat diagnostic "
                        f"{diagnostic['status']} verdict="
                        f"{diagnostic['decision']['verdict']}"
                    )
                else:
                    print(
                        "fillbeat diagnostic "
                        f"{diagnostic['status']} mismatches "
                        f"{diagnostic['mismatch_count']}/{BEAT_BYTES} "
                        f"beat={diagnostic['beat_addr']} "
                        f"observed={diagnostic['beat0_prefix_hex']} "
                        f"expected={diagnostic['expected_prefix_hex']}"
                    )
            return 0 if diagnostic["status"] == "PASS" else 1
        if args.diagnostic_fullbeat_addr is not None:
            diagnostic = run_fullbeat_diagnostic(
                loader,
                args.diagnostic_fullbeat_addr,
                run_dir,
                initial_debug,
            )
            write_json(
                run_dir / "summary.json",
                {
                    "status": diagnostic["status"],
                    "run_dir": str(run_dir),
                    "diagnostic_json": str(run_dir / "fullbeat-diagnostic.json"),
                    "beat_addr": diagnostic["beat_addr"],
                    "mismatch_count": diagnostic["mismatch_count"],
                    "observed_hex": diagnostic.get("observed_hex"),
                    "expected_hex": diagnostic.get("expected_hex"),
                    "verdict": diagnostic["decision"]["verdict"],
                },
            )
            if not args.json_only:
                if diagnostic["mismatch_count"] is None:
                    print(
                        "fullbeat diagnostic "
                        f"{diagnostic['status']} verdict="
                        f"{diagnostic['decision']['verdict']}"
                    )
                else:
                    print(
                        "fullbeat diagnostic "
                        f"{diagnostic['status']} mismatches "
                        f"{diagnostic['mismatch_count']}/{BEAT_BYTES} "
                        f"beat={diagnostic['beat_addr']}"
                    )
            return 0 if diagnostic["status"] == "PASS" else 1
        if args.diagnostic_autoprobe_value is not None:
            diagnostic = run_autoprobe_diagnostic(
                loader,
                args.diagnostic_autoprobe_value,
                args.diagnostic_autoprobe_addr,
                run_dir,
                initial_debug,
            )
            write_json(
                run_dir / "summary.json",
                {
                    "status": diagnostic["status"],
                    "run_dir": str(run_dir),
                    "diagnostic_json": str(run_dir / "autoprobe-diagnostic.json"),
                    "value": diagnostic["value"],
                    "stream_base": diagnostic["stream_base"],
                    "verdict": diagnostic["decision"]["verdict"],
                    "boot_mismatch": diagnostic["final_debug"]["boot_mismatch"],
                    "boot_error": diagnostic["final_debug"]["boot_error"],
                    "wb_ack_count": diagnostic["final_debug"]["wb_ack_count"],
                },
            )
            if not args.json_only:
                print(
                    "autoprobe diagnostic "
                    f"{diagnostic['status']} verdict="
                    f"{diagnostic['decision']['verdict']} "
                    f"base={diagnostic['stream_base']} value=0x{diagnostic['value']:02x}"
                )
            return 0 if diagnostic["status"] == "PASS" else 1
        if args.diagnostic_denseburst_value is not None:
            diagnostic = run_denseburst_diagnostic(
                loader,
                args.diagnostic_denseburst_value,
                args.diagnostic_denseburst_addr,
                run_dir,
                initial_debug,
            )
            write_json(
                run_dir / "summary.json",
                {
                    "status": diagnostic["status"],
                    "run_dir": str(run_dir),
                    "diagnostic_json": str(run_dir / "denseburst-diagnostic.json"),
                    "value": diagnostic["value"],
                    "beat_addr": diagnostic["beat_addr"],
                    "mismatch_count": diagnostic["mismatch_count"],
                    "observed_prefix_hex": diagnostic.get("observed_prefix_hex"),
                    "expected_prefix_hex": diagnostic.get("expected_prefix_hex"),
                    "verdict": diagnostic["decision"]["verdict"],
                    "boot_mismatch": diagnostic["final_debug"]["boot_mismatch"],
                    "boot_error": diagnostic["final_debug"]["boot_error"],
                    "wb_ack_count": diagnostic["final_debug"]["wb_ack_count"],
                },
            )
            if not args.json_only:
                print(
                    "denseburst diagnostic "
                    f"{diagnostic['status']} verdict="
                    f"{diagnostic['decision']['verdict']} "
                    f"beat={diagnostic['beat_addr']} "
                    f"value=0x{diagnostic['value']:02x} "
                    f"mismatches={diagnostic['mismatch_count']}"
                )
            return 0 if diagnostic["status"] == "PASS" else 1
        if args.diagnostic_rtl_fullbeat_base is not None:
            diagnostic = run_rtl_fullbeat_diagnostic(
                loader,
                args.diagnostic_rtl_fullbeat_base,
                args.diagnostic_rtl_fullbeat_addr,
                run_dir,
                initial_debug,
            )
            write_json(
                run_dir / "summary.json",
                {
                    "status": diagnostic["status"],
                    "run_dir": str(run_dir),
                    "diagnostic_json": str(run_dir / "rtl-fullbeat-diagnostic.json"),
                    "base": diagnostic["base"],
                    "beat_addr": diagnostic["beat_addr"],
                    "mismatch_count": diagnostic["mismatch_count"],
                    "write_echo32": diagnostic.get("write_echo32"),
                    "expected_echo32": diagnostic.get("expected_echo32"),
                    "write_echo32_match": diagnostic.get("write_echo32_match"),
                    "observed_prefix_hex": diagnostic.get("observed_prefix_hex"),
                    "expected_prefix_hex": diagnostic.get("expected_prefix_hex"),
                    "verdict": diagnostic["decision"]["verdict"],
                    "boot_mismatch": diagnostic["final_debug"]["boot_mismatch"],
                    "boot_error": diagnostic["final_debug"]["boot_error"],
                    "wb_ack_count": diagnostic["final_debug"]["wb_ack_count"],
                },
            )
            if not args.json_only:
                print(
                    "rtl-fullbeat diagnostic "
                    f"{diagnostic['status']} verdict="
                    f"{diagnostic['decision']['verdict']} "
                    f"beat={diagnostic['beat_addr']} "
                    f"base=0x{diagnostic['base']:02x} "
                    f"mismatches={diagnostic['mismatch_count']}"
                )
            return 0 if diagnostic["status"] == "PASS" else 1
        if args.diagnostic_dense_count:
            diagnostic = run_dense_diagnostic(
                loader, args.diagnostic_dense_count, run_dir, initial_debug
            )
            write_json(
                run_dir / "summary.json",
                {
                    "status": diagnostic["status"],
                    "run_dir": str(run_dir),
                    "diagnostic_json": str(run_dir / "dense-diagnostic.json"),
                    "mismatch_count": diagnostic["mismatch_count"],
                    "count": diagnostic["count"],
                    "beat0_prefix_hex": diagnostic.get("beat0_prefix_hex"),
                    "expected_prefix_hex": diagnostic.get("expected_prefix_hex"),
                    "verdict": diagnostic["decision"]["verdict"],
                },
            )
            if not args.json_only:
                if diagnostic["mismatch_count"] is None:
                    print(
                        "dense diagnostic "
                        f"{diagnostic['status']} verdict="
                        f"{diagnostic['decision']['verdict']}"
                    )
                else:
                    print(
                        "dense diagnostic "
                        f"{diagnostic['status']} mismatches "
                        f"{diagnostic['mismatch_count']}/{diagnostic['count']} "
                        f"observed={diagnostic['beat0_prefix_hex']} "
                        f"expected={diagnostic['expected_prefix_hex']}"
                    )
            return 0 if diagnostic["status"] == "PASS" else 1
        if args.diagnostic_dense_lane_map_count:
            diagnostic = run_dense_lane_map_diagnostic(
                loader, args.diagnostic_dense_lane_map_count, run_dir, initial_debug
            )
            write_json(
                run_dir / "summary.json",
                {
                    "status": diagnostic["status"],
                    "run_dir": str(run_dir),
                    "diagnostic_json": str(run_dir / "dense-lane-map-diagnostic.json"),
                    "count": diagnostic["count"],
                    "verdict": diagnostic["decision"]["verdict"],
                    "target_lane_matches": [
                        sample["target_lane_match"] for sample in diagnostic["samples"]
                    ],
                    "lower128_hex_by_lane": [
                        sample["lower128_hex"] for sample in diagnostic["samples"]
                    ],
                },
            )
            if not args.json_only:
                print(
                    "dense lane-map diagnostic "
                    f"{diagnostic['status']} verdict="
                    f"{diagnostic['decision']['verdict']} "
                    f"count={diagnostic['count']}"
                )
            return 0 if diagnostic["status"] == "PASS" else 1
        load_start = time.monotonic()
        if args.storage_mode == "beat":
            for beat in range(beats_to_load):
                offset = beat * BEAT_BYTES
                loader.write_beat(beat, image[offset : offset + BEAT_BYTES])
                if not args.json_only and args.progress_beats and (beat + 1) % args.progress_beats == 0:
                    elapsed = time.monotonic() - load_start
                    print(f"loaded {beat + 1}/{beats_to_load} beats in {elapsed:.1f}s", flush=True)
        else:
            loaded = 0
            for start, end in load_ranges:
                for stream_addr in range(start, end):
                    loader.write_lowbyte(stream_addr, image[stream_addr])
                    loaded += 1
                    if not args.json_only and args.progress_bytes and loaded % args.progress_bytes == 0:
                        elapsed = time.monotonic() - load_start
                        print(
                            f"loaded {loaded}/{loaded_byte_count} low-byte addresses in {elapsed:.1f}s",
                            flush=True,
                        )
        load_elapsed = time.monotonic() - load_start

        boundary_results = []
        for token in boundary_tokens:
            row_start = row_offset(token, contract)
            row_end = row_start + contract["row_format"]["row_bytes"]
            if not range_covered(row_start, row_end, load_ranges):
                boundary_results.append(
                    {
                        "token": token,
                        "checked": False,
                        "reason": "outside loaded byte ranges",
                    }
                )
                continue
            observed = (
                read_row(loader, token, contract)
                if args.storage_mode == "beat"
                else read_row_lowbyte(loader, token, contract)
            )
            expected = image[row_start:row_end]
            boundary_results.append(
                {
                    "token": token,
                    "checked": True,
                    "offset": row_start,
                    "matches": observed == expected,
                    "observed_sha256": hashlib.sha256(observed).hexdigest(),
                    "expected_sha256": hashlib.sha256(expected).hexdigest(),
                }
            )

        readback_sha = None
        top1 = None
        full_match = None
        full_image_loaded = load_ranges == [(0, len(image))]
        if args.full_readback and full_image_loaded:
            readback = bytearray()
            read_start = time.monotonic()
            if args.storage_mode == "beat":
                for beat in range(total_beats):
                    beat_data, _debug = loader.read_beat(beat)
                    readback.extend(beat_data)
                    if not args.json_only and args.progress_beats and (beat + 1) % args.progress_beats == 0:
                        elapsed = time.monotonic() - read_start
                        print(f"read {beat + 1}/{total_beats} beats in {elapsed:.1f}s", flush=True)
            else:
                for stream_addr in range(len(image)):
                    value, _debug = loader.read_lowbyte(stream_addr)
                    readback.append(value)
                    read_count = stream_addr + 1
                    if not args.json_only and args.progress_bytes and read_count % args.progress_bytes == 0:
                        elapsed = time.monotonic() - read_start
                        print(f"read {read_count}/{len(image)} low-byte addresses in {elapsed:.1f}s", flush=True)
            readback_bytes = bytes(readback)
            (run_dir / "rowstream-ddr3-readback.bin").write_bytes(readback_bytes)
            readback_sha = hashlib.sha256(readback_bytes).hexdigest()
            full_match = readback_bytes == image
            if args.top1_from_model:
                if args.model_path is None or args.adapter_path is None:
                    raise SystemExit("--model-path and --adapter-path are required for --top1-from-model")
                top1 = compute_top1_from_image(
                    readback_bytes,
                    contract,
                    replay,
                    args.model_path,
                    args.adapter_path,
                    args.sample_count,
                )

        final_debug = loader.read_debug()
    finally:
        loader.close()

    boundary_pass = all(
        item.get("matches", False) for item in boundary_results if item.get("checked")
    )
    full_status = (
        load_ranges == [(0, len(image))]
        and boundary_pass
        and (full_match is not False)
        and (top1 is None or top1["status"] == "PASS")
    )
    payload = {
        "artifact_name": "task6-ddr3-rowstream-loader-hardware-run",
        "status": "PASS" if full_status else "PARTIAL" if boundary_pass else "FAIL",
        "date": dt.date.today().isoformat(),
        "run_dir": str(run_dir),
        "bitstream": str(args.bitstream) if args.bitstream else None,
        "rowstream": {
            "path": str(args.rowstream_bin),
            "bytes": len(image),
            "sha256": hashlib.sha256(image).hexdigest(),
            "storage_mode": args.storage_mode,
            "total_beats": total_beats,
            "loaded_beats": beats_to_load,
            "loaded_bytes": bytes_to_load,
            "loaded_byte_count": loaded_byte_count,
            "load_boundary_rows_only": args.load_boundary_rows_only,
            "load_ranges": [{"start": start, "end": end} for start, end in load_ranges],
            "load_elapsed_s": load_elapsed,
        },
        "initial_debug": json_debug(initial_debug),
        "final_debug": json_debug(final_debug),
        "boundary_rows": boundary_results,
        "full_readback": {
            "enabled": args.full_readback,
            "sha256": readback_sha,
            "matches_rowstream": full_match,
        },
        "top1": top1,
    }
    write_json(run_dir / "summary.json", payload)
    if args.json_only:
        print(json.dumps(payload, sort_keys=True))
    else:
        print(json.dumps(payload, indent=2, sort_keys=True))
    return 0 if payload["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
