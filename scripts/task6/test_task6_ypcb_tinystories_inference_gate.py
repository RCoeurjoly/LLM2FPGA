#!/usr/bin/env python3
"""Unit checks for the YPCB TinyStories inference gate wrapper."""

from __future__ import annotations

import json
import tempfile
from pathlib import Path

from task6_ypcb_tinystories_inference_gate import emit_m3_artifact


def manifest() -> dict:
    return {
        "artifact_name": "task6-m3-reference-manifest",
        "status": "PASS",
        "model": {"model_label": "TinyStories-1M", "vocab_size": 50257, "hidden_size": 64},
        "input": {"prompt": "Once upon a time", "prompt_token_ids": [10, 11]},
        "reference": {
            "prompt": "Once upon a time",
            "generated_tokens": [1, 2],
            "generated_text": "Once upon a time...",
        },
    }


def live_m3_summary() -> dict:
    return {
        "artifact_name": "task6-ypcb-ddr3-inference-gate",
        "status": "PASS",
        "bdf": "0000:42:00.0",
        "lspci": "0000:42:00.0 Memory controller [0580]: Xilinx Corporation Device [10ee:0480]",
        "contract": {
            "stage": "M3-full-tinystories-1m",
            "live_compute": True,
            "all_blocks": True,
            "notes": "Board executes all TinyStories-1M transformer blocks.",
        },
        "board_tokens": [1, 2],
    }


def test_emit_m3_artifact_writes_audited_payload() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        tmpdir = Path(tmp)
        manifest_json = tmpdir / "manifest.json"
        summary_json = tmpdir / "gate-summary.json"
        out_json = tmpdir / "m3-board-artifact.json"
        manifest_json.write_text(json.dumps(manifest()) + "\n", encoding="utf-8")
        summary = live_m3_summary()
        summary_json.write_text(json.dumps(summary) + "\n", encoding="utf-8")

        artifact = emit_m3_artifact(summary, manifest_json, summary_json, out_json)
        assert artifact["status"] == "PASS"
        assert artifact["closes_m3"] is True
        assert out_json.exists()
        written = json.loads(out_json.read_text(encoding="utf-8"))
        assert written["status"] == "PASS"
        assert written["reference"]["generated_tokens"] == [1, 2]


def main() -> None:
    test_emit_m3_artifact_writes_audited_payload()


if __name__ == "__main__":
    main()
