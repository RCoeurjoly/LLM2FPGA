#!/usr/bin/env python3
"""Unit checks for the Task 6 M2 full-block PCIe gate contract helpers."""

from __future__ import annotations

import json
import os
from pathlib import Path
import tempfile

from task6_pcie_m2_full_block_gate import (
    CONTRACT,
    compute_path_for_expected,
    contract_for_expected,
    decode_status,
    expected_provenance,
    is_token_live_mode,
    parse_embedding_tb_data_sv,
    parse_expected_json,
    parse_expected_tb_data_sv,
    select_host_vectors,
    validate_expected,
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
    path = write_text(token_assignments + "\n")
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


def main() -> None:
    test_decode_status_magic_bit16()
    test_decode_status_rejects_old_magic_bit14_interpretation()
    test_parse_expected_json_requires_first_64_output()
    test_parse_expected_tb_data_sv_first_token_final_vector()
    test_parse_embedding_tb_data_sv_token_input_vector()
    test_token_live_host_vector_selection_rejects_raw_overrides()
    test_validate_expected_rejects_missing_first_64_output()
    test_wrapper_contract_is_not_live_m2_evidence()
    test_embedding_token_mode_contract_can_close_m2_after_board_pass()
    test_fixture_mode_contract_remains_candidate_only()
    test_expected_provenance_encodes_fixture_token_index()


if __name__ == "__main__":
    main()
