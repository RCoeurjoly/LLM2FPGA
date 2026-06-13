#!/usr/bin/env python3
"""Unit checks for the Task 6 M3 reference manifest builder."""

from __future__ import annotations

import contextlib
import io
import json
import tempfile
from pathlib import Path

from task6_m3_reference_manifest import build_manifest, main
from task6_milestone_evidence_audit import audit_payload


def reference_payload() -> dict:
    return {
        "artifact_name": "reference",
        "status": "PASS",
        "coverage": {"transformer": "PyTorch f32"},
        "model": {
            "model_path": "/nix/store/model",
            "adapter_path": "/repo/TinyStories/model_adapter.py",
            "vocab_size": 50257,
            "hidden_size": 64,
        },
        "quantization": {"scale": "unsigned Q0.24 row sidecar"},
        "prompt": {
            "text": "Once upon a time",
            "token_ids": [10, 11, 12],
        },
        "generation": {
            "max_new_tokens": 2,
            "q024_generated_token_ids": [13, 14],
            "q024_decoded_text": "Once upon a time there was",
        },
        "steps": [{"step": 0}, {"step": 1}],
    }


def test_manifest_pins_m3_reference_without_claiming_board_pass() -> None:
    manifest = build_manifest(reference_payload(), Path("/tmp/reference.json"), "TinyStories-1M")
    assert manifest["artifact_name"] == "task6-m3-reference-manifest"
    assert manifest["closes_m3"] is False
    assert manifest["contract"]["milestone_target"] == "M3-full-tinystories-1m"
    assert manifest["contract"]["stage"] == "M3-reference-target"
    assert manifest["contract"]["live_compute"] is False
    assert manifest["contract"]["all_blocks"] is False
    assert manifest["input"]["prompt_token_ids"] == [10, 11, 12]
    assert manifest["reference"]["generated_tokens"] == [13, 14]
    assert manifest["board"]["status"] == "NOT_RUN"


def test_manifest_is_rejected_as_m3_completion_evidence() -> None:
    manifest = build_manifest(reference_payload(), Path("/tmp/reference.json"), "TinyStories-1M")
    failures = audit_payload("M3", manifest)
    assert any("M3-full-tinystories-1m" in failure for failure in failures)
    assert any("live_compute=true" in failure for failure in failures)
    assert any("all_blocks=true" in failure for failure in failures)
    assert any("board status" in failure for failure in failures)


def test_main_writes_manifest() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        tmpdir = Path(tmp)
        reference_json = tmpdir / "reference.json"
        out_json = tmpdir / "manifest.json"

        reference_json.write_text(json.dumps(reference_payload()) + "\n", encoding="utf-8")
        import sys

        old_argv = sys.argv
        try:
            sys.argv = [
                "task6_m3_reference_manifest.py",
                "--reference-json",
                str(reference_json),
                "--out-json",
                str(out_json),
                "--json-only",
            ]
            with contextlib.redirect_stdout(io.StringIO()):
                assert main() == 0
        finally:
            sys.argv = old_argv
        assert out_json.exists()


def main_test() -> None:
    test_manifest_pins_m3_reference_without_claiming_board_pass()
    test_manifest_is_rejected_as_m3_completion_evidence()
    test_main_writes_manifest()


if __name__ == "__main__":
    main_test()
