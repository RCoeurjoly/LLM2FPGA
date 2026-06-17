#!/usr/bin/env python3
"""Create an auditable immutable reference lock for zero-to-one inference."""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any



DEFAULT_LOCKED_SCRIPTS = [
    "scripts/task6/task6_zero_to_one_inventory.py",
    "scripts/task6/task6_zero_to_one_reference_lock.py",
    "scripts/task6/task6_zero_to_one_guard.py",
    "scripts/task6/task6_zero_to_one_inference_gate.py",
]

DEFAULT_MODEL_SNAPSHOT_MANIFEST = Path(
    "artifacts/task6/parallel-hypotheses/h2-tinystories-1m-model-manifest.json"
)


def candidate_tokenizer_paths(base_snapshot: Path) -> tuple[list[Path], list[Path]]:
    vocab_candidates = [
        base_snapshot / "vocab.json",
        base_snapshot / "tokenizer" / "vocab.json",
    ]
    merges_candidates = [
        base_snapshot / "merges.txt",
        base_snapshot / "tokenizer" / "merges.txt",
    ]
    return vocab_candidates, merges_candidates


def resolve_snapshot_source_for_tokenizers(
    model_snapshot: Path,
    snapshot_extra: dict[str, str],
) -> Path:
    if source_path := snapshot_extra.get("snapshot_source_path"):
        return Path(source_path)
    return model_snapshot


def resolve_tokenizer_artifacts(
    root: Path,
    model_snapshot: Path,
    snapshot_extra: dict[str, str],
    tokenizer_vocab: Path | None,
    tokenizer_merges: Path | None,
) -> tuple[Path, Path]:
    if tokenizer_vocab is not None and tokenizer_merges is None:
        raise SystemExit("--tokenizer-merges is required when --tokenizer-vocab is provided")
    if tokenizer_merges is not None and tokenizer_vocab is None:
        raise SystemExit("--tokenizer-vocab is required when --tokenizer-merges is provided")

    if tokenizer_vocab is not None:
        return (
            artifact_path(root, tokenizer_vocab),
            artifact_path(root, tokenizer_merges),
        )

    snapshot_source = artifact_path(
        root,
        resolve_snapshot_source_for_tokenizers(
            model_snapshot,
            snapshot_extra,
        ),
    )
    vocab_candidates, merges_candidates = candidate_tokenizer_paths(snapshot_source)
    vocab = next((candidate for candidate in vocab_candidates if candidate.exists()), None)
    if vocab is None:
        raise SystemExit(
            "Could not resolve tokenizer vocab; tried: "
            + ", ".join(str(path) for path in vocab_candidates)
        )
    merges = next((candidate for candidate in merges_candidates if candidate.exists()), None)
    if merges is None:
        raise SystemExit(
            "Could not resolve tokenizer merges; tried: "
            + ", ".join(str(path) for path in merges_candidates)
        )
    return vocab, merges


def default_model_snapshot_from_manifest(manifest_path: Path) -> Path | None:
    if not manifest_path.exists():
        return None
    manifest = parse_model_manifest(manifest_path)
    candidate = manifest.get("model_path")
    if isinstance(candidate, str):
        return Path(candidate)
    candidate = manifest.get("config", {}).get("_name_or_path")
    if isinstance(candidate, str):
        return Path(candidate)
    return None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", type=Path, required=True)
    parser.add_argument(
        "--model-snapshot",
        type=Path,
        default=default_model_snapshot_from_manifest(DEFAULT_MODEL_SNAPSHOT_MANIFEST),
    )
    parser.add_argument(
        "--model-snapshot-manifest",
        type=Path,
        default=DEFAULT_MODEL_SNAPSHOT_MANIFEST,
        help="Optional fallback manifest containing a canonical snapshot path",
    )
    parser.add_argument("--model-adapter", type=Path, required=True)
    parser.add_argument("--tokenizer-vocab", type=Path)
    parser.add_argument("--tokenizer-merges", type=Path)
    parser.add_argument("--reference-json", type=Path, required=True)
    parser.add_argument("--weight-manifest", type=Path, action="append", required=True)
    parser.add_argument("--test-vector", type=Path, action="append", required=True)
    parser.add_argument("--unit-test", type=Path, action="append", default=[])
    parser.add_argument("--out-json", type=Path, required=True)
    parser.add_argument("--lock-tag", default="zero-to-one-v1")
    parser.add_argument("--locked-script", action="append", default=DEFAULT_LOCKED_SCRIPTS)
    parser.add_argument("--require-git-clean", action="store_true")
    parser.add_argument("--artifact-name", default="task6-zero-to-one-reference-lock")
    return parser.parse_args()


