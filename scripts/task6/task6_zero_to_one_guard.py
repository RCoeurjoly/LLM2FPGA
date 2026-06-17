#!/usr/bin/env python3
"""Verify zero-to-one references and re-run the pinned inventory check."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
from pathlib import Path
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lock-json", type=Path, required=True)
    parser.add_argument("--out-json", type=Path)
    parser.add_argument("--run-tests", action="store_true")
    parser.add_argument("--script-python", default="python3")
    return parser.parse_args()


def run_command(
    cmd: list[str],
    *,
    cwd: Path | None = None,
    env: dict[str, str] | None = None,
) -> tuple[int, str, str]:
    p = subprocess.run(
        cmd,
        cwd=str(cwd) if cwd else None,
        capture_output=True,
        text=True,
        env=env,
        check=False,
    )
    return p.returncode, p.stdout.strip(), p.stderr.strip()


def hash_file_on_disk(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def hash_path(path: Path) -> str:
    if path.is_file():
        return hash_file_on_disk(path)
    if path.is_dir():
        digest = hashlib.sha256()
        for item in sorted(path.rglob("*"), key=lambda p: p.as_posix()):
            rel = item.relative_to(path).as_posix()
            digest.update(rel.encode("utf-8"))
            digest.update(b"\0")
            if item.is_file():
                digest.update(b"file\0")
                digest.update(hash_file_on_disk(item).encode("utf-8"))
            else:
                mode = item.lstat().st_mode
                digest.update(f"other:{mode}\0".encode("utf-8"))
            digest.update(b"\0")
        return digest.hexdigest()
    raise OSError(f"unsupported file type for hash: {path}")


def resolve_path(base: Path, value: str | os.PathLike[str]) -> Path:
    path = Path(value)
    return path if path.is_absolute() else base / path


def verify_entry(name: str, entry: dict[str, Any], failures: list[str], repo_root: Path) -> None:
    path = resolve_path(repo_root, entry.get("path", ""))
    expected = str(entry.get("sha256"))
    if not path.exists():
        failures.append(f"{name} path missing: {path}")
        return
    if "sha256" not in entry:
        failures.append(f"{name} missing sha256: {path}")
        return
    try:
        observed = hash_path(path)
    except OSError as exc:
        failures.append(f"{name} cannot hash {path}: {exc}")
        return
    if observed != expected:
        failures.append(f"{name} hash mismatch for {path}: expected {expected}, got {observed}")


def _walk_nested(entry: dict[str, Any]) -> list[dict[str, Any]]:
    nested: list[dict[str, Any]] = []
    if isinstance(entry, dict):
        if "path" in entry:
            nested.append(entry)
        else:
            for value in entry.values():
                if isinstance(value, dict):
                    nested.extend(_walk_nested(value))
    return nested


def verify_lock_payload(lock: dict[str, Any], failures: list[str]) -> None:
    repo_root = Path(lock.get("repo", {}).get("root", ".")).resolve()
    required = {
        "schema_version",
        "artifact_name",
        "status",
        "references",
        "repo",
        "weight_manifests",
        "test_vectors",
        "governance",
    }
    missing = sorted(required - set(lock))
    if missing:
        failures.append(f"lock missing required fields: {', '.join(missing)}")
    if lock.get("status") != "LOCKED":
        failures.append(f"unexpected lock status: {lock.get('status')}")
    references = lock.get("references")
    if not isinstance(references, dict):
        failures.append("references must be a dict")
        return

    required_reference_sections = ("model_snapshot", "model_adapter", "tokenizer", "reference_json")
    for section in required_reference_sections:
        entry = references.get(section)
        if not isinstance(entry, dict):
            failures.append(f"reference section missing or invalid: {section}")
            continue
        if section == "tokenizer":
            for key in ("vocab", "merges"):
                nested = entry.get(key)
                if not isinstance(nested, dict):
                    failures.append(f"reference tokenizer missing section: {key}")
                    continue
                verify_entry(f"tokenizer.{key}", nested, failures, repo_root)
            continue
        verify_entry(section, entry, failures, repo_root)

    # Backward-compatible nested walk for any historical alternate reference shapes.
    for section in required_reference_sections:
        entry = references.get(section)
        if not isinstance(entry, dict):
            continue
        for nested in _walk_nested(entry):
            if nested is entry:
                continue
            verify_entry("reference", nested, failures, repo_root)

    for key in ("weight_manifests", "test_vectors"):
        entries = lock.get(key)
        if not isinstance(entries, list):
            failures.append(f"{key} must be a list")
            continue
        if not entries:
            failures.append(f"{key} must contain at least one artifact")
        for entry in entries:
            if not isinstance(entry, dict):
                failures.append(f"{key} entry not an object: {entry}")
                continue
            verify_entry(key, entry, failures, repo_root)

    unit_tests = lock.get("unit_tests")
    if unit_tests is not None:
        if not isinstance(unit_tests, list):
            failures.append("unit_tests must be a list")
        else:
            for entry in unit_tests:
                if not isinstance(entry, dict):
                    failures.append(f"unit test entry not an object: {entry}")
                    continue
                verify_entry("unit_test", entry, failures, repo_root)

    governance = lock.get("governance")
    if not isinstance(governance, dict):
        failures.append("governance must be a dict")
    else:
        locked_scripts = governance.get("locked_scripts")
        if not isinstance(locked_scripts, list):
            failures.append("governance.locked_scripts must be a list")
        elif not locked_scripts:
            failures.append("governance.locked_scripts must contain at least one entry")
        for entry in (locked_scripts or []):
            if not isinstance(entry, dict):
                failures.append(f"governance script entry invalid: {entry}")
                continue
            verify_entry("governance-script", entry, failures, repo_root)


def verify_inventory(lock: dict[str, Any], failures: list[str], script_python: str) -> None:
    repo_root = Path(lock["repo"]["root"]).resolve()
    if not repo_root.exists():
        failures.append(f"repo root missing for inventory rerun: {repo_root}")
        return

    inventory_script = repo_root / "scripts" / "task6" / "task6_zero_to_one_inventory.py"
    if not inventory_script.exists():
        failures.append("inventory script missing")
        return
    inventory_out = repo_root / "artifacts" / "zero-to-one" / "inventory" / "runtime.json"
    inventory_out.parent.mkdir(parents=True, exist_ok=True)
    rc, _, stderr = run_command(
        [
            script_python,
            str(inventory_script),
            "--repo-root",
            str(repo_root),
            "--out-json",
            str(inventory_out),
        ],
    )
    if rc != 0:
        failures.append(f"inventory command failed: {stderr}")
        return
    try:
        inventory_payload = json.loads(inventory_out.read_text(encoding="utf-8"))
    except Exception as exc:
        failures.append(f"cannot parse generated inventory JSON: {exc}")
        return
    if inventory_payload.get("artifact_name") != "task6-zero-to-one-inventory":
        failures.append("inventory artifact_name mismatch")


def run_locked_tests(lock: dict[str, Any], failures: list[str], script_python: str) -> None:
    repo_root = Path(lock.get("repo", {}).get("root", ".")).resolve()
    for unit_test in lock.get("unit_tests", []):
        if not isinstance(unit_test, dict):
            continue
        test_path = Path(unit_test.get("path", ""))
        path = test_path if test_path.is_absolute() else repo_root / test_path
        if not path.exists():
            failures.append(f"unit test missing: {path}")
            continue
        if path.suffix != ".py":
            failures.append(f"non-python unit test skipped by guard: {path}")
            continue
        env = os.environ.copy()
        env["PYTHONPATH"] = f"{repo_root / 'scripts' / 'task6'}:{env.get('PYTHONPATH', '')}".rstrip(":")
        rc, _, stderr = run_command(
            [script_python, str(path)],
            cwd=path.parent,
            env=env,
        )
        if rc != 0:
            failures.append(f"unit test failed: {path}: {stderr}")


def main() -> int:
    args = parse_args()
    failures: list[str] = []

    try:
        lock = json.loads(args.lock_json.read_text(encoding="utf-8"))
    except Exception as exc:
        failures.append(f"cannot load lock JSON: {exc}")
        print(json.dumps({"artifact_name": "task6-zero-to-one-guard-result", "status": "FAIL", "failures": failures}, indent=2, sort_keys=True))
        return 1

    verify_lock_payload(lock, failures)
    verify_inventory(lock, failures, args.script_python)
    if args.run_tests:
        run_locked_tests(lock, failures, args.script_python)

    status = "PASS" if not failures else "FAIL"
    result = {
        "artifact_name": "task6-zero-to-one-guard-result",
        "status": status,
        "lock": str(args.lock_json),
        "failures": failures,
    }
    if args.out_json is not None:
        args.out_json.parent.mkdir(parents=True, exist_ok=True)
        args.out_json.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if status == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
