#!/usr/bin/env python3
"""Write a small command word to a USER JTAG data register through FTDI."""

from __future__ import annotations

import argparse
import json

from read_jtag_debug_ftdi_bitbang import (
    FTDI_FT232H_PRODUCT,
    FTDI_VENDOR,
    FtdiBitbangJtag,
    FtdiMpsseJtag,
)
from read_jtag_debug_xvc import clock_tms, reset_tap, shift_ir


def shift_dr_write(client, value: int, bit_count: int) -> None:
    clock_tms(client, [1, 0, 0])
    tdi_bits = [(value >> bit) & 1 for bit in range(bit_count)]
    tms_bits = [0] * bit_count
    tms_bits[-1] = 1
    client.shift(tms_bits, tdi_bits)
    clock_tms(client, [1, 0])


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--serial", default="210299BF3824")
    parser.add_argument("--vid", type=lambda value: int(value, 0), default=FTDI_VENDOR)
    parser.add_argument("--pid", type=lambda value: int(value, 0), default=FTDI_FT232H_PRODUCT)
    parser.add_argument("--backend", choices=("mpsse", "bitbang"), default="mpsse")
    parser.add_argument("--freq-hz", type=int, default=1_000_000)
    parser.add_argument("--tdo-bit", type=int, choices=(0, 7), default=7)
    parser.add_argument("--ir-len", type=int, default=6)
    parser.add_argument("--user-ir", type=lambda value: int(value, 0), default=0x03)
    parser.add_argument("--bit-delay-us", type=float, default=0.0)
    parser.add_argument("--byte", dest="byte_value", type=lambda value: int(value, 0), required=True)
    parser.add_argument("--bits", type=int, default=16)
    parser.add_argument("--magic-nibble", type=lambda value: int(value, 0), default=0xA)
    parser.add_argument("--json-only", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.byte_value < 0 or args.byte_value > 0xFF:
        raise SystemExit("--byte must fit in 8 bits")
    if args.magic_nibble < 0 or args.magic_nibble > 0xF:
        raise SystemExit("--magic-nibble must fit in 4 bits")

    command = (args.magic_nibble << 12) | (1 << 8) | args.byte_value
    if args.backend == "mpsse":
        client = FtdiMpsseJtag(
            serial=args.serial,
            vid=args.vid,
            pid=args.pid,
            freq_hz=args.freq_hz,
            tdo_bit=args.tdo_bit,
        )
    else:
        client = FtdiBitbangJtag(
            serial=args.serial,
            vid=args.vid,
            pid=args.pid,
            delay_s=args.bit_delay_us / 1_000_000.0,
        )

    try:
        reset_tap(client)
        shift_ir(client, args.user_ir, args.ir_len)
        shift_dr_write(client, command, args.bits)
    finally:
        client.close()

    result = {
        "backend": f"ftdi-{args.backend}",
        "serial": args.serial,
        "user_ir": f"0x{args.user_ir:02x}",
        "bits": args.bits,
        "byte": f"0x{args.byte_value:02x}",
        "command": f"0x{command:04x}",
    }
    if not args.json_only:
        print(f"Wrote USER JTAG command {result['command']} byte={result['byte']}")
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
