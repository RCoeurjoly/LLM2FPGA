#!/usr/bin/env python3
"""Read the YPCB LiteDRAM init/bandwidth probe payload through XVC JTAG."""

from __future__ import annotations

import argparse
import json
import time

from read_jtag_debug_xvc import XvcClient, read_payload, unsigned_field


DEFAULT_BITS = 2400
MAGIC = 0x54364A44
SAMPLE_COUNT = 8
DFII_WORD_COUNT = 16

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

    state = fields.get("state", -1)
    status = fields.get("status", 0)
    decoded_status = decode_status(status)
    extended_status = decode_extended_status(fields.get("extended_status", 0))
    lane_selected_settings = decode_lane_settings(
        fields.get("lane_selected_settings", 0)
    )
    lane_best_mismatch_counts = [
        (fields.get("lane_best_mismatch_counts", 0) >> (lane * 8)) & 0xFF
        for lane in range(8)
    ]
    lane_selected_logical_bytes = [
        (fields.get("lane_selected_logical_bytes", 0) >> (lane * 4)) & 0x7
        for lane in range(8)
    ]
    current_lane_best_setting = decode_setting_byte(
        fields.get("current_lane_best_setting", 0)
    )
    samples = decode_samples(fields)
    dfii_words = decode_dfii_words(fields)
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
            "current_lane_best_setting": current_lane_best_setting,
            "samples": samples,
            "dfii_words": dfii_words,
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
            ),
        },
    }


def pattern_for_addr(addr: int) -> int:
    x = addr & 0x0FFF_FFFF
    high = (0xC0DE_0000 ^ x ^ ((x << 7) & 0xFFFF_FFFF)) & 0xFFFF_FFFF
    low = (0x1357_9BDF ^ (~x & 0xFFFF_FFFF) ^ ((x << 13) & 0xFFFF_FFFF)) & 0xFFFF_FFFF
    return (high << 32) | low


def dfii_pattern_word(index: int) -> int:
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
    return patterns[index & 0xF]


def decode_dfii_words(fields: dict[str, int]) -> list[dict[str, int]]:
    mismatch_mask = fields.get("dfii_word_mismatch_mask", 0)
    words = []
    for index in range(DFII_WORD_COUNT):
        actual = fields.get(f"dfii_rddata_{index}", 0)
        expected = dfii_pattern_word(index)
        words.append(
            {
                "index": index,
                "phase": index // 4,
                "word": index % 4,
                "expected": expected,
                "actual": actual,
                "xor": actual ^ expected,
                "mismatch": bool(mismatch_mask & (1 << index)),
            }
        )
    return words


def decode_samples(fields: dict[str, int]) -> list[dict[str, int]]:
    valid_count = min(fields.get("sample_valid_count", 0), SAMPLE_COUNT)
    samples = []
    for index in range(valid_count):
        actual = fields.get(f"sample_rdata_{index}", 0)
        expected = pattern_for_addr(index)
        samples.append(
            {
                "index": index,
                "expected": expected,
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


def decode_lane_settings(value: int) -> list[dict[str, int]]:
    settings = []
    for lane in range(8):
        byte = (value >> (lane * 8)) & 0xFF
        settings.append({"lane": lane, **decode_setting_byte(byte)})
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
    print(
        "dfii state={state} step={step} ack={ack} wait={wait} "
        "mismatch_mask=0x{mask:04x} last_read=0x{last:08x}".format(
            state=decoded["dfii_seq_state"],
            step=fields.get("dfii_step", 0),
            ack=fields.get("dfii_wb_ack_count", 0),
            wait=fields.get("dfii_wb_wait_count", 0),
            mask=fields.get("dfii_word_mismatch_mask", 0) & 0xFFFF,
            last=fields.get("dfii_last_read_data", 0),
        )
    )
    lane_settings = " ".join(
        "m{lane}->y{logical}=b{bitslip}/d{delay}".format(
            logical=decoded["lane_selected_logical_bytes"][setting["lane"]],
            **setting,
        )
        for setting in decoded["lane_selected_settings"]
    )
    lane_mismatches = " ".join(
        f"m{lane}={count}"
        for lane, count in enumerate(decoded["lane_best_mismatch_counts"])
    )
    current_best = decoded["current_lane_best_setting"]
    print(
        "lane selected: {settings}; lane_best_mismatches: {mismatches}; "
        "current_lane_best=y{logical}/b{bitslip}/d{delay}".format(
            settings=lane_settings,
            mismatches=lane_mismatches,
            logical=fields.get("current_lane_best_logical_byte", 0),
            bitslip=current_best["bitslip"],
            delay=current_best["delay"],
        )
    )
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
    if any(word["actual"] for word in decoded["dfii_words"]) or fields.get(
        "dfii_wb_ack_count", 0
    ):
        print("dfii rddata words:")
        for word in decoded["dfii_words"]:
            print(
                "  [p{phase} w{word}] expected=0x{expected:08x} "
                "actual=0x{actual:08x} xor=0x{xor:08x} mismatch={mismatch}".format(
                    **word
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
