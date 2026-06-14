#!/usr/bin/env python3
"""Unit checks for the Task 6 M2 full-block PCIe gate contract helpers."""

from __future__ import annotations

import json
import os
from pathlib import Path
import tempfile

from task6_pcie_m2_full_block_gate import (
    CONTRACT,
    classify_vector_readback_transform,
    compare_done_stage_checksums,
    compute_path_for_expected,
    contract_for_expected,
    decode_debug,
    decode_done_stage_checksums,
    decode_status,
    expected_provenance,
    is_token_live_mode,
    parse_embedding_tb_data_sv,
    parse_expected_json,
    parse_expected_tb_data_sv,
    pcie7x_inverse_rotate64_bar_vector_words,
    pcie7x_rotate64_compensate_bar_vector_words,
    rd32_window,
    sample_registers,
    select_host_vectors,
    validate_expected,
    vector_bytes_from_words,
    vector_words_from_bytes,
)


def write_json(payload: dict[str, object]) -> Path:
    fd, raw_path = tempfile.mkstemp(prefix="task6-m2-full-block-expected-", suffix=".json")
    os.close(fd)
    path = Path(raw_path)
    path.write_text(json.dumps(payload), encoding="utf-8")
    return path


def write_text(text: str) -> Path:
    fd, raw_path = tempfile.mkstemp(prefix="task6-m2-full-block-expected-", suffix=".sv")
    os.close(fd)
    path = Path(raw_path)
    path.write_text(text, encoding="utf-8")
    return path


def sv_i8(value: int) -> str:
    return f"-8'sd{abs(value)}" if value < 0 else f"8'sd{value}"


def test_decode_status_magic_bit16() -> None:
    decoded = decode_status(0x4D32_0059)
    assert decoded["state_name"] == "DONE"
    assert decoded["done"]
    assert decoded["output_valid"]
    assert decoded["ready"]
    assert not decoded["busy"]
    assert not decoded["error"]
    assert decoded["magic"] == 0x4D32
    assert decoded["schema_consistent"]


def test_decode_status_rejects_old_magic_bit14_interpretation() -> None:
    decoded = decode_status(0x134C_8039)
    assert decoded["magic"] != 0x4D32
    assert not decoded["schema_consistent"]


def test_decode_debug_context_ln_uses_context_namespace() -> None:
    decoded = decode_debug(0xC142_ECBC, 0x000D_FD68, 0xED95_EB8B)
    assert decoded["stage"] == "0xc1"
    assert decoded["meaning"] == "live-context context substage mismatch"
    assert decoded["context_meaning"] == "LN output mismatch"
    assert decoded["ln_index"] == 16
    assert decoded["expected_q"] == "0xbb"
    assert decoded["observed_q"] == "0xbc"
    assert decoded["ln_intermediate_signed"] == {
        "mean_q12": 13,
        "centered_q12": -664,
        "norm_q12": -4715,
        "affine_q12": -5237,
    }


def test_decode_debug_raw_stage_one_remains_embedding_namespace() -> None:
    decoded = decode_debug(0x0142_ECBC, 0x000D_FD68, 0xED95_EB8B)
    assert decoded["stage"] == "0x01"
    assert decoded["meaning"] == "embedding token-id mismatch"
    assert "context_meaning" not in decoded


def test_done_stage_checksum_decode_finds_first_mismatch() -> None:
    observed = decode_done_stage_checksums(0x50F9_7AF2, 0x1ACC_F8DB)
    assert observed == {
        "block_input_checksum_low16": "0x50f9",
        "context_checksum_low16": "0x7af2",
        "attn_out_checksum_low8": "0x1a",
        "attn_residual_checksum_low8": "0xcc",
        "ln2_checksum_low8": "0xf8",
        "c_proj_checksum_low8": "0xdb",
    }
    comparison = compare_done_stage_checksums(
        0x50F9_7AF2,
        0x1ACC_F8DB,
        0x50F9_32E3,
        0x49FB_3A5B,
    )
    assert comparison["matches"]["block_input_checksum_low16"]
    assert not comparison["matches"]["context_checksum_low16"]
    assert comparison["first_mismatch"] == "context_checksum_low16"
    assert not comparison["all_match"]


def test_parse_expected_json_requires_first_64_output() -> None:
    payload = {
        "expected_checksum": 0x12345678,
        "expected_sample0": 0x01020304,
        "expected_sample1": 0x11121314,
        "output_count": 4864,
        "first_64_output_hex": bytes(range(64)).hex(),
    }
    path = write_json(payload)
    expected = parse_expected_json(path)
    validate_expected(expected, path)
    assert expected["checksum"] == 0x12345678
    assert expected["sample0"] == 0x01020304
    assert expected["sample1"] == 0x11121314
    assert expected["output_count"] == 4864
    assert expected["first_64_output"] == bytes(range(64))


