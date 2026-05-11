#!/usr/bin/env python3
"""Validate the UberDDR3 BIST-derived low-byte sequential stream over JTAG."""

from __future__ import annotations

import argparse
import json
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


MAGIC = 0x54364A44


def bit(raw: int, offset: int) -> int:
    return (raw >> offset) & 1


def decode(raw: int) -> dict[str, Any]:
    flags = (raw >> 40) & 0xFF
    status = (raw >> 304) & 0xFFFFFFFF
    stream = (raw >> 240) & 0xFFFFFFFF
    meta = (raw >> 272) & 0xFFFFFFFF
    state_word = (raw >> 416) & 0xFFFF
    return {
        "raw_hex": f"0x{raw:x}",
        "magic": raw & 0xFFFFFFFF,
        "version": (raw >> 32) & 0xFF,
        "calib": flags & 1,
        "calib_seen": (flags >> 1) & 1,
        "cycle": (raw >> 48) & 0xFFFFFFFF,
        "debug0": (raw >> 80) & 0xFFFFFFFF,
        "debug1": (raw >> 112) & 0xFFFFFFFF,
        "ack_count": (raw >> 144) & 0xFFFFFFFF,
        "err_count": (raw >> 176) & 0xFFFFFFFF,
        "stall_count": (raw >> 208) & 0xFFFFFFFF,
        "state": status & 0xF,
        "done": bit(status, 6),
        "write_ack": bit(status, 7),
        "read_ack": bit(status, 8),
        "err": bit(status, 9),
        "stall_seen": bit(status, 10),
        "mismatch_any": bit(status, 11),
        "valid": (raw >> 465) & 0xF,
        "mismatch": (raw >> 469) & 0xF,
        "expected_base": meta & 0xFF,
        "stream_base": (meta >> 8) & 0x3F,
        "command_count": (meta >> 16) & 0xFF,
        "run_count": (meta >> 24) & 0xFF,
        "bytes": [(stream >> (8 * index)) & 0xFF for index in range(4)],
        "status": status,
        "state_word": state_word,
        "stream_write_index": (state_word >> 4) & 0x3,
        "stream_read_index": (state_word >> 6) & 0x3,
    }


def expected_bytes(decoded: dict[str, Any]) -> list[int]:
    return [
        (decoded["expected_base"] + decoded["stream_base"] + index) & 0xFF
        for index in range(4)
    ]


def expected_stream_base(decoded: dict[str, Any]) -> int:
    return ((decoded["run_count"] & 0x0F) * 4) & 0x3F


def check(decoded: dict[str, Any], expected_version: int) -> tuple[bool, list[str]]:
    reasons = []
    if decoded["magic"] != MAGIC:
        reasons.append("bad_magic")
    if decoded["version"] != expected_version:
        reasons.append("bad_version")
    if not decoded["calib"] or not decoded["calib_seen"]:
        reasons.append("not_calibrated")
    if not decoded["done"] or decoded["state"] != 9:
        reasons.append("not_done")
    if not decoded["write_ack"] or not decoded["read_ack"]:
        reasons.append("missing_ack")
    if decoded["err"] or decoded["err_count"] != 0:
        reasons.append("wishbone_error")
    if decoded["valid"] != 0xF:
        reasons.append("bad_valid_mask")
    if decoded["mismatch"] != 0 or decoded["mismatch_any"]:
        reasons.append("mismatch")
    if decoded["bytes"] != expected_bytes(decoded):
        reasons.append("bad_stream_bytes")
    if decoded["stream_base"] != expected_stream_base(decoded):
        reasons.append("bad_stream_base")
    return not reasons, reasons


def print_sample(label: str, decoded: dict[str, Any], ok: bool, reasons: list[str]) -> None:
    print(
        " ".join(
            [
                label,
                f"ok={int(ok)}",
                f"run={decoded['run_count']}",
                f"cmd={decoded['command_count']}",
                f"base={decoded['stream_base']}",
                "bytes=" + ",".join(f"0x{byte:02x}" for byte in decoded["bytes"]),
                "exp=" + ",".join(f"0x{byte:02x}" for byte in expected_bytes(decoded)),
                f"valid=0x{decoded['valid']:x}",
                f"mismatch=0x{decoded['mismatch']:x}",
                f"state={decoded['state']}",
                f"done={decoded['done']}",
                f"ack_wr={decoded['write_ack']}",
                f"ack_rd={decoded['read_ack']}",
                f"err={decoded['err']}",
                f"cycle={decoded['cycle']}",
                "reasons=" + ",".join(reasons),
            ]
        ),
        flush=True,
    )


