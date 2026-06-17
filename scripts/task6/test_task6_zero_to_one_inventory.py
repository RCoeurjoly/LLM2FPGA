#!/usr/bin/env python3
"""Unit tests for inventory classification and lock output shape."""

from __future__ import annotations

from tempfile import TemporaryDirectory
import argparse
import json
from pathlib import Path

from task6_zero_to_one_inventory import classify, collect_files, build_inventory, DEFAULT_KEEP_GLOBS


def test_classification_prefers_remove_before_keep() -> None:
    path = "artifacts/task6/runs/session/reference.json"
    keep = ["artifacts/task6/**"]
    remove = ["artifacts/task6/runs/**"]
    quarantine: list[str] = []
    assert classify(path, keep, remove, quarantine) == "remove"


def test_collect_files_and_inventory_can_build(tmp_path: Path) -> None:
    root = tmp_path / "repo"
    root.mkdir(parents=True, exist_ok=True)
    (root / "a.txt").write_text("hello", encoding="utf-8")
    (root / "artifacts").mkdir()
    (root / "artifacts" / "note.txt").write_text("x", encoding="utf-8")
    items = collect_files(root, max_depth=4)
    assert len(items) == 2

    entries = build_inventory(
        root,
        ["*.txt", "artifacts/**"],
        ["artifacts/**"],
        ["artifacts/task6/runs/**"],
        max_depth=4,
    )
    paths = {entry.path for entry in entries}
    assert "a.txt" in paths
    assert "artifacts/note.txt" in paths
    by_path = {entry.path: entry for entry in entries}
    assert by_path["a.txt"].category in {"keep", "unknown"}
    assert by_path["artifacts/note.txt"].category == "remove"


def test_inventory_main_json_shape(tmp_path: Path) -> None:
    root = tmp_path / "repo"
    root.mkdir(parents=True, exist_ok=True)
    (root / "AGENTS.md").write_text("keep", encoding="utf-8")
    output = root / "artifacts" / "zero-to-one" / "inventory.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    from task6_zero_to_one_inventory import to_json_payload

    args = argparse.Namespace(
        repo_root=root,
        keep_glob=[],
        remove_glob=[],
        quarantine_glob=[],
        scan_depth=8,
        out_json=output,
    )
    payload = to_json_payload(root, output, args)

    assert payload["artifact_name"] == "task6-zero-to-one-inventory"
    assert payload["counts"]["keep"] >= 1
    assert any(item["path"] == "AGENTS.md" for item in payload["files"])
    output.write_text(json.dumps(payload), encoding="utf-8")


def test_classification_defaults_mark_known_extensions(tmp_path: Path) -> None:
    root = tmp_path / "repo"
    root.mkdir(parents=True, exist_ok=True)
    (root / "example.sv").write_text("module example; endmodule", encoding="utf-8")
    entries = build_inventory(
        root,
        DEFAULT_KEEP_GLOBS,
        [],
        [],
        max_depth=8,
    )
    assert any(item.path == "example.sv" and item.category == "keep" for item in entries)


def main_test() -> None:
    test_classification_prefers_remove_before_keep()
    with TemporaryDirectory() as tmpdir:
        workdir = Path(tmpdir)
        test_collect_files_and_inventory_can_build(workdir / "collect")
        test_inventory_main_json_shape(Path(tmpdir))


if __name__ == "__main__":
    main_test()
