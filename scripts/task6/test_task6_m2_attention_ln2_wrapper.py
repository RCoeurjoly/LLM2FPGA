#!/usr/bin/env python3
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
RTL = REPO_ROOT / "fpga/rtl/task6_m2_embedding_live_context_attention_ln2_pcie_accel_top.sv"
TOP = REPO_ROOT / "fpga/rtl/task6_ypcb_pcie_rowstream_ingress_dummy_top.sv"
FLAKE = REPO_ROOT / "flake.nix"


def test_ln2_wrapper_uses_direct_embed_ln_input_handoff() -> None:
    text = RTL.read_text(encoding="utf-8")
    assert "ln_input_q12_by_token_q" not in text
    assert ".external_ln_input_q12_by_token_i(embed_ln_input_q12_by_token_w)" in text


def test_m2_5_top_registers_public_pcie_boundary() -> None:
    text = TOP.read_text(encoding="utf-8")
    assert "rowstream_m2_full_block_status_raw" in text
    assert ".pcie_status_o(rowstream_m2_full_block_status_raw)" in text
    assert "rowstream_m2_full_block_status <= rowstream_m2_full_block_status_raw;" in text
    assert "rowstream_m2_full_block_output_vector <= rowstream_m2_full_block_output_vector_raw;" in text


def test_m2_5_top_decouples_compute_input_from_bar_readback() -> None:
    text = TOP.read_text(encoding="utf-8")
    compact = " ".join(text.split())
    assert "rowstream_m2_full_block_token_ids_for_accel_q" in text
    assert "rowstream_m2_full_block_token_ids_for_accel" in text
    assert (
        "rowstream_m2_full_block_start ? "
        "rowstream_m2_full_block_input_vector[95:0]"
    ) in compact
    assert (
        "rowstream_m2_full_block_token_ids_for_accel_q <= "
        "rowstream_m2_full_block_input_vector[95:0];"
    ) in text
    assert ".pcie_token_ids_i({416'd0, rowstream_m2_full_block_token_ids_for_accel})" in text


def test_m2_5_wrapper_keeps_bar_clear_local_for_timing() -> None:
    text = RTL.read_text(encoding="utf-8")
    assert ".clear_i(pcie_clear_q)" not in text
    assert text.count(".clear_i(1'b0)") >= 2
    assert "Avoid a high-fanout timing path from the PCIe BAR clear bit." in text


def test_m2_5_image_uses_direct_m2_bar_contract() -> None:
    text = FLAKE.read_text(encoding="utf-8")
    start = text.index("task6YpcbPcieRowstreamIngressM25AttentionLn2YosysJson")
    end = text.index("task6YpcbPcieRowstreamIngressM1YosysJson", start)
    block = text[start:end]
    assert "chparam -set M2_INPUT_PCIE7X_ROR64_COMPENSATE 1" not in block


if __name__ == "__main__":
    test_ln2_wrapper_uses_direct_embed_ln_input_handoff()
    test_m2_5_top_registers_public_pcie_boundary()
    test_m2_5_top_decouples_compute_input_from_bar_readback()
    test_m2_5_image_uses_direct_m2_bar_contract()
    print("PASS: M2.5 attention LN2 wrapper uses direct embed LN input handoff")
