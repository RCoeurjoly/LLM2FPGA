#!/usr/bin/env python3
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
RTL = REPO_ROOT / "fpga/rtl/task6_m2_embedding_live_context_attention_ln2_pcie_accel_top.sv"


def test_ln2_wrapper_uses_direct_embed_ln_input_handoff() -> None:
    text = RTL.read_text(encoding="utf-8")
    assert "ln_input_q12_by_token_q" not in text
    assert ".external_ln_input_q12_by_token_i(embed_ln_input_q12_by_token_w)" in text


if __name__ == "__main__":
    test_ln2_wrapper_uses_direct_embed_ln_input_handoff()
    print("PASS: M2.5 attention LN2 wrapper uses direct embed LN input handoff")
