#!/usr/bin/env python3
"""Read the Task 6 self-test debug payload through an XVC JTAG server."""

import argparse
import json
import socket
import struct
import time


DEFAULT_BITS = 2048
MAGIC = 0x54364A44
GEMV_SAMPLE_COUNT = 8
GEMV_SAMPLE_WIDTH = 128
GEMV_SAMPLE_OFFSET = 896
GEMV_EXPECTED_WEIGHT_OFFSET = 808
GEMV_EXPECTED_ACTIVATION_OFFSET = 1920
GEMV_TRANSFER_ACTIVATION_OFFSET = 1984
C_FC_TRANSFER_POST_GELU_OFFSET = 832
C_FC_POST_GELU_SAMPLE_COUNT = 8
C_FC_POST_GELU_SAMPLE_WIDTH = 144
C_FC_POST_GELU_SAMPLE_OFFSET = 896
C_FC_GEMV_SAMPLE_COUNT = 8
C_FC_GEMV_SAMPLE_WIDTH = 128
C_FC_GEMV_SAMPLE_OFFSET = 896
C_FC_GEMV_LANE1_FINAL_ACC = -8317
C_FC_GEMV_LANE1_EXPECTED = [
    {
        "mac_index": 0,
        "issue_index": 1,
        "weight_addr": 0,
        "activation": 7,
        "weight": -55,
        "product": -385,
        "acc_before": 0,
        "acc_after": -385,
    },
    {
        "mac_index": 1,
        "issue_index": 2,
        "weight_addr": 1,
        "activation": 89,
        "weight": -81,
        "product": -7209,
        "acc_before": -385,
        "acc_after": -7594,
    },
    {
        "mac_index": 2,
        "issue_index": 3,
        "weight_addr": 2,
        "activation": -105,
        "weight": -4,
        "product": 420,
        "acc_before": -7594,
        "acc_after": -7174,
    },
    {
        "mac_index": 3,
        "issue_index": 4,
        "weight_addr": 3,
        "activation": 46,
        "weight": 41,
        "product": 1886,
        "acc_before": -7174,
        "acc_after": -5288,
    },
    {
        "mac_index": 15,
        "issue_index": 16,
        "weight_addr": 15,
        "activation": -70,
        "weight": 39,
        "product": -2730,
        "acc_before": -4269,
        "acc_after": -6999,
    },
    {
        "mac_index": 31,
        "issue_index": 32,
        "weight_addr": 31,
        "activation": -14,
        "weight": -42,
        "product": 588,
        "acc_before": -7429,
        "acc_after": -6841,
    },
    {
        "mac_index": 47,
        "issue_index": 48,
        "weight_addr": 47,
        "activation": -62,
        "weight": 62,
        "product": -3844,
        "acc_before": -9482,
        "acc_after": -13326,
    },
    {
        "mac_index": 63,
        "issue_index": 63,
        "weight_addr": 63,
        "activation": 59,
        "weight": -18,
        "product": -1062,
        "acc_before": -7255,
        "acc_after": -8317,
    },
]
C_FC_EXPECTED = [
    {
        "index": 0,
        "acc": -18621,
        "scale": 567278,
        "bias": 0,
        "scaled": -630,
        "output": -34,
    },
    {
        "index": 1,
        "acc": -8317,
        "scale": 546793,
        "bias": 0,
        "scaled": -271,
        "output": -16,
    },
    {
        "index": 2,
        "acc": -20135,
        "scale": 645501,
        "bias": 0,
        "scaled": -775,
        "output": -40,
    },
    {
        "index": 3,
        "acc": 14033,
        "scale": 431115,
        "bias": 0,
        "scaled": 361,
        "output": 24,
    },
    {
        "index": 63,
        "acc": -12757,
        "scale": 587592,
        "bias": 0,
        "scaled": -447,
        "output": -25,
    },
    {
        "index": 127,
        "acc": 4855,
        "scale": 543700,
        "bias": 0,
        "scaled": 157,
        "output": 10,
    },
    {
        "index": 191,
        "acc": -17967,
        "scale": 760191,
        "bias": 0,
        "scaled": -814,
        "output": -42,
    },
    {
        "index": 255,
        "acc": 8057,
        "scale": 503531,
        "bias": 0,
        "scaled": 242,
        "output": 16,
    },
]

