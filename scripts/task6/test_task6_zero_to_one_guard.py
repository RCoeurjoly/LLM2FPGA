#!/usr/bin/env python3
"""Unit checks for the zero-to-one reference guard."""

from __future__ import annotations

import hashlib
import tempfile
from pathlib import Path

from task6_zero_to_one_guard import verify_lock_payload


def make_lock_payload(root: Path) -> dict:
    sample = root / "data"
    sample.write_text("{}", encoding="utf-8")
    return {
        "schema_version": 1,
        "artifact_name": "task6-zero-to-one-reference-lock",
        "status": "LOCKED",
        "lock_tag": "test-v1",
        "repo": {"root": str(root), "branch": "", "commit": ""},
        "references": {
            "model_snapshot": {
                "path": str(sample),
                "sha256": "bad"  # overwritten in test
            },
            "model_adapter": {"path": str(sample), "sha256": "bad", "type": "python"},
            "tokenizer": {
                "vocab": {"path": str(sample), "sha256": "bad"},
                "merges": {"path": str(sample), "sha256": "bad"},
            },
            "reference_json": {"path": str(sample), "sha256": "bad", "kind": "reference-payload"},
        },
        "weight_manifests": [
            {"kind": "weight-manifest", "path": str(sample), "sha256": "bad"}
        ],
        "test_vectors": [
            {"kind": "test-vector", "path": str(sample), "sha256": "bad"}
        ],
        "unit_tests": [],
        "governance": {
            "locked_scripts": [
                {"kind": "governance-script", "path": str(sample), "sha256": "bad"}
            ],
            "anti_reward_hacking_notes": [],
        },
    }


def test_guard_reports_hash_mismatch(tmp_path: Path) -> None:
    payload = make_lock_payload(tmp_path)
    payload["references"]["model_snapshot"]["sha256"] = "0000"
    failures: list[str] = []
    verify_lock_payload(payload, failures)
    assert any("hash mismatch" in failure for failure in failures)


def test_guard_accepts_consistent_lock(tmp_path: Path) -> None:
    sample = tmp_path / "data"
    sample.write_text("{}", encoding="utf-8")
    digest = hashlib.sha256(sample.read_bytes()).hexdigest()
    payload = {
        "schema_version": 1,
        "artifact_name": "task6-zero-to-one-reference-lock",
        "status": "LOCKED",
        "repo": {"root": str(tmp_path), "branch": "", "commit": ""},
        "references": {
            "model_snapshot": {
                "path": "data",
                "sha256": digest,
            },
            "model_adapter": {"path": "data", "sha256": digest, "type": "python"},
            "tokenizer": {
                "vocab": {"path": "data", "sha256": digest},
                "merges": {"path": "data", "sha256": digest},
            },
            "reference_json": {"path": "data", "sha256": digest, "kind": "reference-payload"},
        },
        "weight_manifests": [
            {"kind": "weight-manifest", "path": "data", "sha256": digest}
        ],
        "test_vectors": [
            {"kind": "test-vector", "path": "data", "sha256": digest}
        ],
        "unit_tests": [],
        "governance": {
            "locked_scripts": [
                {"kind": "governance-script", "path": "data", "sha256": digest}
            ],
            "anti_reward_hacking_notes": [],
        },
    }
    for section in (
        payload["references"]["model_snapshot"],
        payload["references"]["model_adapter"],
        payload["references"]["tokenizer"]["vocab"],
        payload["references"]["tokenizer"]["merges"],
        payload["references"]["reference_json"],
        payload["weight_manifests"][0],
        payload["test_vectors"][0],
        payload["governance"]["locked_scripts"][0],
    ):
        section["sha256"] = digest

    failures: list[str] = []
    verify_lock_payload(payload, failures)
    assert not failures


def test_guard_requires_weight_manifests_and_vectors(tmp_path: Path) -> None:
    payload = make_lock_payload(tmp_path)
    payload["weight_manifests"] = []
    payload["test_vectors"] = []
    failures: list[str] = []
    verify_lock_payload(payload, failures)
    assert any("must contain at least one artifact" in failure for failure in failures)


def main_test() -> None:
    with tempfile.TemporaryDirectory() as tmpdir:
        tmp_path = Path(tmpdir)
        payload = make_lock_payload(tmp_path)
        payload["references"]["model_snapshot"]["sha256"] = "0000"
        failures: list[str] = []
        verify_lock_payload(payload, failures)
        assert any("hash mismatch" in failure for failure in failures)

        sample = tmp_path / "data"
        sample.write_text("{}", encoding="utf-8")
        digest = hashlib.sha256(sample.read_bytes()).hexdigest()
        payload = {
            "schema_version": 1,
            "artifact_name": "task6-zero-to-one-reference-lock",
            "status": "LOCKED",
            "repo": {"root": str(tmp_path), "branch": "", "commit": ""},
            "references": {
                "model_snapshot": {
                    "path": "data",
                    "sha256": digest,
                },
                "model_adapter": {"path": "data", "sha256": digest, "type": "python"},
                "tokenizer": {
                    "vocab": {"path": "data", "sha256": digest},
                    "merges": {"path": "data", "sha256": digest},
                },
                "reference_json": {
                    "path": "data",
                    "sha256": digest,
                    "kind": "reference-payload",
                },
            },
            "weight_manifests": [{"kind": "weight-manifest", "path": "data", "sha256": digest}],
            "test_vectors": [{"kind": "test-vector", "path": "data", "sha256": digest}],
            "unit_tests": [],
            "governance": {
                "locked_scripts": [{"kind": "governance-script", "path": "data", "sha256": digest}],
                "anti_reward_hacking_notes": [],
            },
        }
        failures = []
        verify_lock_payload(payload, failures)
        assert not failures


if __name__ == "__main__":
    main_test()
