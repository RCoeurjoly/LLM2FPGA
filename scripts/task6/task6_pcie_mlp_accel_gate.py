#!/usr/bin/env python3
"""Task 6 PCIe-visible reusable int8 MLP accelerator lane gate."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import mmap
import os
import struct
import subprocess
import time
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUT = ROOT / "artifacts" / "task6" / "runs" / "mlp-accel-board-summary.json"
BAR_SIZE = 4096
ALL_ONES = 0xFFFFFFFF
TASK6_MAGIC = 0x54365043
TASK6_VERSION = 3
MLP_ACCEL_MAGIC = 0x54364D41
MLP_ACCEL_VERSION = 1

CONTRACT_VERSION = "task6-transformer-boundary-mlp-accel-v1"
CONTRACT_STAGE = "M1-transformer-boundary-mlp"
CONTRACT_RESP_HOST = [
    "prompt/hidden-state capture orchestration",
    "prompt-derived residual boundary vector generation from reference",
    "checkpoint/retry loop and artifact logging",
]
CONTRACT_RESP_FPGA = [
    "int8 MLP/residual boundary execution",
    "activation/residual vector ingress via BAR",
    "kernel completion/status signaling and full output exposure",
]

REG_MAGIC = 0x000
REG_VERSION = 0x004
REG_STATUS = 0x008
REG_MLP_ACCEL_MAGIC = 0x324
REG_MLP_ACCEL_VERSION = 0x328
REG_MLP_ACCEL_PRESENT = 0x32C
REG_MLP_ACCEL_CONTROL_STATUS = 0x330
REG_MLP_ACCEL_START_COUNT = 0x334
REG_MLP_ACCEL_CYCLE_COUNT = 0x338
REG_MLP_ACCEL_OUTPUT_CHECKSUM = 0x33C
REG_MLP_ACCEL_ACTIVATION = 0x340
REG_MLP_ACCEL_RESIDUAL = 0x380
REG_MLP_ACCEL_OUTPUT_SAMPLE0 = 0x3C0
REG_MLP_ACCEL_OUTPUT_SAMPLE1 = 0x3C4
REG_MLP_ACCEL_OUTPUT_VECTOR = 0x400

ACCEL_DONE_BIT = 9
ACCEL_ERROR_BIT = 10
ACCEL_OUTPUT_VALID_BIT = 11
ACCEL_STATE_DONE = 0x7
ACCEL_STATE_ERROR = 0x8

DEFAULT_ACTIVATION_HEX = (
    "0759972ecf0608f1ad559a01a80f0bba3922f6d3a7ebd4bdd4c07f4efe3a24f2"
    "1d43ffff48e4ee402cfaf919e7bf35c214eece09383bbf12d6adf1461425233b"
)
DEFAULT_RESIDUAL_HEX = (
    "02578e2bc80104eba55491fca00b07b2371ef1cc9fe6ceb6ceb97f4df93721ed19"
    "41fbfa46dee93e29f5f415e2b732bb10e9c7053639b70ed0a6ec4410222038"
)
DEFAULT_EXPECT_OUTPUT_HEX = (
    "0a4c912adef615d69e3fd30cde7318c24b27bdd683e2d1b3d6b47f4dbc3f16144"
    "cf5cecb57d2c60442d4b418c4ba26be0ce1a2062f35a11ffba0d1510825f642"
)
DEFAULT_EXPECT_CHECKSUM = 0x200C
DEFAULT_EXPECT_SAMPLE0 = 0x2A914C0A
DEFAULT_EXPECT_SAMPLE1 = 0xD615F6DE


def run(cmd: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, check=check, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def rd32(mm: mmap.mmap, offset: int) -> int:
    return struct.unpack(">I", bytes(mm[offset : offset + 4]))[0]


def wr32(mm: mmap.mmap, offset: int, value: int) -> None:
    mm[offset : offset + 4] = struct.pack(">I", value & 0xFFFFFFFF)


def parse_hex_vector(text: str, *, name: str) -> bytes:
    cleaned = text.strip().removeprefix("0x").replace("_", "").replace(" ", "")
    try:
        data = bytes.fromhex(cleaned)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(f"{name} is not valid hex: {exc}") from exc
    if len(data) != 64:
        raise argparse.ArgumentTypeError(f"{name} must encode exactly 64 bytes, got {len(data)}")
    return data


def parse_u8_vector(value: Any, *, name: str, expected_len: int = 64) -> list[int]:
    if not isinstance(value, list):
        raise SystemExit(f"{name} must be an array; got {type(value)!r}")
    if len(value) != expected_len:
        raise SystemExit(f"{name} has {len(value)} entries, expected {expected_len}")
    parsed: list[int] = []
    for index, entry in enumerate(value):
        try:
            value_int = int(entry)
        except (TypeError, ValueError) as exc:
            raise SystemExit(f"{name}[{index}] is not an integer: {entry!r}") from exc
        if value_int < -128 or value_int > 127:
            raise SystemExit(f"{name}[{index}]={value_int} is outside int8 range")
        parsed.append(value_int & 0xFF)
    return parsed


def parse_u32(value: Any, *, name: str) -> int | None:
    if value is None:
        return None
    try:
        return int(value)
    except (TypeError, ValueError) as exc:
        raise SystemExit(f"{name} must be parseable as integer: {value!r}") from exc


def write_vector(mm: mmap.mmap, base: int, data: bytes) -> list[int]:
    words = []
    for index in range(16):
        word = int.from_bytes(data[index * 4 : index * 4 + 4], "little")
        wr32(mm, base + index * 4, word)
        words.append(word)
    return words


def read_vector(mm: mmap.mmap, base: int) -> bytes:
    chunks = []
    for index in range(16):
        chunks.append(rd32(mm, base + index * 4).to_bytes(4, "little"))
    return b"".join(chunks)


def decode_state(status: int) -> tuple[int, str]:
    state = status & 0x0F
    names = {
        0x0: "IDLE",
        0x1: "LOAD_ACTIVATION",
        0x2: "LOAD_RESIDUAL",
        0x3: "START",
        0x4: "RUN",
        0x5: "READ_SETUP",
        0x6: "READ_ACCUM",
        0x7: "DONE",
        0x8: "ERROR",
    }
    return state, names.get(state, "UNKNOWN")


def bytes_checksum(data: bytes) -> int:
    return sum(data) & 0xFFFFFFFF


def read_reference_payload(path: Path, max_samples: int | None = None) -> list[dict[str, Any]]:
    with path.open("r", encoding="utf-8") as stream:
        payload = json.load(stream)

    steps = payload.get("steps")
    if not isinstance(steps, list) or not steps:
        raise SystemExit(f"reference JSON missing non-empty steps list: {path}")

    selected = steps[:max_samples] if max_samples is not None else steps
    result: list[dict[str, Any]] = []
    for index, step in enumerate(selected):
        if not isinstance(step, dict):
            raise SystemExit(f"reference step {index} is not an object")

        activation = parse_u8_vector(step.get("activation_q"), name=f"steps[{index}].activation_q")
        residual = parse_u8_vector(step.get("residual_q"), name=f"steps[{index}].residual_q")
        activation_bytes = bytes(activation)
        residual_bytes = bytes(residual)

        output_q = step.get("residual_add_output_q")
        expected_output_bytes = bytes(parse_u8_vector(output_q, name=f"steps[{index}].residual_add_output_q")) if output_q is not None else None
        expected_checksum = parse_u32(
            step.get("residual_add_output_checksum"),
            name=f"steps[{index}].residual_add_output_checksum",
        )
        if expected_checksum is None and expected_output_bytes is not None:
            expected_checksum = bytes_checksum(expected_output_bytes)

        result.append(
            {
                "sample_id": str(step.get("step", f"reference_step_{index}")),
                "reference_step": index,
                "activation": activation_bytes,
                "residual": residual_bytes,
                "activation_scale": step.get("ln2_activation_scale"),
                "residual_scale": step.get("residual_activation_scale"),
                "expected_output": expected_output_bytes,
                "expected_checksum": expected_checksum,
                "expected_sample0": parse_u32(step.get("residual_add_output_sample0"), name=f"steps[{index}].residual_add_output_sample0"),
                "expected_sample1": parse_u32(step.get("residual_add_output_sample1"), name=f"steps[{index}].residual_add_output_sample1"),
            }
        )

    return result


def build_default_payload() -> list[dict[str, Any]]:
    activation = parse_hex_vector(DEFAULT_ACTIVATION_HEX, name="activation")
    residual = parse_hex_vector(DEFAULT_RESIDUAL_HEX, name="residual")
    expected_output = parse_hex_vector(DEFAULT_EXPECT_OUTPUT_HEX, name="expected output")
    return [
        {
            "sample_id": "default-legacy-sample",
            "reference_step": 0,
            "activation": activation,
            "residual": residual,
            "expected_output": expected_output,
            "expected_checksum": DEFAULT_EXPECT_CHECKSUM,
            "expected_sample0": DEFAULT_EXPECT_SAMPLE0,
            "expected_sample1": DEFAULT_EXPECT_SAMPLE1,
        }
    ]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bdf", help="PCI BDF, for example 0000:42:00.0")
    parser.add_argument("--json-out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--reference-json", type=Path, help="Prompt-level reference JSON with per-step activation/residual vectors")
    parser.add_argument("--reference-max-samples", type=int, default=None, help="Limit number of reference steps consumed")
    parser.add_argument("--activation-hex", default=DEFAULT_ACTIVATION_HEX, help="Single 64-byte int8 activation as hex (for legacy manual mode)")
    parser.add_argument("--residual-hex", default=DEFAULT_RESIDUAL_HEX, help="Single 64-byte residual as hex (for legacy manual mode)")
    parser.add_argument("--expect-output-hex", default=DEFAULT_EXPECT_OUTPUT_HEX, help="Expected output vector for legacy manual mode")
    parser.add_argument("--expect-checksum", type=lambda text: int(text, 0), default=DEFAULT_EXPECT_CHECKSUM)
    parser.add_argument("--expect-sample0", type=lambda text: int(text, 0), default=DEFAULT_EXPECT_SAMPLE0)
    parser.add_argument("--expect-sample1", type=lambda text: int(text, 0), default=DEFAULT_EXPECT_SAMPLE1)
    parser.add_argument("--timeout", type=float, default=2.0, help="seconds to wait for accelerator completion")
    parser.add_argument("--poll-interval", type=float, default=0.001)
    parser.add_argument(
        "--require-samples",
        action="store_true",
        help="require sample0/sample1 checks when expectations are provided",
    )
    return parser.parse_args()


def run_single_sample(
    mm: mmap.mmap,
    activation: bytes,
    residual: bytes,
    start_count_before: int,
    timeout: float,
    poll_interval: float,
) -> dict[str, int]:
    if len(activation) != 64 or len(residual) != 64:
        raise SystemExit("activation/residual vectors must be exactly 64 bytes")

    wr32(mm, REG_MLP_ACCEL_CONTROL_STATUS, 0)
    wr32(mm, REG_MLP_ACCEL_CONTROL_STATUS, 2)
    activation_words = write_vector(mm, REG_MLP_ACCEL_ACTIVATION, activation)
    residual_words = write_vector(mm, REG_MLP_ACCEL_RESIDUAL, residual)
    activation_echo = read_vector(mm, REG_MLP_ACCEL_ACTIVATION)
    residual_echo = read_vector(mm, REG_MLP_ACCEL_RESIDUAL)

    wr32(mm, REG_MLP_ACCEL_CONTROL_STATUS, 0)
    wr32(mm, REG_MLP_ACCEL_CONTROL_STATUS, 1)
    deadline = time.monotonic() + timeout
    status = rd32(mm, REG_MLP_ACCEL_CONTROL_STATUS)
    while time.monotonic() < deadline:
        status = rd32(mm, REG_MLP_ACCEL_CONTROL_STATUS)
        if status & (1 << ACCEL_DONE_BIT):
            break
        if status & (1 << ACCEL_ERROR_BIT):
            break
        time.sleep(poll_interval)

    output_checksum = rd32(mm, REG_MLP_ACCEL_OUTPUT_CHECKSUM)
    output_sample0 = rd32(mm, REG_MLP_ACCEL_OUTPUT_SAMPLE0)
    output_sample1 = rd32(mm, REG_MLP_ACCEL_OUTPUT_SAMPLE1)
    output_vector = read_vector(mm, REG_MLP_ACCEL_OUTPUT_VECTOR)
    start_count_after = rd32(mm, REG_MLP_ACCEL_START_COUNT)
    return {
        "activation_echo": activation_echo,
        "residual_echo": residual_echo,
        "activation_words": activation_words,
        "residual_words": residual_words,
        "mlp_accel_status": status,
        "mlp_accel_start_count_before": start_count_before,
        "mlp_accel_start_count_after": start_count_after,
        "mlp_accel_output_checksum": output_checksum,
        "mlp_accel_output_sample0": output_sample0,
        "mlp_accel_output_sample1": output_sample1,
        "mlp_accel_output_vector": output_vector,
    }


def main() -> int:
    args = parse_args()

    if args.reference_json is not None:
        sample_payloads = read_reference_payload(args.reference_json, args.reference_max_samples)
        default_mode = False
    else:
        activation = parse_hex_vector(args.activation_hex, name="activation")
        residual = parse_hex_vector(args.residual_hex, name="residual")
        expected_output = parse_hex_vector(args.expect_output_hex, name="expected output")
        sample_payloads = [
            {
                "sample_id": "default-legacy-sample",
                "reference_step": 0,
                "activation": activation,
                "residual": residual,
                "expected_output": expected_output,
                "expected_checksum": args.expect_checksum,
                "expected_sample0": args.expect_sample0,
                "expected_sample1": args.expect_sample1,
            }
        ]
        default_mode = True

    device = Path("/sys/bus/pci/devices") / args.bdf
    resource0 = device / "resource0"
    if not resource0.exists():
        raise SystemExit(f"missing BAR0 sysfs resource: {resource0}")

    lspci = run(["lspci", "-s", args.bdf]).stdout.strip()
    command = run(["setpci", "-s", args.bdf, "COMMAND"]).stdout.strip()
    started = time.monotonic()

    samples: list[dict[str, Any]] = []
    final_regs: dict[str, int] = {}

    fd = os.open(resource0, os.O_RDWR | os.O_SYNC)
    try:
        with mmap.mmap(fd, BAR_SIZE, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE) as mm:
            magic = rd32(mm, REG_MAGIC)
            version = rd32(mm, REG_VERSION)
            status = rd32(mm, REG_STATUS)
            mlp_present = rd32(mm, REG_MLP_ACCEL_PRESENT)

            if magic != TASK6_MAGIC:
                raise SystemExit(f"bad magic: expected 0x{TASK6_MAGIC:08x}, got 0x{magic:08x}")
            if version != TASK6_VERSION:
                raise SystemExit(f"bad version: expected {TASK6_VERSION}, got {version}")

            for sample_index, sample in enumerate(sample_payloads):
                activation = sample["activation"]
                residual = sample["residual"]
                expected_output = sample.get("expected_output")
                expected_checksum = sample.get("expected_checksum")
                expected_sample0 = sample.get("expected_sample0")
                expected_sample1 = sample.get("expected_sample1")

                start_count_before = rd32(mm, REG_MLP_ACCEL_START_COUNT)
                observed = run_single_sample(
                    mm=mm,
                    activation=activation,
                    residual=residual,
                    start_count_before=start_count_before,
                    timeout=args.timeout,
                    poll_interval=args.poll_interval,
                )
                accel_state, accel_state_name = decode_state(observed["mlp_accel_status"])
                checks = {
                    "activation_echo": observed["activation_echo"] == activation,
                    "residual_echo": observed["residual_echo"] == residual,
                    "start_count_incremented": observed["mlp_accel_start_count_after"] == ((start_count_before + 1) & 0xFFFFFFFF),
                    "state_done": accel_state == ACCEL_STATE_DONE,
                    "done_bit": bool(observed["mlp_accel_status"] & (1 << ACCEL_DONE_BIT)),
                    "no_error": not bool(observed["mlp_accel_status"] & (1 << ACCEL_ERROR_BIT)) and accel_state != ACCEL_STATE_ERROR,
                    "output_valid": bool(observed["mlp_accel_status"] & (1 << ACCEL_OUTPUT_VALID_BIT)),
                }
                if expected_output is not None:
                    checks["output_vector"] = observed["mlp_accel_output_vector"] == expected_output
                if expected_checksum is not None:
                    checks["checksum"] = observed["mlp_accel_output_checksum"] == expected_checksum
                if expected_sample0 is not None:
                    checks["sample0"] = observed["mlp_accel_output_sample0"] == expected_sample0
                if expected_sample1 is not None:
                    checks["sample1"] = observed["mlp_accel_output_sample1"] == expected_sample1

                if args.require_samples and expected_sample0 is None and expected_sample1 is None:
                    checks["sample_checks_required"] = False

                sample_status = "PASS" if all(checks.values()) else "FAIL"

                samples.append(
                    {
                        "sample_index": sample_index,
                        "sample_id": sample["sample_id"],
                        "reference_step": sample.get("reference_step"),
                        "reference_scale": {
                            "activation_scale": sample.get("activation_scale"),
                            "residual_scale": sample.get("residual_scale"),
                        },
                        "input": {
                            "activation_hex": activation.hex(),
                            "residual_hex": residual.hex(),
                            "activation_words_little_packed": [f"0x{word:08x}" for word in observed["activation_words"]],
                            "residual_words_little_packed": [f"0x{word:08x}" for word in observed["residual_words"]],
                        },
                        "expected": {
                            "output_hex": expected_output.hex() if expected_output is not None else None,
                            "checksum": f"0x{expected_checksum:08x}" if expected_checksum is not None else None,
                            "sample0": f"0x{expected_sample0:08x}" if expected_sample0 is not None else None,
                            "sample1": f"0x{expected_sample1:08x}" if expected_sample1 is not None else None,
                        },
                        "observed": {
                            "output_hex": observed["mlp_accel_output_vector"].hex(),
                            "checksum": f"0x{observed['mlp_accel_output_checksum']:08x}",
                            "sample0": f"0x{observed['mlp_accel_output_sample0']:08x}",
                            "sample1": f"0x{observed['mlp_accel_output_sample1']:08x}",
                            "state": accel_state,
                            "state_name": accel_state_name,
                            "start_count_before": observed["mlp_accel_start_count_before"],
                            "start_count_after": observed["mlp_accel_start_count_after"],
                        },
                        "checks": checks,
                        "status": sample_status,
                    }
                )

            final_regs = {
                "magic": magic,
                "version": version,
                "status": status,
                "mlp_accel_magic": rd32(mm, REG_MLP_ACCEL_MAGIC),
                "mlp_accel_version": rd32(mm, REG_MLP_ACCEL_VERSION),
                "mlp_accel_present": mlp_present,
                "mlp_accel_status": rd32(mm, REG_MLP_ACCEL_CONTROL_STATUS),
                "mlp_accel_start_count": rd32(mm, REG_MLP_ACCEL_START_COUNT),
                "mlp_accel_cycle_count": rd32(mm, REG_MLP_ACCEL_CYCLE_COUNT),
            }
    finally:
        os.close(fd)

    mismatch_count = sum(1 for sample in samples if sample["status"] != "PASS")
    global_checks = {
        "task6_magic": final_regs["magic"] == TASK6_MAGIC,
        "task6_version": final_regs["version"] == TASK6_VERSION,
        "not_all_ones": all(value != ALL_ONES for value in final_regs.values()),
        "mlp_accel_magic": final_regs["mlp_accel_magic"] == MLP_ACCEL_MAGIC,
        "mlp_accel_version": final_regs["mlp_accel_version"] == MLP_ACCEL_VERSION,
        "mlp_accel_present": final_regs["mlp_accel_present"] == 1,
        "mismatch_count": mismatch_count == 0,
    }

    status = "PASS" if mismatch_count == 0 and all(global_checks.values()) else "FAIL"
    accel_status = final_regs["mlp_accel_status"]
    accel_state, accel_state_name = decode_state(accel_status)
    result: dict[str, Any] = {
        "artifact_name": "task6-pcie-mlp-accelerator-board-gate",
        "status": status,
        "date": dt.date.today().isoformat(),
        "contract": {
            "version": CONTRACT_VERSION,
            "stage": CONTRACT_STAGE,
            "responsibilities": {
                "host": CONTRACT_RESP_HOST,
                "fpga": CONTRACT_RESP_FPGA,
            },
            "notes": "Host supplies prompt-derived residual-boundary vectors; board executes int8 MLP/residual lane.",
        },
        "bdf": args.bdf,
        "lspci": lspci,
        "command": command,
        "elapsed_seconds": time.monotonic() - started,
        "reference_json": str(args.reference_json) if args.reference_json else None,
        "reference_max_samples": args.reference_max_samples,
        "sample_count": len(samples),
        "input_reference": {
            "default_mode": default_mode,
            "sample_inputs": [
                {
                    "sample_id": sample["sample_id"],
                    "sample_index": sample["sample_index"],
                    "activation_hex": sample["input"]["activation_hex"],
                    "residual_hex": sample["input"]["residual_hex"],
                }
                for sample in samples
            ],
        },
        "expected": {
            "default_sample0": f"0x{DEFAULT_EXPECT_SAMPLE0:08x}",
            "default_sample1": f"0x{DEFAULT_EXPECT_SAMPLE1:08x}",
            "default_checksum": f"0x{DEFAULT_EXPECT_CHECKSUM:08x}",
            "default_output_hex": DEFAULT_EXPECT_OUTPUT_HEX,
        },
        "validation": {
            "mismatch_count": mismatch_count,
            "sample_count": len(samples),
        },
        "samples": samples,
        "checks": global_checks,
        "checks_required": {
            "require_samples": bool(args.require_samples),
            "sample_checks_enabled": len(samples) > 0,
        },
        "register_map": {
            "control_status": f"0x{REG_MLP_ACCEL_CONTROL_STATUS:03x}",
            "activation_vector": f"0x{REG_MLP_ACCEL_ACTIVATION:03x}..0x{REG_MLP_ACCEL_ACTIVATION + 63:03x}",
            "residual_vector": f"0x{REG_MLP_ACCEL_RESIDUAL:03x}..0x{REG_MLP_ACCEL_RESIDUAL + 63:03x}",
            "output_checksum": f"0x{REG_MLP_ACCEL_OUTPUT_CHECKSUM:03x}",
            "output_samples": [f"0x{REG_MLP_ACCEL_OUTPUT_SAMPLE0:03x}", f"0x{REG_MLP_ACCEL_OUTPUT_SAMPLE1:03x}"],
            "output_vector": f"0x{REG_MLP_ACCEL_OUTPUT_VECTOR:03x}..0x{REG_MLP_ACCEL_OUTPUT_VECTOR + 63:03x}",
        },
        "decoded": {
            "mlp_accel_status": accel_status,
            "state": accel_state,
            "state_name": accel_state_name,
        },
        "registers": {name: f"0x{value:08x}" for name, value in final_regs.items()},
    }

    args.json_out.parent.mkdir(parents=True, exist_ok=True)
    args.json_out.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if status == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
