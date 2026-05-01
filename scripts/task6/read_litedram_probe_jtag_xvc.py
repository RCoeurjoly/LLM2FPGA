#!/usr/bin/env python3
"""Read the YPCB LiteDRAM init/bandwidth probe payload through XVC JTAG."""

from __future__ import annotations

import argparse
import json
import time

from read_jtag_debug_xvc import XvcClient, read_payload, unsigned_field


DEFAULT_BITS = 4672
MAGIC = 0x54364A44
SAMPLE_COUNT = 8
BYTE_DIAG_SAMPLE_COUNT = 8
DFII_WORD_COUNT = 20
DFII_ADDR_SLOT_COUNT = 4
NATIVE_CHUNK_COUNT = 9
PHYSICAL_LANE_COUNT = 9
NATIVE_PHASE_CANDIDATE_COUNT = 16
DFII_PATTERN_MODE_NAMES = {
    0: "uniform",
    1: "phase_constant",
    2: "byte_ramp",
    3: "assoc_onehot",
}

STATE_NAMES = {
    0: "PROBE_RESET",
    1: "PROBE_WAIT_INIT",
    2: "PROBE_CAL_CONFIG",
    3: "PROBE_CAL_RUN_WRITES",
    4: "PROBE_CAL_WRITE_DRAIN",
    5: "PROBE_CAL_RUN_READS",
    6: "PROBE_CAL_APPLY_BEST",
    7: "PROBE_CAL_NEXT_LANE",
    8: "PROBE_RUN_WRITES",
    9: "PROBE_WRITE_DRAIN",
    10: "PROBE_RUN_READS",
    11: "PROBE_DONE",
    12: "PROBE_ERROR",
    13: "PROBE_TIMEOUT",
    14: "PROBE_DFII_RUN",
    15: "PROBE_DFII_DONE",
    16: "PROBE_DFII_RESTART",
    17: "PROBE_BYTE_CLEAR_WRITES",
    18: "PROBE_BYTE_MASK_WRITES",
    19: "PROBE_BYTE_WRITE_DRAIN",
    20: "PROBE_BYTE_RUN_READS",
    21: "PROBE_PHASE_CONFIG",
    22: "PROBE_PHASE_RUN_WRITES",
    23: "PROBE_PHASE_WRITE_DRAIN",
    24: "PROBE_PHASE_RUN_READS",
    25: "PROBE_PHASE_APPLY_BEST",
    26: "PROBE_DFII_WBITSLIP_CONFIG",
}

INIT_STATE_NAMES = {
    0: "INIT_RESET",
    1: "INIT_START_WAIT",
    2: "INIT_RUN_STEP",
    3: "INIT_WB_WAIT",
    4: "INIT_DELAY",
    5: "INIT_DONE",
    6: "INIT_ERROR",
}

CAL_CONFIG_STATE_NAMES = {
    0: "CAL_CFG_IDLE",
    1: "CAL_CFG_RUN_STEP",
    2: "CAL_CFG_WB_WAIT",
    3: "CAL_CFG_DONE",
    4: "CAL_CFG_ERROR",
}

DFII_SEQ_STATE_NAMES = {
    0: "DFII_SEQ_IDLE",
    1: "DFII_SEQ_RUN_STEP",
    2: "DFII_SEQ_WB_WAIT",
    3: "DFII_SEQ_DELAY",
    4: "DFII_SEQ_DONE",
    5: "DFII_SEQ_ERROR",
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
    ("init_state", 352, 8),
    ("init_step", 360, 8),
    ("init_delay_remaining", 368, 32),
    ("wb_ack_count", 400, 32),
    ("wb_wait_count", 432, 32),
    ("last_wb_addr", 464, 16),
    ("last_wb_data", 480, 32),
    ("write_data_count", 512, 32),
    ("write_command_count", 544, 32),
    ("compare_addr", 576, 32),
    ("mismatch_count", 608, 32),
    ("first_mismatch_addr", 640, 32),
    ("first_expected", 672, 64),
    ("first_actual", 736, 64),
    ("extended_status", 800, 32),
    ("cal_bitslip", 832, 8),
    ("cal_delay", 840, 8),
    ("cal_config_state", 848, 8),
    ("cal_config_step", 856, 8),
    ("cal_candidates_tested", 864, 32),
    ("best_mismatch_count", 896, 32),
    ("best_bitslip", 928, 8),
    ("best_delay", 936, 8),
    ("selected_bitslip", 944, 8),
    ("selected_delay", 952, 8),
    ("cal_lane", 960, 8),
    ("current_lane_best_mismatch_count", 968, 32),
    ("lane_selected_settings", 1000, 64),
    ("lane_best_mismatch_counts", 1064, 64),
    ("current_lane_best_setting", 1128, 8),
    ("lane_selected_logical_bytes", 1136, 32),
    ("current_lane_best_logical_byte", 1168, 8),
    ("sample_valid_count", 1184, 8),
    ("sample_rdata_0", 1216, 64),
    ("sample_rdata_1", 1280, 64),
    ("sample_rdata_2", 1344, 64),
    ("sample_rdata_3", 1408, 64),
    ("sample_rdata_4", 1472, 64),
    ("sample_rdata_5", 1536, 64),
    ("sample_rdata_6", 1600, 64),
    ("sample_rdata_7", 1664, 64),
    ("dfii_seq_state", 1728, 8),
    ("lane8_selected_setting", 1744, 8),
    ("lane8_best_mismatch_count", 1752, 8),
    ("lane8_selected_write_bitslip", 1760, 4),
    ("lane8_current_best_setting", 1768, 8),
    ("lane8_current_best_write_bitslip", 1776, 8),
    ("dfii_step", 1736, 8),
    ("dfii_wb_ack_count", 1744, 32),
    ("dfii_wb_wait_count", 1776, 32),
    ("dfii_word_mismatch_mask", 1808, 32),
    ("dfii_last_read_data", 1840, 32),
    ("dfii_rddata_0", 1872, 32),
    ("dfii_rddata_1", 1904, 32),
    ("dfii_rddata_2", 1936, 32),
    ("dfii_rddata_3", 1968, 32),
    ("dfii_rddata_4", 2000, 32),
    ("dfii_rddata_5", 2032, 32),
    ("dfii_rddata_6", 2064, 32),
    ("dfii_rddata_7", 2096, 32),
    ("dfii_rddata_8", 2128, 32),
    ("dfii_rddata_9", 2160, 32),
    ("dfii_rddata_10", 2192, 32),
    ("dfii_rddata_11", 2224, 32),
    ("dfii_rddata_12", 2256, 32),
    ("dfii_rddata_13", 2288, 32),
    ("dfii_rddata_14", 2320, 32),
    ("dfii_rddata_15", 2352, 32),
    ("dfii_uniform_mismatch_mask", 2384, 16),
    ("dfii_phase_mismatch_mask", 2400, 16),
    ("dfii_ramp_mismatch_mask", 2416, 16),
    ("dfii_pattern_mode", 2432, 8),
    ("dfii_phasecmd_mismatch_masks", 2464, 256),
    ("dfii_write_command_phase", 2720, 2),
    ("dfii_read_command_phase", 2722, 2),
    ("dfii_phasecmd_index", 2728, 4),
    ("byte_diag_valid_count", 2736, 8),
    ("byte_diag_rdata_0", 2752, 64),
    ("byte_diag_rdata_1", 2816, 64),
    ("byte_diag_rdata_2", 2880, 64),
    ("byte_diag_rdata_3", 2944, 64),
    ("byte_diag_rdata_4", 3008, 64),
    ("byte_diag_rdata_5", 3072, 64),
    ("byte_diag_rdata_6", 3136, 64),
    ("byte_diag_rdata_7", 3200, 64),
    ("dfii_assoc_index", 3264, 4),
    ("dfii_assoc_flags", 3272, 8),
    ("native_phase_mismatch_counts", 3296, 128),
    ("dfii_assoc_nonzero_mask_0", 3296, 16),
    ("dfii_assoc_nonzero_mask_1", 3312, 16),
    ("dfii_assoc_nonzero_mask_2", 3328, 16),
    ("dfii_assoc_nonzero_mask_3", 3344, 16),
    ("dfii_assoc_nonzero_mask_4", 3360, 16),
    ("dfii_assoc_nonzero_mask_5", 3376, 16),
    ("dfii_assoc_nonzero_mask_6", 3392, 16),
    ("dfii_assoc_nonzero_mask_7", 3408, 16),
    ("dfii_assoc_nonzero_mask_8", 3424, 16),
    ("dfii_assoc_nonzero_mask_9", 3440, 16),
    ("dfii_assoc_nonzero_mask_10", 3456, 16),
    ("dfii_assoc_nonzero_mask_11", 3472, 16),
    ("dfii_assoc_nonzero_mask_12", 3488, 16),
    ("dfii_assoc_nonzero_mask_13", 3504, 16),
    ("dfii_assoc_nonzero_mask_14", 3520, 16),
    ("dfii_assoc_nonzero_mask_15", 3536, 16),
    ("dfii_assoc_match_mask_0", 3552, 16),
    ("dfii_assoc_match_mask_1", 3568, 16),
    ("dfii_assoc_match_mask_2", 3584, 16),
    ("dfii_assoc_match_mask_3", 3600, 16),
    ("dfii_assoc_match_mask_4", 3616, 16),
    ("dfii_assoc_match_mask_5", 3632, 16),
    ("dfii_assoc_match_mask_6", 3648, 16),
    ("dfii_assoc_match_mask_7", 3664, 16),
    ("dfii_assoc_match_mask_8", 3680, 16),
    ("dfii_assoc_match_mask_9", 3696, 16),
    ("dfii_assoc_match_mask_10", 3712, 16),
    ("dfii_assoc_match_mask_11", 3728, 16),
    ("dfii_assoc_match_mask_12", 3744, 16),
    ("dfii_assoc_match_mask_13", 3760, 16),
    ("dfii_assoc_match_mask_14", 3776, 16),
    ("dfii_assoc_match_mask_15", 3792, 16),
    ("dfii_addr_index", 3808, 4),
    ("dfii_addr_flags", 3816, 8),
    ("dfii_addr_columns", 3824, 64),
    ("dfii_addr_mismatch_masks", 3888, 64),
    ("dfii_addr_nonzero_masks", 3952, 64),
    ("dfii_addr_match_masks", 4016, 64),
    ("dfii_disable_write_command", 4080, 1),
    ("dfii_phase_matrix_only", 4081, 1),
    ("dfii_source_command_matrix_only", 4082, 1),
    ("dfii_source_order_matrix_only", 4083, 1),
    ("dfii_source_command_read_phase", 4084, 2),
    ("dfii_csr_wrdata_mask_controllable", 4086, 1),
    ("dfii_wbitslip_sweep_only", 4086, 1),
    ("dfii_half_order_matrix_only", 4087, 1),
    ("dfii_source_order_source_phase", 4088, 2),
    ("dfii_source_order_write_phase", 4090, 2),
    ("dfii_source_order_read_phase", 4092, 2),
    ("dfii_displacement_probe_only", 4094, 1),
    ("dfii_csr_echo_probe_only", 4095, 1),
    ("dfii_rddata_16", 4096, 32),
    ("dfii_rddata_17", 4128, 32),
    ("dfii_rddata_18", 4160, 32),
    ("dfii_rddata_19", 4192, 32),
    ("dfii_half_nonzero_high_masks", 4224, 64),
    ("dfii_half_low_match_high_masks", 4288, 64),
    ("dfii_half_high_match_low_masks", 4352, 256),
    ("dfii_half_high_match_high_masks", 4608, 64),
    ("first_chunk_mismatch_mask", 1728, 16),
]

