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
REG_M2_OUTPUT_VECTOR = 0x600

M2_READY_BIT = 0
M2_BUSY_BIT = 1
M2_ERROR_BIT = 2
M2_OUTPUT_VALID_BIT = 3
M2_STATE_SHIFT = 4
M2_STATE_MASK = 0xF
M2_STATE_DONE = 0x3

STATUS_SCHEMA = {
    "ready": M2_READY_BIT,
    "busy": M2_BUSY_BIT,
    "error": M2_ERROR_BIT,
    "output_valid": M2_OUTPUT_VALID_BIT,
    "state_lsb": M2_STATE_SHIFT,
    "state_width": 4,
    "magic_lsb": 14,
    "magic_value": 0x4D32,
}

CONTRACT = {
    "version": "task6-m2-one-full-block-replay-accel-v1",
    "stage": "M2-one-full-block",
    "responsibilities": {
        "host": [
            "prompt/model artifact orchestration",
            "PCIe lifecycle/recovery orchestration",
            "M2 contract selection and result comparison",
        ],
        "fpga": [
            "host-started M2 one-full-block replay lane",
            "BAR-visible status/checksum/sample/full-first-64-byte output",
            "board execution proof for the composed fixed-point full-block artifact",
        ],
    },
    "notes": (
        "This gate validates the reusable M2 full-block BAR contract. The current "
        "RTL lane replays the composed fixed-point artifact; replacing replay ROM "
        "pieces with live layernorm/attention/MLP sub-lanes remains the next gate."
    ),
}


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


def parse_expected_json(path: Path) -> dict[str, int]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    expected: dict[str, int] = {}
    for json_key, out_key in (
        ("expected_checksum", "checksum"),
        ("expected_sample0", "sample0"),
        ("expected_sample1", "sample1"),
        ("output_count", "output_count"),
    ):
        value = payload.get(json_key)
        if value is not None:
            expected[out_key] = int(value)
    return expected


def decode_status(status: int) -> dict[str, Any]:
    state = (status >> M2_STATE_SHIFT) & M2_STATE_MASK
    magic = (status >> STATUS_SCHEMA["magic_lsb"]) & 0xFFFF
    names = {
        0x0: "IDLE",
        0x1: "CAPTURE_INPUT",
        0x2: "RUN",
        0x3: "DONE",
        0x4: "ERROR",
    }
    return {
        "state": state,
        "state_name": names.get(state, "UNKNOWN"),
        "ready": bool(status & (1 << M2_READY_BIT)),
        "busy": bool(status & (1 << M2_BUSY_BIT)),
        "error": bool(status & (1 << M2_ERROR_BIT)) or state == 0x4,
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
    parser.add_argument("--expected-json", type=Path, help="Generated M2 full-block replay tb-data summary JSON")
    parser.add_argument("--expect-checksum", type=lambda text: int(text, 0))
    parser.add_argument("--expect-sample0", type=lambda text: int(text, 0))
    parser.add_argument("--expect-sample1", type=lambda text: int(text, 0))
    parser.add_argument("--expect-output-count", type=lambda text: int(text, 0))
    parser.add_argument("--input-hex", default="00" * 64, help="64-byte block input vector as hex")
    parser.add_argument("--residual-hex", default="00" * 64, help="64-byte residual-after-attention vector as hex")
    parser.add_argument("--timeout", type=float, default=2.0)
    parser.add_argument("--poll-interval", type=float, default=0.001)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    expected = parse_expected_json(args.expected_json) if args.expected_json else {}
    if args.expect_checksum is not None:
        expected["checksum"] = args.expect_checksum
    if args.expect_sample0 is not None:
        expected["sample0"] = args.expect_sample0
    if args.expect_sample1 is not None:
        expected["sample1"] = args.expect_sample1
    if args.expect_output_count is not None:
        expected["output_count"] = args.expect_output_count

    block_input = parse_hex_vector(args.input_hex, name="input")
    residual = parse_hex_vector(args.residual_hex, name="residual")

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

            observed = {
                "start_count_before": start_count_before,
                "start_count_after": rd32(mm, REG_M2_START_COUNT),
                "status": m2_status,
                "cycle_count": rd32(mm, REG_M2_CYCLE_COUNT),
                "checksum": rd32(mm, REG_M2_OUTPUT_CHECKSUM),
                "output_count": rd32(mm, REG_M2_OUTPUT_COUNT),
                "sample0": rd32(mm, REG_M2_OUTPUT_SAMPLE0),
                "sample1": rd32(mm, REG_M2_OUTPUT_SAMPLE1),
                "output_vector": read_vector(mm, REG_M2_OUTPUT_VECTOR),
            }
    finally:
        os.close(fd)

    checks = {
        "task6_magic": magic == TASK6_MAGIC,
        "task6_version": version == TASK6_VERSION,
        "not_all_ones": all(
            value != ALL_ONES
            for value in (magic, version, status, m2_magic, m2_version, m2_present, observed["status"])
        ),
        "m2_magic": m2_magic == M2_MAGIC,
        "m2_version": m2_version == M2_VERSION,
        "m2_present": m2_present == 1,
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

    result: dict[str, Any] = {
        "artifact_name": "task6-pcie-m2-full-block-board-gate",
        "status": "PASS" if all(checks.values()) else "FAIL",
        "date": dt.date.today().isoformat(),
        "contract": CONTRACT,
        "bdf": args.bdf,
        "lspci": lspci,
        "command": command,
        "elapsed_seconds": time.monotonic() - started,
        "registers": {
            "magic": f"0x{magic:08x}",
            "version": version,
            "status": f"0x{status:08x}",
            "m2_magic": f"0x{m2_magic:08x}",
            "m2_version": m2_version,
            "m2_present": m2_present,
        },
        "fingerprints": {
            "gate_script_sha256": sha256_file(Path(__file__)),
            "expected_json": str(args.expected_json) if args.expected_json else None,
            "expected_json_sha256": sha256_file(args.expected_json) if args.expected_json else None,
            "block_input_sha256": sha256_bytes(block_input),
            "residual_after_attention_sha256": sha256_bytes(residual),
            "expected_params_sha256": sha256_bytes(
                json.dumps(expected, sort_keys=True, separators=(",", ":")).encode("utf-8")
            ),
        },
        "input": {
            "block_input_hex": block_input.hex(),
            "residual_after_attention_hex": residual.hex(),
            "block_input_words_little_packed": [f"0x{word:08x}" for word in input_words],
            "residual_words_little_packed": [f"0x{word:08x}" for word in residual_words],
        },
        "expected": {key: f"0x{value:08x}" for key, value in expected.items() if key != "output_count"}
        | ({"output_count": expected["output_count"]} if "output_count" in expected else {}),
        "observed": {
            "status": f"0x{observed['status']:08x}",
            "decoded_status": decoded,
            "start_count_before": observed["start_count_before"],
            "start_count_after": observed["start_count_after"],
            "cycle_count": observed["cycle_count"],
            "checksum": f"0x{observed['checksum']:08x}",
            "sample0": f"0x{observed['sample0']:08x}",
            "sample1": f"0x{observed['sample1']:08x}",
            "output_count": observed["output_count"],
            "first_64_output_hex": observed["output_vector"].hex(),
        },
        "checks": checks,
    }

    args.json_out.parent.mkdir(parents=True, exist_ok=True)
    args.json_out.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if result["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
