#!/usr/bin/env python3
"""Unit checks for Task 6 milestone evidence classification."""

from __future__ import annotations

from pathlib import Path

from task6_milestone_evidence_audit import audit_payload
from task6_pcie_m2_full_block_gate import (
    CONTRACT as M2_FULL_BLOCK_WRAPPER_CONTRACT,
    CONTRACT_TOKEN_LIVE as M2_TOKEN_LIVE_CONTRACT,
)
from task6_pcie_m2_ln_attn_sublane_gate import CONTRACT as M2_SUBLANE_CONTRACT


SCRIPT_DIR = Path(__file__).resolve().parent


def m2_passing_bar_checks() -> dict[str, bool]:
    return {
        "task6_magic": True,
        "task6_version": True,
        "not_all_ones": True,
        "m2_magic": True,
        "m2_version": True,
        "m2_present": True,
        "m2_provenance": True,
        "status_schema": True,
        "start_count_incremented": True,
        "state_done": True,
        "no_error": True,
        "output_valid": True,
        "output_count_live": True,
        "checksum": True,
        "sample0": True,
        "sample1": True,
        "output_count": True,
        "first_64_output": True,
    }


def m1_live_payload() -> dict:
    activation = "01" * 64
    residual = "02" * 64
    output = "03" * 64
    return {
        "status": "PASS",
        "contract": {
            "stage": "M1-transformer-boundary-mlp",
            "notes": "Host supplies prompt-derived residual-boundary vectors; board executes int8 MLP/residual lane.",
        },
        "reference_contract": {
            "compatible": True,
            "reason": "default vector is generated from the compiled full TinyStories-1M MLP contract",
        },
        "validation": {"mismatch_count": 0},
        "samples": [
            {
                "status": "PASS",
                "checks": {
                    "activation_echo": True,
                    "residual_echo": True,
                    "start_count_incremented": True,
                    "done_bit": True,
                    "output_valid": True,
                    "state_done": True,
                    "checksum": True,
                    "sample0": True,
                    "sample1": True,
                    "output_vector": True,
                },
                "input": {
                    "activation_hex": activation,
                    "residual_hex": residual,
                },
                "expected": {"output_hex": output},
                "observed": {
                    "activation_echo_hex": activation,
                    "residual_echo_hex": residual,
                    "output_hex": output,
                },
            }
        ],
    }


def test_m1_accepts_prompt_derived_full_vector_boundary_shape() -> None:
    assert audit_payload("M1", m1_live_payload()) == []


def test_m1_rejects_selftest_only_contract() -> None:
    payload = m1_live_payload()
    payload["contract"]["notes"] = "Boundary-stage selftest proof."
    payload["reference_contract"] = {}
    failures = audit_payload("M1", payload)
    assert any("selftest" in failure for failure in failures)
    assert any("reference contract" in failure for failure in failures)


def test_m1_requires_echo_and_output_checks() -> None:
    payload = m1_live_payload()
    payload["samples"][0]["checks"]["residual_echo"] = False
    payload["samples"][0]["observed"]["output_hex"] = "04" * 64
    failures = audit_payload("M1", payload)
    assert any("residual_echo" in failure for failure in failures)
    assert any("observed output" in failure for failure in failures)


def test_m2_rejects_replay_contract() -> None:
    payload = {
        "status": "PASS",
        "contract": {
            "stage": "M2-one-full-block-replay",
            "live_compute": False,
            "notes": "This RTL lane replays the composed fixed-point artifact.",
        },
        "observed": {"first_64_output_hex": "00" * 64},
        "expected": {"first_64_output_hex": "00" * 64},
    }
    failures = audit_payload("M2", payload)
    assert any("replay/fixture" in failure for failure in failures)


