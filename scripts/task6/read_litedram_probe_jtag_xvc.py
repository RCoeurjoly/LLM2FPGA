#!/usr/bin/env python3
"""Read the YPCB LiteDRAM init/bandwidth probe payload through XVC JTAG."""

from __future__ import annotations

import argparse
import json
import time

from read_jtag_debug_xvc import XvcClient, read_payload, unsigned_field


DEFAULT_BITS = 512
MAGIC = 0x54364A44

STATE_NAMES = {
    0: "PROBE_RESET",
    1: "PROBE_WAIT_INIT",
    2: "PROBE_RUN_READS",
    3: "PROBE_DONE",
    4: "PROBE_ERROR",
    5: "PROBE_TIMEOUT",
}

FIELDS = [
    ("magic", 0, 32),
    ("version", 32, 8),
    ("state", 40, 8),
    ("status", 48, 16),
    ("read_cycle_count", 64, 32),
    ("command_count", 96, 32),
    ("response_count", 128, 32),
    ("command_stall_count", 160, 32),
    ("checksum", 192, 32),
    ("last_rdata", 224, 64),
    ("next_read_addr", 288, 28),
    ("target_read_count", 320, 32),
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=3721)
    parser.add_argument("--timeout", type=float, default=5.0)
    parser.add_argument("--tck-ns", type=int, default=100)
    parser.add_argument("--bits", type=int, default=DEFAULT_BITS)
    parser.add_argument("--ir-len", type=int, default=6)
    parser.add_argument("--user-ir", type=lambda value: int(value, 0), default=0x02)
    parser.add_argument("--poll", action="store_true")
    parser.add_argument("--poll-count", type=int, default=100)
    parser.add_argument("--poll-interval", type=float, default=0.1)
    parser.add_argument("--json-only", action="store_true")
    return parser.parse_args()


def decode_status(status: int) -> dict[str, bool]:
    return {
        "sys_rstn": bool(status & (1 << 0)),
        "init_done": bool(status & (1 << 1)),
        "init_error": bool(status & (1 << 2)),
        "pll_locked": bool(status & (1 << 3)),
        "user_rst": bool(status & (1 << 4)),
        "cmd_ready": bool(status & (1 << 5)),
        "rdata_valid": bool(status & (1 << 6)),
        "outstanding_full": bool(status & (1 << 7)),
        "read_target_issued": bool(status & (1 << 8)),
        "read_target_seen": bool(status & (1 << 9)),
        "timeout_seen": bool(status & (1 << 10)),
    }


def decode_payload(payload: int, bit_count: int) -> dict[str, object]:
    fields = {}
    for name, offset, width in FIELDS:
        if offset + width <= bit_count:
            fields[name] = unsigned_field(payload, offset, width)

    state = fields.get("state", -1)
    status = fields.get("status", 0)
    decoded_status = decode_status(status)
    return {
        "raw_hex": f"0x{payload:0{(bit_count + 3) // 4}x}",
        "magic_ok": fields.get("magic") == MAGIC,
        "fields": fields,
        "decoded": {
            "state": STATE_NAMES.get(state, f"UNKNOWN_{state}"),
            "status": decoded_status,
            "complete": decoded_status["read_target_seen"],
            "failed": decoded_status["init_error"] or decoded_status["timeout_seen"],
        },
    }


def print_summary(result: dict[str, object]) -> None:
    fields = result["fields"]
    decoded = result["decoded"]
    status = decoded["status"]
    print(
        "magic_ok={magic_ok} version={version} state={state} "
        "init_done={init_done} init_error={init_error} pll_locked={pll_locked} "
        "commands={commands} responses={responses} target={target} "
        "cycles={cycles} stalls={stalls} checksum=0x{checksum:08x}".format(
            magic_ok=result["magic_ok"],
            version=fields.get("version"),
            state=decoded["state"],
            init_done=status["init_done"],
            init_error=status["init_error"],
            pll_locked=status["pll_locked"],
            commands=fields.get("command_count"),
            responses=fields.get("response_count"),
            target=fields.get("target_read_count"),
            cycles=fields.get("read_cycle_count"),
            stalls=fields.get("command_stall_count"),
            checksum=fields.get("checksum", 0),
        )
    )
    print(f"last_rdata=0x{fields.get('last_rdata', 0):016x}")


def main() -> None:
    args = parse_args()
    client = XvcClient(args.host, args.port, args.timeout)
    try:
        info = client.getinfo()
        actual_tck_ns = client.settck(args.tck_ns)
        decoded = None
        attempts = args.poll_count if args.poll else 1
        for attempt in range(attempts):
            payload = read_payload(client, args.ir_len, args.user_ir, args.bits)
            decoded = decode_payload(payload, args.bits)
            status = decoded["decoded"]["status"]
            if (
                not args.poll
                or status["read_target_seen"]
                or status["init_error"]
                or status["timeout_seen"]
            ):
                break
            if attempt + 1 < attempts:
                time.sleep(args.poll_interval)

        result = {
            "xvc_info": info,
            "actual_tck_ns": actual_tck_ns,
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
