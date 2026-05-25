#!/usr/bin/env python3
"""Read and decode the Task 6 PCIe BAR app USER2 JTAG status payload."""

import argparse
import json
import subprocess
import sys

MAGIC = 0x54365041  # T6PA


def field(payload: int, offset: int, width: int) -> int:
    return (payload >> offset) & ((1 << width) - 1)


def decode(raw_hex: str, bit_count: int) -> dict:
    payload = int(raw_hex, 16)
    flags = field(payload, 40, 32)
    return {
        "raw_hex": raw_hex,
        "magic": field(payload, 0, 32),
        "magic_ok": field(payload, 0, 32) == MAGIC,
        "version": field(payload, 32, 8),
        "flags_word": flags,
        "flags": {
            "rst_n": bool(flags & 1),
        },
        "clk_count": field(payload, 72, 32),
        "ar_count": field(payload, 104, 32),
        "r_count": field(payload, 136, 32),
        "aw_count": field(payload, 168, 32),
        "w_count": field(payload, 200, 32),
        "b_count": field(payload, 232, 32),
        "last_araddr": field(payload, 264, 32),
        "last_rdata": field(payload, 296, 32),
        "last_awaddr": field(payload, 328, 32),
        "last_wdata": field(payload, 360, 32),
        "bit_count": bit_count,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reader", default="scripts/task6/read_jtag_debug_ftdi_bitbang.py")
    parser.add_argument("--serial", default="210299BF3824")
    parser.add_argument("--tdo-bit", type=int, choices=(0, 7), default=7)
    parser.add_argument("--bits", type=int, default=384)
    parser.add_argument("--user-ir", default="0x03")
    parser.add_argument("--freq-hz", type=int, default=1_000_000)
    parser.add_argument("--json-only", action="store_true")
    args = parser.parse_args()

    cmd = [
        sys.executable,
        args.reader,
        "--serial",
        args.serial,
        "--tdo-bit",
        str(args.tdo_bit),
        "--bits",
        str(args.bits),
        "--user-ir",
        args.user_ir,
        "--freq-hz",
        str(args.freq_hz),
        "--json-only",
    ]
    completed = subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    result = {
        "command": cmd,
        "returncode": completed.returncode,
        "reader_output": completed.stdout,
    }
    if completed.returncode == 0:
        parsed = json.loads(completed.stdout)
        result["reader"] = parsed
        raw_hex = parsed.get("raw_hex")
        if raw_hex:
            result["pcie_app"] = decode(raw_hex, args.bits)
    if not args.json_only:
        app = result.get("pcie_app", {})
        print(
            "magic_ok={magic_ok} rst_n={rst_n} ar={ar} r={r} aw={aw} w={w} b={b}".format(
                magic_ok=app.get("magic_ok"),
                rst_n=app.get("flags", {}).get("rst_n"),
                ar=app.get("ar_count"),
                r=app.get("r_count"),
                aw=app.get("aw_count"),
                w=app.get("w_count"),
                b=app.get("b_count"),
            )
        )
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if completed.returncode == 0 else completed.returncode


if __name__ == "__main__":
    raise SystemExit(main())
