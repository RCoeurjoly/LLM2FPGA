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
COMPILED_MLP_CONTRACT = {
    "artifact_name": "h2-full-tinystories-1m-block0-pwl-mlp-chain-residual-add-rtl-proof",
    "model_contract": "tiny-stories-1m-h64-l8-block0",
    "top_name": "task6_int8_l2_mlp_chain_residual_add_kernel",
    "note": (
        "Current bitstream MLP weights/scales are compiled from the full "
        "TinyStories-1M block-0 PWL MLP/residual proof bundle."
    ),
}
KNOWN_INCOMPATIBLE_REFERENCE_ARTIFACTS = {
    "h2-tinystories-1m-prompt-output-head-q024-reference",
}

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
ACCEL_V2_STATE_SHIFT = 4
ACCEL_V2_STATE_MASK = 0xF
ACCEL_V2_READY_BIT = 0
ACCEL_V2_BUSY_BIT = 1
ACCEL_V2_ERROR_BIT = 2
ACCEL_V2_OUTPUT_VALID_BIT = 3
ACCEL_V2_STATE_DONE = 0xB
ACCEL_V2_STATE_ERROR = 0xC

DEFAULT_ACTIVATION_HEX = (
    "0b16cefff9ed06fc9503c5eef406eef8bf330f62cc2e0203d8febe0c0ff2cb4c"
    "8b0d164b022b81cc425a1239a8eb27f24ed46017e41302af24020d11d81c0666"
)
DEFAULT_RESIDUAL_HEX = (
    "0c1acffffbed07fd9404c5f0f509f1fbbd381264ca2f0306d801bf0e11f2cd4b"
    "8d0e1849043081cc465c143eaeed2cf44fd6661be31602b128020e14d81e086b"
)
DEFAULT_EXPECT_OUTPUT_HEX = (
    "3eff10de6ced3efd1bf9c626b3c5130c8cf0d74b01050006296bfecc53e1c7e"
    "cff91cf48fd0b81cc4542c651acf725d060094f712c418eef7e041e2bf71c3b49"
)
DEFAULT_EXPECT_CHECKSUM = 0x1EEC
DEFAULT_EXPECT_SAMPLE0 = 0xDE10FF3E
DEFAULT_EXPECT_SAMPLE1 = 0xFD3EED6C


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


def decode_accel_status(status: int) -> dict[str, Any]:
    legacy_state, legacy_name = decode_state(status)
    v2_state = (status >> ACCEL_V2_STATE_SHIFT) & ACCEL_V2_STATE_MASK
    v2_names = {
        0x0: "BOOT_LOAD_C_FC_WEIGHT",
        0x1: "BOOT_LOAD_C_FC_REQUANT",
        0x2: "BOOT_LOAD_C_PROJ_WEIGHT",
        0x3: "BOOT_LOAD_C_PROJ_REQUANT",
        0x4: "IDLE",
        0x5: "LOAD_ACTIVATION",
        0x6: "LOAD_RESIDUAL",
        0x7: "START",
        0x8: "RUN",
        0x9: "READ_SETUP",
        0xA: "READ_ACCUM",
        0xB: "DONE",
        0xC: "ERROR",
    }
    legacy_done = bool(status & (1 << ACCEL_DONE_BIT)) or legacy_state == ACCEL_STATE_DONE
    legacy_error = bool(status & (1 << ACCEL_ERROR_BIT)) or legacy_state == ACCEL_STATE_ERROR
    legacy_output_valid = bool(status & (1 << ACCEL_OUTPUT_VALID_BIT))
    v2_done = v2_state == ACCEL_V2_STATE_DONE
    v2_error = bool(status & (1 << ACCEL_V2_ERROR_BIT)) or v2_state == ACCEL_V2_STATE_ERROR
    v2_output_valid = bool(status & (1 << ACCEL_V2_OUTPUT_VALID_BIT))
    if v2_done or v2_output_valid or (status & 0xFFFF0000):
        return {
            "format": "v2",
            "state": v2_state,
            "state_name": v2_names.get(v2_state, "UNKNOWN"),
            "done": v2_done,
            "error": v2_error,
            "output_valid": v2_output_valid,
            "busy": bool(status & (1 << ACCEL_V2_BUSY_BIT)),
            "ready": bool(status & (1 << ACCEL_V2_READY_BIT)),
        }
    return {
        "format": "legacy",
        "state": legacy_state,
        "state_name": legacy_name,
        "done": legacy_done,
        "error": legacy_error,
        "output_valid": legacy_output_valid,
        "busy": not legacy_done and not legacy_error,
        "ready": True,
    }


def bytes_checksum(data: bytes) -> int:
    return sum(data) & 0xFFFFFFFF