FIELDS.extend(
    [
        (f"first_expected_chunk_{chunk}", 1792 + chunk * 64, 64)
        for chunk in range(NATIVE_CHUNK_COUNT)
    ]
)
FIELDS.extend(
    [
        (f"first_actual_chunk_{chunk}", 2368 + chunk * 64, 64)
        for chunk in range(NATIVE_CHUNK_COUNT)
    ]
)


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
        "init_seq_running": bool(status & (1 << 11)),
        "init_seq_done": bool(status & (1 << 12)),
        "init_seq_error": bool(status & (1 << 13)),
        "wb_error_seen": bool(status & (1 << 14)),
        "wb_timeout_seen": bool(status & (1 << 15)),
    }


def decode_extended_status(status: int) -> dict[str, bool]:
    return {
        "wdata_ready": bool(status & (1 << 0)),
        "wdata_valid": bool(status & (1 << 1)),
        "cmd_valid": bool(status & (1 << 2)),
        "cmd_we": bool(status & (1 << 3)),
        "write_data_target_seen": bool(status & (1 << 4)),
        "write_command_target_seen": bool(status & (1 << 5)),
        "write_drain_done": bool(status & (1 << 6)),
        "mismatch_seen": bool(status & (1 << 7)),
        "read_target_seen": bool(status & (1 << 8)),
        "probe_done": bool(status & (1 << 9)),
        "probe_error": bool(status & (1 << 10)),
        "probe_timeout": bool(status & (1 << 11)),
        "wb_ctrl_err": bool(status & (1 << 12)),
        "wb_ctrl_ack": bool(status & (1 << 13)),
        "wb_ctrl_we": bool(status & (1 << 14)),
        "wb_ctrl_stb": bool(status & (1 << 15)),
        "wb_ctrl_cyc": bool(status & (1 << 16)),
        "core_rst": bool(status & (1 << 17)),
        "config_reset_done": bool(status & (1 << 18)),
        "cal_mode": bool(status & (1 << 19)),
        "cal_config_done": bool(status & (1 << 20)),
        "cal_candidate_success": bool(status & (1 << 21)),
        "cal_last_candidate": bool(status & (1 << 22)),
    }


def decode_payload(payload: int, bit_count: int) -> dict[str, object]:
    fields = {}
    for name, offset, width in FIELDS:
        if offset + width <= bit_count:
            fields[name] = unsigned_field(payload, offset, width)

    version = fields.get("version", 0)
    if version >= 65:
        assoc_flags = fields.get("dfii_assoc_flags", 0)
        fields["dfii_wbitslip_sweep_only"] = int(
            bool(fields.get("dfii_wbitslip_sweep_only", 0) or (assoc_flags & 0x08))
        )
        fields["dfii_rbitslip_sweep_only"] = int(bool(assoc_flags & 0x10))
        fields["dfii_edge_map_probe_only"] = int(
            bool(version >= 66 and (assoc_flags & 0x20))
        )
        fields["dfii_edge_comp_probe_only"] = int(
            bool(version >= 68 and (assoc_flags & 0x40))
        )
        fields["dfii_edge_lane7_locator_probe_only"] = int(
            bool(version >= 69 and (assoc_flags & 0x80))
        )

    state = fields.get("state", -1)
    status = fields.get("status", 0)
    decoded_status = decode_status(status)
    extended_status = decode_extended_status(fields.get("extended_status", 0))
    lane_selected_settings = decode_lane_settings(
        fields.get("lane_selected_settings", 0),
        fields,
        version,
    )
    lane_best_mismatch_counts = [
        (fields.get("lane_best_mismatch_counts", 0) >> (lane * 8)) & 0xFF
        for lane in range(8)
    ]
    if version == 50:
        lane_best_mismatch_counts.append(
            fields.get("lane8_best_mismatch_count", 0) & 0xFF
        )
    lane_selected_logical_bytes = [
        (fields.get("lane_selected_logical_bytes", 0) >> (lane * 4)) & 0x7
        for lane in range(8)
    ]
    if version == 50:
        lane_selected_logical_bytes.append(
            fields.get("lane8_selected_write_bitslip", 0) & 0x7
        )
    lane_selected_write_bitslips = (
        lane_selected_logical_bytes if version >= 35 else []
    )
    current_lane_best_write_bitslip = (
        fields.get("current_lane_best_logical_byte", 0) if version >= 35 else None
    )
    current_lane_best_setting = decode_setting_byte(
        fields.get("current_lane_best_setting", 0)
    )
    samples = decode_samples(fields)
    byte_diag_samples = decode_byte_diag_samples(fields)
    dfii_words = decode_dfii_words(fields)
    dfii_lane_error_counts = decode_dfii_lane_error_counts(dfii_words)
    displacement_like = bool(
        fields.get("dfii_displacement_probe_only", 0)
        or fields.get("dfii_wbitslip_sweep_only", 0)
        or fields.get("dfii_rbitslip_sweep_only", 0)
        or fields.get("dfii_edge_map_probe_only", 0)
        or fields.get("dfii_edge_comp_probe_only", 0)
        or fields.get("dfii_edge_lane7_locator_probe_only", 0)
    )
    dfii_assoc_matrix = decode_dfii_assoc_matrix(fields)
    dfii_phase_matrix = decode_dfii_phase_matrix(fields)
    dfii_addr_matrix = decode_dfii_addr_matrix(fields)
    native_phase_sweep = (
        decode_native_phase_sweep(fields) if 52 <= version < 54 else None
    )
    native_first_mismatch_chunks = (
        decode_native_first_mismatch_chunks(fields)
        if 49 <= version < 54
        else []
    )
    dfii_word_mismatch_mask = fields.get("dfii_word_mismatch_mask", 0) & 0xFFFF
    dfii_mode_masks = {
        "uniform": fields.get("dfii_uniform_mismatch_mask", 0) & 0xFFFF,
        "phase_constant": fields.get("dfii_phase_mismatch_mask", 0) & 0xFFFF,
        "byte_ramp": fields.get("dfii_ramp_mismatch_mask", 0) & 0xFFFF,
    }
    if version >= 54:
        dfii_data_failed = (
            fields.get("dfii_wb_ack_count", 0) != 0
            and (
                dfii_word_mismatch_mask != 0
                or any(mask != 0 for mask in dfii_mode_masks.values())
            )
        )
        dfii_data_pass = (
            fields.get("dfii_wb_ack_count", 0) != 0
            and dfii_word_mismatch_mask == 0
            and all(mask == 0 for mask in dfii_mode_masks.values())
        )
    elif version >= 49:
        dfii_data_failed = False
        dfii_data_pass = False
    elif version >= 37:
        dfii_data_failed = any(mask != 0 for mask in dfii_mode_masks.values())
        dfii_data_pass = all(mask == 0 for mask in dfii_mode_masks.values())
    else:
        dfii_data_failed = (
            state == 15
            and fields.get("dfii_wb_ack_count", 0) != 0
            and dfii_word_mismatch_mask != 0
        )
        dfii_data_pass = (
            state == 15
            and fields.get("dfii_wb_ack_count", 0) != 0
            and dfii_word_mismatch_mask == 0
        )
    return {
        "raw_hex": f"0x{payload:0{(bit_count + 3) // 4}x}",
        "magic_ok": fields.get("magic") == MAGIC,
        "fields": fields,
        "decoded": {
            "state": STATE_NAMES.get(state, f"UNKNOWN_{state}"),
            "init_state": INIT_STATE_NAMES.get(
                fields.get("init_state", -1),
                f"UNKNOWN_{fields.get('init_state', -1)}",
            ),
            "cal_config_state": CAL_CONFIG_STATE_NAMES.get(
                fields.get("cal_config_state", -1),
                f"UNKNOWN_{fields.get('cal_config_state', -1)}",
            ),
            "dfii_seq_state": DFII_SEQ_STATE_NAMES.get(
                fields.get("dfii_seq_state", -1),
                f"UNKNOWN_{fields.get('dfii_seq_state', -1)}",
            ),
            "status": decoded_status,
            "extended_status": extended_status,
            "lane_selected_settings": lane_selected_settings,
            "lane_best_mismatch_counts": lane_best_mismatch_counts,
            "lane_selected_logical_bytes": lane_selected_logical_bytes,
            "lane_selected_write_bitslips": lane_selected_write_bitslips,
            "current_lane_best_write_bitslip": current_lane_best_write_bitslip,
            "current_lane_best_setting": current_lane_best_setting,
            "samples": samples,
            "byte_diag_samples": byte_diag_samples,
            "dfii_words": dfii_words,
            "dfii_displacement_observed": decode_dfii_displacement_observed(
                dfii_words
            )
            if displacement_like
            else [],
            "dfii_displacement_shift_scores": decode_dfii_displacement_shift_scores(
                dfii_words
            )
            if displacement_like
            else [],
            "dfii_lane_error_counts": dfii_lane_error_counts,
            "dfii_mode_masks": dfii_mode_masks,
            "dfii_phasecmd_mismatch_masks": decode_dfii_phasecmd_masks(fields),
            "dfii_assoc_matrix": dfii_assoc_matrix,
            "dfii_phase_matrix": dfii_phase_matrix,
            "dfii_addr_matrix": dfii_addr_matrix,
            "native_phase_sweep": native_phase_sweep,
            "native_first_mismatch_chunks": native_first_mismatch_chunks,
            "dfii_pattern_mode": DFII_PATTERN_MODE_NAMES.get(
                fields.get("dfii_pattern_mode", 0),
                f"unknown_{fields.get('dfii_pattern_mode', 0)}",
            ),
            "dfii_data_pass": dfii_data_pass,
            "dfii_data_failed": dfii_data_failed,
            "complete": (
                (
                    decoded_status["read_target_seen"]
                    and extended_status["probe_done"]
                    and not extended_status["mismatch_seen"]
                )
                or state == 15
            ),
            "failed": (
                decoded_status["init_error"]
                or decoded_status["timeout_seen"]
                or decoded_status["init_seq_error"]
                or decoded_status["wb_error_seen"]
                or decoded_status["wb_timeout_seen"]
                or extended_status["probe_error"]
                or extended_status["probe_timeout"]
                or extended_status["mismatch_seen"]
                or dfii_data_failed
            ),
        },
    }


