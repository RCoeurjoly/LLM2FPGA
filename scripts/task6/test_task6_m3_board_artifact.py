#!/usr/bin/env python3
"""Unit checks for shaping Task 6 M3 board artifacts."""

from __future__ import annotations

import contextlib
import io
import json
import tempfile
from pathlib import Path

from task6_m3_board_artifact import build_board_artifact, main
from task6_milestone_evidence_audit import audit_payload


def manifest() -> dict:
    return {
        "artifact_name": "task6-m3-reference-manifest",
        "status": "PASS",
        "model": {
            "model_label": "TinyStories-1M",
            "model_path": "/nix/store/frozen-model",
            "adapter_path": "/nix/store/frozen-adapter.py",
            "vocab_size": 50257,
            "hidden_size": 64,
        },
        "input": {
            "prompt": "Once upon a time",
            "prompt_token_ids": [10, 11],
            "tokenizer": "GPT-Neo/GPT-2 BPE",
        },
        "reference": {
            "prompt": "Once upon a time",
            "generated_tokens": [1, 2, 3],
            "generated_text": "Once upon a time...",
            "tokenizer": "GPT-Neo/GPT-2 BPE",
        },
    }


def live_board_summary(tokens: list[int] | None = None) -> dict:
    return {
        "artifact_name": "task6-ypcb-m3-full-inference-gate",
        "status": "PASS",
        "bdf": "0000:42:00.0",
        "lspci": "0000:42:00.0 Memory controller [0580]: Xilinx Corporation Device [10ee:0480]",
        "contract": {
            "stage": "M3-full-tinystories-1m",
            "live_compute": True,
            "all_blocks": True,
            "notes": "Board executes all TinyStories-1M transformer blocks.",
        },
        "board": {
            "status": "PASS",
            "generated_tokens": tokens if tokens is not None else [1, 2, 3],
        },
    }


def host_assisted_summary() -> dict:
    return {
        "artifact_name": "task6-prompt-infer-board-summary",
        "prompt_infer_status": "PASS",
        "bdf": "0000:42:00.0",
        "board_tokens": [1, 2, 3],
        "contract": {
            "stage": "M0-host-assisted-rowstream-top1",
            "notes": "Host-assisted transformer hidden-state generation.",
        },
        "board": {"status": "PASS", "sample_count": 3},
    }


def ypcb_step_summary() -> dict:
    return {
        "artifact_name": "task6-ypcb-ddr3-inference-gate",
        "status": "PASS",
        "bdf": "0000:42:00.0",
        "lspci": "0000:42:00.0 Memory controller [0580]: Xilinx Corporation Device [10ee:0480]",
        "steps": [
            {
                "name": "tinystories-inference",
                "payload": {
                    "top1": {
                        "samples": [
                            {"ddr3_readback_top1_token": 1},
                            {"ddr3_readback_top1_token": 2},
                            {"ddr3_readback_top1_token": 3},
                        ],
                        "status": "PASS",
                    },
                },
            }
        ],
    }


def ypcb_step_summary_no_contract() -> dict:
    return {
        "artifact_name": "task6-ypcb-ddr3-inference-gate",
        "status": "PASS",
        "bdf": "0000:42:00.0",
        "lspci": "0000:42:00.0 Memory controller [0580]: Xilinx Corporation Device [10ee:0480]",
        "steps": [
            {
                "name": "tinystories-inference",
                "payload": {
                    "top1": {
                        "samples": [
                            {"ddr3_readback_top1_token": 1},
                            {"top1_token": 2},
                        ],
                        "status": "PASS",
                    },
                },
            }
        ],
    }


def ypcb_step_summary_without_passing_top1() -> dict:
    return {
        "artifact_name": "task6-ypcb-ddr3-inference-gate",
        "status": "PASS",
        "bdf": "0000:42:00.0",
        "lspci": "0000:42:00.0 Memory controller [0580]: Xilinx Corporation Device [10ee:0480]",
        "steps": [
            {
                "name": "tinystories-inference",
                "payload": {
                    "top1": {
                        "samples": [],
                        "status": "PASS",
                    },
                },
            }
        ],
    }


def test_live_board_summary_can_build_passing_m3_artifact() -> None:
    artifact = build_board_artifact(
        manifest(),
        live_board_summary(),
        Path("/tmp/manifest.json"),
        Path("/tmp/board.json"),
    )
    assert artifact["status"] == "PASS"
    assert artifact["closes_m3"] is True
    assert artifact["m3_audit_failures"] == []
    assert audit_payload("M3", artifact) == []


def test_ypcb_step_summary_can_build_passing_m3_artifact() -> None:
    artifact = build_board_artifact(
        manifest(),
        ypcb_step_summary(),
        Path("/tmp/manifest.json"),
        Path("/tmp/board.json"),
    )
    assert artifact["status"] == "PASS"
    assert artifact["board"]["board_tokens"] == [1, 2, 3]
    assert artifact["closes_m3"] is True
    assert artifact["m3_audit_failures"] == []


