#!/usr/bin/env python3
"""Task 6 PCIe-visible M2 live layernorm/attention sublane gate."""

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
DEFAULT_OUT = ROOT / "artifacts" / "task6" / "runs" / "m2-ln-attn-sublane-board-summary.json"
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
REG_M2_OUTPUT_VECTOR = 0x600

M2_READY_BIT = 0
M2_BUSY_BIT = 1
M2_ERROR_BIT = 2
M2_OUTPUT_VALID_BIT = 3
M2_STATE_SHIFT = 4
M2_STATE_MASK = 0x7
M2_STATE_DONE = 0x5
M2_STATE_ERROR = 0x6
M2_MAGIC_SHIFT = 16

STATUS_SCHEMA = {
    "ready": M2_READY_BIT,
    "busy": M2_BUSY_BIT,
    "error": M2_ERROR_BIT,
    "output_valid": M2_OUTPUT_VALID_BIT,
    "state_lsb": M2_STATE_SHIFT,
    "state_width": 3,
    "magic_lsb": M2_MAGIC_SHIFT,
    "magic_value": 0x4D32,
}

CONTRACT = {
    "version": "task6-m2-host-live-ln-fixture-attn-sublane-v1",
    "stage": "M2-host-live-LN-fixture-attention-sublane",
    "responsibilities": {
        "host": [
            "prompt-derived layernorm input vector supply",
            "PCIe lifecycle/recovery orchestration",
            "BAR-visible result comparison",
        ],
        "fpga": [
            "host-started live layernorm arithmetic over 64 Q12 activations",
            "fixture-based attention score/value accumulator checks against compiled TinyStories-1M block-0 constants",
            "BAR-visible status/checksum/sample/full layernorm output exposure",
        ],
    },
    "notes": (
        "This validates host-live layernorm plus static fixture attention checks "
        "through the M2 BAR aperture. It is not live end-to-end attention and is "
        "not yet the full M2 token/control block compute contract."
    ),
}

ASSIGN_RE = re.compile(
    r"^\s*(?P<name>[A-Za-z0-9_]+)\[(?P<index>\d+)\]\s*=\s*"
    r"(?P<sign>-?)(?P<bits>\d+)'sd(?P<value>\d+)\s*;"
)


def run(cmd: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, check=check, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def rd32(mm: mmap.mmap, offset: int) -> int:
    return struct.unpack(">I", bytes(mm[offset : offset + 4]))[0]


def wr32(mm: mmap.mmap, offset: int, value: int) -> None:
    mm[offset : offset + 4] = struct.pack(">I", value & 0xFFFFFFFF)
    _ = mm[0:4]


def write_vector(mm: mmap.mmap, base: int, data: bytes) -> list[int]:
    if len(data) != 64:
        raise SystemExit(f"vector must be exactly 64 bytes, got {len(data)}")
    words = []
    for index in range(16):
        word = int.from_bytes(data[index * 4 : index * 4 + 4], "little")
        wr32(mm, base + index * 4, word)
        words.append(word)
    return words


def read_vector(mm: mmap.mmap, base: int) -> bytes:
    return b"".join(rd32(mm, base + index * 4).to_bytes(4, "little") for index in range(16))


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path | None) -> str | None:
    if path is None or not path.exists():
        return None
    return sha256_bytes(path.read_bytes())


def parse_signed_literal(sign: str, value: str) -> int:
    parsed = int(value)
    return -parsed if sign == "-" else parsed


def parse_tb_data(path: Path) -> dict[str, Any]:
    values: dict[str, dict[int, int]] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        match = ASSIGN_RE.match(line)
        if match is None:
            continue
        name = match.group("name")
        index = int(match.group("index"))
        values.setdefault(name, {})[index] = parse_signed_literal(match.group("sign"), match.group("value"))

    input_q12 = [values.get("ln_input_q12", {}).get(index) for index in range(64)]
    expected_i8 = [values.get("ln_expected_q", {}).get(index) for index in range(64)]
    if any(value is None for value in input_q12):
        raise SystemExit(f"{path} does not contain all 64 ln_input_q12 values")
    if any(value is None for value in expected_i8):
        raise SystemExit(f"{path} does not contain all 64 ln_expected_q values")

    block_input = b"".join(int(value).to_bytes(2, "little", signed=True) for value in input_q12[:32])
    residual = b"".join(int(value).to_bytes(2, "little", signed=True) for value in input_q12[32:])
    output = bytes(int(value) & 0xFF for value in expected_i8)
    checksum = sum(byte * (index + 1) for index, byte in enumerate(output)) & 0xFFFFFFFF
    sample0 = int.from_bytes(output[0:4], "little")
    sample1 = int.from_bytes(output[4:8], "little")
    return {
        "input_q12": input_q12,
        "expected_i8": expected_i8,
        "block_input": block_input,
        "residual": residual,
        "output": output,
        "checksum": checksum,
        "sample0": sample0,
        "sample1": sample1,
        "output_count": 64,
    }


