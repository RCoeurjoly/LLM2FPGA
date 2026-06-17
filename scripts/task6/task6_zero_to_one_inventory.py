#!/usr/bin/env python3
"""Create a machine-readable repository inventory for zero-to-one planning."""

from __future__ import annotations

import argparse
import dataclasses
import fnmatch
import hashlib
import json
import os
import subprocess
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


DEFAULT_KEEP_GLOBS = [
    ".",
    "*.nix",
    "*.py",
    "*.sv",
    "*.v",
    "*.vh",
    "*.md",
    "*.org",
    "*.txt",
    "*.json",
    "*.toml",
    "*.yml",
    "*.yaml",
    "*.sh",
    "*.bash",
    "*.tcl",
    "flake.nix",
    "AGENTS.md",
    "README*",
    "LICENSE",
    "artifacts/task6/*",
    "scripts/**",
    "nix/**",
    "fpga/**",
    "src/**",
    "sim/**",
    "rtl/**",
    "TinyStories/**",
    "artifacts/task6/baselines/**",
]

DEFAULT_REMOVE_GLOBS = [
    "result",
    "result-*",
    "**/*.tmp",
    "**/*.pyc",
    "**/__pycache__/**",
    ".Xil/**",
    "tmp/**",
    "tmp-*/**",
]

DEFAULT_QUARANTINE_GLOBS = [
    "artifacts/task6/runs/**",
    "artifacts/task6/autonight/**",
    "deliverables/**",
    "docs/task6-task-notes/**",
    "**/.mypy_cache/**",
    "**/.pytest_cache/**",
]


@dataclasses.dataclass(frozen=True)
class InventoryFile:
    path: str
    category: str
    size_bytes: int
    sha256: str
    note: str | None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", default=ROOT, type=Path)
    parser.add_argument("--out-json", type=Path, required=True)
    parser.add_argument("--keep-glob", action="append", default=[])
    parser.add_argument("--remove-glob", action="append", default=[])
    parser.add_argument("--quarantine-glob", action="append", default=[])
    parser.add_argument(
        "--scan-depth",
        type=int,
        default=8,
        help="Ignore files deeper than this number of path components",
    )
    return parser.parse_args()


def run_git(*args: str, cwd: Path) -> str:
    result = subprocess.run(
        ["git", "-C", str(cwd), *args],
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


def hash_bytes(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def hash_symlink(path: Path) -> str:
    target = os.readlink(path)
    return hashlib.sha256(target.encode("utf-8")).hexdigest()


def match_any(path: str, patterns: list[str]) -> bool:
    return any(fnmatch.fnmatch(path, pattern) for pattern in patterns)


def classify(path: str, keep: list[str], remove: list[str], quarantine: list[str]) -> str:
    if match_any(path, remove):
        return "remove"
    if match_any(path, quarantine):
        return "quarantine"
    if match_any(path, keep):
        return "keep"
    return "unknown"


def path_depth(path: str) -> int:
    return len(Path(path).parts)


def gather_repo_info(root: Path) -> dict[str, object]:
    try:
        branch = run_git("branch", "--show-current", cwd=root)
    except subprocess.CalledProcessError:
        branch = ""
    try:
        commit = run_git("rev-parse", "HEAD", cwd=root)
    except subprocess.CalledProcessError:
        commit = ""
    try:
        status = run_git("status", "--short", cwd=root)
        clean = status == ""
    except subprocess.CalledProcessError:
        clean = False
        status = ""
    return {
        "branch": branch,
        "commit": commit,
        "clean": clean,
        "status_short": status,
    }


def collect_files(root: Path, max_depth: int) -> list[Path]:
    entries: list[Path] = []
    for path in root.rglob("*"):
        rel = path.relative_to(root)
        if rel.parts[:1] == (".git",):
            continue
        if rel.name == ".gitkeep":
            continue
        if path_depth(str(rel)) > max_depth:
            continue
        if path.is_file() or path.is_symlink():
            entries.append(path)
    return sorted(entries)


def hash_path(path: Path) -> str:
    if path.is_symlink():
        return hash_symlink(path)
    if not path.is_file():
        raise SystemExit(f"unsupported file type for hash: {path}")
    return hash_bytes(path)


def file_payload(path: Path, category: str, root: Path) -> InventoryFile:
    rel = path.relative_to(root).as_posix()
    return InventoryFile(
        path=rel,
        category=category,
        size_bytes=path.lstat().st_size,
        sha256=hash_path(path),
        note=None,
    )


def build_inventory(root: Path, keep: list[str], remove: list[str], quarantine: list[str], max_depth: int) -> list[InventoryFile]:
    root = root.resolve()
    entries = collect_files(root, max_depth)
    results: list[InventoryFile] = []
    for path in entries:
        rel = path.relative_to(root).as_posix()
        category = classify(rel, keep, remove, quarantine)
        note = None
        if category == "unknown":
            note = "requires manual review before removing or freezing"
        payload = file_payload(path, category, root)
        payload = dataclasses.replace(payload, note=note)
        results.append(payload)
    return results


def to_json_payload(root: Path, out_json: Path, args: argparse.Namespace) -> dict[str, object]:
    keep = sorted(DEFAULT_KEEP_GLOBS + args.keep_glob)
    remove = sorted(DEFAULT_REMOVE_GLOBS + args.remove_glob)
    quarantine = sorted(DEFAULT_QUARANTINE_GLOBS + args.quarantine_glob)
    files = build_inventory(root, keep, remove, quarantine, args.scan_depth)
    by_category = {
        "keep": sum(1 for entry in files if entry.category == "keep"),
        "remove": sum(1 for entry in files if entry.category == "remove"),
        "quarantine": sum(1 for entry in files if entry.category == "quarantine"),
        "unknown": sum(1 for entry in files if entry.category == "unknown"),
    }
    return {
        "schema_version": 1,
        "artifact_name": "task6-zero-to-one-inventory",
        "generated_utc": datetime.now(timezone.utc).isoformat(),
        "generated_by": "scripts/task6/task6_zero_to_one_inventory.py",
        "repo_root": str(root.resolve()),
        "rules": {
            "keep": keep,
            "remove": remove,
            "quarantine": quarantine,
        },
        "git": gather_repo_info(root),
        "counts": by_category,
        "files": [
            dataclasses.asdict(entry)
            for entry in files
        ],
    }


def main() -> int:
    args = parse_args()
    args.out_json.parent.mkdir(parents=True, exist_ok=True)
    payload = to_json_payload(args.repo_root, args.out_json, args)
    args.out_json.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"status": "PASS", "artifact": str(args.out_json), "file_count": len(payload["files"])}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