def check_reference_contract(payload: dict[str, Any], path: Path, allow_mismatch: bool) -> dict[str, Any]:
    artifact_name = payload.get("artifact_name")
    mlp_contract = payload.get("mlp_contract") or payload.get("compiled_mlp_contract")
    contract_status = {
        "reference_artifact_name": artifact_name,
        "compiled_mlp_contract": COMPILED_MLP_CONTRACT,
        "reference_mlp_contract": mlp_contract,
        "allow_reference_contract_mismatch": allow_mismatch,
        "compatible": True,
        "reason": "no explicit incompatible MLP contract identity found",
    }

    if isinstance(mlp_contract, dict):
        reference_contract_name = mlp_contract.get("artifact_name")
        reference_model_contract = mlp_contract.get("model_contract")
        if (
            reference_contract_name not in (None, COMPILED_MLP_CONTRACT["artifact_name"])
            or reference_model_contract not in (None, COMPILED_MLP_CONTRACT["model_contract"])
        ):
            contract_status["compatible"] = False
            contract_status["reason"] = "explicit reference MLP contract does not match compiled hardware contract"
    elif artifact_name in KNOWN_INCOMPATIBLE_REFERENCE_ARTIFACTS:
        contract_status["compatible"] = False
        contract_status["reason"] = (
            "reference is a TinyStories-1M output-head prompt artifact, while "
            "the current MLP lane is compiled from the v1k L2 MLP/residual contract"
        )

    if not contract_status["compatible"] and not allow_mismatch:
        raise SystemExit(
            "MLP reference contract does not match the compiled accelerator contract:\n"
            f"  reference: {path}\n"
            f"  reference artifact: {artifact_name}\n"
            f"  expected MLP contract: {COMPILED_MLP_CONTRACT['artifact_name']} "
            f"({COMPILED_MLP_CONTRACT['model_contract']})\n"
            f"  reason: {contract_status['reason']}\n"
            "  action: regenerate a reference from the compiled MLP contract, rebuild "
            "the bitstream for this reference, or rerun with "
            "--allow-reference-contract-mismatch for a deliberate negative experiment."
        )

    return contract_status


def reference_payloads_from_document(payload: dict[str, Any], path: Path, max_samples: int | None = None) -> list[dict[str, Any]]:
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