def test_m2_accepts_live_full_block_shape() -> None:
    payload = {
        "status": "PASS",
        "contract": {
            "stage": "M2-one-full-block",
            "live_compute": True,
            "notes": "Board executes one complete TinyStories transformer block from token/control input.",
            "responsibilities": {
                "fpga": ["one complete TinyStories block live compute"],
                "host": ["token/control input"],
            },
        },
        "input": {"token_ids": [1, 2, 3], "control": {"block_index": 0}},
        "board": {"status": "PASS"},
        "bdf": "0000:42:00.0",
        "lspci": "0000:42:00.0 Processing accelerators [1200]: Xilinx Corporation Device [10ee:0480]",
        "observed": {"compute_path": "live", "first_64_output_hex": "00" * 64},
        "expected": {"first_64_output_hex": "00" * 64},
        "checks": m2_passing_bar_checks(),
    }
    assert audit_payload("M2", payload) == []


def test_m2_accepts_token_live_gate_contract_shape() -> None:
    payload = {
        "status": "PASS",
        "contract": M2_TOKEN_LIVE_CONTRACT,
        "input": {"token_ids": [7454, 2402, 257, 640, 612, 373], "block_index": 0},
        "board": {"status": "PASS"},
        "bdf": "0000:42:00.0",
        "lspci": "0000:42:00.0 Processing accelerators [1200]: Xilinx Corporation Device [10ee:0480]",
        "observed": {"compute_path": "live-full-block", "first_64_output_hex": "00" * 64},
        "expected": {"first_64_output_hex": "00" * 64},
        "checks": m2_passing_bar_checks(),
    }
    assert audit_payload("M2", payload) == []


def test_m2_accepts_board_nested_pcie_identity() -> None:
    payload = {
        "status": "PASS",
        "contract": M2_TOKEN_LIVE_CONTRACT,
        "input": {"token_ids": [7454, 2402, 257, 640, 612, 373], "block_index": 0},
        "board": {
            "status": "PASS",
            "bdf": "0000:42:00.0",
            "lspci": "0000:42:00.0 Memory controller [0580]: Xilinx Corporation Device [10ee:0480]",
        },
        "observed": {"compute_path": "live-full-block", "first_64_output_hex": "00" * 64},
        "expected": {"first_64_output_hex": "00" * 64},
        "checks": m2_passing_bar_checks(),
    }
    assert audit_payload("M2", payload) == []


def test_m2_requires_matching_first_64_output() -> None:
    payload = {
        "status": "PASS",
        "contract": {
            "stage": "M2-one-full-block",
            "live_compute": True,
            "notes": "Board executes one complete TinyStories transformer block from token/control input.",
            "responsibilities": {"fpga": ["one complete TinyStories block live compute"]},
        },
        "input": {"token_ids": [1], "control": {"block_index": 0}},
        "observed": {"compute_path": "live", "first_64_output_hex": "00" * 64},
        "expected": {"first_64_output_hex": "01" * 64},
        "checks": m2_passing_bar_checks(),
    }
    failures = audit_payload("M2", payload)
    assert any("first-64-byte output" in failure for failure in failures)


def test_m2_requires_token_control_and_live_compute_path() -> None:
    payload = {
        "status": "PASS",
        "contract": {
            "stage": "M2-one-full-block",
            "live_compute": True,
            "notes": "Board executes one complete TinyStories transformer block from token/control input.",
            "responsibilities": {"fpga": ["one complete TinyStories block live compute"]},
        },
        "observed": {"first_64_output_hex": "00" * 64},
        "expected": {"first_64_output_hex": "00" * 64},
    }
    failures = audit_payload("M2", payload)
    assert any("token/control token IDs" in failure for failure in failures)
    assert any("block_index=0" in failure for failure in failures)
    assert any("compute_path" in failure for failure in failures)
    assert any("board/PCIe" in failure for failure in failures)
    assert any("board status" in failure for failure in failures)


