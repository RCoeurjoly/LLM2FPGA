#!/usr/bin/env python3
"""Unit checks for the Task 6 M2 full-block PCIe gate contract helpers."""

from __future__ import annotations

import json
import os
from pathlib import Path
import tempfile

from task6_pcie_m2_full_block_gate import (
    CONTRACT,
    CONTRACT_ATTENTION_SLICE,
    bar_contract_checks,
    classify_vector_readback_transform,
    compare_done_stage_checksums,
    compute_path_for_expected,
    contract_for_expected,
    decode_debug,
    decode_done_stage_checksums,
    decode_status,
    embedding_handoff_contract_checks,
    expected_provenance,
    is_token_live_mode,
    merge_context_expected,
    m2_version_abi_matches,
    parse_context_tb_data_sv,
    parse_embedding_tb_data_sv,
    parse_expected_json,
    parse_expected_tb_data_sv,
    pcie7x_inverse_rotate64_bar_vector_words,
    pcie7x_rotate64_compensate_bar_vector_words,
    rd32_window,
    sample_registers,
    select_host_vectors,
    start_clear_contract_checks,
    stable_or_leading_all_ones,
    validate_expected,
    vector_bytes_from_words,
    vector_hash128,
    warmup_register_reads,
    vector_write_words_for_mode,
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


def test_parse_expected_tb_data_sv_attention_ln2_vector() -> None:
    ln2_assignments = "\n".join(
        f"  ln2_expected_q[{index}] = {sv_i8(index - 32)};"
        for index in range(64)
    )
    path = write_text(
        "\n".join(
            [
                "localparam logic [31:0] LN2_EXPECTED_CHECKSUM = 32'h0003c720;",
                "localparam logic [31:0] LN2_EXPECTED_SAMPLE0 = 32'he1e0dfde;",
                "localparam logic [31:0] LN2_EXPECTED_SAMPLE1 = 32'he5e4e3e2;",
                "localparam int M2_FULL_BLOCK_TOKEN_INDEX = 5;",
                ln2_assignments,
                "",
            ]
        )
    )
    expected = parse_expected_tb_data_sv(path, output_boundary="attention-ln2")
    validate_expected(expected, path)
    assert expected["checksum"] == 0x0003C720
    assert expected["sample0"] == 0xE1E0DFDE
    assert expected["sample1"] == 0xE5E4E3E2
    assert expected["output_count"] == 64
    assert expected["first_64_output"] == bytes((index - 32) & 0xFF for index in range(64))
    assert expected["token_index"] == 5
    assert expected["provenance_mode"] == 0x4200


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
    block_input_assignments = "\n".join(
        f"  embed_block_expected_last_input_q[{index}] = {sv_i8(index)};"
        for index in range(64)
    )
    path = write_text(
        token_assignments + "\n" + ln_input_assignments + "\n" + block_input_assignments + "\n"
    )
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
    assert expected["embedding_block_input_vector"] == bytes(range(64))
    assert expected["block_input_checksum"] == sum(index * (index + 1) for index in range(64))


def test_parse_embedding_tb_data_sv_reads_summary_block_checksum() -> None:
    token_assignments = "\n".join(
        f"  embed_block_expected_token_ids[{index}] = 16'd{token_id};"
        for index, token_id in enumerate([7454, 2402, 257, 640, 612, 373])
    )
    ln_input_assignments = "\n".join(
        f"  embed_block_expected_ln_input_q12_by_token[{token}][{dim}] = 16'sd0;"
        for token in range(6)
        for dim in range(64)
    )
    block_input_assignments = "\n".join(
        f"  embed_block_expected_last_input_q[{index}] = {sv_i8(index)};"
        for index in range(64)
    )
    with tempfile.TemporaryDirectory(prefix="task6-m2-embedding-fixture-") as raw_dir:
        fixture_dir = Path(raw_dir)
        path = fixture_dir / "task6_m2_embedding_block_input_tb_data.sv"
        path.write_text(
            token_assignments + "\n" + ln_input_assignments + "\n" + block_input_assignments + "\n",
            encoding="utf-8",
        )
        checksum = sum(index * (index + 1) for index in range(64))
        (fixture_dir / "summary.json").write_text(
            json.dumps({"block_input_checksum": checksum}),
            encoding="utf-8",
        )
        expected = parse_embedding_tb_data_sv(path)
    assert expected["block_input_checksum"] == checksum


def test_parse_context_tb_data_sv_fixture_signature() -> None:
    path = write_text(
        "\n".join(
            [
                "  ln_input_q12_by_token[5][1] = -16'sd374;",
                "  ln_inv_std_q16_by_token[5] = 32'sd526188;",
                "  ln_expected_q_by_token[5][1] = -8'sd36;",
                "  context_expected_q[0] = -8'sd53;",
                "  context_expected_q[1] = 8'sd16;",
                "  context_expected_q[2] = -8'sd61;",
                "  context_expected_q[3] = -8'sd45;",
                "  context_expected_q[4] = -8'sd36;",
                "  context_expected_q[5] = 8'sd29;",
                "  context_expected_q[6] = -8'sd63;",
                "  context_expected_q[7] = 8'sd16;",
                *[
                    f"  context_expected_q[{index}] = 8'sd0;"
                    for index in range(8, 64)
                ],
                "",
            ]
        )
    )
    expected = parse_context_tb_data_sv(path)
    assert expected["context_fixture_signature"] == 0xC5DC_8A6C
    assert expected["context_fixture_signature_token"] == 5
    assert expected["context_fixture_signature_dim"] == 1
    assert expected["first_64_output"][:8] == bytes.fromhex("cb10c3d3dc1dc110")
    assert expected["checksum"] == 0x00001141
    assert expected["sample0"] == 0xD3C310CB
    assert expected["sample1"] == 0x10C11DDC
    assert expected["output_count"] == 64
    assert "provenance_mode" not in expected


def test_merge_context_expected_preserves_attention_ln2_output_oracle() -> None:
    expected: dict[str, object] = {
        "checksum": 0x0003ED3A,
        "sample0": 0xFBDBB2F9,
        "sample1": 0x7FC2F7B0,
        "output_count": 64,
        "first_64_output": bytes.fromhex("f9b2dbfb" + "00" * 60),
        "provenance_mode": 0x4200,
    }
    context_expected = {
        "context_fixture_signature": 0xC5DC8A6C,
        "context_fixture_signature_token": 5,
        "context_fixture_signature_dim": 1,
        "checksum": 0x000432E3,
        "sample0": 0xD3C310CB,
        "sample1": 0x10C11DDC,
        "output_count": 64,
        "first_64_output": bytes.fromhex("cb10c3d3" + "00" * 60),
    }

    merge_context_expected(
        expected,
        context_expected,
        preserve_output_boundary=True,
    )

    assert expected["checksum"] == 0x0003ED3A
    assert expected["sample0"] == 0xFBDBB2F9
    assert expected["sample1"] == 0x7FC2F7B0
    assert expected["first_64_output"] == bytes.fromhex("f9b2dbfb" + "00" * 60)
    assert expected["context_fixture_signature"] == 0xC5DC8A6C


def test_attention_slice_contract_is_focused_m2_4_evidence() -> None:
    expected = {
        "token_ids": [7454, 2402, 257, 640, 612, 373],
        "provenance_mode": 0x4100,
        "first_64_output": bytes(64),
    }
    assert is_token_live_mode(expected)
    assert contract_for_expected(expected) is CONTRACT_ATTENTION_SLICE
    assert compute_path_for_expected(expected) == "live-context-attention-slice"
    assert expected_provenance({**expected, "token_index": 5}) == 0x4D32_4105


def test_attention_ln2_contract_is_focused_m2_5_evidence() -> None:
    expected = {
        "token_ids": [7454, 2402, 257, 640, 612, 373],
        "provenance_mode": 0x4200,
        "first_64_output": bytes(64),
    }
    assert is_token_live_mode(expected)
    contract = contract_for_expected(expected)
    assert contract["stage"] == "M2.5-attention-out-proj-residual-ln2"
    assert contract["milestone_target"] == "M2.5-attention-out-proj-residual-ln2"
    assert contract["live_compute"] is True
    assert compute_path_for_expected(expected) == "live-context-attention-ln2"
    assert expected_provenance({**expected, "token_index": 5}) == 0x4D32_4205


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


def test_input_shadow_direct_write_mode_uses_inverse_compensation() -> None:
    requested = bytes.fromhex(
        "1e1d6209010180026402750100000000"
        "00000000000000000000000000000000"
        "00000000000000000000000000000000"
        "00000000000000000000000000000000"
    )
    requested_words = vector_words_from_bytes(requested)
    assert vector_write_words_for_mode(requested_words, "input-shadow-direct-compensated")[:3] == [
        0x84B10E8F,
        0x01400080,
        0x00BA8132,
    ]
    assert vector_write_words_for_mode(requested_words, "readback-compensated")[:3] == [
        0x12C43A3C,
        0x05000202,
        0x02EA04C8,
    ]


def test_bar_contract_checks_require_direct_identity_and_idle_status() -> None:
    requested = bytes(range(64))
    checks = bar_contract_checks(
        status=0x4D32_0001,
        provenance=0x4D32_3005,
        input_readback=requested,
        residual_readback=bytes(64),
        block_input=requested,
        residual=bytes(64),
        start_count_before=7,
        start_count_after=7,
    )

    assert checks == {
        "status_not_all_ones": True,
        "provenance_not_all_ones": True,
        "status_schema_consistent": True,
        "provenance_schema_consistent": True,
        "state_idle": True,
        "no_error": True,
        "start_count_unchanged": True,
        "input_readback_identity": True,
        "residual_readback_identity": True,
    }

    stale = bar_contract_checks(
        status=0xFFFF_FFFF,
        provenance=0xFFFF_FFFF,
        input_readback=bytes(64),
        residual_readback=bytes(64),
        block_input=requested,
        residual=bytes(64),
        start_count_before=7,
        start_count_after=8,
    )
    assert not all(stale.values())
    assert not stale["status_not_all_ones"]
    assert not stale["input_readback_identity"]
    assert not stale["start_count_unchanged"]


def test_start_clear_contract_checks_require_start_increment_and_clear_idle() -> None:
    checks = start_clear_contract_checks(
        run_status=0x4D32_0059,
        clear_status=0x4D32_0001,
        provenance=0x4D32_3005,
        input_readback=bytes(range(64)),
        residual_readback=bytes(64),
        block_input=bytes(range(64)),
        residual=bytes(64),
        start_count_before=11,
        start_count_after_start=12,
        start_count_after_clear=12,
        allow_error=False,
    )
    assert checks == {
        "run_status_not_all_ones": True,
        "clear_status_not_all_ones": True,
        "provenance_not_all_ones": True,
        "run_status_schema_consistent": True,
        "clear_status_schema_consistent": True,
        "provenance_schema_consistent": True,
        "start_count_incremented": True,
        "start_count_stable_after_clear": True,
        "run_reached_terminal": True,
        "run_reached_allowed_terminal": True,
        "clear_state_idle": True,
        "clear_no_error": True,
        "input_readback_identity": True,
        "residual_readback_identity": True,
    }

    stale = start_clear_contract_checks(
        run_status=0xFFFF_FFFF,
        clear_status=0xFFFF_FFFF,
        provenance=0xFFFF_FFFF,
        input_readback=bytes(64),
        residual_readback=bytes(64),
        block_input=bytes(range(64)),
        residual=bytes(64),
        start_count_before=11,
        start_count_after_start=11,
        start_count_after_clear=10,
        allow_error=False,
    )
    assert not all(stale.values())
    assert not stale["run_status_not_all_ones"]
    assert not stale["start_count_incremented"]
    assert not stale["clear_state_idle"]

    precise_error = start_clear_contract_checks(
        run_status=0x4D32_0064,
        clear_status=0x4D32_0001,
        provenance=0x4D32_3005,
        input_readback=bytes(range(64)),
        residual_readback=bytes(64),
        block_input=bytes(range(64)),
        residual=bytes(64),
        start_count_before=11,
        start_count_after_start=12,
        start_count_after_clear=12,
        allow_error=True,
    )
    assert precise_error["run_reached_terminal"]
    assert precise_error["run_reached_allowed_terminal"]
    assert all(precise_error.values())


def test_embedding_handoff_contract_requires_vector_not_hash_fallback() -> None:
    expected_vector = bytes(range(64))
    wrong_vector = bytes(reversed(range(64)))
    checks = embedding_handoff_contract_checks(
        run_decoded=decode_status(0x4D32_0059),
        output_count=64,
        checksum=0x0003_50F9,
        debug=0x88FA_5E3A,
        debug1=0x0003_50F9,
        debug2=0x88FA_5E3A,
        debug3=0x50F9_5E3A,
        output_vector=wrong_vector,
        output_hash=vector_hash128(expected_vector),
        expected_block_input_checksum=0x0003_50F9,
        expected_ln_input_checksum=0x88FA_5E3A,
        expected_block_vector=expected_vector,
    )
    status_checks = dict(checks)
    status_checks.pop("embedding_output_hash", None)

    assert checks["embedding_output_hash"]
    assert not checks["embedding_output_vector"]
    assert not all(status_checks.values())


def test_embedding_handoff_contract_records_hash_diagnostic_separately() -> None:
    expected_vector = bytes(range(64))
    checks = embedding_handoff_contract_checks(
        run_decoded=decode_status(0x4D32_0059),
        output_count=64,
        checksum=0x0003_50F9,
        debug=0x88FA_5E3A,
        debug1=0x0003_50F9,
        debug2=0x88FA_5E3A,
        debug3=0x50F9_5E3A,
        output_vector=expected_vector,
        output_hash=bytes(16),
        expected_block_input_checksum=0x0003_50F9,
        expected_ln_input_checksum=0x88FA_5E3A,
        expected_block_vector=expected_vector,
    )
    status_checks = dict(checks)
    status_checks.pop("embedding_output_hash", None)

    assert checks["embedding_output_vector"]
    assert not checks["embedding_output_hash"]
    assert all(status_checks.values())


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


def test_warmup_register_reads_discards_observed_values_before_strict_sampling() -> None:
    reads = {
        0x008: [0x00000061, 0x00400061, 0x00400061, 0x00400061],
        0x5D4: [0xFFFF_FFFF, 0x4D32_4105, 0x4D32_4105, 0x4D32_4105],
    }

    def read32(offset: int) -> int:
        return reads[offset].pop(0)

    warmup = warmup_register_reads(
        read32,
        {"status": 0x008, "m2_provenance": 0x5D4},
        samples=1,
    )
    values, samples, stable = sample_registers(
        read32,
        {"status": 0x008, "m2_provenance": 0x5D4},
        samples=3,
        interval=0.0,
    )

    assert warmup == {"status": [0x00000061], "m2_provenance": [0xFFFF_FFFF]}
    assert values == {"status": 0x00400061, "m2_provenance": 0x4D32_4105}
    assert samples == {
        "status": [0x00400061, 0x00400061, 0x00400061],
        "m2_provenance": [0x4D32_4105, 0x4D32_4105, 0x4D32_4105],
    }
    assert stable == {"status": True, "m2_provenance": True}


def test_preflight_accepts_single_leading_all_ones_then_stable_value() -> None:
    assert stable_or_leading_all_ones([0x4D32_3005, 0x4D32_3005, 0x4D32_3005])
    assert stable_or_leading_all_ones([0xFFFF_FFFF, 0x4D32_3005, 0x4D32_3005])
    assert not stable_or_leading_all_ones([0x4D32_3005, 0xFFFF_FFFF, 0x4D32_3005])
    assert not stable_or_leading_all_ones([0xFFFF_FFFF, 0x4D32_3005, 0x4D32_3006])
    assert not stable_or_leading_all_ones([0xFFFF_FFFF, 0xFFFF_FFFF, 0xFFFF_FFFF])


def test_m2_version_accepts_feature_bits_with_abi_low_half() -> None:
    assert m2_version_abi_matches(0x0000_0001)
    assert m2_version_abi_matches(0x0020_0001)
    assert not m2_version_abi_matches(0x0000_0002)
    assert not m2_version_abi_matches(0xFFFF_FFFF)


def main() -> None:
    test_decode_status_magic_bit16()
    test_decode_status_rejects_old_magic_bit14_interpretation()
    test_decode_debug_context_ln_uses_context_namespace()
    test_decode_debug_raw_stage_one_remains_embedding_namespace()
    test_done_stage_checksum_decode_finds_first_mismatch()
    test_parse_expected_json_requires_first_64_output()
    test_parse_expected_tb_data_sv_first_token_final_vector()
    test_parse_expected_tb_data_sv_attention_ln2_vector()
    test_parse_embedding_tb_data_sv_token_input_vector()
    test_parse_embedding_tb_data_sv_reads_summary_block_checksum()
    test_parse_context_tb_data_sv_fixture_signature()
    test_merge_context_expected_preserves_attention_ln2_output_oracle()
    test_attention_ln2_contract_is_focused_m2_5_evidence()
    test_bar_contract_checks_require_direct_identity_and_idle_status()
    test_start_clear_contract_checks_require_start_increment_and_clear_idle()
    test_embedding_handoff_contract_requires_vector_not_hash_fallback()
    test_embedding_handoff_contract_records_hash_diagnostic_separately()
    test_token_live_host_vector_selection_rejects_raw_overrides()
    test_validate_expected_rejects_missing_first_64_output()
    test_wrapper_contract_is_not_live_m2_evidence()
    test_embedding_token_mode_contract_can_close_m2_after_board_pass()
    test_fixture_mode_contract_remains_candidate_only()
    test_expected_provenance_encodes_fixture_token_index()
    test_sample_registers_records_stable_preflight_values()
    test_rd32_window_decodes_word_from_64_byte_snapshot()
    test_sample_registers_detects_transient_all_ones_preflight_read()
    test_warmup_register_reads_discards_observed_values_before_strict_sampling()
    test_preflight_accepts_single_leading_all_ones_then_stable_value()
    test_m2_version_accepts_feature_bits_with_abi_low_half()


if __name__ == "__main__":
    main()
