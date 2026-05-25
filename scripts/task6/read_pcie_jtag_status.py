#!/usr/bin/env python3
"""Read and decode the Task 6 PCIe diagnostic USER1 JTAG status payload."""

import argparse
import json
import subprocess
import sys
from pathlib import Path

MAGIC = 0x54365049  # T6PI


def field(payload: int, offset: int, width: int) -> int:
    return (payload >> offset) & ((1 << width) - 1)


def decode(raw_hex: str, bit_count: int) -> dict:
    payload = int(raw_hex, 16)
    flags = field(payload, 40, 32)
    gt_ltssm_word = field(payload, 104, 32)
    cfg_id_word = field(payload, 136, 32)
    last_word = field(payload, 296, 32)
    decoded = {
        "raw_hex": raw_hex,
        "magic": field(payload, 0, 32),
        "magic_ok": field(payload, 0, 32) == MAGIC,
        "version": field(payload, 32, 8),
        "flags_word": flags,
        "flags": {
            "sys_rst_n": bool(flags & (1 << 0)),
            "pipe_mmcm_lock": bool(flags & (1 << 1)),
            "user_reset": bool(flags & (1 << 2)),
            "user_lnk_up": bool(flags & (1 << 3)),
            "cfg_command_io_enable": bool(flags & (1 << 9)),
            "cfg_command_mem_enable": bool(flags & (1 << 10)),
            "cfg_command_bus_master_enable": bool(flags & (1 << 11)),
            "cfg_lstatus_nonzero": bool(flags & (1 << 12)),
            "cfg_bus_number_nonzero": bool(flags & (1 << 13)),
        },
        "cfg_pcie_link_state_from_flags": field(flags, 6, 3),
        "gt_reset_fsm_low2_from_flags": field(flags, 4, 2),
        "user_clk_count": field(payload, 72, 32),
        "pl_ltssm_state": field(gt_ltssm_word, 5, 6),
        "gt_reset_fsm": field(gt_ltssm_word, 11, 5),
        "cfg_bus_number": field(cfg_id_word, 0, 8),
        "cfg_device_number": field(cfg_id_word, 8, 5),
        "cfg_function_number": field(cfg_id_word, 13, 3),
        "cfg_pcie_link_state": field(cfg_id_word, 16, 3),
        "cfg_status": field(payload, 168, 16),
        "cfg_command": field(payload, 200, 16),
        "cfg_dstatus": field(payload, 216, 16),
        "cfg_dcommand": field(payload, 232, 16),
        "cfg_lstatus": field(payload, 248, 16),
        "cfg_lcommand": field(payload, 264, 16),
        "cfg_dcommand2": field(payload, 280, 16),
        "last_ltssm_state": field(last_word, 10, 6),
        "last_lstatus": field(last_word, 16, 16),
        "user_reset_seen_count": field(payload, 328, 32),
        "link_up_seen_count": field(payload, 360, 32),
        "bit_count": bit_count,
    }
    return decoded


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reader", default="scripts/task6/read_jtag_debug_ftdi_bitbang.py")
    parser.add_argument("--serial", default="210299BF3824")
    parser.add_argument("--tdo-bit", type=int, choices=(0, 7), default=7)
    parser.add_argument("--bits", type=int, default=512)
    parser.add_argument("--user-ir", default="0x02")
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
            result["pcie"] = decode(raw_hex, args.bits)
    if not args.json_only:
        pcie = result.get("pcie", {})
        print(
            "magic_ok={magic_ok} sys_rst_n={sys_rst_n} pipe_mmcm_lock={pipe_mmcm_lock} "
            "user_reset={user_reset} user_lnk_up={user_lnk_up} ltssm=0x{ltssm:02x} "
            "cfg_bus={bus} cfg_lstatus=0x{lstatus:04x}".format(
                magic_ok=pcie.get("magic_ok"),
                sys_rst_n=pcie.get("flags", {}).get("sys_rst_n"),
                pipe_mmcm_lock=pcie.get("flags", {}).get("pipe_mmcm_lock"),
                user_reset=pcie.get("flags", {}).get("user_reset"),
                user_lnk_up=pcie.get("flags", {}).get("user_lnk_up"),
                ltssm=pcie.get("pl_ltssm_state", 0),
                bus=pcie.get("cfg_bus_number"),
                lstatus=pcie.get("cfg_lstatus", 0),
            )
        )
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if completed.returncode == 0 else completed.returncode


if __name__ == "__main__":
    raise SystemExit(main())