def test_m2_requires_explicit_board_pass_status() -> None:
    payload = {
        "status": "PASS",
        "contract": {
            "stage": "M2-one-full-block",
            "live_compute": True,
            "notes": "Board executes one complete TinyStories transformer block from token/control input.",
            "responsibilities": {"fpga": ["one complete TinyStories block live compute"]},
        },
        "input": {"token_ids": [1], "control": {"block_index": 0}},
        "bdf": "0000:42:00.0",
        "lspci": "0000:42:00.0 Processing accelerators [1200]: Xilinx Corporation Device [10ee:0480]",
        "observed": {"compute_path": "live", "first_64_output_hex": "00" * 64},
        "expected": {"first_64_output_hex": "00" * 64},
        "checks": m2_passing_bar_checks(),
    }
    failures = audit_payload("M2", payload)
    assert any("board status" in failure for failure in failures)


def test_m2_requires_passing_bar_gate_checks() -> None:
    payload = {
        "status": "PASS",
        "contract": M2_TOKEN_LIVE_CONTRACT,
        "input": {"token_ids": [7454, 2402, 257, 640, 612, 373], "block_index": 0},
        "board": {"status": "PASS"},
        "bdf": "0000:42:00.0",
        "lspci": "0000:42:00.0 Processing accelerators [1200]: Xilinx Corporation Device [10ee:0480]",
        "observed": {"compute_path": "live-full-block", "first_64_output_hex": "00" * 64},
        "expected": {"first_64_output_hex": "00" * 64},
        "checks": {**m2_passing_bar_checks(), "m2_provenance": False},
    }
    failures = audit_payload("M2", payload)
    assert any("m2_provenance" in failure for failure in failures)


def test_m2_rejects_first_token_wrapper_even_with_matching_output() -> None:
    payload = {
        "status": "PASS",
        "contract": M2_FULL_BLOCK_WRAPPER_CONTRACT,
        "input": {"token_ids": [1], "control": {"block_index": 0}},
        "bdf": "0000:42:00.0",
        "lspci": "0000:42:00.0 Processing accelerators [1200]: Xilinx Corporation Device [10ee:0480]",
        "observed": {
            "compute_path": "first-token-full-block-wrapper",
            "first_64_output_hex": "00" * 64,
        },
        "expected": {"first_64_output_hex": "00" * 64},
    }
    failures = audit_payload("M2", payload)
    assert any("first-token/sublane" in failure for failure in failures)
    assert any("live_compute=true" in failure for failure in failures)


def test_m3_rejects_m0_prompt_infer_contract() -> None:
    payload = {
        "prompt_infer_status": "PASS",
        "contract": {"stage": "M0-host-assisted-rowstream-top1"},
        "reference": {"generated_tokens": [1, 2]},
        "board_tokens": [1, 2],
    }
    failures = audit_payload("M3", payload)
    assert any("M3-full-tinystories-1m" in failure for failure in failures)


def test_m3_requires_token_exact_output() -> None:
    payload = {
        "status": "PASS",
        "contract": {
            "stage": "M3-full-tinystories-1m",
            "live_compute": True,
            "all_blocks": True,
            "notes": "Board executes all TinyStories-1M transformer blocks for greedy inference.",
        },
        "input": {"prompt": "Once upon a time", "prompt_token_ids": [10, 11]},
        "model": {"model_label": "TinyStories-1M"},
        "reference": {"generated_tokens": [1, 2]},
        "board_tokens": [1, 3],
    }
    failures = audit_payload("M3", payload)
    assert any("do not match" in failure for failure in failures)
    assert any("board status" in failure for failure in failures)


def test_m3_requires_explicit_board_pass_status() -> None:
    payload = {
        "status": "PASS",
        "contract": {
            "stage": "M3-full-tinystories-1m",
            "live_compute": True,
            "all_blocks": True,
            "notes": "Board executes all TinyStories-1M transformer blocks for token-exact greedy generation.",
        },
        "input": {"prompt": "Once upon a time", "prompt_token_ids": [10, 11]},
        "model": {"model_label": "TinyStories-1M"},
        "reference": {"generated_tokens": [1, 2], "prompt": "Once upon a time"},
        "board_tokens": [1, 2],
    }
    failures = audit_payload("M3", payload)
    assert any("board status" in failure for failure in failures)
    assert any("board/PCIe identity" in failure for failure in failures)


