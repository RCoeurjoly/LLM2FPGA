#!/usr/bin/env python3
"""Dump the Task 6 PCIe BAR debug aperture without sudo.

The debug block starts at BAR0 offset 0x200 and is intended for first-stage
board bring-up when PCIe enumeration works but DDR3/rowstream boot does not.
"""

from __future__ import annotations

import argparse
import mmap
import os
from pathlib import Path
import struct
import subprocess
import time

BAR_SIZE = 4096
TASK6_MAGIC = 0x54365043
TASK6_VERSION = 3
DEBUG_MAGIC = 0x54364442
DEBUG_VERSION = 1
ALL_ONES = 0xFFFFFFFF

REG_MAGIC = 0x000
REG_VERSION = 0x004
REG_STATUS = 0x008
REG_ACCEPTED = 0x00C
REG_LOADER = 0x034
REG_LAST_OPCODE = 0x038
REG_LAST_ADDR = 0x03C
REG_WAIT_CYCLES = 0x040
REG_DDR_DEBUG1 = 0x054
REG_TOP1_STATUS = 0x060
REG_DEBUG_MAGIC = 0x200
REG_DEBUG_VERSION = 0x204
REG_DEBUG_HEARTBEAT_COUNT = 0x208
REG_DEBUG_ROWSTREAM_STATUS = 0x20C
REG_DEBUG_ROWSTREAM_SEEN = 0x210
REG_DEBUG_DDR_DEBUG1 = 0x214
REG_DEBUG_LOADER_WAIT = 0x218
REG_DEBUG_TOP1_STATUS = 0x21C
REG_DEBUG_TOP1_READER_ADDR = 0x220
REG_DEBUG_TOP1_WB_ACK_COUNT = 0x224
REG_DEBUG_TOP1_WB_ERR_COUNT = 0x228
REG_MLP_MAGIC = 0x300
REG_MLP_VERSION = 0x304
REG_MLP_PRESENT = 0x308
REG_MLP_STATUS = 0x30C
REG_MLP_CYCLE_COUNT = 0x310
REG_MLP_FAIL_DETAIL = 0x314
REG_MLP_FAIL_VALUES = 0x318
REG_MLP_FIRST_ADD_SAMPLE = 0x31C
REG_MLP_FIRST_REQUANT_SAMPLE = 0x320
REG_MLP_REQUANT_DEBUG_BASE = 0x3D0
REG_MLP_DEBUG_SELECT = 0x3C8

MLP_DEBUG_SELECT_LABELS = {
    0: "c_proj_acc0",
    1: "post_gelu_transfer_lo",
    2: "post_gelu_transfer_hi",
    3: "c_proj_weight_samples_lo",
    4: "c_proj_weight_samples_hi",
    5: "c_proj_activation_samples_lo",
    6: "c_proj_activation_samples_hi",
    7: "c_proj_sample0_addr_data",
    8: "c_proj_sample0_acc",
    9: "c_proj_final_acc",
    10: "c_proj_requant_scale",
    11: "c_proj_requant_bias",
    12: "c_proj_requant_product_lo",
    13: "c_proj_requant_product_hi",
    14: "c_proj_requant_scaled_lo",
    15: "c_proj_requant_biased_lo",
    16: "c_fc_post_gelu_samples_lo",
    17: "c_fc_post_gelu_samples_hi",
    18: "c_fc_activation_samples_lo",
    19: "c_fc_activation_samples_hi",
    20: "c_fc_weight_samples_lo",
    21: "c_fc_weight_samples_hi",
    22: "c_fc_acc_vs_post_acc0",
    23: "c_fc_scaled_vs_output0",
}


def run(cmd: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, text=True, capture_output=True, check=check)


def rd32(mm: mmap.mmap, offset: int) -> int:
    return struct.unpack(">I", bytes(mm[offset : offset + 4]))[0]


def wr32(mm: mmap.mmap, offset: int, value: int) -> None:
    mm[offset : offset + 4] = struct.pack(">I", value & 0xFFFFFFFF)