STATE_NAMES = {
    0: "SELFTEST_BOOT",
    1: "SELFTEST_LOAD_C_FC_ACTIVATION",
    2: "SELFTEST_LOAD_C_FC_WEIGHT",
    3: "SELFTEST_LOAD_C_FC_REQUANT",
    4: "SELFTEST_LOAD_C_PROJ_WEIGHT",
    5: "SELFTEST_LOAD_C_PROJ_REQUANT",
    6: "SELFTEST_LOAD_RESIDUAL",
    7: "SELFTEST_START",
    8: "SELFTEST_RUN",
    9: "SELFTEST_READ_SETUP",
    10: "SELFTEST_READ_CHECK",
    11: "SELFTEST_PASS",
    12: "SELFTEST_FAIL",
}

FAIL_REASON_NAMES = {
    0: "NONE",
    1: "TIMEOUT",
    2: "MISMATCH",
    3: "DEFAULT",
}

V4K_STATE_NAMES = {
    0: "SELFTEST_BOOT",
    1: "SELFTEST_CHECK_EMBED_TOKEN_SETUP",
    2: "SELFTEST_CHECK_EMBED_TOKEN_ACCUM",
    3: "SELFTEST_CHECK_EMBED_DONE",
    4: "SELFTEST_LOAD_C_FC_ACTIVATION",
    5: "SELFTEST_LOAD_C_FC_WEIGHT",
    6: "SELFTEST_LOAD_C_FC_REQUANT",
    7: "SELFTEST_LOAD_C_PROJ_WEIGHT",
    8: "SELFTEST_LOAD_C_PROJ_REQUANT",
    9: "SELFTEST_LOAD_RESIDUAL",
    10: "SELFTEST_LOAD_VOCAB_WEIGHT_SETUP",
    11: "SELFTEST_LOAD_VOCAB_WEIGHT_WRITE",
    12: "SELFTEST_START_RESIDUAL",
    13: "SELFTEST_RUN_RESIDUAL",
    14: "SELFTEST_LOAD_HEAD_ACTIVATION_SETUP",
    15: "SELFTEST_LOAD_HEAD_ACTIVATION_WRITE",
    16: "SELFTEST_START_OUTPUT_HEAD",
    17: "SELFTEST_RUN_OUTPUT_HEAD",
    18: "SELFTEST_PASS",
    19: "SELFTEST_FAIL",
}

V4K_FAIL_REASON_NAMES = {
    0: "NONE",
    1: "TIMEOUT",
    2: "RESIDUAL_MISMATCH",
    3: "TOP_INDEX",
    4: "TOP_ACC",
    5: "EMBEDDING_MISMATCH",
    7: "DEFAULT",
}

C_PROJ_STAGE_NAMES = {
    0: "OK_OR_DOWNSTREAM",
    1: "ACC",
    2: "SCALE",
    3: "BIAS",
    4: "PRODUCT",
    5: "SHIFT",
    6: "BIASED",
    7: "OUTPUT",
}

FIELDS = [
    ("magic", 0, 32, False),
    ("version", 32, 8, False),
    ("state", 40, 4, False),
    ("status", 44, 4, False),
    ("cycle_count", 48, 32, False),
    ("fail_reason", 80, 8, False),
    ("fail_index", 88, 8, False),
    ("fail_expected", 96, 8, True),
    ("fail_observed", 104, 8, True),
    ("fail_expected_c_proj", 112, 8, True),
    ("first_add_residual", 120, 8, True),
    ("first_add_c_proj", 128, 8, True),
    ("first_add_output", 136, 8, True),
    ("first_add_seen", 144, 8, False),
    ("c_proj_requant_stage", 152, 8, False),
    ("first_c_proj_requant_output", 160, 8, True),
    ("expected_c_proj_output0", 168, 8, True),
    ("expected_residual_add_output0", 176, 8, True),
    ("first_c_proj_requant_seen", 184, 8, False),
    ("expected_c_proj_acc0", 192, 32, True),
    ("expected_c_proj_scale0", 224, 32, True),
    ("expected_c_proj_bias0", 256, 32, True),
    ("expected_c_proj_product0", 288, 64, True),
    ("expected_c_proj_scaled0", 352, 64, True),
    ("expected_c_proj_biased0", 416, 64, True),
    ("first_c_proj_requant_acc", 480, 32, True),
    ("first_c_proj_requant_scale", 512, 32, True),
    ("first_c_proj_requant_bias", 544, 32, True),
    ("first_c_proj_requant_product", 576, 64, True),
    ("first_c_proj_requant_scaled", 640, 64, True),
    ("first_c_proj_requant_biased", 704, 64, True),
    ("debug_sample_count", 768, 8, False),
    ("c_proj_gemv_lane0_sample_count", 768, 8, False),
    ("c_proj_gemv_lane0_final_acc", 776, 32, True),
    ("c_fc_gemv_lane1_sample_count", 768, 8, False),
    ("c_fc_gemv_lane1_final_acc", 776, 32, True),
    ("c_fc_transfer_post_gelu_samples", 832, 64, False),
    ("second_add_residual", 768, 8, True),
    ("second_add_c_proj", 776, 8, True),
    ("second_add_output", 784, 8, True),
    ("expected_residual1", 792, 8, True),
    ("expected_c_proj_output1", 800, 8, True),
    ("expected_residual_add_output1", 808, 8, True),
    ("second_add_seen", 816, 8, False),
    ("second_c_proj_requant_seen", 824, 8, False),
    ("expected_c_proj_acc1", 832, 32, True),
    ("expected_c_proj_scale1", 864, 32, True),
    ("expected_c_proj_bias1", 896, 32, True),
    ("second_c_proj_requant_acc", 928, 32, True),
    ("second_c_proj_requant_scale", 960, 32, True),
    ("second_c_proj_requant_bias", 992, 32, True),
    ("second_c_proj_requant_product", 1024, 64, True),
    ("second_c_proj_requant_scaled", 1088, 64, True),
    ("second_c_proj_requant_biased", 1152, 64, True),
    ("second_c_proj_requant_output", 1216, 8, True),
    ("c_proj_gemv_lane0_expected_weights", 808, 64, False),
    ("c_proj_gemv_expected_activation_samples", 1920, 64, False),
    ("c_proj_transfer_post_gelu_samples", 1984, 64, False),
]