def pattern_for_addr(addr: int) -> int:
    x = addr & 0x0FFF_FFFF
    high = (0xC0DE_0000 ^ x ^ ((x << 7) & 0xFFFF_FFFF)) & 0xFFFF_FFFF
    low = (0x1357_9BDF ^ (~x & 0xFFFF_FFFF) ^ ((x << 13) & 0xFFFF_FFFF)) & 0xFFFF_FFFF
    return (high << 32) | low


def native_chunk_expected(addr: int, chunk: int) -> int:
    lane_tag = 0x10 + (chunk & 0xFF)
    return pattern_for_addr(addr) ^ int.from_bytes(bytes([lane_tag]) * 8, "little")


def byte_diag_expected(index: int) -> int:
    lane = index & 7
    return (0xA0 | lane) << (lane * 8)


def dfii_assoc_signature(source: int) -> int:
    source &= 0xF
    return (
        ((0xA0 | source) << 24)
        | ((0xB0 | source) << 16)
        | ((0xC0 | source) << 8)
        | (0xD0 | source)
    )


def dfii_phase_source_pattern(source_phase: int, word: int) -> int:
    base = 0x10 + ((source_phase & 0x3) << 4) + ((word & 0x3) << 2)
    return (
        ((base + 0) << 24)
        | ((base + 1) << 16)
        | ((base + 2) << 8)
        | (base + 3)
    )


def dfii_source_order_tag(slot: int) -> int:
    return 0x80 + (slot & 0xF)


def dfii_source_order_word(slot: int, word: int) -> int:
    slot &= 0xF
    word &= 0x3
    if word != ((slot >> 2) & 0x3):
        return 0
    return dfii_source_order_tag(slot) << ((slot & 0x3) * 8)


def dfii_half_low_tag(slot: int) -> int:
    return 0x90 + (slot & 0xF)


def dfii_half_high_tag(slot: int) -> int:
    return 0xA0 + (slot & 0xF)


def dfii_half_lane(slot: int) -> int:
    slot &= 0xF
    if slot <= 8:
        return slot
    if slot in (9, 10):
        return 7
    if slot in (11, 12, 15):
        return 8
    return 0


def dfii_half_low_enabled(slot: int) -> bool:
    slot &= 0xF
    return slot <= 9 or slot in (11, 13, 15)


def dfii_half_high_enabled(slot: int) -> bool:
    slot &= 0xF
    return slot <= 8 or slot in (10, 12, 14, 15)


def dfii_half_low_position(lane: int) -> tuple[int, int]:
    lane &= 0xF
    if lane <= 3:
        return 0, lane
    if lane <= 7:
        return 1, lane - 4
    return 2, 0


def dfii_half_high_position(lane: int) -> tuple[int, int]:
    lane &= 0xF
    if lane <= 2:
        return 2, lane + 1
    if lane <= 6:
        return 3, lane - 3
    if lane == 7:
        return 4, 0
    return 4, 1


def dfii_place_byte(tag: int, byte: int) -> int:
    return (tag & 0xFF) << ((byte & 0x3) * 8)


def dfii_half_order_word(slot: int, word: int) -> int:
    lane = dfii_half_lane(slot)
    value = 0
    if dfii_half_low_enabled(slot):
        low_word, low_byte = dfii_half_low_position(lane)
        if (word & 0x7) == low_word:
            value |= dfii_place_byte(dfii_half_low_tag(slot), low_byte)
    if dfii_half_high_enabled(slot):
        high_word, high_byte = dfii_half_high_position(lane)
        if (word & 0x7) == high_word:
            value |= dfii_place_byte(dfii_half_high_tag(slot), high_byte)
    return value


def dfii_displacement_word(word: int) -> int:
    words = [
        (
            dfii_place_byte(0x10, 0)
            | dfii_place_byte(0x11, 1)
            | dfii_place_byte(0x12, 2)
            | dfii_place_byte(0x13, 3)
        ),
        (
            dfii_place_byte(0x14, 0)
            | dfii_place_byte(0x15, 1)
            | dfii_place_byte(0x16, 2)
            | dfii_place_byte(0x17, 3)
        ),
        (
            dfii_place_byte(0x18, 0)
            | dfii_place_byte(0x20, 1)
            | dfii_place_byte(0x21, 2)
            | dfii_place_byte(0x22, 3)
        ),
        (
            dfii_place_byte(0x23, 0)
            | dfii_place_byte(0x24, 1)
            | dfii_place_byte(0x25, 2)
            | dfii_place_byte(0x26, 3)
        ),
        (
            dfii_place_byte(0x27, 0)
            | dfii_place_byte(0x28, 1)
            | dfii_place_byte(0x2A, 2)
            | dfii_place_byte(0x2B, 3)
        ),
    ]
    return words[word % 5]


def dfii_edge_map_tag(phase: int, high_half: bool, lane: int) -> int:
    return 0x10 + ((phase & 0x3) << 5) + (0x10 if high_half else 0) + (lane & 0xF)


def dfii_edge_map_word(phase: int, word: int) -> int:
    words = [
        (
            dfii_place_byte(dfii_edge_map_tag(phase, False, 0), 0)
            | dfii_place_byte(dfii_edge_map_tag(phase, False, 1), 1)
            | dfii_place_byte(dfii_edge_map_tag(phase, False, 2), 2)
            | dfii_place_byte(dfii_edge_map_tag(phase, False, 3), 3)
        ),
        (
            dfii_place_byte(dfii_edge_map_tag(phase, False, 4), 0)
            | dfii_place_byte(dfii_edge_map_tag(phase, False, 5), 1)
            | dfii_place_byte(dfii_edge_map_tag(phase, False, 6), 2)
            | dfii_place_byte(dfii_edge_map_tag(phase, False, 7), 3)
        ),
        (
            dfii_place_byte(dfii_edge_map_tag(phase, False, 8), 0)
            | dfii_place_byte(dfii_edge_map_tag(phase, True, 0), 1)
            | dfii_place_byte(dfii_edge_map_tag(phase, True, 1), 2)
            | dfii_place_byte(dfii_edge_map_tag(phase, True, 2), 3)
        ),
        (
            dfii_place_byte(dfii_edge_map_tag(phase, True, 3), 0)
            | dfii_place_byte(dfii_edge_map_tag(phase, True, 4), 1)
            | dfii_place_byte(dfii_edge_map_tag(phase, True, 5), 2)
            | dfii_place_byte(dfii_edge_map_tag(phase, True, 6), 3)
        ),
        (
            dfii_place_byte(dfii_edge_map_tag(phase, True, 7), 0)
            | dfii_place_byte(dfii_edge_map_tag(phase, True, 8), 1)
            | dfii_place_byte(0xC0 | (phase & 0x3), 2)
            | dfii_place_byte(0xD0 | (phase & 0x3), 3)
        ),
    ]
    return words[word % 5]


def dfii_edge_comp_tag(lane: int, version: int = 0) -> int:
    lane &= 0xF
    if version >= 73 and lane == 7:
        return 0xA0
    return 0x90 + lane


def dfii_edge_comp_read_word(word: int, version: int = 0) -> int:
    words = [
        (
            dfii_place_byte(dfii_edge_comp_tag(0, version), 0)
            | dfii_place_byte(dfii_edge_comp_tag(1, version), 1)
            | dfii_place_byte(dfii_edge_comp_tag(2, version), 2)
            | dfii_place_byte(dfii_edge_comp_tag(3, version), 3)
        ),
        (
            dfii_place_byte(dfii_edge_comp_tag(4, version), 0)
            | dfii_place_byte(dfii_edge_comp_tag(5, version), 1)
            | dfii_place_byte(dfii_edge_comp_tag(6, version), 2)
            | dfii_place_byte(dfii_edge_comp_tag(7, version), 3)
        ),
        (
            dfii_place_byte(dfii_edge_comp_tag(8, version), 0)
            | dfii_place_byte(dfii_edge_comp_tag(0, version), 1)
            | dfii_place_byte(dfii_edge_comp_tag(1, version), 2)
            | dfii_place_byte(dfii_edge_comp_tag(2, version), 3)
        ),
        (
            dfii_place_byte(dfii_edge_comp_tag(3, version), 0)
            | dfii_place_byte(dfii_edge_comp_tag(4, version), 1)
            | dfii_place_byte(dfii_edge_comp_tag(5, version), 2)
            | dfii_place_byte(dfii_edge_comp_tag(6, version), 3)
        ),
        (
            dfii_place_byte(dfii_edge_comp_tag(7, version), 0)
            | dfii_place_byte(dfii_edge_comp_tag(8, version), 1)
        ),
    ]
    return words[word % 5]