def test_ypcb_step_summary_without_contract_can_build_passing_m3_artifact() -> None:
    artifact = build_board_artifact(
        manifest(),
        ypcb_step_summary_no_contract(),
        Path("/tmp/manifest.json"),
        Path("/tmp/board.json"),
    )
    assert artifact["status"] == "PASS"
    assert artifact["closes_m3"] is True
    assert artifact["board"]["generated_tokens"] == [1, 2]


def test_ypcb_step_summary_without_passing_top1_cannot_close_m3() -> None:
    artifact = build_board_artifact(
        manifest(),
        ypcb_step_summary_without_passing_top1(),
        Path("/tmp/manifest.json"),
        Path("/tmp/board.json"),
    )
    assert artifact["status"] == "FAIL"
    assert artifact["closes_m3"] is False
    assert any(
        "live_compute=true" in failure or "do not match" in failure
        for failure in artifact["m3_audit_failures"]
    )


def test_ypcb_step_summary_failing_status_cannot_close_m3() -> None:
    summary = ypcb_step_summary_no_contract()
    summary["status"] = "FAIL"
    artifact = build_board_artifact(
        manifest(),
        summary,
        Path("/tmp/manifest.json"),
        Path("/tmp/board.json"),
    )
    assert artifact["status"] == "FAIL"
    assert artifact["closes_m3"] is False
    assert any("board status" in failure for failure in artifact["m3_audit_failures"])


def test_ypcb_step_summary_with_zero_token_can_build_passing_m3_artifact() -> None:
    zero_case = ypcb_step_summary()
    zero_case["steps"][0]["payload"]["top1"]["samples"][0]["ddr3_readback_top1_token"] = 0
    artifact = build_board_artifact(
        manifest(),
        zero_case,
        Path("/tmp/manifest.json"),
        Path("/tmp/board.json"),
    )
    assert artifact["status"] == "PASS"
    assert artifact["board"]["generated_tokens"][:1] == [0]


def test_mismatched_tokens_fail_m3_artifact() -> None:
    artifact = build_board_artifact(
        manifest(),
        live_board_summary([1, 4, 3]),
        Path("/tmp/manifest.json"),
        Path("/tmp/board.json"),
    )
    assert artifact["status"] == "FAIL"
    assert artifact["closes_m3"] is False
    assert any("do not match" in failure for failure in artifact["m3_audit_failures"])


def test_build_artifact_carries_model_and_tokenizer_provenance() -> None:
    artifact = build_board_artifact(
        manifest(),
        live_board_summary(),
        Path("/tmp/manifest.json"),
        Path("/tmp/board.json"),
    )
    assert artifact["source"]["model_path"] == "/nix/store/frozen-model"
    assert artifact["source"]["adapter_path"] == "/nix/store/frozen-adapter.py"
    assert artifact["source"]["tokenizer"] == "GPT-Neo/GPT-2 BPE"


def test_host_assisted_top1_summary_cannot_close_m3() -> None:
    artifact = build_board_artifact(
        manifest(),
        host_assisted_summary(),
        Path("/tmp/manifest.json"),
        Path("/tmp/board.json"),
    )
    assert artifact["status"] == "FAIL"
    assert artifact["closes_m3"] is False
    assert any("live_compute=true" in failure for failure in artifact["m3_audit_failures"])
    assert any("all_blocks=true" in failure for failure in artifact["m3_audit_failures"])


def test_main_writes_failure_for_host_assisted_summary() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        tmpdir = Path(tmp)
        manifest_json = tmpdir / "manifest.json"
        board_json = tmpdir / "board.json"
        out_json = tmpdir / "m3-artifact.json"
        manifest_json.write_text(json.dumps(manifest()) + "\n", encoding="utf-8")
        board_json.write_text(json.dumps(host_assisted_summary()) + "\n", encoding="utf-8")

        import sys

        old_argv = sys.argv
        try:
            sys.argv = [
                "task6_m3_board_artifact.py",
                "--manifest-json",
                str(manifest_json),
                "--board-summary-json",
                str(board_json),
                "--out-json",
                str(out_json),
                "--json-only",
            ]
            with contextlib.redirect_stdout(io.StringIO()):
                assert main() == 1
        finally:
            sys.argv = old_argv
        payload = json.loads(out_json.read_text(encoding="utf-8"))
        assert payload["status"] == "FAIL"


def main_test() -> None:
    test_live_board_summary_can_build_passing_m3_artifact()
    test_ypcb_step_summary_can_build_passing_m3_artifact()
    test_ypcb_step_summary_without_contract_can_build_passing_m3_artifact()
    test_ypcb_step_summary_without_passing_top1_cannot_close_m3()
    test_ypcb_step_summary_failing_status_cannot_close_m3()
    test_ypcb_step_summary_with_zero_token_can_build_passing_m3_artifact()
    test_mismatched_tokens_fail_m3_artifact()
    test_host_assisted_top1_summary_cannot_close_m3()
    test_build_artifact_carries_model_and_tokenizer_provenance()
    test_main_writes_failure_for_host_assisted_summary()


if __name__ == "__main__":
    main_test()