def test_m3_requires_ypcb_board_identity() -> None:
    payload = {
        "status": "PASS",
        "contract": {
            "stage": "M3-full-tinystories-1m",
            "live_compute": True,
            "all_blocks": True,
            "notes": "Board executes all TinyStories-1M transformer blocks for token-exact greedy generation.",
        },
        "input": {"prompt": "Once upon a time", "prompt_token_ids": [10, 11]},
        "model": {"model_label": "TinyStories-1M"},
        "reference": {"generated_tokens": [1, 2], "prompt": "Once upon a time"},
        "board": {"status": "PASS", "sample_count": 2, "generated_tokens": [1, 2]},
    }
    failures = audit_payload("M3", payload)
    assert any("board/PCIe identity" in failure for failure in failures)


def test_m3_rejects_reference_prompt_mismatch() -> None:
    payload = {
        "status": "PASS",
        "contract": {
            "stage": "M3-full-tinystories-1m",
            "live_compute": True,
            "all_blocks": True,
            "notes": "Board executes all TinyStories-1M transformer blocks for token-exact greedy generation.",
        },
        "input": {
            "prompt": "Once upon a time",
            "prompt_token_ids": [10, 11],
        },
        "model": {"model_label": "TinyStories-1M"},
        "reference": {
            "prompt": "A different prompt",
            "prompt_token_ids": [10, 11],
            "generated_tokens": [1, 2],
        },
        "board": {
            "status": "PASS",
            "bdf": "0000:42:00.0",
            "lspci": "0000:42:00.0 Memory controller [0580]: Xilinx Corporation Device [10ee:0480]",
            "sample_count": 2,
            "generated_tokens": [1, 2],
        },
    }
    failures = audit_payload("M3", payload)
    assert any("does not match reference prompt" in failure for failure in failures)


def test_m3_rejects_prompt_token_mismatch_to_reference() -> None:
    payload = {
        "status": "PASS",
        "contract": {
            "stage": "M3-full-tinystories-1m",
            "live_compute": True,
            "all_blocks": True,
            "notes": "Board executes all TinyStories-1M transformer blocks for token-exact greedy generation.",
        },
        "input": {
            "prompt": "Once upon a time",
            "prompt_token_ids": [10, 12],
        },
        "model": {"model_label": "TinyStories-1M"},
        "reference": {
            "prompt": "Once upon a time",
            "prompt_token_ids": [10, 11],
            "generated_tokens": [1, 2],
        },
        "board": {
            "status": "PASS",
            "bdf": "0000:42:00.0",
            "lspci": "0000:42:00.0 Memory controller [0580]: Xilinx Corporation Device [10ee:0480]",
            "sample_count": 2,
            "generated_tokens": [1, 2],
        },
    }
    failures = audit_payload("M3", payload)
    assert any(
        "do not match reference prompt token IDs" in failure for failure in failures
    )


def test_m3_accepts_full_model_token_exact_shape() -> None:
    payload = {
        "status": "PASS",
        "contract": {
            "stage": "M3-full-tinystories-1m",
            "live_compute": True,
            "all_blocks": True,
            "notes": "Board executes all TinyStories-1M transformer blocks for token-exact greedy generation.",
            "responsibilities": {
                "fpga": ["all TinyStories-1M transformer blocks", "greedy token selection"],
                "host": ["prompt token/control input"],
            },
        },
        "input": {"prompt": "Once upon a time", "prompt_token_ids": [10, 11]},
        "model": {"model_label": "TinyStories-1M"},
        "reference": {"generated_tokens": [1, 2], "prompt": "Once upon a time"},
        "board": {
            "status": "PASS",
            "bdf": "0000:42:00.0",
            "lspci": "0000:42:00.0 Memory controller [0580]: Xilinx Corporation Device [10ee:0480]",
            "sample_count": 2,
            "generated_tokens": [1, 2],
        },
    }
    assert audit_payload("M3", payload) == []


