#!/usr/bin/env python3
"""Unit checks for the zero-to-one reference lock builder."""

from __future__ import annotations

import json
from pathlib import Path
import tempfile

from task6_zero_to_one_reference_lock import (
    build_payload,
    validate_reference_payload,
    resolve_model_snapshot,
    resolve_tokenizer_artifacts,
)


def write_minimal_reference_vector(path: Path) -> None:
    payload = {
        "steps": [{"step": 0}],
        "generation": {"q024_generated_token_ids": [0]},
    }
    path.write_text(json.dumps(payload, sort_keys=True), encoding="utf-8")


def test_build_payload_includes_every_required_family(tmp_path: Path) -> None:
    root = tmp_path / "repo"
    root.mkdir(parents=True, exist_ok=True)
    model_snapshot = root / "snapshot.bin"
    model_snapshot.write_bytes(b"snapshot")
    model_adapter = root / "model_adapter.py"
    model_adapter.write_text("print('adapter')", encoding="utf-8")
    tokenizer_vocab = root / "vocab.json"
    tokenizer_vocab.write_text("{}", encoding="utf-8")
    tokenizer_merges = root / "merges.txt"
    tokenizer_merges.write_text("", encoding="utf-8")
    reference_json = root / "reference.json"
    write_minimal_reference_vector(reference_json)
    weight_manifest = root / "weight.json"
    weight_manifest.write_text("{}", encoding="utf-8")
    test_vector = root / "vector.json"
    write_minimal_reference_vector(test_vector)
    unit_test = root / "test_tmp.py"
    unit_test.write_text("def test_ok():\n    assert True\n", encoding="utf-8")

    payload = build_payload(
        root=root,
        model_snapshot=model_snapshot,
        model_snapshot_type="pytorch-bin",
        model_snapshot_extra={},
        model_adapter=model_adapter,
        tokenizer_vocab=tokenizer_vocab,
        tokenizer_merges=tokenizer_merges,
        reference_json=reference_json,
        weight_manifests=[weight_manifest],
        test_vectors=[test_vector],
        unit_tests=[unit_test],
        locked_scripts=[
            str((Path(__file__).resolve().parent / "task6_zero_to_one_inventory.py").resolve()),
            str((Path(__file__).resolve().parent / "task6_zero_to_one_guard.py").resolve()),
        ],
        lock_tag="test-lock",
        artifact_name="test-zero-to-one-reference-lock",
    )

    assert payload["schema_version"] == 1
    assert payload["status"] == "LOCKED"
    assert payload["artifact_name"] == "test-zero-to-one-reference-lock"
    assert payload["references"]["model_snapshot"]["path"] == str(model_snapshot)
    assert payload["references"]["model_snapshot"]["type"] == "pytorch-bin"
    assert payload["references"]["model_adapter"]["type"] == "python"
    assert len(payload["weight_manifests"]) == 1
    assert payload["weight_manifests"][0]["kind"] == "weight-manifest"
    assert len(payload["test_vectors"]) == 1
    assert len(payload["unit_tests"]) == 1
    assert payload["governance"]["locked_scripts"][0]["kind"] == "governance-script"


def test_build_payload_supports_manifest_fallback(tmp_path: Path) -> None:
    root = tmp_path / "repo"
    root.mkdir(parents=True, exist_ok=True)
    missing_snapshot = root / "snapshot.bin"
    manifest = root / "manifest.json"
    manifest.write_text(
        json.dumps(
            {
                "model_path": str(missing_snapshot),
                "config": {"_name_or_path": str(missing_snapshot)},
            },
            sort_keys=True,
        ),
        encoding="utf-8",
    )
    model_adapter = root / "model_adapter.py"
    model_adapter.write_text("print('adapter')", encoding="utf-8")
    tokenizer_vocab = root / "vocab.json"
    tokenizer_vocab.write_text("{}", encoding="utf-8")
    tokenizer_merges = root / "merges.txt"
    tokenizer_merges.write_text("", encoding="utf-8")
    reference_json = root / "reference.json"
    write_minimal_reference_vector(reference_json)
    weight_manifest = root / "weight.json"
    weight_manifest.write_text("{}", encoding="utf-8")
    test_vector = root / "vector.json"
    write_minimal_reference_vector(test_vector)

    resolved_snapshot, resolved_type, resolved_extra = resolve_model_snapshot(
        root, missing_snapshot, manifest
    )
    assert resolved_snapshot == manifest
    assert resolved_type == "pytorch-manifest"
    assert resolved_extra == {"snapshot_source_path": str(missing_snapshot)}

    payload = build_payload(
        root=root,
        model_snapshot=resolved_snapshot,
        model_snapshot_type=resolved_type,
        model_snapshot_extra=resolved_extra,
        model_adapter=model_adapter,
        tokenizer_vocab=tokenizer_vocab,
        tokenizer_merges=tokenizer_merges,
        reference_json=reference_json,
        weight_manifests=[weight_manifest],
        test_vectors=[test_vector],
        unit_tests=[],
        locked_scripts=[],
        lock_tag="test-lock",
        artifact_name="test-zero-to-one-reference-lock",
    )

    assert payload["references"]["model_snapshot"]["path"] == str(manifest)
    assert payload["references"]["model_snapshot"]["type"] == "pytorch-manifest"
    assert (
        payload["references"]["model_snapshot"]["snapshot_source_path"]
        == str(missing_snapshot)
    )