def read_reference_document(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as stream:
        payload = json.load(stream)
    if not isinstance(payload, dict):
        raise SystemExit(f"reference JSON must contain an object: {path}")
    return payload


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
    parser.add_argument("--expect-output-hex", default=None, help="Expected output vector for legacy manual mode")
    parser.add_argument("--expect-checksum", type=lambda text: int(text, 0), default=None)
    parser.add_argument("--expect-sample0", type=lambda text: int(text, 0), default=None)
    parser.add_argument("--expect-sample1", type=lambda text: int(text, 0), default=None)
    parser.add_argument(
        "--output-surface",
        choices=("full", "checksum-sample", "auto"),
        default="full",
        help="validation surface exposed by this bitstream; full preserves legacy 64-byte output checking",
    )
    parser.add_argument("--timeout", type=float, default=2.0, help="seconds to wait for accelerator completion")
    parser.add_argument("--poll-interval", type=float, default=0.001)
    parser.add_argument(
        "--require-samples",
        action="store_true",
        help="require sample0/sample1 checks when expectations are provided",
    )
    parser.add_argument(
        "--allow-reference-contract-mismatch",
        action="store_true",
        help="run even when the reference identity is known to differ from the compiled MLP contract",
    )
    return parser.parse_args()


def run_single_sample(
    mm: mmap.mmap,
    activation: bytes,
    residual: bytes,
    start_count_before: int,
    timeout: float,
    poll_interval: float,
    read_output_vector_flag: bool,
) -> dict[str, Any]:
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
        decoded_status = decode_accel_status(status)
        if decoded_status["done"]:
            break
        if decoded_status["error"]:
            break
        time.sleep(poll_interval)

    output_checksum = rd32(mm, REG_MLP_ACCEL_OUTPUT_CHECKSUM)
    output_sample0 = rd32(mm, REG_MLP_ACCEL_OUTPUT_SAMPLE0)
    output_sample1 = rd32(mm, REG_MLP_ACCEL_OUTPUT_SAMPLE1)
    output_vector = read_vector(mm, REG_MLP_ACCEL_OUTPUT_VECTOR) if read_output_vector_flag else None
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
        reference_document = read_reference_document(args.reference_json)
        reference_contract = check_reference_contract(
            reference_document,
            args.reference_json,
            args.allow_reference_contract_mismatch,
        )
        sample_payloads = reference_payloads_from_document(
            reference_document,
            args.reference_json,
            args.reference_max_samples,
        )
        default_mode = False
    else:
        reference_contract = {
            "reference_artifact_name": None,
            "compiled_mlp_contract": COMPILED_MLP_CONTRACT,
            "reference_mlp_contract": None,
            "allow_reference_contract_mismatch": False,
            "compatible": True,
            "reason": "default vector is generated from the compiled full TinyStories-1M MLP contract",
        }
        activation = parse_hex_vector(args.activation_hex, name="activation")
        residual = parse_hex_vector(args.residual_hex, name="residual")
        if args.output_surface == "full":
            expect_output_hex = args.expect_output_hex or DEFAULT_EXPECT_OUTPUT_HEX
            expected_output = parse_hex_vector(expect_output_hex, name="expected output")
            expected_checksum = args.expect_checksum if args.expect_checksum is not None else DEFAULT_EXPECT_CHECKSUM
            expected_sample0 = args.expect_sample0 if args.expect_sample0 is not None else DEFAULT_EXPECT_SAMPLE0
            expected_sample1 = args.expect_sample1 if args.expect_sample1 is not None else DEFAULT_EXPECT_SAMPLE1
        else:
            expected_output = parse_hex_vector(args.expect_output_hex, name="expected output") if args.expect_output_hex else None
            expected_checksum = args.expect_checksum
            expected_sample0 = args.expect_sample0
            expected_sample1 = args.expect_sample1
        sample_payloads = [
            {
                "sample_id": "default-legacy-sample",
                "reference_step": 0,
                "activation": activation,
                "residual": residual,
                "expected_output": expected_output,
                "expected_checksum": expected_checksum,
                "expected_sample0": expected_sample0,
                "expected_sample1": expected_sample1,
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
                require_output_vector = args.output_surface == "full" or (
                    args.output_surface == "auto" and expected_output is not None and expected_checksum is None
                )

                start_count_before = rd32(mm, REG_MLP_ACCEL_START_COUNT)
                observed = run_single_sample(
                    mm=mm,
                    activation=activation,
                    residual=residual,
                    start_count_before=start_count_before,
                    timeout=args.timeout,
                    poll_interval=args.poll_interval,
                    read_output_vector_flag=require_output_vector,
                )
                decoded_status = decode_accel_status(observed["mlp_accel_status"])
                accel_state = int(decoded_status["state"])
                accel_state_name = str(decoded_status["state_name"])
                require_echo = args.output_surface == "full"
                checks = {
                    "start_count_incremented": observed["mlp_accel_start_count_after"] == ((start_count_before + 1) & 0xFFFFFFFF),
                    "state_done": bool(decoded_status["done"]),
                    "done_bit": bool(decoded_status["done"]),
                    "no_error": not bool(decoded_status["error"]),
                    "output_valid": bool(decoded_status["output_valid"]),
                }
                if require_echo:
                    checks["activation_echo"] = observed["activation_echo"] == activation
                    checks["residual_echo"] = observed["residual_echo"] == residual
                if expected_output is not None and require_output_vector:
                    checks["output_vector"] = observed["mlp_accel_output_vector"] == expected_output
                if expected_checksum is not None:
                    checks["checksum"] = observed["mlp_accel_output_checksum"] == expected_checksum
                elif args.output_surface == "checksum-sample":
                    checks["checksum_live"] = observed["mlp_accel_output_checksum"] != ALL_ONES
                if expected_sample0 is not None:
                    checks["sample0"] = observed["mlp_accel_output_sample0"] == expected_sample0
                elif args.output_surface == "checksum-sample":
                    checks["sample0_live"] = observed["mlp_accel_output_sample0"] != ALL_ONES
                if expected_sample1 is not None:
                    checks["sample1"] = observed["mlp_accel_output_sample1"] == expected_sample1
                elif args.output_surface == "checksum-sample":
                    checks["sample1_live"] = observed["mlp_accel_output_sample1"] != ALL_ONES

                if args.require_samples and expected_sample0 is None and expected_sample1 is None and args.output_surface != "checksum-sample":
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
                            "activation_echo_hex": observed["activation_echo"].hex(),
                            "residual_echo_hex": observed["residual_echo"].hex(),
                            "output_hex": (
                                observed["mlp_accel_output_vector"].hex()
                                if observed["mlp_accel_output_vector"] is not None
                                else None
                            ),
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
    decoded_final_status = decode_accel_status(accel_status)
    accel_state = int(decoded_final_status["state"])
    accel_state_name = str(decoded_final_status["state_name"])
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
        "reference_contract": reference_contract,
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
            "output_surface": args.output_surface,
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
            "mlp_accel_status_format": decoded_final_status["format"],
            "state": accel_state,
            "state_name": accel_state_name,
            "done": decoded_final_status["done"],
            "error": decoded_final_status["error"],
            "output_valid": decoded_final_status["output_valid"],
        },
        "registers": {name: f"0x{value:08x}" for name, value in final_regs.items()},
    }

    args.json_out.parent.mkdir(parents=True, exist_ok=True)
    args.json_out.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if status == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