V4K_FIELDS = [
    ("magic", 0, 32, False),
    ("version", 32, 8, False),
    ("state", 40, 8, False),
    ("status", 48, 8, False),
    ("cycle_count", 56, 32, False),
    ("fail_reason", 88, 8, False),
    ("fail_index", 96, 8, False),
    ("fail_expected_residual", 104, 8, True),
    ("fail_observed_residual", 112, 8, True),
    ("fail_observed_top_index", 120, 16, False),
    ("expected_top_index", 136, 16, False),
    ("fail_observed_top_acc", 152, 32, True),
    ("expected_top_acc", 184, 32, True),
    ("live_top_index", 216, 16, False),
    ("live_top_acc_low24", 232, 24, True),
    ("vocab_load_checksum", 256, 32, False),
    ("expected_vocab_weight_checksum", 288, 32, False),
    ("vocab_first_word", 320, 32, False),
    ("expected_vocab_first_word", 352, 32, False),
    ("vocab_last_word", 384, 32, False),
    ("expected_vocab_last_word", 416, 32, False),
    ("head_activation_checksum", 448, 32, False),
    ("expected_head_activation_checksum", 480, 32, False),
    ("embedding_token_checksum", 512, 32, False),
    ("expected_embedding_token_checksum", 544, 32, False),
    ("embedding_position_checksum", 576, 32, False),
    ("expected_embedding_position_checksum", 608, 32, False),
    ("embedding_combined_checksum", 640, 32, False),
    ("expected_embedding_combined_checksum", 672, 32, False),
    ("embedding_token_id", 704, 16, False),
    ("embedding_position_id", 720, 16, False),
]