def test_parse_expected_tb_data_sv_first_token_final_vector() -> None:
    final_assignments = "\n".join(
        f"  mlp_final_expected_q[{index}] = {sv_i8(index if index < 64 else 0)};"
        for index in range(64)
    )
    block_input_assignments = "\n".join(
        f"  out_proj_block_input_q[{index}] = {sv_i8(63 - index)};"
        for index in range(64)
    )
    context_assignments = "\n".join(
        f"  out_proj_context_q[{index}] = {sv_i8(index - 32)};"
        for index in range(64)
    )
    path = write_text(
        "\n".join(
            [
                "localparam logic [31:0] MLP_FINAL_EXPECTED_CHECKSUM = 32'h000365ee;",
                "localparam logic [31:0] MLP_FINAL_EXPECTED_SAMPLE0 = 32'h03020100;",
                "localparam logic [31:0] MLP_FINAL_EXPECTED_SAMPLE1 = 32'h07060504;",
                "localparam int M2_FULL_BLOCK_TOKEN_INDEX = 5;",
                final_assignments,
                block_input_assignments,
                context_assignments,
                "",
            ]
        )
    )
    expected = parse_expected_tb_data_sv(path)
    validate_expected(expected, path)
    assert expected["checksum"] == 0x000365EE
    assert expected["sample0"] == 0x03020100
    assert expected["sample1"] == 0x07060504
    assert expected["output_count"] == 64
    assert expected["first_64_output"] == bytes(range(64))
    assert expected["fixture_block_input"] == bytes(range(63, -1, -1))
    assert expected["fixture_context"] == bytes((index - 32) & 0xFF for index in range(64))
    assert expected["token_index"] == 5
    assert expected["provenance_mode"] == 0x2000


def test_parse_embedding_tb_data_sv_token_input_vector() -> None:
    token_assignments = "\n".join(
        f"  embed_block_expected_token_ids[{index}] = 16'd{token_id};"
        for index, token_id in enumerate([7454, 2402, 257, 640, 612, 373])
    )
    ln_input_assignments = "\n".join(
        f"  embed_block_expected_ln_input_q12_by_token[{token}][{dim}] = 16'sd0;"
        for token in range(6)
        for dim in range(64)
    )
    path = write_text(token_assignments + "\n" + ln_input_assignments + "\n")
    expected = parse_embedding_tb_data_sv(path)
    assert expected["token_ids"] == [7454, 2402, 257, 640, 612, 373]
    assert expected["provenance_mode"] == 0x3000
    assert expected["reserved_input"] == bytes(64)
    token_input = expected["token_input"]
    assert isinstance(token_input, bytes)
    assert token_input[:12] == b"".join(
        token_id.to_bytes(2, "little")
        for token_id in [7454, 2402, 257, 640, 612, 373]
    )
    assert token_input[12:] == bytes(52)


def test_vector_readback_transform_classifies_board_ror1() -> None:
    requested = bytes.fromhex(
        "1e1d6209010180026402750100000000"
        "00000000000000000000000000000000"
        "00000000000000000000000000000000"
        "00000000000000000000000000000000"
    )
    observed = bytes.fromhex(
        "8f0eb184800040013281ba0000000000"
        "00000000000000000000000000000000"
        "00000000000000000000000000000000"
        "00000000000000000000000000000000"
    )
    words = vector_words_from_bytes(requested)
    assert vector_bytes_from_words(pcie7x_inverse_rotate64_bar_vector_words(words)) == observed
    assert classify_vector_readback_transform(requested, observed) == "pcie7x-64bit-ror1"
    compensated = vector_bytes_from_words(pcie7x_rotate64_compensate_bar_vector_words(words))
    assert classify_vector_readback_transform(requested, compensated) == "pcie7x-64bit-rol1"
    assert classify_vector_readback_transform(requested, requested) == "identity"
    assert classify_vector_readback_transform(requested, bytes(64)) == "all-zero"


def test_token_live_host_vector_selection_rejects_raw_overrides() -> None:
    expected = {
        "token_input": bytes([1, 0, 2, 0, 3, 0]) + bytes(58),
        "reserved_input": bytes(64),
        "token_ids": [1, 2, 3, 4, 5, 6],
        "provenance_mode": 0x3000,
    }
    block_input, residual, block_source, residual_source = select_host_vectors(
        expected,
        input_hex=None,
        residual_hex=None,
    )
    assert block_input[:6] == bytes([1, 0, 2, 0, 3, 0])
    assert residual == bytes(64)
    assert block_source == "embedding_tb_data_sv token_ids"
    assert residual_source == "embedding_tb_data_sv reserved token-control vector"

    try:
        select_host_vectors(
            expected,
            input_hex=bytes(64).hex(),
            residual_hex=None,
        )
    except SystemExit as exc:
        assert "does not allow --input-hex or --residual-hex" in str(exc)
    else:
        raise AssertionError("token-live mode accepted a raw input override")


