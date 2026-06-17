#!/usr/bin/env python3
"""Unit checks for zero-to-one inference parity orchestration."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import tempfile
from pathlib import Path
from types import SimpleNamespace
from subprocess import CompletedProcess

from task6_zero_to_one_inference_gate import (
    run_guard,
    run_single_vector,
    ParityError,
    validate_reference_vector,
    summarize_gate_summary,
)
import task6_zero_to_one_inference_gate as inference_gate


def hash_hex(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def make_locked_payload(root: Path) -> dict:
    sample = root / "artifacts/task6/zero-to-one/sample.json"
    sample.parent.mkdir(parents=True, exist_ok=True)
    sample.write_text("{}", encoding="utf-8")
    digest = hash_hex(sample)
    return {
        "schema_version": 1,
        "artifact_name": "task6-zero-to-one-reference-lock",
        "status": "LOCKED",
        "lock_tag": "unit-test",
        "repo": {"root": str(root), "branch": "", "commit": ""},
        "references": {
            "model_snapshot": {"path": str(sample), "sha256": digest, "type": "pytorch-bin"},
            "model_adapter": {"path": str(sample), "sha256": digest, "type": "python"},
            "tokenizer": {
                "vocab": {"path": str(sample), "sha256": digest},
                "merges": {"path": str(sample), "sha256": digest},
            },
            "reference_json": {"path": str(sample), "sha256": digest, "kind": "reference-payload"},
        },
        "weight_manifests": [
            {"kind": "weight-manifest", "path": str(sample), "sha256": digest},
        ],
        "test_vectors": [
            {"kind": "test-vector", "path": str(sample), "sha256": digest},
        ],
        "unit_tests": [],
        "governance": {
            "locked_scripts": [
                {"kind": "governance-script", "path": str(sample), "sha256": digest},
            ],
            "anti_reward_hacking_notes": [],
        },
        "rules": ["require-digest-match"],
    }


def test_summarize_gate_summary_detects_failure() -> None:
    status, mismatch_count, sample_count, failures, sample_failures = summarize_gate_summary(
        {
            "status": "FAIL",
            "validation": {"mismatch_count": 1},
            "samples": [
                {
                    "sample_id": 0,
                    "matches_token": True,
                    "matches_score_low32": False,
                    "matches_rows_scanned": True,
                    "no_top1_error": None,
                }
            ],
        }
    )
    assert status == "FAIL"
    assert mismatch_count == 1
    assert sample_count == 1
    assert sample_failures
    assert len(failures) == 2
    assert "mismatch_count=1" in failures[0]


def test_run_guard_validates_lock() -> None:
    payload = make_locked_payload(Path("/tmp"))
    failures = run_guard(
        payload,
        argparse.Namespace(
            guard=False,
            guard_only=False,
            skip_inventory=True,
            run_tests=False,
            python="python3",
        ),
    )
    assert not failures


def test_run_single_vector_parses_top1_summary(tmp_path: Path) -> None:
    root = tmp_path / "repo"
    root.mkdir(exist_ok=True)
    vector = root / "vector.json"
    vector.write_text(
        json.dumps(
            {
                "steps": [{"a": 1}],
                "generation": {"q024_generated_token_ids": [7]},
            }
        ),
        encoding="utf-8",
    )

    original_run_gate = inference_gate.run_gate_command

    def fake_run_gate_command(
        gate_path: Path,
        lock_root: Path,
        test_vector_path: Path,
        out_json: Path,
        args: argparse.Namespace,
        python: str,
    ) -> CompletedProcess[str]:
        del gate_path, lock_root, args, python
        out_json.parent.mkdir(parents=True, exist_ok=True)
        out_json.write_text(
            json.dumps(
                {
                    "status": "PASS",
                    "validation": {"mismatch_count": 0},
                    "samples": [
                        {
                            "sample_id": 0,
                            "matches_token": True,
                            "matches_score_low32": True,
                            "matches_rows_scanned": True,
                            "no_top1_error": True,
                        }
                    ],
                }
            ),
            encoding="utf-8",
        )
        return CompletedProcess(args=["top1-gate"], returncode=0, stdout="", stderr="")

    inference_gate.run_gate_command = fake_run_gate_command
    try:
        args = SimpleNamespace(
            image=None,
            contract_json=None,
            replay_json=None,
            top1_timeout=1.0,
            top1_retries=0,
            boot_timeout=1.0,
            poll_timeout=1.0,
            packet_ack_mode="auto",
            packet_settle=0.0,
            verify_samples=1,
            simulate=False,
            load_image=True,
            bdf="0000:42:00.0",
        )
        vector_run = run_single_vector(
            lock_root=root,
            gate_path=tmp_path / "fake_gate.py",
            vector_entry={"path": str(vector), "sha256": hash_hex(vector)},
            run_dir=tmp_path / "run",
            python="python3",
            args=args,
        )
        assert vector_run.status == "PASS"
        assert vector_run.mismatch_count == 0
        assert vector_run.sample_count == 1
    finally:
        inference_gate.run_gate_command = original_run_gate


def test_run_single_vector_fails_on_invalid_gate_summary(tmp_path: Path) -> None:
    root = tmp_path / "repo"
    root.mkdir(exist_ok=True)
    vector = root / "vector.json"
    vector.write_text(
        json.dumps(
            {
                "steps": [{"a": 1}],
                "generation": {"q024_generated_token_ids": [7]},
            }
        ),
        encoding="utf-8",
    )

    original_run_gate = inference_gate.run_gate_command

    def fake_run_gate_command(
        gate_path: Path,
        lock_root: Path,
        test_vector_path: Path,
        out_json: Path,
        args: argparse.Namespace,
        python: str,
    ) -> CompletedProcess[str]:
        del gate_path, lock_root, test_vector_path, args, python
        out_json.parent.mkdir(parents=True, exist_ok=True)
        out_json.write_text("not json", encoding="utf-8")
        return CompletedProcess(args=["top1-gate"], returncode=0, stdout="", stderr="")

    inference_gate.run_gate_command = fake_run_gate_command
    try:
        args = SimpleNamespace(
            image=None,
            contract_json=None,
            replay_json=None,
            top1_timeout=1.0,
            top1_retries=0,
            boot_timeout=1.0,
            poll_timeout=1.0,
            packet_ack_mode="auto",
            packet_settle=0.0,
            verify_samples=1,
            simulate=False,
            load_image=True,
            bdf="0000:42:00.0",
        )
        vector_run = run_single_vector(
            lock_root=root,
            gate_path=tmp_path / "fake_gate.py",
            vector_entry={"path": str(vector), "sha256": hash_hex(vector)},
            run_dir=tmp_path / "run",
            python="python3",
            args=args,
        )
        assert vector_run.status == "FAIL"
        assert any("parse failed" in item.lower() for item in vector_run.failures)
    finally:
        inference_gate.run_gate_command = original_run_gate


def test_run_single_vector_simulates_top1_summary(tmp_path: Path) -> None:
    root = tmp_path / "repo"
    root.mkdir(exist_ok=True)
    vector = root / "vector.json"
    generation = [13, 14, 15]
    vector.write_text(
        json.dumps(
            {
                "steps": [{"a": 1}, {"a": 2}, {"a": 3}],
                "generation": {"q024_generated_token_ids": generation},
            }
        ),
        encoding="utf-8",
    )

    args = SimpleNamespace(
        image=None,
        contract_json=None,
        replay_json=None,
        top1_timeout=1.0,
        top1_retries=0,
        boot_timeout=1.0,
        poll_timeout=1.0,
        packet_ack_mode="auto",
        packet_settle=0.0,
        verify_samples=2,
        simulate=True,
        load_image=True,
        bdf="0000:42:00.0",
    )
    vector_run = run_single_vector(
        lock_root=root,
        gate_path=tmp_path / "fake_gate.py",
        vector_entry={"path": str(vector), "sha256": hash_hex(vector)},
        run_dir=tmp_path / "run",
        python="python3",
        args=args,
    )
    assert vector_run.status == "PASS"
    assert vector_run.sample_count == 2
    assert vector_run.summary["simulated"] is True
    assert vector_run.summary["samples"][0]["top1_token"] == generation[0]


def test_validate_reference_vector_rejects_rowwise_replay_schema(tmp_path: Path) -> None:
    vector = tmp_path / "rowwise.json"
    vector.write_text(
        json.dumps(
            {
                "samples": [
                    {
                        "position": 0,
                        "token_ids": [1, 2, 3],
                        "rowwise_q024_top5": [10, 20, 30],
                    }
                ],
            }
        ),
        encoding="utf-8",
    )
    try:
        validate_reference_vector(vector)
        raise AssertionError("expected validate_reference_vector to reject rowwise schema")
    except ParityError:
        pass


def test_main_guard_only_writes_artifact() -> None:
    with tempfile.TemporaryDirectory() as tmpdir:
        root = Path(tmpdir)
        lock = make_locked_payload(root)
        lock_path = root / "artifacts/zero-to-one/reference-lock.json"
        lock_path.parent.mkdir(parents=True, exist_ok=True)
        lock_path.write_text(json.dumps(lock), encoding="utf-8")
        out_json = root / "artifacts/zero-to-one/guard-only.json"

        original_argv = sys.argv
        try:
            sys.argv = [
                "task6_zero_to_one_inference_gate.py",
                "--lock-json",
                str(lock_path),
                "--guard-only",
                "--skip-inventory",
                "--out-json",
                str(out_json),
            ]
            rc = inference_gate.main()
        finally:
            sys.argv = original_argv

        assert rc == 0
        payload = json.loads(out_json.read_text(encoding="utf-8"))
        assert payload["status"] == "PASS"


def main() -> None:
    with tempfile.TemporaryDirectory() as tmpdir:
        tmp_path = Path(tmpdir)
        test_summarize_gate_summary_detects_failure()
        test_run_guard_validates_lock()
        test_run_single_vector_parses_top1_summary(tmp_path)
        test_run_single_vector_fails_on_invalid_gate_summary(tmp_path)
        test_run_single_vector_simulates_top1_summary(tmp_path)
        test_validate_reference_vector_rejects_rowwise_replay_schema(tmp_path)
        test_main_guard_only_writes_artifact()


if __name__ == "__main__":
    main()