def parse_hex_vector(text: str, *, name: str) -> bytes:
    cleaned = text.strip().removeprefix("0x").replace("_", "").replace(" ", "")
    try:
        data = bytes.fromhex(cleaned)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(f"{name} is not valid hex: {exc}") from exc
    if len(data) != 64:
        raise argparse.ArgumentTypeError(f"{name} must encode exactly 64 bytes, got {len(data)}")
    return data


def parse_output_hex(text: str) -> bytes:
    data = parse_hex_vector(text, name="expected-output")
    return data


def decode_status(status: int) -> dict[str, Any]:
    state = (status >> M2_STATE_SHIFT) & M2_STATE_MASK
    magic = (status >> M2_MAGIC_SHIFT) & 0xFFFF
    names = {
        0x0: "IDLE",
        0x1: "CAPTURE",
        0x2: "RUN_LN",
        0x3: "RUN_ATTN_SCORE",
        0x4: "RUN_ATTN_VALUE",
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


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bdf", help="PCI BDF, for example 0000:42:00.0")
    parser.add_argument("--json-out", type=Path, default=DEFAULT_OUT)
    parser.add_argument(
        "--tb-data-sv",
        type=Path,
        required=True,
        help="Generated tb_data.sv matching the bitstream, for example $(nix build .#task6-m2-ln-attn-sublane-selftest-tb-data-sv --print-out-paths)/tb_data.sv",
    )
    parser.add_argument("--input-hex", help="Override 64-byte low-half Q12 input vector as hex")
    parser.add_argument("--residual-hex", help="Override 64-byte high-half Q12 input vector as hex")
    parser.add_argument(
        "--expect-output-hex",
        type=parse_output_hex,
        help="Expected 64-byte output vector as hex; required with custom input/residual overrides",
    )
    parser.add_argument("--expect-checksum", type=lambda text: int(text, 0))
    parser.add_argument("--expect-sample0", type=lambda text: int(text, 0))
    parser.add_argument("--expect-sample1", type=lambda text: int(text, 0))
    parser.add_argument("--expect-output-count", type=lambda text: int(text, 0), default=64)
    parser.add_argument("--timeout", type=float, default=2.0)
    parser.add_argument("--poll-interval", type=float, default=0.001)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not args.tb_data_sv.exists():
        raise SystemExit(f"missing tb-data SV file: {args.tb_data_sv}")

    fixture = parse_tb_data(args.tb_data_sv)
    has_custom_input = args.input_hex is not None or args.residual_hex is not None
    if has_custom_input and args.expect_output_hex is None:
        raise SystemExit("--input-hex/--residual-hex require --expect-output-hex")
    block_input = parse_hex_vector(args.input_hex, name="input") if args.input_hex else fixture["block_input"]
    residual = parse_hex_vector(args.residual_hex, name="residual") if args.residual_hex else fixture["residual"]
    expected_output = args.expect_output_hex if args.expect_output_hex is not None else fixture["output"]
    expected = {
        "checksum": args.expect_checksum
        if args.expect_checksum is not None
        else sum(byte * (index + 1) for index, byte in enumerate(expected_output)) & 0xFFFFFFFF,
        "sample0": args.expect_sample0
        if args.expect_sample0 is not None
        else int.from_bytes(expected_output[0:4], "little"),
        "sample1": args.expect_sample1
        if args.expect_sample1 is not None
        else int.from_bytes(expected_output[4:8], "little"),
        "output_count": args.expect_output_count,
        "output": expected_output,
    }

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
            magic = rd32(mm, REG_MAGIC)
            version = rd32(mm, REG_VERSION)
            status = rd32(mm, REG_STATUS)
            m2_magic = rd32(mm, REG_M2_MAGIC)
            m2_version = rd32(mm, REG_M2_VERSION)
            m2_present = rd32(mm, REG_M2_PRESENT)

            wr32(mm, REG_M2_CONTROL_STATUS, 0)
            wr32(mm, REG_M2_CONTROL_STATUS, 2)
            input_words = write_vector(mm, REG_M2_INPUT, block_input)
            residual_words = write_vector(mm, REG_M2_RESIDUAL, residual)
            wr32(mm, REG_M2_CONTROL_STATUS, 0)
            start_count_before = rd32(mm, REG_M2_START_COUNT)
            wr32(mm, REG_M2_CONTROL_STATUS, 1)

            deadline = time.monotonic() + args.timeout
            m2_status = rd32(mm, REG_M2_CONTROL_STATUS)
            decoded = decode_status(m2_status)
            while time.monotonic() < deadline:
                m2_status = rd32(mm, REG_M2_CONTROL_STATUS)
                decoded = decode_status(m2_status)
                if decoded["done"] or decoded["error"]:
                    break
                time.sleep(args.poll_interval)

            start_count_after = rd32(mm, REG_M2_START_COUNT)
            cycle_count = rd32(mm, REG_M2_CYCLE_COUNT)
            output_checksum = rd32(mm, REG_M2_OUTPUT_CHECKSUM)
            output_count = rd32(mm, REG_M2_OUTPUT_COUNT)
            sample0 = rd32(mm, REG_M2_OUTPUT_SAMPLE0)
            sample1 = rd32(mm, REG_M2_OUTPUT_SAMPLE1)
            debug = rd32(mm, REG_M2_DEBUG)
            output_vector = read_vector(mm, REG_M2_OUTPUT_VECTOR)
    finally:
        os.close(fd)

    mismatches: list[dict[str, Any]] = []
    for name, observed, exp in (
        ("task6_magic", magic, TASK6_MAGIC),
        ("task6_version", version, TASK6_VERSION),
        ("m2_magic", m2_magic, M2_MAGIC),
        ("m2_version", m2_version, M2_VERSION),
        ("m2_present", m2_present, 1),
        ("output_checksum", output_checksum, expected["checksum"]),
        ("output_count", output_count, expected["output_count"]),
        ("output_sample0", sample0, expected["sample0"]),
        ("output_sample1", sample1, expected["sample1"]),
    ):
        if observed != exp:
            mismatches.append({"field": name, "observed": observed, "expected": exp})
    if output_vector != expected["output"]:
        mismatches.append(
            {
                "field": "output_vector",
                "observed_hex": output_vector.hex(),
                "expected_hex": expected["output"].hex(),
            }
        )

    pass_status = (
        not mismatches
        and magic != ALL_ONES
        and status != ALL_ONES
        and decoded["done"]
        and decoded["output_valid"]
        and not decoded["error"]
        and decoded["schema_consistent"]
        and start_count_after == start_count_before + 1
    )

    summary = {
        "artifact_name": "task6-m2-ln-attn-sublane-board-summary",
        "status": "PASS" if pass_status else "FAIL",
        "timestamp_utc": dt.datetime.now(dt.UTC).isoformat(),
        "contract": CONTRACT,
        "bdf": args.bdf,
        "lspci": lspci,
        "pci_command": command,
        "tb_data_sv": str(args.tb_data_sv),
        "tb_data_sha256": sha256_file(args.tb_data_sv),
        "registers": {
            "magic": f"0x{magic:08x}",
            "version": version,
            "status": f"0x{status:08x}",
            "m2_magic": f"0x{m2_magic:08x}",
            "m2_version": m2_version,
            "m2_present": m2_present,
            "m2_status": f"0x{m2_status:08x}",
            "m2_status_decoded": decoded,
            "m2_start_count_before": start_count_before,
            "m2_start_count_after": start_count_after,
            "m2_cycle_count": cycle_count,
            "m2_output_checksum": f"0x{output_checksum:08x}",
            "m2_output_count": output_count,
            "m2_output_sample0": f"0x{sample0:08x}",
            "m2_output_sample1": f"0x{sample1:08x}",
            "m2_debug": f"0x{debug:08x}",
            "m2_output_vector_hex": output_vector.hex(),
        },
        "expected": {
            "checksum": f"0x{expected['checksum']:08x}",
            "output_count": expected["output_count"],
            "sample0": f"0x{expected['sample0']:08x}",
            "sample1": f"0x{expected['sample1']:08x}",
            "output_vector_hex": expected["output"].hex(),
        },
        "input": {
            "block_input_hex": block_input.hex(),
            "residual_hex": residual.hex(),
            "block_input_words": [f"0x{word:08x}" for word in input_words],
            "residual_words": [f"0x{word:08x}" for word in residual_words],
            "block_input_sha256": sha256_bytes(block_input),
            "residual_sha256": sha256_bytes(residual),
        },
        "mismatch_count": len(mismatches),
        "mismatches": mismatches,
        "elapsed_s": time.monotonic() - started,
    }

    args.json_out.parent.mkdir(parents=True, exist_ok=True)
    args.json_out.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(summary, indent=2, sort_keys=True))
    return 0 if pass_status else 1


if __name__ == "__main__":
    raise SystemExit(main())
