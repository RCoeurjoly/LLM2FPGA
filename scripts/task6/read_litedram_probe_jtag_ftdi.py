#!/usr/bin/env python3
"""Read the YPCB LiteDRAM probe payload directly through an FTDI JTAG cable."""

from __future__ import annotations

import argparse
import json
import time

from read_jtag_debug_ftdi_bitbang import (
    FTDI_FT232H_PRODUCT,
    FTDI_VENDOR,
    FtdiBitbangJtag,
    FtdiMpsseJtag,
)
from read_jtag_debug_xvc import reset_tap, shift_dr_read, shift_ir
from read_litedram_probe_jtag_xvc import DEFAULT_BITS, decode_payload, print_summary


def read_payload(client, ir_len: int, user_ir: int, bit_count: int) -> int:
    reset_tap(client)
    shift_ir(client, user_ir, ir_len)
    return shift_dr_read(client, bit_count)


def read_idcode(client, ir_len: int, idcode_ir: int) -> int:
    reset_tap(client)
    shift_ir(client, idcode_ir, ir_len)
    return shift_dr_read(client, 32)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--serial", default="210299BF3824")
    parser.add_argument("--vid", type=lambda value: int(value, 0), default=FTDI_VENDOR)
    parser.add_argument("--pid", type=lambda value: int(value, 0), default=FTDI_FT232H_PRODUCT)
    parser.add_argument("--backend", choices=("mpsse", "bitbang"), default="mpsse")
    parser.add_argument("--freq-hz", type=int, default=1_000_000)
    parser.add_argument("--tdo-bit", type=int, choices=(0, 7), default=0)
    parser.add_argument("--bits", type=int, default=DEFAULT_BITS)
    parser.add_argument("--ir-len", type=int, default=6)
    parser.add_argument("--user-ir", type=lambda value: int(value, 0), default=0x02)
    parser.add_argument("--idcode-ir", type=lambda value: int(value, 0), default=0x09)
    parser.add_argument("--poll", action="store_true")
    parser.add_argument("--poll-count", type=int, default=100)
    parser.add_argument("--poll-interval", type=float, default=0.1)
    parser.add_argument("--bit-delay-us", type=float, default=0.0)
    parser.add_argument("--idcode-only", action="store_true")
    parser.add_argument("--json-only", action="store_true")
    return parser.parse_args()


def make_client(args: argparse.Namespace):
    if args.backend == "mpsse":
        return FtdiMpsseJtag(
            serial=args.serial,
            vid=args.vid,
            pid=args.pid,
            freq_hz=args.freq_hz,
            tdo_bit=args.tdo_bit,
        )

    return FtdiBitbangJtag(
        serial=args.serial,
        vid=args.vid,
        pid=args.pid,
        delay_s=args.bit_delay_us / 1_000_000.0,
    )


def main() -> None:
    args = parse_args()
    client = make_client(args)
    try:
        if args.idcode_only:
            idcode = read_idcode(client, args.ir_len, args.idcode_ir)
            print(
                json.dumps(
                    {
                        "backend": f"ftdi-{args.backend}",
                        "serial": args.serial,
                        "idcode": idcode,
                        "idcode_hex": f"0x{idcode:08x}",
                    },
                    indent=2,
                    sort_keys=True,
                )
            )
            return

        decoded = None
        attempts = args.poll_count if args.poll else 1
        for attempt in range(attempts):
            payload = read_payload(client, args.ir_len, args.user_ir, args.bits)
            decoded = decode_payload(payload, args.bits)
            status = decoded["decoded"]["status"]
            extended_status = decoded["decoded"]["extended_status"]
            if (
                not args.poll
                or status["read_target_seen"]
                or extended_status["probe_done"]
                or extended_status["probe_error"]
                or extended_status["probe_timeout"]
                or status["init_error"]
                or status["timeout_seen"]
                or status["init_seq_error"]
                or status["wb_error_seen"]
                or status["wb_timeout_seen"]
            ):
                break
            if attempt + 1 < attempts:
                time.sleep(args.poll_interval)

        result = {
            "backend": f"ftdi-{args.backend}",
            "serial": args.serial,
            "attempts": attempt + 1,
            **decoded,
        }
        if not args.json_only:
            print_summary(result)
        print(json.dumps(result, indent=2, sort_keys=True))
    finally:
        client.close()


if __name__ == "__main__":
    main()