def decode_bits(value: int, fields: tuple[tuple[int, str], ...]) -> str:
    names = [name for bit, name in fields if value & (1 << bit)]
    return ",".join(names) or "0"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bdf", help="PCI BDF, for example 0000:42:00.0")
    parser.add_argument("--samples", type=int, default=2, help="number of heartbeat samples to read")
    parser.add_argument(
        "--mlp-debug-select",
        type=lambda value: int(value, 0),
        help="write the MLP selftest debug selector before reading BAR debug words",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    device = Path("/sys/bus/pci/devices") / args.bdf
    resource0 = device / "resource0"
    if not resource0.exists():
        raise SystemExit(f"missing BAR0 sysfs resource: {resource0}")

    endpoint = run(["lspci", "-s", args.bdf]).stdout.strip()
    command = run(["setpci", "-s", args.bdf, "COMMAND"]).stdout.strip()
    print(endpoint)
    print(f"COMMAND: 0x{int(command, 16):04x}")

    fd = os.open(resource0, os.O_RDWR | os.O_SYNC)
    try:
        with mmap.mmap(fd, BAR_SIZE, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE) as mm:
            if args.mlp_debug_select is not None:
                wr32(mm, REG_MLP_DEBUG_SELECT, args.mlp_debug_select)
                time.sleep(0.05)
            regs = {
                "magic": rd32(mm, REG_MAGIC),
                "version": rd32(mm, REG_VERSION),
                "status": rd32(mm, REG_STATUS),
                "accepted": rd32(mm, REG_ACCEPTED),
                "loader": rd32(mm, REG_LOADER),
                "last_opcode": rd32(mm, REG_LAST_OPCODE),
                "last_addr": rd32(mm, REG_LAST_ADDR),
                "wait_cycles": rd32(mm, REG_WAIT_CYCLES),
                "ddr_debug1": rd32(mm, REG_DDR_DEBUG1),
                "top1_status": rd32(mm, REG_TOP1_STATUS),
                "debug_magic": rd32(mm, REG_DEBUG_MAGIC),
                "debug_version": rd32(mm, REG_DEBUG_VERSION),
                "debug_status": rd32(mm, REG_DEBUG_ROWSTREAM_STATUS),
                "debug_seen": rd32(mm, REG_DEBUG_ROWSTREAM_SEEN),
                "debug_ddr_debug1": rd32(mm, REG_DEBUG_DDR_DEBUG1),
                "debug_loader_wait": rd32(mm, REG_DEBUG_LOADER_WAIT),
                "debug_top1_status": rd32(mm, REG_DEBUG_TOP1_STATUS),
                "debug_top1_reader_addr": rd32(mm, REG_DEBUG_TOP1_READER_ADDR),
                "debug_top1_wb_ack_or_fault_token": rd32(mm, REG_DEBUG_TOP1_WB_ACK_COUNT),
                "debug_top1_wb_err_or_fault_sidecar": rd32(mm, REG_DEBUG_TOP1_WB_ERR_COUNT),
                "mlp_magic": rd32(mm, REG_MLP_MAGIC),
                "mlp_version": rd32(mm, REG_MLP_VERSION),
                "mlp_present": rd32(mm, REG_MLP_PRESENT),
                "mlp_status": rd32(mm, REG_MLP_STATUS),
                "mlp_cycle_count": rd32(mm, REG_MLP_CYCLE_COUNT),
                "mlp_fail_detail": rd32(mm, REG_MLP_FAIL_DETAIL),
                "mlp_fail_values": rd32(mm, REG_MLP_FAIL_VALUES),
                "mlp_first_add_sample": rd32(mm, REG_MLP_FIRST_ADD_SAMPLE),
                "mlp_first_requant_sample": rd32(mm, REG_MLP_FIRST_REQUANT_SAMPLE),
                "mlp_debug_select": rd32(mm, REG_MLP_DEBUG_SELECT),
            }
            for idx in range(2):
                regs[f"mlp_requant_debug{idx}"] = rd32(mm, REG_MLP_REQUANT_DEBUG_BASE + idx * 4)
            heartbeat_samples = []
            for sample in range(max(args.samples, 1)):
                heartbeat_samples.append(rd32(mm, REG_DEBUG_HEARTBEAT_COUNT))
                if sample + 1 < max(args.samples, 1):
                    time.sleep(0.1)

            for name in (
                "magic",
                "version",
                "status",
                "accepted",
                "loader",
                "last_opcode",
                "last_addr",
                "wait_cycles",
                "ddr_debug1",
                "top1_status",
                "debug_magic",
                "debug_version",
                "debug_status",
                "debug_seen",
                "debug_ddr_debug1",
                "debug_loader_wait",
                "debug_top1_status",
                "debug_top1_reader_addr",
                "debug_top1_wb_ack_or_fault_token",
                "debug_top1_wb_err_or_fault_sidecar",
                "mlp_magic",
                "mlp_version",
                "mlp_present",
                "mlp_status",
                "mlp_cycle_count",
                "mlp_fail_detail",
                "mlp_fail_values",
                "mlp_first_add_sample",
                "mlp_first_requant_sample",
                "mlp_debug_select",
            ):
                print(f"{name:18s}: 0x{regs[name]:08x}")
            for idx in range(2):
                print(f"mlp_requant_debug{idx:<2d}: 0x{regs[f'mlp_requant_debug{idx}']:08x}")
            print("heartbeat_samples : " + " ".join(f"0x{x:08x}" for x in heartbeat_samples))

            print("status bits        : " + decode_bits(regs["status"], (
                (0, "pcie_rst_n"),
                (1, "event_active"),
                (2, "loader_done"),
                (3, "loader_error"),
                (4, "doorbell_error"),
                (5, "calib_complete"),
                (6, "boot_done"),
            )))
            print("loader bits        : " + decode_bits(regs["loader"], (
                (0, "calib_complete"),
                (1, "boot_done"),
                (2, "done"),
                (3, "error"),
                (4, "magic_ok"),
                (5, "accepted"),
            )))
            print("debug status bits  : " + decode_bits(regs["debug_status"], (
                (0, "pcie_rst_n"),
                (1, "rowstream_rst_n"),
                (2, "calib_complete"),
                (3, "boot_done"),
                (4, "rowstream_heartbeat"),
                (5, "loader_done"),
                (6, "loader_error"),
                (7, "top1_busy"),
            )))
            print("debug seen bits    : " + decode_bits(regs["debug_seen"], (
                (0, "rowstream_heartbeat_seen"),
                (1, "rowstream_rst_n_seen"),
                (2, "calib_complete_seen"),
                (3, "boot_done_seen"),
                (4, "ddr_debug1_nonzero_seen"),
            )))
            print("mlp status bits    : " + decode_bits(regs["mlp_status"], (
                (8, "busy"),
                (9, "done"),
                (10, "first_add_seen"),
                (11, "first_requant_seen"),
            )))
            mlp_state = regs["mlp_status"] & 0x0f
            mlp_state_name = {
                0x0: "BOOT",
                0x1: "LOAD_C_FC_ACTIVATION",
                0x2: "LOAD_C_FC_WEIGHT",
                0x3: "LOAD_C_FC_REQUANT",
                0x4: "LOAD_C_PROJ_WEIGHT",
                0x5: "LOAD_C_PROJ_REQUANT",
                0x6: "LOAD_RESIDUAL",
                0x7: "START",
                0x8: "RUN",
                0x9: "READ_SETUP",
                0xA: "READ_CHECK",
                0xB: "PASS",
                0xC: "FAIL",
            }.get(mlp_state, "UNKNOWN")
            mlp_fail_reason = (regs["mlp_fail_detail"] >> 8) & 0x03
            print(f"mlp state          : 0x{mlp_state:01x} ({mlp_state_name})")
            print(f"mlp pass           : {mlp_state == 0xB and mlp_fail_reason == 0}")
            print(f"mlp fail reason   : 0x{mlp_fail_reason:01x}")
            print(f"mlp fail index    : 0x{regs['mlp_fail_detail'] & 0xff:02x}")
            if regs["mlp_present"] == 1:
                print(
                    "mlp requant acc    : "
                    f"expected 0x{regs['mlp_requant_debug0']:08x} "
                    f"observed 0x{regs['mlp_requant_debug1']:08x}"
                )
                selector = regs["mlp_debug_select"] & 0x1F
                label = MLP_DEBUG_SELECT_LABELS.get(selector, "packed_status")
                print(
                    "mlp debug selected : "
                    f"{selector} ({label}) expected 0x{regs['mlp_requant_debug0']:08x} "
                    f"observed 0x{regs['mlp_requant_debug1']:08x}"
                )
            print("top1 debug bits    : " + decode_bits(regs["debug_top1_status"], (
                (0, "rst_n"),
                (1, "ddr_debug_ok"),
                (2, "calib_complete"),
                (3, "read_probe_done"),
                (4, "start_accepted"),
                (5, "start_rejected"),
                (6, "reader_busy"),
                (7, "reader_done"),
                (8, "reader_error"),
                (9, "reader_wb_cyc"),
                (10, "reader_wb_stb"),
                (11, "reader_wb_we"),
                (12, "wb_stall"),
                (13, "reader_wb_ack"),
                (14, "reader_wb_err"),
                (15, "cutout_valid"),
                (16, "cutout_done"),
                (17, "cutout_busy"),
                (18, "cutout_reserved_error"),
                (19, "row_valid"),
                (20, "row_ready"),
                (21, "row_last"),
            )))
            if regs["debug_top1_status"] & (1 << 18):
                fault_token_word = regs["debug_top1_wb_ack_or_fault_token"]
                print(f"top1 fault seen    : {bool(fault_token_word & 0x00010000)}")
                print(f"top1 fault token   : 0x{fault_token_word & 0xffff:04x}")
                print(f"top1 fault sidecar : 0x{regs['debug_top1_wb_err_or_fault_sidecar']:08x}")
                print(f"top1 fault addr    : 0x{regs['debug_top1_reader_addr']:08x}")

            if regs["magic"] == ALL_ONES or regs["debug_magic"] == ALL_ONES:
                raise SystemExit("BAR returned all ones; endpoint may be stale")
            if regs["magic"] != TASK6_MAGIC or regs["version"] != TASK6_VERSION:
                raise SystemExit("main Task 6 BAR header did not match")
            if regs["debug_magic"] != DEBUG_MAGIC or regs["debug_version"] != DEBUG_VERSION:
                raise SystemExit("debug aperture is not present in this bitstream")
    finally:
        os.close(fd)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