def test_validate_expected_rejects_missing_first_64_output() -> None:
    path = write_json(
        {
            "expected_checksum": 0x12345678,
            "expected_sample0": 0x01020304,
            "expected_sample1": 0x11121314,
            "output_count": 4864,
        }
    )
    expected = parse_expected_json(path)
    try:
        validate_expected(expected, path)
    except SystemExit as exc:
        assert "first_64_output" in str(exc)
    else:
        raise AssertionError("validate_expected accepted a fixture without first_64_output")


def test_wrapper_contract_is_not_live_m2_evidence() -> None:
    assert CONTRACT["stage"] == "M2-full-block-pcie-wrapper"
    assert CONTRACT["milestone_target"] == "M2-one-full-block"
    assert CONTRACT["live_compute"] is False
    assert CONTRACT["artifact_role"] == "pcie-bar-full-block-candidate-gate"


def test_embedding_token_mode_contract_can_close_m2_after_board_pass() -> None:
    expected = {"token_ids": [7454, 2402, 257, 640, 612, 373], "provenance_mode": 0x3000}
    contract = contract_for_expected(expected)
    assert is_token_live_mode(expected)
    assert contract["stage"] == "M2-one-full-block"
    assert contract["live_compute"] is True
    assert "one complete TinyStories transformer block" in contract["notes"]
    assert "fixture" not in json.dumps(contract).lower()
    assert compute_path_for_expected(expected) == "live-full-block"


def test_fixture_mode_contract_remains_candidate_only() -> None:
    expected = {"token_index": 5, "provenance_mode": 0x2000}
    assert not is_token_live_mode(expected)
    assert contract_for_expected(expected) is CONTRACT
    assert compute_path_for_expected(expected) == "fixture-full-block-wrapper"


def test_expected_provenance_encodes_fixture_token_index() -> None:
    assert expected_provenance({"token_index": 5}) == 0x4D32_2005
    assert expected_provenance({"token_index": 0x105}) == 0x4D32_2005
    assert expected_provenance({}) == 0x4D32_2000
    assert expected_provenance({"token_index": 5, "provenance_mode": 0x3000}) == 0x4D32_3005


def test_sample_registers_records_stable_preflight_values() -> None:
    values, samples, stable = sample_registers(
        lambda offset: {0x000: 0x54365043, 0x508: 0x00000001}[offset],
        {"magic": 0x000, "m2_present": 0x508},
        samples=3,
        interval=0.0,
    )
    assert values == {"magic": 0x54365043, "m2_present": 0x00000001}
    assert samples == {
        "magic": [0x54365043, 0x54365043, 0x54365043],
        "m2_present": [0x00000001, 0x00000001, 0x00000001],
    }
    assert stable == {"magic": True, "m2_present": True}


def test_rd32_window_decodes_word_from_64_byte_snapshot() -> None:
    data = bytearray(0x600)
    data[0x500:0x504] = bytes.fromhex("54364d32")
    data[0x508:0x50C] = bytes.fromhex("00000001")
    assert rd32_window(data, 0x500) == 0x54364D32
    assert rd32_window(data, 0x508) == 0x00000001


def test_sample_registers_detects_transient_all_ones_preflight_read() -> None:
    reads = {
        0x000: [0x54365043, 0x54365043, 0x54365043],
        0x508: [0x00000001, 0xFFFFFFFF, 0x00000001],
    }

    def read32(offset: int) -> int:
        return reads[offset].pop(0)

    values, samples, stable = sample_registers(
        read32,
        {"magic": 0x000, "m2_present": 0x508},
        samples=3,
        interval=0.0,
    )
    assert values["m2_present"] == 0x00000001
    assert samples["m2_present"] == [0x00000001, 0xFFFFFFFF, 0x00000001]
    assert stable == {"magic": True, "m2_present": False}


def main() -> None:
    test_decode_status_magic_bit16()
    test_decode_status_rejects_old_magic_bit14_interpretation()
    test_decode_debug_context_ln_uses_context_namespace()
    test_decode_debug_raw_stage_one_remains_embedding_namespace()
    test_done_stage_checksum_decode_finds_first_mismatch()
    test_parse_expected_json_requires_first_64_output()
    test_parse_expected_tb_data_sv_first_token_final_vector()
    test_parse_embedding_tb_data_sv_token_input_vector()
    test_token_live_host_vector_selection_rejects_raw_overrides()
    test_validate_expected_rejects_missing_first_64_output()
    test_wrapper_contract_is_not_live_m2_evidence()
    test_embedding_token_mode_contract_can_close_m2_after_board_pass()
    test_fixture_mode_contract_remains_candidate_only()
    test_expected_provenance_encodes_fixture_token_index()
    test_sample_registers_records_stable_preflight_values()
    test_rd32_window_decodes_word_from_64_byte_snapshot()
    test_sample_registers_detects_transient_all_ones_preflight_read()


if __name__ == "__main__":
    main()
