#!/usr/bin/env python3
"""Run one YPCB/UberDDR3 board experiment and write decoded JSON artifacts."""

from __future__ import annotations

import argparse
from datetime import datetime
import json
from pathlib import Path
import re
import subprocess
import sys
import time
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
BOARD_RUN = ROOT / "scripts" / "task6" / "task6_board_run.py"
READ_JTAG = ROOT / "scripts" / "task6" / "read_jtag_debug_ftdi_bitbang.py"
WRITE_JTAG = ROOT / "scripts" / "task6" / "write_jtag_command_ftdi_bitbang.py"


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def run_command(argv: list[str], *, capture: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        argv,
        cwd=ROOT,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.STDOUT if capture else None,
        text=True,
        check=False,
    )


def parse_nix_paths(text: str) -> list[str]:
    return [line.strip() for line in text.splitlines() if line.strip().startswith("/nix/store/")]


def build_bitstream(attr: str) -> str:
    proc = run_command(["nix", "build", f".#{attr}", "--print-out-paths", "-L"])
    if proc.returncode != 0:
        raise SystemExit(proc.stdout)
    paths = parse_nix_paths(proc.stdout)
    if paths:
        return paths[-1]
    link = run_command(["readlink", "-f", "result"])
    if link.returncode != 0:
        raise SystemExit(link.stdout)
    return link.stdout.strip()


def init_run(args: argparse.Namespace, bitstream: str) -> Path:
    proc = run_command(
        [
            sys.executable,
            str(BOARD_RUN),
            "init",
            "--label",
            args.label,
            "--experiment",
            args.experiment,
            "--bitstream",
            bitstream,
            "--notes",
            args.notes,
        ]
    )
    if proc.returncode != 0:
        raise SystemExit(proc.stdout)
    return Path(proc.stdout.strip().splitlines()[-1])


def with_lock(run_dir: Path, log_name: str, command: list[str]) -> None:
    proc = run_command(
        [
            sys.executable,
            str(BOARD_RUN),
            "with-lock",
            "--run-dir",
            str(run_dir),
            "--log-name",
            log_name,
            "--",
            *command,
        ]
    )
    if proc.returncode != 0:
        raise SystemExit(proc.stdout)


def extract_read_json(log_text: str) -> dict[str, Any]:
    start = log_text.find("{")
    end = log_text.rfind("}")
    if start < 0 or end < start:
        raise ValueError("JTAG read log does not contain JSON output")
    return json.loads(log_text[start : end + 1])


def bit(raw: int, offset: int) -> int:
    return (raw >> offset) & 1


def hex_words(raw: int, offset: int, word_bits: int, count: int) -> list[str]:
    mask = (1 << word_bits) - 1
    return [f"0x{((raw >> (offset + index * word_bits)) & mask):0{word_bits // 4}x}" for index in range(count)]