def dfii_edge_comp_write_word(
    phase: int, word: int, variant: int = 0, version: int = 0
) -> int:
    phase &= 0x3
    word %= 5
    variant &= 0x3
    if phase == 0 and word == 0:
        return (
            dfii_place_byte(dfii_edge_comp_tag(0, version), 0)
            | dfii_place_byte(dfii_edge_comp_tag(1, version), 1)
            | dfii_place_byte(dfii_edge_comp_tag(2, version), 2)
            | dfii_place_byte(dfii_edge_comp_tag(3, version), 3)
        )
    if phase == 0 and word == 1:
        return (
            dfii_place_byte(dfii_edge_comp_tag(4, version), 0)
            | dfii_place_byte(dfii_edge_comp_tag(5, version), 1)
            | dfii_place_byte(dfii_edge_comp_tag(6, version), 2)
            | dfii_place_byte(dfii_edge_comp_tag(7, version), 3)
        )
    if phase == 0 and word == 2:
        return dfii_place_byte(dfii_edge_comp_tag(8, version), 0)
    if word == 4:
        if variant == 3:
            return 0
        if phase == 0 or variant in (0, 2):
            value = dfii_place_byte(dfii_edge_comp_tag(7, version), 0)
            if variant != 2:
                value |= dfii_place_byte(dfii_edge_comp_tag(8, version), 1)
            return value
    return 0


def dfii_lane7_locator_expected_word(word: int) -> int:
    value = dfii_edge_comp_read_word(word)
    if word % 5 == 1:
        return value & 0x00FFFFFF
    if word % 5 == 4:
        return value & 0xFFFFFF00
    return value


def dfii_csr_echo_word(index: int) -> int:
    phase = index // 5
    word = index % 5
    base = 0x10 + (phase << 5) + (word << 2)
    value = dfii_place_byte(base, 0) | dfii_place_byte(base + 1, 1)
    if word != 4:
        value |= dfii_place_byte(base + 2, 2) | dfii_place_byte(base + 3, 3)
    return value


def dfii_displacement_tag_label(tag: int) -> str:
    for phase in range(4):
        low_base = 0x10 + (phase << 5)
        high_base = low_base + 0x10
        if low_base <= tag <= low_base + 8:
            return f"p{phase}_low_lane{tag - low_base}"
        if high_base <= tag <= high_base + 8:
            return f"p{phase}_high_lane{tag - high_base}"
        if tag == (0xC0 | phase):
            return f"p{phase}_pad_w4_b2"
        if tag == (0xD0 | phase):
            return f"p{phase}_pad_w4_b3"
    if 0x90 <= tag <= 0x98:
        return f"comp_lane{tag - 0x90}"
    if 0xA0 <= tag <= 0xB0:
        candidate = tag - 0xA0
        if candidate == 0:
            return "cand_p0_low_lane7"
        if 1 <= candidate <= 4:
            return f"cand_p{candidate - 1}_high_lane7"
        if 5 <= candidate <= 8:
            return f"cand_p{candidate - 5}_high_lane8"
        if 9 <= candidate <= 12:
            return f"cand_p{candidate - 9}_pad_w4_b2"
        return f"cand_p{candidate - 13}_pad_w4_b3"
    if 0x10 <= tag <= 0x18:
        return f"low_lane{tag - 0x10}"
    if 0x20 <= tag <= 0x28:
        return f"high_lane{tag - 0x20}"
    if tag == 0x2A:
        return "pad_w4_b2"
    if tag == 0x2B:
        return "pad_w4_b3"
    return f"unknown_0x{tag:02x}"


def decode_dfii_displacement_observed(
    dfii_words: list[dict[str, int]],
) -> list[dict[str, int | str]]:
    observed = []
    for entry in dfii_words:
        actual = entry["actual"]
        for byte in range(4):
            value = (actual >> (byte * 8)) & 0xFF
            if value == 0:
                continue
            observed.append(
                {
                    "phase": entry["phase"],
                    "word": entry["word"],
                    "byte": byte,
                    "value": value,
                    "label": dfii_displacement_tag_label(value),
                }
            )
    return observed


def word_bytes_le(word: int) -> list[int]:
    return [(word >> (byte * 8)) & 0xFF for byte in range(4)]


def decode_dfii_displacement_shift_scores(
    dfii_words: list[dict[str, int]],
) -> list[dict[str, object]]:
    by_phase: dict[int, list[dict[str, int]]] = {}
    for entry in dfii_words:
        by_phase.setdefault(entry["phase"], []).append(entry)

    decoded = []
    for phase in sorted(by_phase):
        entries = sorted(by_phase[phase], key=lambda item: item["word"])
        if len(entries) < 2:
            continue

        expected_bytes: list[int] = []
        actual_bytes: list[int] = []
        for entry in entries:
            expected_bytes.extend(word_bytes_le(entry["expected"]))
            actual_bytes.extend(word_bytes_le(entry["actual"]))

        scores = []
        for offset in range(-(len(expected_bytes) - 1), len(expected_bytes)):
            compared = 0
            exact = 0
            tagged = 0
            false_nonzero = 0
            matched_positions = []
            for actual_index, actual in enumerate(actual_bytes):
                expected_index = actual_index + offset
                if expected_index < 0 or expected_index >= len(expected_bytes):
                    continue
                compared += 1
                expected = expected_bytes[expected_index]
                if actual == expected:
                    exact += 1
                    if actual != 0:
                        tagged += 1
                        matched_positions.append(
                            {
                                "actual_byte": actual_index,
                                "expected_byte": expected_index,
                                "value": actual,
                            }
                        )
                elif actual != 0:
                    false_nonzero += 1
            scores.append(
                {
                    "offset": offset,
                    "compared": compared,
                    "exact": exact,
                    "tagged": tagged,
                    "false_nonzero": false_nonzero,
                    "matched_positions": matched_positions[:8],
                }
            )

        scores.sort(
            key=lambda item: (
                item["tagged"],
                item["exact"],
                -item["false_nonzero"],
                item["compared"],
            ),
            reverse=True,
        )
        decoded.append(
            {
                "phase": phase,
                "byte_count": len(actual_bytes),
                "top_offsets": scores[:5],
            }
        )
    return decoded


def dfii_pattern_word(
    index: int,
    version: int = 0,
    mode: int | None = None,
    assoc_index: int = 0,
    addr_index: int = 0,
    addr_sweep: bool = False,
) -> int:
    def apply_addr_tag(value: int) -> int:
        if not addr_sweep:
            return value
        tag = 0x40 + (addr_index & 0x3)
        return value ^ int.from_bytes(bytes([tag]) * 4, "big")

    index &= 0xF
    if version >= 37:
        mode = 2 if mode is None else mode
        if mode == 0:
            return apply_addr_tag(0xA55A_3CC3)
        if mode == 1:
            phase = (index >> 2) & 0x3
            return apply_addr_tag(
                ((phase << 4) | 0x8) << 24
                | ((phase << 4) | 0x4) << 16
                | ((phase << 4) | 0x2) << 8
                | ((phase << 4) | 0x1)
            )
        if mode == 3:
            source = assoc_index & 0xF
            return dfii_assoc_signature(source) if index == source else 0

    if version >= 33:
        return apply_addr_tag(
            ((index << 4) | 0x8) << 24
            | ((index << 4) | 0x4) << 16
            | ((index << 4) | 0x2) << 8
            | ((index << 4) | 0x1)
        )

    patterns = [
        0x11223344,
        0x55667788,
        0x99AABBCC,
        0xDDEEFF11,
        0x22446688,
        0xAACCDD99,
        0x13579BDF,
        0x2468ACE1,
        0x0F1E2D3C,
        0x4B5A6978,
        0x87A5C3E1,
        0xF1D3B597,
        0x31415926,
        0x53589793,
        0x23846264,
        0x33832795,
    ]
    return apply_addr_tag(patterns[index])