def make_client(args: argparse.Namespace) -> FtdiBitbangJtag | FtdiMpsseJtag:
    if args.backend == "mpsse":
        return FtdiMpsseJtag(args.serial, args.vid, args.pid, args.freq_hz, args.tdo_bit)
    return FtdiBitbangJtag(args.serial, args.vid, args.pid, args.bit_delay_us / 1_000_000.0)


def read_debug(client: FtdiBitbangJtag | FtdiMpsseJtag, args: argparse.Namespace) -> dict[str, Any]:
    reset_tap(client)
    shift_ir(client, args.debug_ir, args.ir_len)
    return decode(shift_dr_read(client, args.bits))


def write_command(client: FtdiBitbangJtag | FtdiMpsseJtag, args: argparse.Namespace) -> None:
    command = (args.magic_nibble << 12) | (1 << 8) | args.command_byte
    reset_tap(client)
    shift_ir(client, args.command_ir, args.ir_len)
    shift_dr_write(client, command, 16, "idle")


def wait_done(
    client: FtdiBitbangJtag | FtdiMpsseJtag,
    args: argparse.Namespace,
    label: str,
    want_run: int | None,
) -> tuple[dict[str, Any], bool, list[str]]:
    last = None
    last_ok = False
    last_reasons = ["not_read"]
    for poll in range(args.polls):
        last = read_debug(client, args)
        last_ok, last_reasons = check(last, args.expected_version)
        print_sample(f"{label}.poll{poll:02d}", last, last_ok, last_reasons)
        if last_ok and (want_run is None or last["run_count"] == want_run):
            return last, True, []
        time.sleep(args.poll_interval)
    assert last is not None
    if want_run is not None and last["run_count"] != want_run:
        last_reasons = [*last_reasons, "run_count_not_advanced"]
    return last, False, last_reasons


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--serial", default="210299BF3824")
    parser.add_argument("--vid", type=lambda value: int(value, 0), default=FTDI_VENDOR)
    parser.add_argument("--pid", type=lambda value: int(value, 0), default=FTDI_FT232H_PRODUCT)
    parser.add_argument("--backend", choices=("mpsse", "bitbang"), default="mpsse")
    parser.add_argument("--freq-hz", type=int, default=1_000_000)
    parser.add_argument("--tdo-bit", type=int, choices=(0, 7), default=7)
    parser.add_argument("--bit-delay-us", type=float, default=1.0)
    parser.add_argument("--bits", type=int, default=1024)
    parser.add_argument("--ir-len", type=int, default=6)
    parser.add_argument("--debug-ir", type=lambda value: int(value, 0), default=0x02)
    parser.add_argument("--command-ir", type=lambda value: int(value, 0), default=0x03)
    parser.add_argument("--command-byte", type=lambda value: int(value, 0), default=0x00)
    parser.add_argument("--magic-nibble", type=lambda value: int(value, 0), default=0xA)
    parser.add_argument("--expected-version", type=int, default=32)
    parser.add_argument("--windows", type=int, default=16)
    parser.add_argument("--polls", type=int, default=80)
    parser.add_argument("--poll-interval", type=float, default=0.05)
    parser.add_argument("--json-out")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    samples = []
    client = make_client(args)
    try:
        first, ok, reasons = wait_done(client, args, "initial", None)
        samples.append(first)
        previous_run = first["run_count"]
        all_ok = ok
        if not ok:
            print("RESULT FAIL initial " + ",".join(reasons), flush=True)
            return 1
        for window in range(1, args.windows):
            want_run = (previous_run + 1) & 0xFF
            write_command(client, args)
            sample, ok, reasons = wait_done(client, args, f"window{window:02d}", want_run)
            samples.append(sample)
            all_ok = all_ok and ok
            previous_run = sample["run_count"]
            if not ok:
                print(f"RESULT FAIL window{window:02d} " + ",".join(reasons), flush=True)
                break
    finally:
        client.close()

    result = {
        "schema": "task6-uberddr3-lowbyte-stream-validation-v1",
        "result": "pass" if all_ok else "fail",
        "windows_requested": args.windows,
        "windows_observed": len(samples),
        "samples": samples,
    }
    if args.json_out:
        with open(args.json_out, "w", encoding="utf-8") as handle:
            json.dump(result, handle, indent=2, sort_keys=True)
            handle.write("\n")
    print("RESULT " + result["result"].upper(), flush=True)
    return 0 if all_ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