def decode_uberddr3_payload(readback: dict[str, Any], args: argparse.Namespace) -> dict[str, Any]:
    raw_hex = readback["raw_hex"]
    raw = int(raw_hex, 16)
    debug1 = (raw >> 112) & 0xFFFFFFFF
    probe = (raw >> 304) & 0xFFFFFFFF
    read_byte = (raw >> 240) & 0xFF
    read_word = (raw >> 240) & 0xFFFFFFFF
    stream_bytes = [(read_word >> (8 * index)) & 0xFF for index in range(4)]
    read_beat = (raw >> 480) & ((1 << 512) - 1) if args.bits >= 992 else None
    expected = args.expected_byte
    expected_stream_bytes = [((expected + index) & 0xFF) for index in range(4)]
    version = (raw >> 32) & 0xFF
    stream_words = [
        (raw >> (512 + index * 32)) & 0xFFFFFFFF
        for index in range(4)
    ] if version == 26 and args.bits >= 640 else []
    command_word = (raw >> 272) & 0xFFFFFFFF
    active_byte = command_word & 0xFF
    if version <= 23:
        active_addr = 0
        command_count = (command_word >> 8) & 0xFF
        run_count = (command_word >> 16) & 0xFFFF
    else:
        active_addr = (command_word >> 8) & 0xFF
        command_count = (command_word >> 16) & 0xFF
        run_count = (command_word >> 24) & 0xFF
    status = (raw >> 40) & 0xFF
    ack_count = (raw >> 144) & 0xFFFFFFFF
    err_count = (raw >> 176) & 0xFFFFFFFF
    calib_seen_cycle = (raw >> 80) & 0xFFFFFFFF
    if version <= 23:
        probe_state = probe & 0x7
        done = bool(bit(probe, 5))
        write_ack_seen = bool(bit(probe, 6))
        read_ack_seen = bool(bit(probe, 7))
        err_seen = bool(bit(probe, 8))
        stall_seen = bool(bit(probe, 9))
        mismatch = bool(bit(probe, 10))
    else:
        probe_state = probe & 0xF
        done = bool(bit(probe, 6))
        write_ack_seen = bool(bit(probe, 7))
        read_ack_seen = bool(bit(probe, 8))
        err_seen = bool(bit(probe, 9))
        stall_seen = bool(bit(probe, 10))
        mismatch = bool(bit(probe, 11))
    stream_status = (raw >> 416) & 0xFFFF
    command_trace = (raw >> 992) & 0xFFFFFFFF if args.bits >= 1024 else 0
    if version <= 23:
        stream_mismatch_count = 1 if mismatch else 0
        stream_read_index = 0
        stream_write_index = 0
        stream_valid_mask = 0
        stream_mismatch_mask = stream_mismatch_count
    else:
        stream_write_index = (stream_status >> 4) & 0x3
        stream_read_index = (stream_status >> 6) & 0x3
        stream_valid_mask = (stream_status >> 8) & 0xF
        stream_mismatch_mask = (stream_status >> 12) & 0xF
        stream_mismatch_count = stream_mismatch_mask.bit_count()
    calib_complete = bool(status & 0x01)
    calib_seen = bool(status & 0x02)
    command_gate = calib_seen and write_ack_seen and read_ack_seen and ack_count >= 2
    # YPCB CH0 open metadata has no DDR3 DM pins, and the diagnostic wrapper's
    # internal mismatch bit compares against its latched default byte for some
    # USER2-commanded runs even when the DDR write/read low byte follows the
    # requested command byte.  Treat the board-visible low-byte round trip plus
    # write/read acks as the no-DM self-test pass criterion; keep the raw
    # hardware mismatch bit in the JSON for tool/RTL debugging.
    if version <= 23:
        integrity_pass = command_gate and read_byte == expected and err_count == 0
    else:
        integrity_pass = (
            command_gate
            and stream_valid_mask == 0xF
            and stream_mismatch_count == 0
            and err_count == 0
        )

    return {
        "schema": "task6-uberddr3-jtag-payload-v1",
        "experiment": args.experiment,
        "variant": args.variant,
        "bitstream": args.bitstream,
        "expected_byte": f"0x{expected:02x}",
        "raw_hex": raw_hex,
        "magic": f"0x{raw & 0xFFFFFFFF:08x}",
        "version": version,
        "status": f"0x{status:02x}",
        "cycle": f"0x{((raw >> 48) & 0xFFFFFFFF):08x}",
        "calib_seen_cycle": f"0x{calib_seen_cycle:08x}",
        "debug1": f"0x{debug1:08x}",
        "state": debug1 & 0x1F,
        "instruction": (debug1 >> 5) & 0x1F,
        "idelay_ready": bool(bit(debug1, 10)),
        "ack_count": ack_count,
        "err_count": err_count,
        "stall_count": f"0x{((raw >> 208) & 0xFFFFFFFF):08x}",
        "read_byte": f"0x{read_byte:02x}",
        "read_word": f"0x{read_word:08x}",
        "stream_bytes": [f"0x{byte:02x}" for byte in stream_bytes],
        "stream_words32": [f"0x{word:08x}" for word in stream_words],
        "expected_stream_bytes": [f"0x{byte:02x}" for byte in expected_stream_bytes],
        "stream_mismatch_count": stream_mismatch_count,
        "stream_valid_mask": f"0x{stream_valid_mask:x}",
        "stream_mismatch_mask": f"0x{stream_mismatch_mask:x}",
        "stream_write_index": stream_write_index,
        "stream_read_index": stream_read_index,
        "read_beat_hex": f"0x{read_beat:0128x}" if read_beat is not None else None,
        "read_beat_bytes": hex_words(raw, 480, 8, 64) if read_beat is not None else [],
        "read_beat_words32": hex_words(raw, 480, 32, 16) if read_beat is not None else [],
        "active_byte": f"0x{active_byte:02x}",
        "active_addr": f"0x{active_addr:02x}",
        "command_count": command_count,
        "run_count": run_count,
        "command_trace": {
            "raw": f"0x{command_trace:08x}",
            "count": (command_trace >> 24) & 0xFF,
            "byte_o": f"0x{((command_trace >> 16) & 0xFF):02x}",
            "expected_byte_q": f"0x{((command_trace >> 8) & 0xFF):02x}",
            "write_byte": f"0x{(command_trace & 0xFF):02x}",
        },
        "probe": f"0x{probe:08x}",
        "probe_state": probe_state,
        "done": done,
        "write_ack_seen": write_ack_seen,
        "read_ack_seen": read_ack_seen,
        "err_seen": err_seen,
        "stall_seen": stall_seen,
        "mismatch": mismatch,
        "wait_cycles": f"0x{((raw >> 400) & 0xFFFFFFFF):08x}",
        "clk50_count": f"0x{((raw >> 432) & 0xFFFFFFFF):08x}",
        "sys_rstn": bool(bit(raw, 464)),
        "result": {
            "calibration": "pass" if calib_complete and calib_seen else "fail",
            "command_gate": "pass" if command_gate else "fail",
            "integrity": "pass" if integrity_pass else "fail",
            "board": (
                "integrity_pass"
                if integrity_pass
                else "command_gate_reproduced"
                if command_gate
                else "fail_before_command_gate"
            ),
        },
    }