def test_m3_rejects_host_assisted_even_when_tokens_match() -> None:
    payload = {
        "status": "PASS",
        "contract": {
            "stage": "M3-full-tinystories-1m",
            "live_compute": True,
            "all_blocks": True,
            "notes": "Host-assisted rowstream replay.",
        },
        "input": {"prompt": "Once upon a time", "prompt_token_ids": [10, 11]},
        "model": {"model_label": "TinyStories-1M"},
        "reference": {"generated_tokens": [1, 2]},
        "board_tokens": [1, 2],
    }
    failures = audit_payload("M3", payload)
    assert any("host-assisted" in failure for failure in failures)


def test_offline_m2_producers_do_not_claim_live_stage() -> None:
    offenders = []
    allowed_hardware_gates = {"task6_pcie_m2_full_block_gate.py"}
    for path in SCRIPT_DIR.glob("*.py"):
        if path.name == Path(__file__).name or path.name in allowed_hardware_gates:
            continue
        text = path.read_text(encoding="utf-8")
        if '"stage": "M2-one-full-block"' in text:
            offenders.append(path.name)
    assert offenders == [], f"offline scripts claim live M2 stage: {offenders}"


def test_m2_sublane_contract_is_not_live_m2_evidence() -> None:
    assert M2_SUBLANE_CONTRACT["stage"] == "M2-host-live-LN-live-QKV-fixture-attention-output-sublane"
    assert M2_SUBLANE_CONTRACT["milestone_target"] == "M2-one-full-block"
    assert M2_SUBLANE_CONTRACT["live_compute"] is False
    assert M2_SUBLANE_CONTRACT["artifact_role"] == "pcie-bar-live-sublane-fixture-gate"


def test_m2_full_block_wrapper_contract_is_not_live_m2_evidence() -> None:
    assert M2_FULL_BLOCK_WRAPPER_CONTRACT["stage"] == "M2-full-block-pcie-wrapper"
    assert M2_FULL_BLOCK_WRAPPER_CONTRACT["milestone_target"] == "M2-one-full-block"
    assert M2_FULL_BLOCK_WRAPPER_CONTRACT["live_compute"] is False
    assert M2_FULL_BLOCK_WRAPPER_CONTRACT["artifact_role"] == "pcie-bar-full-block-candidate-gate"


def main() -> None:
    test_m1_accepts_prompt_derived_full_vector_boundary_shape()
    test_m1_rejects_selftest_only_contract()
    test_m1_requires_echo_and_output_checks()
    test_m2_rejects_replay_contract()
    test_m2_accepts_live_full_block_shape()
    test_m2_accepts_token_live_gate_contract_shape()
    test_m2_accepts_board_nested_pcie_identity()
    test_m2_requires_matching_first_64_output()
    test_m2_requires_token_control_and_live_compute_path()
    test_m2_requires_explicit_board_pass_status()
    test_m2_requires_passing_bar_gate_checks()
    test_m2_rejects_first_token_wrapper_even_with_matching_output()
    test_m3_rejects_m0_prompt_infer_contract()
    test_m3_requires_token_exact_output()
    test_m3_requires_explicit_board_pass_status()
    test_m3_requires_ypcb_board_identity()
    test_m3_rejects_reference_prompt_mismatch()
    test_m3_rejects_prompt_token_mismatch_to_reference()
    test_m3_accepts_full_model_token_exact_shape()
    test_m3_rejects_host_assisted_even_when_tokens_match()
    test_offline_m2_producers_do_not_claim_live_stage()
    test_m2_sublane_contract_is_not_live_m2_evidence()
    test_m2_full_block_wrapper_contract_is_not_live_m2_evidence()


if __name__ == "__main__":
    main()