def parse_model_manifest(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def snapshot_referenced_by_manifest(path: Path, manifest_path: Path) -> bool:
    manifest = parse_model_manifest(manifest_path)
    requested = str(path)
    candidates = {
        manifest.get("model_path"),
        manifest.get("config", {}).get("_name_or_path"),
    }
    return requested in candidates


def resolve_model_snapshot(
    root: Path,
    raw_snapshot: Path | None,
    manifest_path: Path,
) -> tuple[Path, str, dict[str, str]]:
    if raw_snapshot is None:
        raw_snapshot = default_model_snapshot_from_manifest(manifest_path)
    if raw_snapshot is None:
        raise SystemExit(
            "model-snapshot not provided and no canonical model path was found in the manifest"
        )

    snapshot = artifact_path(root, raw_snapshot)
    if snapshot.exists():
        return snapshot, "pytorch-bin", {}

    manifest = artifact_path(root, manifest_path)
    if manifest.exists() and snapshot_referenced_by_manifest(snapshot, manifest):
        return manifest, "pytorch-manifest", {"snapshot_source_path": str(snapshot)}

    if manifest.exists():
        raise SystemExit(
            f"model_snapshot missing and does not match model manifest"
            f" '{manifest}': {snapshot}"
        )
    raise SystemExit(
        f"model_snapshot missing and model snapshot manifest not available: {snapshot}"
    )


def run_git(*args: str, cwd: Path) -> str:
    result = subprocess.run(
        ["git", "-C", str(cwd), *args],
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


def hash_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def hash_path(path: Path) -> str:
    if path.is_file():
        return hash_file(path)
    if path.is_dir():
        digest = hashlib.sha256()
        for item in sorted(path.rglob("*"), key=lambda p: p.as_posix()):
            rel = item.relative_to(path).as_posix()
            digest.update(rel.encode("utf-8"))
            digest.update(b"\0")
            if item.is_file():
                digest.update(b"file\0")
                digest.update(hash_file(item).encode("utf-8"))
            else:
                mode = item.lstat().st_mode
                digest.update(f"other:{mode}\0".encode("utf-8"))
            digest.update(b"\0")
        return digest.hexdigest()
    raise SystemExit(f"unsupported file type for hash: {path}")


def git_head(root: Path) -> dict[str, str]:
    try:
        branch = run_git("branch", "--show-current", cwd=root)
    except subprocess.CalledProcessError:
        branch = ""
    try:
        commit = run_git("rev-parse", "HEAD", cwd=root)
    except subprocess.CalledProcessError:
        commit = ""
    return {"branch": branch, "commit": commit}


def ensure_repo_clean(root: Path, require_clean: bool) -> None:
    if not require_clean:
        return
    status = run_git("status", "--short", cwd=root)
    if status.strip():
        raise SystemExit("repository is not clean but --require-git-clean was set")


def artifact_entry(kind: str, path: Path) -> dict[str, str]:
    return {
        "kind": kind,
        "path": str(path),
        "sha256": hash_path(path),
    }


def write_lock(payload: dict, out_json: Path) -> None:
    out_json.parent.mkdir(parents=True, exist_ok=True)
    out_json.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def sorted_paths(values: list[Path]) -> list[Path]:
    return sorted(values, key=lambda path: str(path))


def artifact_path(base: Path, value: Path) -> Path:
    if value.is_absolute():
        return value
    return base / value


def normalize_lock_payload(payload: dict) -> dict:
    # Provide stable and portable representation for review and tests.
    payload["rules"] = sorted(payload.get("rules", []))
    return payload


def validate_reference_payload(path: Path) -> None:
    payload = json.loads(path.read_text(encoding="utf-8"))
    steps = payload.get("steps")
    if not isinstance(steps, list) or not steps:
        raise SystemExit(f"reference payload has no steps: {path}")
    generation = payload.get("generation", {})
    tokens = generation.get("q024_generated_token_ids") or []
    if not isinstance(tokens, list):
        raise SystemExit(f"reference payload generation tokens invalid: {path}")
    if len(steps) != len(tokens):
        raise SystemExit(
            f"reference payload mismatch between steps and generated tokens: {path} "
            f"({len(steps)} steps vs {len(tokens)} tokens)"
        )


def build_payload(
    *,
    root: Path,
    model_snapshot: Path,
    model_snapshot_type: str,
    model_snapshot_extra: dict[str, str],
    model_adapter: Path,
    tokenizer_vocab: Path,
    tokenizer_merges: Path,
    reference_json: Path,
    weight_manifests: list[Path],
    test_vectors: list[Path],
    unit_tests: list[Path],
    locked_scripts: list[str],
    lock_tag: str,
    artifact_name: str,
) -> dict:
    payload = {
        "schema_version": 1,
        "artifact_name": artifact_name,
        "status": "LOCKED",
        "lock_tag": lock_tag,
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "repo": {
            **git_head(root),
            "root": str(root),
        },
        "references": {
            "model_snapshot": {
                "path": str(model_snapshot),
                "sha256": hash_path(model_snapshot),
                "type": model_snapshot_type,
                **model_snapshot_extra,
            },
            "model_adapter": {
                "path": str(model_adapter),
                "sha256": hash_file(model_adapter),
                "type": "python",
            },
            "tokenizer": {
                "vocab": {
                    "path": str(tokenizer_vocab),
                    "sha256": hash_file(tokenizer_vocab),
                },
                "merges": {
                    "path": str(tokenizer_merges),
                    "sha256": hash_file(tokenizer_merges),
                },
            },
            "reference_json": {
                "path": str(reference_json),
                "sha256": hash_file(reference_json),
                "kind": "reference-payload",
            },
        },
        "weight_manifests": [
            artifact_entry("weight-manifest", manifest)
            for manifest in sorted_paths(weight_manifests)
        ],
        "test_vectors": [
            artifact_entry("test-vector", vector)
            for vector in sorted_paths(test_vectors)
        ],
        "unit_tests": [
            artifact_entry("unit-test", unit_test)
            for unit_test in sorted_paths(unit_tests)
        ],
        "governance": {
            "locked_scripts": [
                artifact_entry("governance-script", artifact_path(root, Path(item)))
                for item in sorted(locked_scripts)
            ],
            "anti_reward_hacking_notes": [
                "Do not edit reference payload files directly; update this lock first",
                "Do not modify locked test vectors or unit tests without updating the lock",
                "Do not bypass reference checks by changing validation code without changing lock_tag",
            ],
        },
        "rules": [
            "require-digest-match",
        ],
    }
    return normalize_lock_payload(payload)


def main() -> int:
    args = parse_args()
    root = args.repo_root.resolve()
    model_snapshot, model_snapshot_type, snapshot_extra = resolve_model_snapshot(
        root,
        args.model_snapshot,
        args.model_snapshot_manifest,
    )
    tokenizer_vocab, tokenizer_merges = resolve_tokenizer_artifacts(
        root,
        model_snapshot,
        snapshot_extra,
        args.tokenizer_vocab,
        args.tokenizer_merges,
    )
    for p in [
        model_snapshot,
        args.model_adapter,
        tokenizer_vocab,
        tokenizer_merges,
        args.reference_json,
        *args.weight_manifest,
        *args.test_vector,
        *args.unit_test,
        *[artifact_path(root, Path(path)) for path in args.locked_script],
    ]:
        if not p.exists():
            raise SystemExit(f"locked input does not exist: {p}")
    validate_reference_payload(artifact_path(root, args.reference_json))
    for vector in args.test_vector:
        validate_reference_payload(artifact_path(root, vector))

    ensure_repo_clean(root, args.require_git_clean)

    payload = build_payload(
        root=root,
        model_snapshot=model_snapshot,
        model_snapshot_type=model_snapshot_type,
        model_snapshot_extra=snapshot_extra,
        model_adapter=artifact_path(root, args.model_adapter),
        tokenizer_vocab=tokenizer_vocab,
        tokenizer_merges=tokenizer_merges,
        reference_json=args.reference_json,
        weight_manifests=args.weight_manifest,
        test_vectors=args.test_vector,
        unit_tests=args.unit_test,
        locked_scripts=sorted(args.locked_script),
        lock_tag=args.lock_tag,
        artifact_name=args.artifact_name,
    )
    write_lock(payload, args.out_json)
    print(json.dumps({"status": "PASS", "artifact": str(args.out_json)}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