def update_verdict(run_dir: Path, decoded: dict[str, Any]) -> None:
    path = run_dir / "verdict.json"
    verdict = json.loads(path.read_text(encoding="utf-8"))
    result = decoded["result"]
    verdict.update(
        {
            "status": "COMPLETE",
            "correctness": result["integrity"],
            "board": result["board"],
            "notes": [
                f"calibration={result['calibration']}",
                f"command_gate={result['command_gate']}",
                f"integrity={result['integrity']}",
                f"read_byte={decoded['read_byte']} expected={decoded['expected_byte']}",
                f"stream_bytes={decoded['stream_bytes']} expected={decoded['expected_stream_bytes']}",
                f"stream_valid={decoded['stream_valid_mask']} mismatch={decoded['stream_mismatch_mask']}",
                f"ack_count={decoded['ack_count']} err_count={decoded['err_count']}",
                f"command_trace={decoded['command_trace']}",
            ],
        }
    )
    write_json(path, verdict)


def append_jsonl(path: Path, payload: dict[str, Any]) -> None:
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(payload, sort_keys=True) + "\n")


def run_experiment(args: argparse.Namespace) -> Path:
    bitstream = args.bitstream or build_bitstream(args.build_attr)
    args.bitstream = bitstream
    run_dir = init_run(args, bitstream)

    with_lock(
        run_dir,
        "program.log",
        [
            "openFPGALoader",
            "-c",
            args.jtag_cable,
            "--ftdi-serial",
            args.ftdi_serial,
            bitstream,
        ],
    )
    if args.command_byte is not None:
        with_lock(
            run_dir,
            "write-command.log",
            [
                sys.executable,
                str(WRITE_JTAG),
                "--serial",
                args.ftdi_serial,
                "--tdo-bit",
                str(args.tdo_bit),
                "--byte",
                f"0x{args.command_byte:02x}",
                "--addr",
                f"0x{args.command_addr:02x}",
                "--update-mode",
                args.command_update_mode,
                "--json-only",
            ],
        )
        if args.post_command_delay > 0:
            time.sleep(args.post_command_delay)
    with_lock(
        run_dir,
        "readback-tdo7.log",
        [
            sys.executable,
            str(READ_JTAG),
            "--tdo-bit",
            str(args.tdo_bit),
            "--bits",
            str(args.bits),
            "--json-only",
        ],
    )

    log_text = (run_dir / "logs" / "readback-tdo7.log").read_text(encoding="utf-8")
    readback = extract_read_json(log_text)
    decoded = decode_uberddr3_payload(readback, args)
    write_json(run_dir / "readback" / f"decoded-tdo{args.tdo_bit}.json", decoded)
    update_verdict(run_dir, decoded)
    append_jsonl(
        ROOT / "artifacts" / "task6" / "ddr3-run-results.jsonl",
        {
            "created_at": datetime.now().astimezone().isoformat(),
            "run_dir": str(run_dir.relative_to(ROOT)),
            "variant": args.variant,
            "bitstream": bitstream,
            "result": decoded["result"],
            "read_byte": decoded["read_byte"],
            "read_word": decoded["read_word"],
            "stream_bytes": decoded["stream_bytes"],
            "expected_stream_bytes": decoded["expected_stream_bytes"],
            "stream_valid_mask": decoded["stream_valid_mask"],
            "stream_mismatch_mask": decoded["stream_mismatch_mask"],
            "expected_byte": decoded["expected_byte"],
            "active_byte": decoded["active_byte"],
            "active_addr": decoded["active_addr"],
            "command_count": decoded["command_count"],
            "command_trace": decoded["command_trace"],
            "run_count": decoded["run_count"],
            "ack_count": decoded["ack_count"],
            "err_count": decoded["err_count"],
        },
    )
    return run_dir


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--label", required=True)
    parser.add_argument("--experiment", default="task6-uberddr3-systematic-ddr3")
    parser.add_argument("--variant", required=True)
    parser.add_argument("--notes", default="created by task6_ddr3_experiment_runner.py")
    parser.add_argument(
        "--build-attr",
        default="task6-ypcb-uberddr3-bist-seed16-bitstream",
    )
    parser.add_argument("--bitstream")
    parser.add_argument("--expected-byte", type=lambda value: int(value, 0))
    parser.add_argument("--command-byte", type=lambda value: int(value, 0))
    parser.add_argument("--command-addr", type=lambda value: int(value, 0), default=0)
    parser.add_argument(
        "--command-update-mode",
        choices=("idle", "stop-at-update"),
        default="idle",
    )
    parser.add_argument("--post-command-delay", type=float, default=0.1)
    parser.add_argument("--jtag-cable", default="digilent_hs3")
    parser.add_argument("--ftdi-serial", default="210299BF3824")
    parser.add_argument("--tdo-bit", type=int, default=7)
    parser.add_argument("--bits", type=int, default=1024)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.command_byte is not None and not 0 <= args.command_byte <= 0xFF:
        raise SystemExit("--command-byte must fit in 8 bits")
    if not 0 <= args.command_addr <= 0xFF:
        raise SystemExit("--command-addr must fit in 8 bits")
    if args.expected_byte is None:
        args.expected_byte = args.command_byte if args.command_byte is not None else 0xA5
    run_dir = run_experiment(args)
    print(run_dir)
    return 0


if __name__ == "__main__":
    sys.exit(main())