def pack_bits(bits):
    data = bytearray((len(bits) + 7) // 8)
    for index, bit in enumerate(bits):
        if bit:
            data[index // 8] |= 1 << (index % 8)
    return bytes(data)


def unpack_bits(data, bit_count):
    bits = []
    for index in range(bit_count):
        bits.append((data[index // 8] >> (index % 8)) & 1)
    return bits


def bits_to_int(bits):
    value = 0
    for index, bit in enumerate(bits):
        value |= int(bit) << index
    return value


def unsigned_field(payload, offset, width):
    return (payload >> offset) & ((1 << width) - 1)


def signed_field(payload, offset, width):
    value = unsigned_field(payload, offset, width)
    sign_bit = 1 << (width - 1)
    if value & sign_bit:
        value -= 1 << width
    return value


def decode_gemv_samples(payload, bit_count):
    samples = []
    for sample_index in range(GEMV_SAMPLE_COUNT):
        offset = GEMV_SAMPLE_OFFSET + sample_index * GEMV_SAMPLE_WIDTH
        if offset + GEMV_SAMPLE_WIDTH > bit_count:
            break
        expected_weight = signed_field(
            payload, GEMV_EXPECTED_WEIGHT_OFFSET + sample_index * 8, 8
        )
        activation = signed_field(payload, offset + 32, 8)
        sample = {
            "sample_index": sample_index,
            "mac_index": unsigned_field(payload, offset + 0, 8),
            "issue_index": unsigned_field(payload, offset + 8, 8),
            "weight_addr": unsigned_field(payload, offset + 16, 16),
            "activation": activation,
            "weight_lane0": signed_field(payload, offset + 40, 8),
            "expected_weight_lane0": expected_weight,
            "weight_matches_expected": (
                signed_field(payload, offset + 40, 8) == expected_weight
            ),
            "product": signed_field(payload, offset + 48, 16),
            "acc_before": signed_field(payload, offset + 64, 32),
            "acc_after": signed_field(payload, offset + 96, 32),
        }
        if GEMV_TRANSFER_ACTIVATION_OFFSET + (sample_index + 1) * 8 <= bit_count:
            expected_activation = signed_field(
                payload, GEMV_EXPECTED_ACTIVATION_OFFSET + sample_index * 8, 8
            )
            transfer_activation = signed_field(
                payload, GEMV_TRANSFER_ACTIVATION_OFFSET + sample_index * 8, 8
            )
            sample.update(
                {
                    "expected_activation": expected_activation,
                    "transfer_activation": transfer_activation,
                    "activation_matches_expected": (
                        activation == expected_activation
                    ),
                    "transfer_matches_expected": (
                        transfer_activation == expected_activation
                    ),
                    "activation_matches_transfer": (
                        activation == transfer_activation
                    ),
                }
            )
        samples.append(sample)
    return samples


def decode_c_fc_post_gelu_samples(payload, bit_count):
    samples = []
    for sample_index in range(C_FC_POST_GELU_SAMPLE_COUNT):
        offset = C_FC_POST_GELU_SAMPLE_OFFSET + (
            sample_index * C_FC_POST_GELU_SAMPLE_WIDTH
        )
        if offset + C_FC_POST_GELU_SAMPLE_WIDTH > bit_count:
            break
        expected = C_FC_EXPECTED[sample_index]
        sample = {
            "sample_index": sample_index,
            "index": unsigned_field(payload, offset + 0, 8),
            "acc": signed_field(payload, offset + 8, 32),
            "scale": signed_field(payload, offset + 40, 32),
            "bias": signed_field(payload, offset + 72, 32),
            "scaled": signed_field(payload, offset + 104, 32),
            "output": signed_field(payload, offset + 136, 8),
            "expected": expected,
        }
        for key in ("index", "acc", "scale", "bias", "scaled", "output"):
            sample[f"{key}_matches_expected"] = sample[key] == expected[key]
        samples.append(sample)
    return samples


def decode_c_fc_transfer_post_gelu_samples(payload, bit_count):
    samples = []
    for sample_index in range(C_FC_POST_GELU_SAMPLE_COUNT):
        offset = C_FC_TRANSFER_POST_GELU_OFFSET + sample_index * 8
        if offset + 8 > bit_count:
            break
        expected = C_FC_EXPECTED[sample_index]
        value = signed_field(payload, offset, 8)
        samples.append(
            {
                "sample_index": sample_index,
                "index": expected["index"],
                "transfer_output": value,
                "expected_output": expected["output"],
                "transfer_matches_expected": value == expected["output"],
            }
        )
    return samples


def decode_c_fc_gemv_lane1_samples(payload, bit_count):
    samples = []
    for sample_index in range(C_FC_GEMV_SAMPLE_COUNT):
        offset = C_FC_GEMV_SAMPLE_OFFSET + sample_index * C_FC_GEMV_SAMPLE_WIDTH
        if offset + C_FC_GEMV_SAMPLE_WIDTH > bit_count:
            break
        expected = C_FC_GEMV_LANE1_EXPECTED[sample_index]
        sample = {
            "sample_index": sample_index,
            "mac_index": unsigned_field(payload, offset + 0, 8),
            "issue_index": unsigned_field(payload, offset + 8, 8),
            "weight_addr": unsigned_field(payload, offset + 16, 16),
            "activation": signed_field(payload, offset + 32, 8),
            "weight_lane1": signed_field(payload, offset + 40, 8),
            "product": signed_field(payload, offset + 48, 16),
            "acc_before": signed_field(payload, offset + 64, 32),
            "acc_after": signed_field(payload, offset + 96, 32),
            "expected": expected,
        }
        for key in (
            "mac_index",
            "issue_index",
            "weight_addr",
            "activation",
            "product",
            "acc_before",
            "acc_after",
        ):
            sample[f"{key}_matches_expected"] = sample[key] == expected[key]
        sample["weight_matches_expected"] = (
            sample["weight_lane1"] == expected["weight"]
        )
        samples.append(sample)
    return samples


class XvcClient:
    def __init__(self, host, port, timeout):
        self.sock = socket.create_connection((host, port), timeout=timeout)
        self.sock.settimeout(timeout)

    def close(self):
        self.sock.close()

    def read_exact(self, byte_count):
        chunks = []
        remaining = byte_count
        while remaining:
            chunk = self.sock.recv(remaining)
            if not chunk:
                raise RuntimeError("XVC server closed the connection")
            chunks.append(chunk)
            remaining -= len(chunk)
        return b"".join(chunks)

    def read_until_newline(self):
        chunks = []
        while True:
            chunk = self.sock.recv(1)
            if not chunk:
                raise RuntimeError("XVC server closed the connection")
            chunks.append(chunk)
            if chunk == b"\n":
                return b"".join(chunks)

    def getinfo(self):
        self.sock.sendall(b"getinfo:")
        return self.read_until_newline().decode("ascii", errors="replace").strip()

    def settck(self, period_ns):
        self.sock.sendall(b"settck:" + struct.pack("<I", period_ns))
        return struct.unpack("<I", self.read_exact(4))[0]

    def shift(self, tms_bits, tdi_bits):
        if len(tms_bits) != len(tdi_bits):
            raise ValueError("TMS and TDI vectors must have the same length")
        bit_count = len(tms_bits)
        byte_count = (bit_count + 7) // 8
        command = (
            b"shift:"
            + struct.pack("<I", bit_count)
            + pack_bits(tms_bits)
            + pack_bits(tdi_bits)
        )
        self.sock.sendall(command)
        return unpack_bits(self.read_exact(byte_count), bit_count)


def clock_tms(client, tms_bits):
    if tms_bits:
        client.shift(tms_bits, [0] * len(tms_bits))


def reset_tap(client):
    clock_tms(client, [1, 1, 1, 1, 1, 1, 0])


def shift_ir(client, instruction, ir_len):
    clock_tms(client, [1, 1, 0, 0])
    tdi_bits = [(instruction >> bit) & 1 for bit in range(ir_len)]
    tms_bits = [0] * ir_len
    tms_bits[-1] = 1
    client.shift(tms_bits, tdi_bits)
    clock_tms(client, [1, 0])


def shift_dr_read(client, bit_count):
    clock_tms(client, [1, 0, 0])
    tms_bits = [0] * bit_count
    tms_bits[-1] = 1
    tdo_bits = client.shift(tms_bits, [0] * bit_count)
    clock_tms(client, [1, 0])
    return bits_to_int(tdo_bits)


def read_payload(client, ir_len, user_ir, bit_count):
    reset_tap(client)
    shift_ir(client, user_ir, ir_len)
    return shift_dr_read(client, bit_count)


def decode_payload(payload, bit_count):
    version = unsigned_field(payload, 32, 8) if bit_count >= 40 else 0
    if version in {10, 11, 12, 13}:
        fields = {}
        for name, offset, width, signed in V4K_FIELDS:
            if offset + width <= bit_count:
                if signed:
                    fields[name] = signed_field(payload, offset, width)
                else:
                    fields[name] = unsigned_field(payload, offset, width)

        state = fields.get("state", -1)
        status = fields.get("status", 0)
        fail_reason = fields.get("fail_reason", -1)
        return {
            "raw_hex": f"0x{payload:0{(bit_count + 3) // 4}x}",
            "magic_ok": fields.get("magic") == MAGIC,
            "fields": fields,
            "c_proj_gemv_lane0_samples": [],
            "c_fc_post_gelu_samples": [],
            "c_fc_transfer_post_gelu_samples": [],
            "c_fc_gemv_lane1_samples": [],
            "decoded": {
                "state": V4K_STATE_NAMES.get(state, f"UNKNOWN_{state}"),
                "status": {
                    "pass": bool(status & 0x1),
                    "fail": bool(status & 0x2),
                    "residual_done": bool(status & 0x4),
                    "output_head_done": bool(status & 0x8),
                },
                "fail_reason": V4K_FAIL_REASON_NAMES.get(
                    fail_reason, f"UNKNOWN_{fail_reason}"
                ),
                "c_proj_requant_stage": "N/A",
            },
        }

    fields = {}
    for name, offset, width, signed in FIELDS:
        if offset + width <= bit_count:
            if signed:
                fields[name] = signed_field(payload, offset, width)
            else:
                fields[name] = unsigned_field(payload, offset, width)

    state = fields.get("state", -1)
    status = fields.get("status", 0)
    fail_reason = fields.get("fail_reason", -1)
    stage = fields.get("c_proj_requant_stage", -1)
    version = fields.get("version", 0)
    c_proj_samples = []
    c_fc_samples = []
    c_fc_gemv_samples = []
    c_fc_transfer_samples = []
    if version == 9:
        c_proj_samples = decode_gemv_samples(payload, bit_count)
    elif version == 7:
        c_fc_samples = decode_c_fc_post_gelu_samples(payload, bit_count)
        c_fc_transfer_samples = decode_c_fc_transfer_post_gelu_samples(
            payload, bit_count
        )
    elif version >= 5:
        c_fc_gemv_samples = decode_c_fc_gemv_lane1_samples(payload, bit_count)
    elif version >= 4:
        c_fc_samples = decode_c_fc_post_gelu_samples(payload, bit_count)
    else:
        c_proj_samples = decode_gemv_samples(payload, bit_count)

    return {
        "raw_hex": f"0x{payload:0{(bit_count + 3) // 4}x}",
        "magic_ok": fields.get("magic") == MAGIC,
        "fields": fields,
        "c_proj_gemv_lane0_samples": c_proj_samples,
        "c_fc_post_gelu_samples": c_fc_samples,
        "c_fc_transfer_post_gelu_samples": c_fc_transfer_samples,
        "c_fc_gemv_lane1_samples": c_fc_gemv_samples,
        "decoded": {
            "state": STATE_NAMES.get(state, f"UNKNOWN_{state}"),
            "status": {
                "pass": bool(status & 0x1),
                "fail": bool(status & 0x2),
                "first_add_seen": bool(status & 0x4),
                "first_c_proj_requant_seen": bool(status & 0x8),
            },
            "fail_reason": FAIL_REASON_NAMES.get(
                fail_reason, f"UNKNOWN_{fail_reason}"
            ),
            "c_proj_requant_stage": C_PROJ_STAGE_NAMES.get(
                stage, f"UNKNOWN_{stage}"
            ),
        },
    }


def print_summary(decoded):
    fields = decoded["fields"]
    names = decoded["decoded"]
    if fields.get("version") in {10, 11, 12, 13}:
        print(
            "summary: "
            f"magic_ok={decoded['magic_ok']} "
            f"state={names['state']} "
            f"status={names['status']} "
            f"fail_reason={names['fail_reason']}"
        )
        print(
            "residual: "
            f"index {fields.get('fail_index')} "
            f"expected {fields.get('fail_expected_residual')} "
            f"observed {fields.get('fail_observed_residual')}"
        )
        print(
            "output_head: "
            f"observed_top_index {fields.get('fail_observed_top_index')} "
            f"expected_top_index {fields.get('expected_top_index')} "
            f"observed_top_acc {fields.get('fail_observed_top_acc')} "
            f"expected_top_acc {fields.get('expected_top_acc')} "
            f"live_top_index {fields.get('live_top_index')} "
            f"live_top_acc_low24 {fields.get('live_top_acc_low24')}"
        )
        if fields.get("version", 0) >= 11:
            print(
                "vocab_load: "
                f"checksum 0x{fields.get('vocab_load_checksum', 0):08x} "
                f"expected 0x{fields.get('expected_vocab_weight_checksum', 0):08x} "
                f"first 0x{fields.get('vocab_first_word', 0):08x} "
                f"expected_first 0x{fields.get('expected_vocab_first_word', 0):08x} "
                f"last 0x{fields.get('vocab_last_word', 0):08x} "
                f"expected_last 0x{fields.get('expected_vocab_last_word', 0):08x}"
            )
            print(
                "head_activation: "
                f"checksum 0x{fields.get('head_activation_checksum', 0):08x} "
                f"expected 0x{fields.get('expected_head_activation_checksum', 0):08x}"
            )
        if fields.get("version", 0) >= 13:
            print(
                "embedding: "
                f"token_id {fields.get('embedding_token_id')} "
                f"position_id {fields.get('embedding_position_id')} "
                f"token_checksum 0x{fields.get('embedding_token_checksum', 0):08x} "
                f"expected 0x{fields.get('expected_embedding_token_checksum', 0):08x} "
                f"position_checksum 0x{fields.get('embedding_position_checksum', 0):08x} "
                f"expected 0x{fields.get('expected_embedding_position_checksum', 0):08x} "
                f"combined_checksum 0x{fields.get('embedding_combined_checksum', 0):08x} "
                f"expected 0x{fields.get('expected_embedding_combined_checksum', 0):08x}"
            )
        return

    print(
        "summary: "
        f"magic_ok={decoded['magic_ok']} "
        f"state={names['state']} "
        f"status={names['status']} "
        f"fail_reason={names['fail_reason']} "
        f"stage={names['c_proj_requant_stage']}"
    )
    if fields.get("version", 0) == 9:
        print(
            "fail: "
            f"index {fields.get('fail_index')} "
            f"expected {fields.get('fail_expected')} "
            f"observed {fields.get('fail_observed')} "
            f"expected_c_proj {fields.get('fail_expected_c_proj')}"
        )
        print(
            "c_proj_gemv[1/lane1]: "
            f"final_acc {fields.get('c_proj_gemv_lane0_final_acc')} "
            f"expected {fields.get('expected_c_proj_acc0')}; "
            f"samples {fields.get('c_proj_gemv_lane0_sample_count')}"
        )
        for sample in decoded.get("c_proj_gemv_lane0_samples", []):
            print(
                "  sample "
                f"{sample['sample_index']}: "
                f"mac {sample['mac_index']} "
                f"issue {sample['issue_index']} "
                f"waddr {sample['weight_addr']} "
                f"act {sample['activation']} "
                f"exp_act {sample.get('expected_activation')} "
                f"xfer {sample.get('transfer_activation')} "
                f"w {sample['weight_lane0']} "
                f"exp_w {sample['expected_weight_lane0']} "
                f"w_ok {sample['weight_matches_expected']} "
                f"prod {sample['product']} "
                f"acc {sample['acc_before']}->{sample['acc_after']}"
            )
        return
    print(
        "c_proj[0]: "
        f"acc {fields.get('first_c_proj_requant_acc')} "
        f"expected {fields.get('expected_c_proj_acc0')}; "
        f"scale {fields.get('first_c_proj_requant_scale')} "
        f"expected {fields.get('expected_c_proj_scale0')}; "
        f"bias {fields.get('first_c_proj_requant_bias')} "
        f"expected {fields.get('expected_c_proj_bias0')}; "
        f"product {fields.get('first_c_proj_requant_product')} "
        f"expected {fields.get('expected_c_proj_product0')}; "
        f"scaled {fields.get('first_c_proj_requant_scaled')} "
        f"expected {fields.get('expected_c_proj_scaled0')}; "
        f"biased {fields.get('first_c_proj_requant_biased')} "
        f"expected {fields.get('expected_c_proj_biased0')}; "
        f"output {fields.get('first_c_proj_requant_output')} "
        f"expected {fields.get('expected_c_proj_output0')}"
    )
    print(
        "residual_add[0]: "
        f"residual {fields.get('first_add_residual')} "
        f"c_proj {fields.get('first_add_c_proj')} "
        f"output {fields.get('first_add_output')} "
        f"expected {fields.get('expected_residual_add_output0')}"
    )
    print(
        "fail: "
        f"index {fields.get('fail_index')} "
        f"expected {fields.get('fail_expected')} "
        f"observed {fields.get('fail_observed')} "
        f"expected_c_proj {fields.get('fail_expected_c_proj')}"
    )
    if fields.get("version", 0) == 8:
        print(
            "c_proj[1]: "
            f"acc {fields.get('second_c_proj_requant_acc')} "
            f"expected {fields.get('expected_c_proj_acc1')}; "
            f"scale {fields.get('second_c_proj_requant_scale')} "
            f"expected {fields.get('expected_c_proj_scale1')}; "
            f"bias {fields.get('second_c_proj_requant_bias')} "
            f"expected {fields.get('expected_c_proj_bias1')}; "
            f"product {fields.get('second_c_proj_requant_product')}; "
            f"scaled {fields.get('second_c_proj_requant_scaled')}; "
            f"biased {fields.get('second_c_proj_requant_biased')}; "
            f"output {fields.get('second_c_proj_requant_output')} "
            f"expected {fields.get('expected_c_proj_output1')}; "
            f"seen {bool(fields.get('second_c_proj_requant_seen'))}"
        )
        print(
            "residual_add[1]: "
            f"residual {fields.get('second_add_residual')} "
            f"expected {fields.get('expected_residual1')}; "
            f"c_proj {fields.get('second_add_c_proj')} "
            f"expected {fields.get('expected_c_proj_output1')}; "
            f"output {fields.get('second_add_output')} "
            f"expected {fields.get('expected_residual_add_output1')}; "
            f"seen {bool(fields.get('second_add_seen'))}"
        )
    elif fields.get("version", 0) == 7:
        print(
            "c_fc_gemv[hidden1/lane1]: "
            f"final_acc {fields.get('c_fc_gemv_lane1_final_acc')} "
            f"expected {C_FC_GEMV_LANE1_FINAL_ACC}"
        )
        print(f"c_fc_post_gelu: samples {fields.get('debug_sample_count')}")
        transfer_samples = {
            sample["sample_index"]: sample
            for sample in decoded.get("c_fc_transfer_post_gelu_samples", [])
        }
        for sample in decoded.get("c_fc_post_gelu_samples", []):
            expected = sample["expected"]
            transfer = transfer_samples.get(sample["sample_index"], {})
            transfer_output = transfer.get("transfer_output")
            print(
                "  sample "
                f"{sample['sample_index']}: "
                f"idx {sample['index']} exp_idx {expected['index']} "
                f"acc {sample['acc']} exp {expected['acc']} "
                f"scale {sample['scale']} exp {expected['scale']} "
                f"bias {sample['bias']} exp {expected['bias']} "
                f"scaled {sample['scaled']} exp {expected['scaled']} "
                f"output {sample['output']} exp {expected['output']} "
                f"transfer {transfer_output} "
                f"matches acc={sample['acc_matches_expected']} "
                f"scale={sample['scale_matches_expected']} "
                f"bias={sample['bias_matches_expected']} "
                f"scaled={sample['scaled_matches_expected']} "
                f"output={sample['output_matches_expected']} "
                f"transfer={transfer.get('transfer_matches_expected')}"
            )
    elif fields.get("version", 0) >= 5:
        print(
            "c_fc_gemv[hidden1/lane1]: "
            f"final_acc {fields.get('c_fc_gemv_lane1_final_acc')} "
            f"expected {C_FC_GEMV_LANE1_FINAL_ACC}; "
            f"samples {fields.get('c_fc_gemv_lane1_sample_count')}"
        )
        for sample in decoded.get("c_fc_gemv_lane1_samples", []):
            expected = sample["expected"]
            print(
                "  sample "
                f"{sample['sample_index']}: "
                f"mac {sample['mac_index']} exp {expected['mac_index']} "
                f"issue {sample['issue_index']} exp {expected['issue_index']} "
                f"waddr {sample['weight_addr']} exp {expected['weight_addr']} "
                f"act {sample['activation']} exp {expected['activation']} "
                f"w {sample['weight_lane1']} exp {expected['weight']} "
                f"prod {sample['product']} exp {expected['product']} "
                f"acc {sample['acc_before']}->{sample['acc_after']} "
                f"exp {expected['acc_before']}->{expected['acc_after']} "
                f"matches act={sample['activation_matches_expected']} "
                f"w={sample['weight_matches_expected']} "
                f"prod={sample['product_matches_expected']} "
                f"acc_after={sample['acc_after_matches_expected']}"
            )
    elif fields.get("version", 0) >= 4:
        print(f"c_fc_post_gelu: samples {fields.get('debug_sample_count')}")
        for sample in decoded.get("c_fc_post_gelu_samples", []):
            expected = sample["expected"]
            print(
                "  sample "
                f"{sample['sample_index']}: "
                f"idx {sample['index']} exp_idx {expected['index']} "
                f"acc {sample['acc']} exp {expected['acc']} "
                f"scale {sample['scale']} exp {expected['scale']} "
                f"bias {sample['bias']} exp {expected['bias']} "
                f"scaled {sample['scaled']} exp {expected['scaled']} "
                f"output {sample['output']} exp {expected['output']} "
                f"matches acc={sample['acc_matches_expected']} "
                f"scale={sample['scale_matches_expected']} "
                f"bias={sample['bias_matches_expected']} "
                f"scaled={sample['scaled_matches_expected']} "
                f"output={sample['output_matches_expected']}"
            )
    else:
        print(
            "c_proj_gemv[0]: "
            f"final_acc {fields.get('c_proj_gemv_lane0_final_acc')} "
            f"expected {fields.get('expected_c_proj_acc0')}; "
            f"samples {fields.get('c_proj_gemv_lane0_sample_count')}"
        )
        for sample in decoded.get("c_proj_gemv_lane0_samples", []):
            print(
                "  sample "
                f"{sample['sample_index']}: "
                f"mac {sample['mac_index']} "
                f"issue {sample['issue_index']} "
                f"waddr {sample['weight_addr']} "
                f"act {sample['activation']} "
                f"exp_act {sample.get('expected_activation')} "
                f"xfer {sample.get('transfer_activation')} "
                f"w {sample['weight_lane0']} "
                f"exp_w {sample['expected_weight_lane0']} "
                f"w_ok {sample['weight_matches_expected']} "
                f"prod {sample['product']} "
                f"acc {sample['acc_before']}->{sample['acc_after']}"
            )


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=3721)
    parser.add_argument("--timeout", type=float, default=5.0)
    parser.add_argument("--tck-ns", type=int, default=100)
    parser.add_argument("--bits", type=int, default=DEFAULT_BITS)
    parser.add_argument("--ir-len", type=int, default=6)
    parser.add_argument("--user-ir", type=lambda value: int(value, 0), default=0x02)
    parser.add_argument("--poll", action="store_true")
    parser.add_argument("--poll-count", type=int, default=50)
    parser.add_argument("--poll-interval", type=float, default=0.1)
    parser.add_argument("--json-only", action="store_true")
    return parser.parse_args()


def main():
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
            if not args.poll or status["pass"] or status["fail"]:
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
