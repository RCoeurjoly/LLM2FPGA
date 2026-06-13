#!/usr/bin/env python3
"""Build the Task 6 M3 reference target manifest from a greedy reference JSON."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_REFERENCE_JSON = (
    ROOT
    / "artifacts"
    / "task6"
    / "parallel-hypotheses"
    / "h2-tinystories-1m-prompt-output-head-q024-reference.json"
)
DEFAULT_OUT_JSON = (
    ROOT / "artifacts" / "task6" / "parallel-hypotheses" / "task6-m3-reference-manifest.json"
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference-json", type=Path, default=DEFAULT_REFERENCE_JSON)
    parser.add_argument("--out-json", type=Path, default=DEFAULT_OUT_JSON)
    parser.add_argument("--model-label", default="TinyStories-1M")
    parser.add_argument("--json-only", action="store_true")
    return parser.parse_args()


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def require_list(payload: dict[str, Any], path: tuple[str, ...]) -> list[Any]:
    value: Any = payload
    for key in path:
        if not isinstance(value, dict) or key not in value:
            raise SystemExit(f"missing required reference field: {'.'.join(path)}")
        value = value[key]
    if not isinstance(value, list) or not value:
        raise SystemExit(f"required reference field is not a non-empty list: {'.'.join(path)}")
    return value


def require_str(payload: dict[str, Any], path: tuple[str, ...]) -> str:
    value: Any = payload
    for key in path:
        if not isinstance(value, dict) or key not in value:
            raise SystemExit(f"missing required reference field: {'.'.join(path)}")
        value = value[key]
    if not isinstance(value, str) or not value:
        raise SystemExit(f"required reference field is not a non-empty string: {'.'.join(path)}")
    return value


def build_manifest(reference: dict[str, Any], reference_path: Path, model_label: str) -> dict[str, Any]:
    prompt_text = require_str(reference, ("prompt", "text"))
    prompt_token_ids = [int(token) for token in require_list(reference, ("prompt", "token_ids"))]
    generated_tokens = [int(token) for token in require_list(reference, ("generation", "q024_generated_token_ids"))]
    steps = reference.get("steps", [])
    if not isinstance(steps, list):
        raise SystemExit("reference steps field is not a list")
    if len(steps) != len(generated_tokens):
        raise SystemExit(
            "reference step count does not match generated token count: "
            f"{len(steps)} vs {len(generated_tokens)}"
        )

    generation = reference.get("generation", {})
    model = reference.get("model", {})
    quantization = reference.get("quantization", {})
    coverage = reference.get("coverage", {})
    return {
        "artifact_name": "task6-m3-reference-manifest",
        "status": "PASS",
        "closes_m3": False,
        "reference_json": str(reference_path),
        "contract": {
            "stage": "M3-reference-target",
            "milestone_target": "M3-full-tinystories-1m",
            "live_compute": False,
            "all_blocks": False,
            "artifact_role": "offline-reference-target",
            "notes": (
                "CPU/host reference target only. This pins the TinyStories-1M "
                "prompt and token-exact greedy output expected from a future "
                "board M3 gate; it is not board inference evidence."
            ),
            "acceptance_requires": [
                "board status PASS",
                "host-supplied prompt token IDs match this manifest",
                "board executes all TinyStories-1M transformer blocks",
                "board performs greedy token selection or returns equivalent logits/top1",
                "board-generated token IDs equal reference.generated_tokens",
                "artifact passes scripts/task6/task6_milestone_evidence_audit.py M3",
            ],
        },
        "model": {
            "model_label": model_label,
            "model_path": model.get("model_path"),
            "adapter_path": model.get("adapter_path"),
            "vocab_size": model.get("vocab_size"),
            "hidden_size": model.get("hidden_size"),
        },
        "input": {
            "prompt": prompt_text,
            "prompt_token_ids": prompt_token_ids,
        },
        "reference": {
            "prompt": prompt_text,
            "generated_tokens": generated_tokens,
            "generated_text": generation.get("q024_decoded_text"),
            "max_new_tokens": generation.get("max_new_tokens"),
            "quantized_top1": "rowwise-int8-q024",
        },
        "coverage": {
            "source": coverage,
            "quantization": quantization,
            "step_count": len(steps),
        },
        "board": {
            "status": "NOT_RUN",
            "generated_tokens": [],
        },
    }


def main() -> int:
    args = parse_args()
    reference = read_json(args.reference_json)
    manifest = build_manifest(reference, args.reference_json, args.model_label)
    args.out_json.parent.mkdir(parents=True, exist_ok=True)
    args.out_json.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    if args.json_only:
        print(json.dumps(manifest, indent=2, sort_keys=True))
    else:
        print("PASS")
        print(f"prompt_token_ids: {manifest['input']['prompt_token_ids']}")
        print(f"reference_generated_tokens: {manifest['reference']['generated_tokens']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