def test_resolve_model_snapshot_defaults_to_manifest_when_none(tmp_path: Path) -> None:
    manifest = tmp_path / "manifest.json"
    manifest.write_text(
        json.dumps({"model_path": "/nix/store/missing-snapshot"}, sort_keys=True),
        encoding="utf-8",
    )

    snapshot, snapshot_type, snapshot_extra = resolve_model_snapshot(
        tmp_path, None, manifest
    )
    assert snapshot == manifest
    assert snapshot_type == "pytorch-manifest"
    assert snapshot_extra == {"snapshot_source_path": "/nix/store/missing-snapshot"}


def test_resolve_tokenizer_artifacts_prefers_snapshot_root(tmp_path: Path) -> None:
    root = tmp_path / "repo"
    root.mkdir()

    missing_snapshot = root / "missing.snapshot"
    source_snapshot = root / "snapshot"
    source_snapshot.mkdir()
    vocab = source_snapshot / "vocab.json"
    merges = source_snapshot / "merges.txt"
    vocab.write_text("{}", encoding="utf-8")
    merges.write_text("", encoding="utf-8")
    manifest = root / "manifest.json"
    manifest.write_text(
        json.dumps({"model_path": str(missing_snapshot), "config": {"_name_or_path": str(missing_snapshot)}}, sort_keys=True),
        encoding="utf-8",
    )

    snapshot, snapshot_type, snapshot_extra = resolve_model_snapshot(
        root,
        missing_snapshot,
        manifest,
    )
    assert snapshot == manifest
    assert snapshot_type == "pytorch-manifest"
    snapshot_extra = {"snapshot_source_path": str(source_snapshot)}

    resolved_vocab, resolved_merges = resolve_tokenizer_artifacts(
        root,
        snapshot,
        snapshot_extra,
        tokenizer_vocab=None,
        tokenizer_merges=None,
    )
    # Because there is no explicit override, use explicit source snapshot path.
    assert resolved_vocab == vocab
    assert resolved_merges == merges


def test_resolve_tokenizer_artifacts_prefers_tokenizer_subdir(tmp_path: Path) -> None:
    root = tmp_path / "repo"
    root.mkdir()

    snapshot = root / "snapshot"
    tokenizer_dir = snapshot / "tokenizer"
    tokenizer_dir.mkdir(parents=True)
    vocab = tokenizer_dir / "vocab.json"
    merges = tokenizer_dir / "merges.txt"
    vocab.write_text("{}", encoding="utf-8")
    merges.write_text("", encoding="utf-8")

    resolved_vocab, resolved_merges = resolve_tokenizer_artifacts(
        root,
        snapshot,
        {},
        tokenizer_vocab=None,
        tokenizer_merges=None,
    )
    assert resolved_vocab == vocab
    assert resolved_merges == merges


def test_validate_reference_payload_requires_step_schema(tmp_path: Path) -> None:
    invalid_vector = tmp_path / "invalid.json"
    invalid_vector.write_text("{}", encoding="utf-8")
    try:
        validate_reference_payload(invalid_vector)
        raise AssertionError("expected validate_reference_payload to reject invalid schema")
    except SystemExit:
        pass


def test_resolve_tokenizer_artifacts_requires_both_explicit_args(tmp_path: Path) -> None:
    root = tmp_path / "repo"
    root.mkdir()
    vocab = root / "vocab.json"
    merges = root / "merges.txt"
    vocab.write_text("{}", encoding="utf-8")

    try:
        resolve_tokenizer_artifacts(root, root, {}, tokenizer_vocab=vocab, tokenizer_merges=None)
        raise AssertionError("Expected resolve_tokenizer_artifacts to reject partial tokenizer args")
    except SystemExit as exc:
        assert "--tokenizer-merges" in str(exc)


if __name__ == "__main__":
    tests = (
        test_build_payload_includes_every_required_family,
        test_build_payload_supports_manifest_fallback,
        test_resolve_model_snapshot_defaults_to_manifest_when_none,
        test_resolve_tokenizer_artifacts_prefers_snapshot_root,
        test_resolve_tokenizer_artifacts_prefers_tokenizer_subdir,
        test_validate_reference_payload_requires_step_schema,
        test_resolve_tokenizer_artifacts_requires_both_explicit_args,
    )
    for test_case in tests:
        with tempfile.TemporaryDirectory() as workdir:
            test_case(Path(workdir))