def decode_dfii_words(fields: dict[str, int]) -> list[dict[str, int]]:
    mismatch_mask = fields.get("dfii_word_mismatch_mask", 0)
    version = fields.get("version", 0)
    active_mode = fields.get("dfii_pattern_mode", None) if version >= 37 else None
    assoc_index = fields.get("dfii_assoc_index", 0)
    phase_matrix_only = bool(fields.get("dfii_phase_matrix_only", 0))
    source_command_matrix_only = bool(
        fields.get("dfii_source_command_matrix_only", 0)
    )
    source_order_matrix_only = bool(fields.get("dfii_source_order_matrix_only", 0))
    half_order_matrix_only = bool(fields.get("dfii_half_order_matrix_only", 0))
    displacement_probe_only = bool(fields.get("dfii_displacement_probe_only", 0))
    csr_echo_probe_only = bool(fields.get("dfii_csr_echo_probe_only", 0))
    wbitslip_sweep_only = bool(fields.get("dfii_wbitslip_sweep_only", 0))
    rbitslip_sweep_only = bool(fields.get("dfii_rbitslip_sweep_only", 0))
    edge_map_probe_only = bool(fields.get("dfii_edge_map_probe_only", 0))
    edge_comp_probe_only = bool(fields.get("dfii_edge_comp_probe_only", 0))
    lane7_locator_probe_only = bool(
        fields.get("dfii_edge_lane7_locator_probe_only", 0)
    )
    matrix_only = (
        phase_matrix_only
        or source_command_matrix_only
        or source_order_matrix_only
        or half_order_matrix_only
        or displacement_probe_only
        or csr_echo_probe_only
        or wbitslip_sweep_only
        or rbitslip_sweep_only
        or edge_map_probe_only
        or edge_comp_probe_only
        or lane7_locator_probe_only
    )
    phase_matrix_source = fields.get("dfii_phasecmd_index", 0) >> 2
    source_order_slot = fields.get("dfii_phasecmd_index", 0) & 0xF
    addr_flags = fields.get("dfii_addr_flags", 0)
    addr_sweep = bool(addr_flags & 0x4)
    addr_index = fields.get("dfii_addr_index", 0)
    if version >= 54 and not matrix_only and any(
        fields.get(f"dfii_assoc_nonzero_mask_{source}", 0)
        or fields.get(f"dfii_assoc_match_mask_{source}", 0)
        for source in range(16)
    ):
        active_mode = 3
    words = []
    use_five_word_phase = (
        half_order_matrix_only
        or displacement_probe_only
        or csr_echo_probe_only
        or wbitslip_sweep_only
        or rbitslip_sweep_only
        or edge_map_probe_only
        or edge_comp_probe_only
        or lane7_locator_probe_only
    )
    for index in range(DFII_WORD_COUNT):
        actual = fields.get(f"dfii_rddata_{index}", 0)
        if csr_echo_probe_only:
            expected = dfii_csr_echo_word(index)
        elif lane7_locator_probe_only:
            expected = dfii_lane7_locator_expected_word(index % 5)
        elif edge_comp_probe_only:
            if version >= 79:
                expected = dfii_edge_comp_write_word(
                    index // 5,
                    index % 5,
                    fields.get("dfii_phasecmd_index", 0) & 0x3,
                    version,
                )
            else:
                expected = dfii_edge_comp_read_word(index % 5, version)
        elif edge_map_probe_only:
            expected = dfii_edge_map_word(index // 5, index % 5)
        elif displacement_probe_only or wbitslip_sweep_only or rbitslip_sweep_only:
            expected = dfii_displacement_word(index % 5)
        elif half_order_matrix_only:
            expected = dfii_half_order_word(source_order_slot, index % 5)
        elif source_order_matrix_only:
            expected = dfii_source_order_word(source_order_slot, index & 0x3)
        elif matrix_only:
            expected = dfii_phase_source_pattern(phase_matrix_source, index & 0x3)
        else:
            expected = dfii_pattern_word(
                index,
                version,
                active_mode,
                assoc_index,
                addr_index,
                addr_sweep,
            )
        words.append(
            {
                "index": index,
                "phase": index // 5 if use_five_word_phase else index // 4,
                "word": index % 5 if use_five_word_phase else index % 4,
                "expected": expected,
                "actual": actual,
                "xor": actual ^ expected,
                "mismatch": (actual != expected)
                if csr_echo_probe_only
                else bool(mismatch_mask & (1 << index)),
            }
        )
    return words


def decode_dfii_phasecmd_masks(fields: dict[str, int]) -> list[dict[str, int]]:
    masks = fields.get("dfii_phasecmd_mismatch_masks", 0)
    decoded = []
    for index in range(16):
        decoded.append(
            {
                "index": index,
                "write_phase": index >> 2,
                "read_phase": index & 0x3,
                "mismatch_mask": (masks >> (index * 16)) & 0xFFFF,
            }
        )
    return decoded


def decode_dfii_phase_matrix(fields: dict[str, int]) -> list[dict[str, int]]:
    mismatch_masks = fields.get("dfii_phasecmd_mismatch_masks", 0)
    source_command = bool(fields.get("dfii_source_command_matrix_only", 0))
    source_order = bool(fields.get("dfii_source_order_matrix_only", 0))
    half_order = bool(fields.get("dfii_half_order_matrix_only", 0))
    fixed_read_phase = fields.get("dfii_source_command_read_phase", 2) & 0x3
    source_order_source_phase = fields.get("dfii_source_order_source_phase", 0) & 0x3
    source_order_write_phase = fields.get("dfii_source_order_write_phase", 0) & 0x3
    source_order_read_phase = fields.get("dfii_source_order_read_phase", 2) & 0x3
    half_nonzero_high = fields.get("dfii_half_nonzero_high_masks", 0)
    half_low_high = fields.get("dfii_half_low_match_high_masks", 0)
    half_high_low = fields.get("dfii_half_high_match_low_masks", 0)
    half_high_high = fields.get("dfii_half_high_match_high_masks", 0)
    decoded = []
    for index in range(16):
        if half_order:
            source_phase = source_order_source_phase
            write_phase = source_order_write_phase
            read_phase = source_order_read_phase
            byte_slot = index
            word = None
            byte = None
            lane = dfii_half_lane(index)
            tag = None
            low_tag = dfii_half_low_tag(index)
            high_tag = dfii_half_high_tag(index)
            low_word, low_byte = dfii_half_low_position(lane)
            high_word, high_byte = dfii_half_high_position(lane)
            nonzero_low_mask = fields.get(
                f"dfii_assoc_nonzero_mask_{index}", 0
            ) & 0xFFFF
            nonzero_high_mask = (half_nonzero_high >> (index * 4)) & 0xF
            low_match_low_mask = fields.get(
                f"dfii_assoc_match_mask_{index}", 0
            ) & 0xFFFF
            low_match_high_mask = (half_low_high >> (index * 4)) & 0xF
            high_match_low_mask = (half_high_low >> (index * 16)) & 0xFFFF
            high_match_high_mask = (half_high_high >> (index * 4)) & 0xF
        elif source_order:
            source_phase = source_order_source_phase
            write_phase = source_order_write_phase
            read_phase = source_order_read_phase
            byte_slot = index
            word = index >> 2
            byte = index & 0x3
            lane = None
            tag = dfii_source_order_tag(index)
            low_tag = None
            high_tag = None
            low_word = None
            low_byte = None
            high_word = None
            high_byte = None
            nonzero_low_mask = fields.get(
                f"dfii_assoc_nonzero_mask_{index}", 0
            ) & 0xFFFF
            nonzero_high_mask = 0
            low_match_low_mask = fields.get(
                f"dfii_assoc_match_mask_{index}", 0
            ) & 0xFFFF
            low_match_high_mask = 0
            high_match_low_mask = 0
            high_match_high_mask = 0
        else:
            source_phase = index >> 2
            write_phase = index & 0x3 if source_command else source_phase
            read_phase = fixed_read_phase if source_command else index & 0x3
            byte_slot = None
            word = None
            byte = None
            lane = None
            tag = None
            low_tag = None
            high_tag = None
            low_word = None
            low_byte = None
            high_word = None
            high_byte = None
            nonzero_low_mask = fields.get(
                f"dfii_assoc_nonzero_mask_{index}", 0
            ) & 0xFFFF
            nonzero_high_mask = 0
            low_match_low_mask = fields.get(
                f"dfii_assoc_match_mask_{index}", 0
            ) & 0xFFFF
            low_match_high_mask = 0
            high_match_low_mask = 0
            high_match_high_mask = 0
        decoded.append(
            {
                "index": index,
                "source_phase": source_phase,
                "write_phase": write_phase,
                "read_phase": read_phase,
                "byte_slot": byte_slot,
                "word": word,
                "byte": byte,
                "lane": lane,
                "tag": tag,
                "low_tag": low_tag,
                "high_tag": high_tag,
                "low_word": low_word,
                "low_byte": low_byte,
                "high_word": high_word,
                "high_byte": high_byte,
                "mismatch_mask": (mismatch_masks >> (index * 16)) & 0xFFFF,
                "nonzero_mask": nonzero_low_mask,
                "nonzero_high_mask": nonzero_high_mask,
                "match_mask": low_match_low_mask,
                "low_match_high_mask": low_match_high_mask,
                "high_match_low_mask": high_match_low_mask,
                "high_match_high_mask": high_match_high_mask,
            }
        )
    return decoded


def decode_dfii_assoc_matrix(fields: dict[str, int]) -> list[dict[str, int]]:
    decoded = []
    for source in range(16):
        decoded.append(
            {
                "source": source,
                "signature": dfii_assoc_signature(source),
                "nonzero_mask": fields.get(
                    f"dfii_assoc_nonzero_mask_{source}", 0
                )
                & 0xFFFF,
                "match_mask": fields.get(
                    f"dfii_assoc_match_mask_{source}", 0
                )
                & 0xFFFF,
            }
        )
    return decoded


def decode_dfii_addr_matrix(fields: dict[str, int]) -> list[dict[str, int]]:
    columns = fields.get("dfii_addr_columns", 0)
    mismatch_masks = fields.get("dfii_addr_mismatch_masks", 0)
    nonzero_masks = fields.get("dfii_addr_nonzero_masks", 0)
    match_masks = fields.get("dfii_addr_match_masks", 0)
    decoded = []
    for slot in range(DFII_ADDR_SLOT_COUNT):
        decoded.append(
            {
                "slot": slot,
                "column": (columns >> (slot * 16)) & 0xFFFF,
                "mismatch_mask": (mismatch_masks >> (slot * 16)) & 0xFFFF,
                "nonzero_mask": (nonzero_masks >> (slot * 16)) & 0xFFFF,
                "match_mask": (match_masks >> (slot * 16)) & 0xFFFF,
            }
        )
    return decoded


def decode_native_phase_sweep(fields: dict[str, int]) -> dict[str, object]:
    counts = fields.get("native_phase_mismatch_counts", 0)
    decoded_counts = []
    for index in range(NATIVE_PHASE_CANDIDATE_COUNT):
        decoded_counts.append(
            {
                "index": index,
                "wrphase": index >> 2,
                "rdphase": index & 0x3,
                "mismatches": (counts >> (index * 8)) & 0xFF,
            }
        )
    return {
        "candidate_index": fields.get("cal_lane", 0) & 0xF,
        "current_rdphase": fields.get("cal_bitslip", 0) & 0x3,
        "current_wrphase": fields.get("cal_delay", 0) & 0x3,
        "best_rdphase": fields.get("best_bitslip", 0) & 0x3,
        "best_wrphase": fields.get("best_delay", 0) & 0x3,
        "best_mismatches": fields.get("best_mismatch_count", 0),
        "candidates_tested": fields.get("cal_candidates_tested", 0),
        "counts": decoded_counts,
    }


def decode_dfii_lane_error_counts(dfii_words: list[dict[str, int]]) -> list[int]:
    errors = []
    for lane in range(8):
        lane_errors = 0
        for phase in range(4):
            for byte_index in (lane, lane + 8):
                word_index = phase * 4 + (byte_index // 4)
                byte_shift = (byte_index % 4) * 8
                word = dfii_words[word_index]
                actual = (word["actual"] >> byte_shift) & 0xFF
                expected = (word["expected"] >> byte_shift) & 0xFF
                lane_errors += (actual ^ expected).bit_count()
        errors.append(lane_errors)
    return errors


def decode_samples(fields: dict[str, int]) -> list[dict[str, int]]:
    valid_count = min(fields.get("sample_valid_count", 0), SAMPLE_COUNT)
    version = fields.get("version", 0)
    samples = []
    for index in range(valid_count):
        actual = fields.get(f"sample_rdata_{index}", 0)
        expected = (
            native_chunk_expected(index, 0)
            if version >= 47
            else pattern_for_addr(index)
        )
        samples.append(
            {
                "index": index,
                "expected": expected,
                "actual": actual,
                "xor": actual ^ expected,
            }
        )
    return samples


def decode_native_first_mismatch_chunks(fields: dict[str, int]) -> list[dict[str, int]]:
    mask = fields.get("first_chunk_mismatch_mask", 0)
    chunks = []
    for chunk in range(NATIVE_CHUNK_COUNT):
        expected = fields.get(f"first_expected_chunk_{chunk}", 0)
        actual = fields.get(f"first_actual_chunk_{chunk}", 0)
        chunks.append(
            {
                "chunk": chunk,
                "mismatch": bool(mask & (1 << chunk)),
                "expected": expected,
                "actual": actual,
                "xor": expected ^ actual,
            }
        )
    return chunks


def decode_byte_diag_samples(fields: dict[str, int]) -> list[dict[str, int]]:
    valid_count = min(
        fields.get("byte_diag_valid_count", 0),
        BYTE_DIAG_SAMPLE_COUNT,
    )
    samples = []
    for index in range(valid_count):
        actual = fields.get(f"byte_diag_rdata_{index}", 0)
        expected = byte_diag_expected(index)
        samples.append(
            {
                "index": index,
                "write_enable": 1 << index,
                "expected_if_byte_enable_works": expected,
                "actual": actual,
                "xor": actual ^ expected,
            }
        )
    return samples


def decode_setting_byte(value: int) -> dict[str, int]:
    return {
        "bitslip": (value >> 5) & 0x7,
        "delay": value & 0x1F,
    }


def decode_lane_settings(
    value: int,
    fields: dict[str, int] | None = None,
    version: int = 0,
) -> list[dict[str, int]]:
    settings = []
    for lane in range(8):
        byte = (value >> (lane * 8)) & 0xFF
        settings.append({"lane": lane, **decode_setting_byte(byte)})
    if version == 50 and fields is not None:
        settings.append({
            "lane": 8,
            **decode_setting_byte(fields.get("lane8_selected_setting", 0)),
        })
    return settings


def print_summary(result: dict[str, object]) -> None:
    fields = result["fields"]
    decoded = result["decoded"]
    status = decoded["status"]
    extended_status = decoded["extended_status"]
    print(
        "magic_ok={magic_ok} version={version} state={state} "
        "init_state={init_state} init_step={init_step} "
        "init_done={init_done} init_error={init_error} pll_locked={pll_locked} "
        "writes={writes}/{write_commands} reads={commands} responses={responses} target={target} "
        "cycles={cycles} stalls={stalls} checksum=0x{checksum:08x}".format(
            magic_ok=result["magic_ok"],
            version=fields.get("version"),
            state=decoded["state"],
            init_state=decoded["init_state"],
            init_step=fields.get("init_step"),
            init_done=status["init_done"],
            init_error=status["init_error"],
            pll_locked=status["pll_locked"],
            writes=fields.get("write_data_count"),
            write_commands=fields.get("write_command_count"),
            commands=fields.get("command_count"),
            responses=fields.get("response_count"),
            target=fields.get("target_read_count"),
            cycles=fields.get("read_cycle_count"),
            stalls=fields.get("command_stall_count"),
            checksum=fields.get("checksum", 0),
        )
    )
    print(
        "last_rdata=0x{last_rdata:016x} wb_ack={wb_ack} "
        "wb_wait={wb_wait} last_wb=0x{addr:04x}:0x{data:08x}".format(
            last_rdata=fields.get("last_rdata", 0),
            wb_ack=fields.get("wb_ack_count"),
            wb_wait=fields.get("wb_wait_count"),
            addr=fields.get("last_wb_addr", 0),
            data=fields.get("last_wb_data", 0),
        )
    )
    print(
        "mismatches={mismatches} first_mismatch_addr=0x{addr:08x} "
        "expected=0x{expected:016x} actual=0x{actual:016x} "
        "complete={complete} failed={failed}".format(
            mismatches=fields.get("mismatch_count", 0),
            addr=fields.get("first_mismatch_addr", 0),
            expected=fields.get("first_expected", 0),
            actual=fields.get("first_actual", 0),
            complete=decoded["complete"],
            failed=decoded["failed"],
        )
    )
    if decoded.get("native_phase_sweep") is not None:
        phase = decoded["native_phase_sweep"]
        phase_counts = " ".join(
            "w{wrphase}/r{rdphase}={mismatches}".format(**entry)
            for entry in phase["counts"]
        )
        print(
            "native phase sweep index={index} current=w{cur_w}/r{cur_r} "
            "state={cal_state} step={step} candidates={candidates} "
            "best={best}@w{best_w}/r{best_r}".format(
                index=phase["candidate_index"],
                cur_w=phase["current_wrphase"],
                cur_r=phase["current_rdphase"],
                cal_state=decoded["cal_config_state"],
                step=fields.get("cal_config_step", 0),
                candidates=phase["candidates_tested"],
                best=phase["best_mismatches"],
                best_w=phase["best_wrphase"],
                best_r=phase["best_rdphase"],
            )
        )
        print(f"native phase mismatch counts: {phase_counts}")
    else:
        print(
            "cal lane={lane} bitslip={bitslip} delay={delay} state={cal_state} step={step} "
            "candidates={candidates} best={best_mismatches}@b{best_bitslip}/d{best_delay} "
            "selected=b{selected_bitslip}/d{selected_delay} lane_best={lane_best}".format(
                lane=fields.get("cal_lane", 0),
                bitslip=fields.get("cal_bitslip", 0),
                delay=fields.get("cal_delay", 0),
                cal_state=decoded["cal_config_state"],
                step=fields.get("cal_config_step", 0),
                candidates=fields.get("cal_candidates_tested", 0),
                best_mismatches=fields.get("best_mismatch_count", 0),
                best_bitslip=fields.get("best_bitslip", 0),
                best_delay=fields.get("best_delay", 0),
                selected_bitslip=fields.get("selected_bitslip", 0),
                selected_delay=fields.get("selected_delay", 0),
                lane_best=fields.get("current_lane_best_mismatch_count", 0),
            )
        )
    if fields.get("version", 0) < 49 or fields.get("version", 0) >= 54:
        print(
            "dfii state={state} step={step} no_write={no_write} "
            "phase_matrix={phase_matrix} source_command_matrix={source_command_matrix} "
            "source_order_matrix={source_order_matrix} "
            "half_order_matrix={half_order_matrix} "
            "displacement_probe={displacement_probe} "
            "csr_echo={csr_echo} "
            "wbitslip_sweep={wbitslip_sweep} "
            "rbitslip_sweep={rbitslip_sweep} "
            "edge_map={edge_map} "
            "edge_comp={edge_comp} "
            "lane7_locator={lane7_locator} "
            "ack={ack} wait={wait} "
            "mismatch_mask=0x{mask:04x} last_read=0x{last:08x} "
            "data_pass={data_pass}".format(
                state=decoded["dfii_seq_state"],
                step=fields.get("dfii_step", 0),
                no_write=bool(fields.get("dfii_disable_write_command", 0)),
                phase_matrix=bool(fields.get("dfii_phase_matrix_only", 0)),
                source_command_matrix=bool(
                    fields.get("dfii_source_command_matrix_only", 0)
                ),
                source_order_matrix=bool(
                    fields.get("dfii_source_order_matrix_only", 0)
                ),
                half_order_matrix=bool(
                    fields.get("dfii_half_order_matrix_only", 0)
                ),
                displacement_probe=bool(
                    fields.get("dfii_displacement_probe_only", 0)
                ),
                csr_echo=bool(fields.get("dfii_csr_echo_probe_only", 0)),
                wbitslip_sweep=bool(fields.get("dfii_wbitslip_sweep_only", 0)),
                rbitslip_sweep=bool(fields.get("dfii_rbitslip_sweep_only", 0)),
                edge_map=bool(fields.get("dfii_edge_map_probe_only", 0)),
                edge_comp=bool(fields.get("dfii_edge_comp_probe_only", 0)),
                lane7_locator=bool(
                    fields.get("dfii_edge_lane7_locator_probe_only", 0)
                ),
                ack=fields.get("dfii_wb_ack_count", 0),
                wait=fields.get("dfii_wb_wait_count", 0),
                mask=fields.get("dfii_word_mismatch_mask", 0) & 0xFFFF,
                last=fields.get("dfii_last_read_data", 0),
                data_pass=decoded["dfii_data_pass"],
            )
        )
    if 37 <= fields.get("version", 0) < 49 or fields.get("version", 0) >= 54:
        masks = decoded["dfii_mode_masks"]
        print(
            "dfii mode masks: uniform=0x{uniform:04x} "
            "phase_constant=0x{phase:04x} byte_ramp=0x{ramp:04x} "
            "active_mode={mode}".format(
                uniform=masks["uniform"],
                phase=masks["phase_constant"],
                ramp=masks["byte_ramp"],
                mode=decoded["dfii_pattern_mode"],
            )
        )
    phase_matrix_only = bool(fields.get("dfii_phase_matrix_only", 0))
    source_command_matrix_only = bool(
        fields.get("dfii_source_command_matrix_only", 0)
    )
    source_order_matrix_only = bool(fields.get("dfii_source_order_matrix_only", 0))
    half_order_matrix_only = bool(fields.get("dfii_half_order_matrix_only", 0))
    displacement_probe_only = bool(fields.get("dfii_displacement_probe_only", 0))
    csr_echo_probe_only = bool(fields.get("dfii_csr_echo_probe_only", 0))
    wbitslip_sweep_only = bool(fields.get("dfii_wbitslip_sweep_only", 0))
    rbitslip_sweep_only = bool(fields.get("dfii_rbitslip_sweep_only", 0))
    edge_map_probe_only = bool(fields.get("dfii_edge_map_probe_only", 0))
    edge_comp_probe_only = bool(fields.get("dfii_edge_comp_probe_only", 0))
    lane7_locator_probe_only = bool(
        fields.get("dfii_edge_lane7_locator_probe_only", 0)
    )
    matrix_only = (
        phase_matrix_only
        or source_command_matrix_only
        or source_order_matrix_only
        or half_order_matrix_only
    )
    if csr_echo_probe_only:
        words = decoded["dfii_words"]
        read_count = fields.get("dfii_wb_ack_count", 0)
        complete = decoded["dfii_seq_state"] == "DFII_SEQ_DONE" and read_count >= 42
        matches = sum(1 for entry in words if not entry["mismatch"])
        status = "complete" if complete else "incomplete"
        print(
            "dfii csr echo probe: read back pi*_wrdata0..4 CSR storage, "
            f"{status}, dfii_ack={read_count}, matches={matches}/{len(words)}"
        )
        bad = [entry for entry in words if entry["mismatch"]]
        if bad:
            formatted = " ".join(
                "p{phase}/w{word}:exp=0x{expected:08x}/act=0x{actual:08x}".format(
                    **entry
                )
                for entry in bad[:8]
            )
            suffix = " ..." if len(bad) > 8 else ""
            print(f"dfii csr echo mismatches: {formatted}{suffix}")
    if wbitslip_sweep_only or rbitslip_sweep_only:
        half_nonzero_high = fields.get("dfii_half_nonzero_high_masks", 0)
        half_low_high = fields.get("dfii_half_low_match_high_masks", 0)
        kind = "read-bitslip" if rbitslip_sweep_only else "write-bitslip"
        print(
            f"dfii {kind} sweep: dense displacement probe after {kind} "
            "reset plus N pulses across all nine DQS groups"
        )
        for pulses in range(8):
            value = (7 + pulses) & 0x7
            nonzero_low = fields.get(f"dfii_assoc_nonzero_mask_{pulses}", 0)
            exact_low = fields.get(f"dfii_assoc_match_mask_{pulses}", 0)
            nonzero_high = (half_nonzero_high >> (pulses * 4)) & 0xF
            exact_high = (half_low_high >> (pulses * 4)) & 0xF
            print(
                "  pulses={pulses} value={value} "
                "nonzero_low=0x{nonzero_low:04x} exact_low=0x{exact_low:04x} "
                "nonzero_high=0x{nonzero_high:x} exact_high=0x{exact_high:x} "
                "visible={visible}/20 exact={exact}/20".format(
                    pulses=pulses,
                    value=value,
                    nonzero_low=nonzero_low,
                    exact_low=exact_low,
                    nonzero_high=nonzero_high,
                    exact_high=exact_high,
                    visible=nonzero_low.bit_count() + nonzero_high.bit_count(),
                    exact=exact_low.bit_count() + exact_high.bit_count(),
                )
            )
    displacement_like = (
        displacement_probe_only
        or wbitslip_sweep_only
        or rbitslip_sweep_only
        or edge_map_probe_only
        or edge_comp_probe_only
        or lane7_locator_probe_only
    )
    if displacement_like:
        shift_scores = decoded["dfii_displacement_shift_scores"]
        if shift_scores:
            print(
                "dfii shifted-byte scores: offset means "
                "actual_byte[i] == expected_byte[i+offset]"
            )
            for phase_score in shift_scores:
                top = phase_score["top_offsets"][:3]
                formatted = " ".join(
                    "off={offset:+d}:tagged={tagged}/{compared},exact={exact},"
                    "false_nz={false_nonzero}".format(**score)
                    for score in top
                )
                print(
                    "  phase={phase} bytes={byte_count} {scores}".format(
                        phase=phase_score["phase"],
                        byte_count=phase_score["byte_count"],
                        scores=formatted,
                    )
                )
    if (
        displacement_probe_only
        or edge_map_probe_only
        or edge_comp_probe_only
        or lane7_locator_probe_only
    ):
        observed = decoded["dfii_displacement_observed"]
        if lane7_locator_probe_only:
            print(
                "dfii lane7 source locator: known-good lanes fixed, "
                "candidate tags A0..B0 placed on low/high lane7, lane8, "
                "and pad source slots"
            )
        elif edge_comp_probe_only:
            if fields.get("version", 0) >= 77:
                masks = decoded["dfii_phasecmd_mismatch_masks"]
                print(
                    "dfii compensated-edge probe: one-bitstream final-word "
                    "variant sweep at separate columns"
                )
                dfii_complete = (
                    fields.get("init_state", -1) == 5
                    and fields.get("dfii_seq_state", -1) == 4
                )
                if fields.get("version", 0) >= 78:
                    print(
                        "dfii compensated-edge probe: wrdata CSR echo masks "
                        "are printed before DRAM readback masks"
                    )
                if fields.get("version", 0) >= 79:
                    print(
                        "dfii compensated-edge probe: CSR-only variant sweep; "
                        "no DRAM write/read commands are issued"
                    )
                if not dfii_complete:
                    print(
                        "dfii compensated-edge probe: variant masks are not "
                        "valid because init/DFII did not complete"
                    )
                labels = [
                    "all-phase lane7/lane8 final bytes",
                    "phase0-only lane7/lane8 final bytes",
                    "all-phase lane7-only final byte",
                    "no final-word bytes, expected to fail",
                ]
                csr_echo_high_masks = fields.get("dfii_half_nonzero_high_masks", 0)
                for index, label in enumerate(labels):
                    mask = masks[index]["mismatch_mask"]
                    dram_result = "PASS" if mask == 0 else "FAIL"
                    if fields.get("version", 0) >= 79:
                        csr_high = (csr_echo_high_masks >> (index * 4)) & 0xF
                        csr_mask = mask | (csr_high << 16)
                        csr_result = "PASS" if csr_mask == 0 else "FAIL"
                        if dfii_complete:
                            print(
                                f"  variant{index}: {label}: "
                                f"csr_echo_mismatch=0x{csr_mask:05x} "
                                f"{csr_result}"
                            )
                        else:
                            print(
                                f"  variant{index}: {label}: "
                                f"csr_echo_mismatch=0x{csr_mask:05x}; invalid"
                            )
                    elif fields.get("version", 0) >= 78:
                        csr_low = fields.get(f"dfii_assoc_nonzero_mask_{index}", 0)
                        csr_high = (csr_echo_high_masks >> (index * 4)) & 0xF
                        csr_mask = csr_low | (csr_high << 16)
                        csr_result = "PASS" if csr_mask == 0 else "FAIL"
                        if dfii_complete:
                            print(
                                f"  variant{index}: {label}: "
                                f"csr_echo_mismatch=0x{csr_mask:05x} "
                                f"{csr_result}; "
                                f"dram_mismatch=0x{mask:04x} {dram_result}"
                            )
                        else:
                            print(
                                f"  variant{index}: {label}: "
                                f"csr_echo_mismatch=0x{csr_mask:05x}; "
                                f"dram_mismatch=0x{mask:04x}; invalid"
                            )
                    else:
                        if dfii_complete:
                            print(
                                f"  variant{index}: {label}: "
                                f"mismatch_mask=0x{mask:04x} {dram_result}"
                            )
                        else:
                            print(
                                f"  variant{index}: {label}: "
                                f"mismatch_mask=0x{mask:04x}; invalid"
                            )
            elif fields.get("version", 0) >= 76:
                print(
                    "dfii compensated-edge probe: lane7 expects 0xa0 and "
                    "only phase-0 lane7/lane8 final-word bytes are written"
                )
            elif fields.get("version", 0) >= 75:
                print(
                    "dfii compensated-edge probe: lane7 expects 0xa0 and "
                    "only lane7/lane8 final-word bytes are written"
                )
            elif fields.get("version", 0) >= 74:
                print(
                    "dfii compensated-edge probe: lane7 expects 0xa0 and "
                    "v69 word4 filler is restored"
                )
            elif fields.get("version", 0) >= 73:
                print(
                    "dfii compensated-edge probe: v70 source map, lane7 "
                    "uses repeatable 0xa0 locator value"
                )
            else:
                print(
                    "dfii compensated-edge probe: known lanes through source "
                    "phase 0, lane7 driven on every DFI source phase"
                )
        elif edge_map_probe_only:
            print(
                "dfii edge-map probe: tagged bytes across all DFI phases/halves, "
                "write p{write}/read p{read}".format(
                    write=fields.get("dfii_source_order_write_phase", 0),
                    read=fields.get("dfii_source_order_read_phase", 0),
                )
            )
        else:
            print(
                "dfii displacement probe: dense low/high lane-tag pattern, "
                "fixed source p{source}/write p{write}/read p{read}".format(
                    source=fields.get("dfii_source_order_source_phase", 0),
                    write=fields.get("dfii_source_order_write_phase", 0),
                    read=fields.get("dfii_source_order_read_phase", 0),
                )
            )
        if observed:
            formatted = " ".join(
                "p{phase}/w{word}/b{byte}=0x{value:02x}({label})".format(
                    **entry
                )
                for entry in observed
            )
        else:
            formatted = "none"
        print(f"dfii displacement observed bytes: {formatted}")
    if matrix_only:
        phase_matrix = decoded["dfii_phase_matrix"]
        if half_order_matrix_only:
            print(
                "dfii half-order matrix: low/high 72-bit half tags, "
                "fixed source p{source}/write p{write}/read p{read}".format(
                    source=fields.get("dfii_source_order_source_phase", 0),
                    write=fields.get("dfii_source_order_write_phase", 0),
                    read=fields.get("dfii_source_order_read_phase", 0),
                )
            )
            print(
                "dfii CSR wrdata_mask controllable: "
                f"{bool(fields.get('dfii_csr_wrdata_mask_controllable', 0))}"
            )
        elif source_order_matrix_only:
            print(
                "dfii source-order matrix: one tagged byte slot, "
                "fixed source p{source}/write p{write}/read p{read}".format(
                    source=fields.get("dfii_source_order_source_phase", 0),
                    write=fields.get("dfii_source_order_write_phase", 0),
                    read=fields.get("dfii_source_order_read_phase", 0),
                )
            )
            print(
                "dfii CSR wrdata_mask controllable: "
                f"{bool(fields.get('dfii_csr_wrdata_mask_controllable', 0))}"
            )
        elif source_command_matrix_only:
            print(
                "dfii source/command matrix: source phase x write phase, "
                f"fixed read phase p{fields.get('dfii_source_command_read_phase', 0)}"
            )
            print(
                "dfii CSR wrdata_mask controllable: "
                f"{bool(fields.get('dfii_csr_wrdata_mask_controllable', 0))}"
            )
        else:
            print("dfii phase/source matrix: source/write phase x read phase")
        for entry in phase_matrix:
            if half_order_matrix_only:
                print(
                    "  [slot {byte_slot:02d} lane {lane} "
                    "low=0x{low_tag:02x}@w{low_word}/b{low_byte} "
                    "high=0x{high_tag:02x}@w{high_word}/b{high_byte}] "
                    "nonzero=0x{nonzero_high_mask:x}_{nonzero_mask:04x} "
                    "low_match=0x{low_match_high_mask:x}_{match_mask:04x} "
                    "high_match=0x{high_match_high_mask:x}_{high_match_low_mask:04x}".format(
                        **entry
                    )
                )
            elif source_order_matrix_only:
                print(
                    "  [slot {byte_slot:02d} word {word}/byte {byte} "
                    "tag=0x{tag:02x}] "
                    "tag_absent=0x{mismatch_mask:04x} "
                    "nonzero=0x{nonzero_mask:04x} "
                    "tag_match=0x{match_mask:04x}".format(**entry)
                )
            else:
                print(
                    "  [src p{source_phase}/write p{write_phase}/read p{read_phase}] "
                    "mismatch=0x{mismatch_mask:04x} "
                    "nonzero=0x{nonzero_mask:04x} "
                    "match=0x{match_mask:04x}".format(**entry)
                )
        hits = [
            (
                "slot {byte_slot}:low=0x{low_match_high_mask:x}_{match_mask:04x}/"
                "high=0x{high_match_high_mask:x}_{high_match_low_mask:04x}"
                if half_order_matrix_only
                else "slot {byte_slot}:0x{match_mask:04x}"
                if source_order_matrix_only
                else (
                    "src p{source_phase}/write p{write_phase}/read p{read_phase}:"
                    "0x{match_mask:04x}"
                )
            ).format(**entry)
            for entry in phase_matrix
            if (
                entry["match_mask"] != 0
                or entry.get("low_match_high_mask", 0) != 0
                or entry.get("high_match_low_mask", 0) != 0
                or entry.get("high_match_high_mask", 0) != 0
            )
        ]
        nonzero = [
            (
                "slot {byte_slot}:0x{nonzero_high_mask:x}_{nonzero_mask:04x}"
                if half_order_matrix_only
                else "slot {byte_slot}:0x{nonzero_mask:04x}"
                if source_order_matrix_only
                else (
                    "src p{source_phase}/write p{write_phase}/read p{read_phase}:"
                    "0x{nonzero_mask:04x}"
                )
            ).format(**entry)
            for entry in phase_matrix
            if entry["nonzero_mask"] != 0 or entry.get("nonzero_high_mask", 0) != 0
        ]
        label = (
            "dfii half-order tag matches"
            if half_order_matrix_only
            else "dfii source-order tag matches"
            if source_order_matrix_only
            else "dfii phase/source matrix matches"
        )
        print(
            "{label}: {matches}; nonzero combos: {nonzero}".format(
                label=label,
                matches=", ".join(hits) if hits else "none",
                nonzero=", ".join(nonzero) if nonzero else "none",
            )
        )
    elif 38 <= fields.get("version", 0) < 49 or fields.get("version", 0) >= 54:
        phase_masks = decoded["dfii_phasecmd_mismatch_masks"]
        formatted = " ".join(
            "w{write_phase}/r{read_phase}=0x{mismatch_mask:04x}".format(**entry)
            for entry in phase_masks
        )
        passing = [
            "w{write_phase}/r{read_phase}".format(**entry)
            for entry in phase_masks
            if entry["mismatch_mask"] == 0
        ]
        print(f"dfii command phase masks: {formatted}")
        print(
            "dfii command phase pass combos: {combos}; "
            "active=w{write}/r{read} sweep_index={index}".format(
                combos=", ".join(passing) if passing else "none",
                write=fields.get("dfii_write_command_phase", 0),
                read=fields.get("dfii_read_command_phase", 0),
                index=fields.get("dfii_phasecmd_index", 0),
            )
        )
    assoc_matrix = decoded["dfii_assoc_matrix"]
    if (
        not matrix_only
        and any(entry["nonzero_mask"] or entry["match_mask"] for entry in assoc_matrix)
    ):
        flags = fields.get("dfii_assoc_flags", 0)
        print(
            "dfii assoc matrix: active_source={source} final={final} "
            "sweep={sweep} addr_sweep={addr_sweep}".format(
                source=fields.get("dfii_assoc_index", 0),
                final=bool(flags & 0x1),
                sweep=bool(flags & 0x2),
                addr_sweep=bool(flags & 0x4),
            )
        )
        for entry in assoc_matrix:
            print(
                "  [src {source:02d}] sig=0x{signature:08x} "
                "nonzero=0x{nonzero_mask:04x} "
                "match=0x{match_mask:04x}".format(**entry)
            )
    addr_matrix = decoded["dfii_addr_matrix"]
    if fields.get("version", 0) >= 56 and any(
        entry["mismatch_mask"] or entry["nonzero_mask"] or entry["match_mask"]
        for entry in addr_matrix
    ):
        flags = fields.get("dfii_addr_flags", 0)
        print(
            "dfii address matrix: active_slot={slot} final={final} "
            "assoc_sweep={assoc_sweep} addr_sweep={addr_sweep}".format(
                slot=fields.get("dfii_addr_index", 0),
                final=bool(flags & 0x1),
                assoc_sweep=bool(flags & 0x2),
                addr_sweep=bool(flags & 0x4),
            )
        )
        for entry in addr_matrix:
            print(
                "  [slot {slot}] column=0x{column:04x} "
                "mismatch=0x{mismatch_mask:04x} "
                "nonzero=0x{nonzero_mask:04x} "
                "match=0x{match_mask:04x}".format(**entry)
            )
    if fields.get("version", 0) >= 52:
        lane_settings = ""
        current_best_suffix = ""
    elif fields.get("version", 0) >= 35:
        lane_settings = " ".join(
            "m{lane}=wb{write_bitslip}/rb{bitslip}/d{delay}".format(
                write_bitslip=decoded["lane_selected_write_bitslips"][
                    setting["lane"]
                ],
                **setting,
            )
            for setting in decoded["lane_selected_settings"]
        )
        current_best_suffix = "/wb{}".format(
            decoded["current_lane_best_write_bitslip"]
        )
    else:
        lane_settings = " ".join(
            "m{lane}->y{logical}=b{bitslip}/d{delay}".format(
                logical=decoded["lane_selected_logical_bytes"][setting["lane"]],
                **setting,
            )
            for setting in decoded["lane_selected_settings"]
        )
        current_best_suffix = "/y{}".format(
            fields.get("current_lane_best_logical_byte", 0)
        )
    lane_mismatches = " ".join(
        f"m{lane}={count}"
        for lane, count in enumerate(decoded["lane_best_mismatch_counts"])
    )
    dfii_lane_errors = " ".join(
        f"m{lane}={count}"
        for lane, count in enumerate(decoded["dfii_lane_error_counts"])
    )
    current_best = decoded["current_lane_best_setting"]
    if fields.get("version", 0) < 52:
        print(
            "lane selected: {settings}; lane_best_mismatches: {mismatches}; "
            "current_lane_best=b{bitslip}/d{delay}{suffix}".format(
                settings=lane_settings,
                mismatches=lane_mismatches,
                bitslip=current_best["bitslip"],
                delay=current_best["delay"],
                suffix=current_best_suffix,
            )
        )
    if fields.get("version", 0) < 49 or fields.get("version", 0) >= 54:
        print(f"dfii lane bit errors: {dfii_lane_errors}")
    if extended_status["write_data_target_seen"] or extended_status["write_command_target_seen"]:
        print(
            "write_targets data={data_done} commands={cmd_done} "
            "drain_done={drain_done} wdata_ready={wdata_ready}".format(
                data_done=extended_status["write_data_target_seen"],
                cmd_done=extended_status["write_command_target_seen"],
                drain_done=extended_status["write_drain_done"],
                wdata_ready=extended_status["wdata_ready"],
            )
        )
    samples = decoded["samples"]
    if samples:
        print("readback samples:")
        for sample in samples:
            print(
                "  [{index}] expected=0x{expected:016x} actual=0x{actual:016x} "
                "xor=0x{xor:016x}".format(**sample)
            )
    if (fields.get("version", 0) < 49 or fields.get("version", 0) >= 54) and (
        any(word["actual"] for word in decoded["dfii_words"]) or fields.get(
            "dfii_wb_ack_count", 0
        )
    ):
        print("dfii rddata words:")
        for word in decoded["dfii_words"]:
            print(
                "  [p{phase} w{word}] expected=0x{expected:08x} "
                "actual=0x{actual:08x} xor=0x{xor:08x} mismatch={mismatch}".format(
                    **word
                )
            )
    native_chunks = decoded.get("native_first_mismatch_chunks", [])
    if fields.get("version", 0) >= 49 and native_chunks:
        print(
            "native first mismatch chunk mask=0x{mask:03x}".format(
                mask=fields.get("first_chunk_mismatch_mask", 0) & 0x1FF
            )
        )
        for chunk in native_chunks:
            print(
                "  [chunk {chunk}] expected=0x{expected:016x} "
                "actual=0x{actual:016x} xor=0x{xor:016x} "
                "mismatch={mismatch}".format(**chunk)
            )
    byte_diag_samples = decoded["byte_diag_samples"]
    if byte_diag_samples:
        print("byte-enable diagnostic samples:")
        for sample in byte_diag_samples:
            print(
                "  [{index}] we=0x{write_enable:02x} "
                "expected=0x{expected_if_byte_enable_works:016x} "
                "actual=0x{actual:016x} xor=0x{xor:016x}".format(
                    **sample
                )
            )


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
                or decoded["decoded"]["extended_status"]["probe_done"]
                or decoded["decoded"]["state"] == "PROBE_DFII_DONE"
                or decoded["decoded"]["extended_status"]["probe_error"]
                or decoded["decoded"]["extended_status"]["probe_timeout"]
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
