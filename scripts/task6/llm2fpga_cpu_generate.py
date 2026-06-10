#!/usr/bin/env python3
"""CPU/fixed-point TinyStories generation CLI for LLM2FPGA comparisons."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[2]
REFERENCE_TOOL = ROOT / "scripts" / "task6" / "task6_tinystories_generation_reference.py"
DEFAULT_MODEL = ROOT / "TinyStories"
DEFAULT_VOCAB = DEFAULT_MODEL / "gpt2-vocab.json"
DEFAULT_MERGES = DEFAULT_MODEL / "gpt2-merges.txt"
DEFAULT_ADAPTER = DEFAULT_MODEL / "model_adapter.py"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("prompt", nargs="?", default="Once upon a time there was")
    parser.add_argument("--model-path", type=Path, default=DEFAULT_MODEL)
    parser.add_argument("--adapter-path", type=Path, default=DEFAULT_ADAPTER)
    parser.add_argument("--tokenizer-vocab", type=Path, default=DEFAULT_VOCAB)
    parser.add_argument("--tokenizer-merges", type=Path, default=DEFAULT_MERGES)
    parser.add_argument("--steps", type=int, default=8)
    parser.add_argument("--top-k", type=int, default=5)
    parser.add_argument("--json-out", type=Path)
    parser.add_argument("--tokens-only", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    with tempfile.TemporaryDirectory() as tempdir:
        out_json = args.json_out or (Path(tempdir) / "reference.json")
        cmd = [
            os.environ.get("PYTHON", "python3"),
            str(REFERENCE_TOOL),
            "--model-path",
            str(args.model_path),
            "--adapter-path",
            str(args.adapter_path),
            "--tokenizer-vocab",
            str(args.tokenizer_vocab),
            "--tokenizer-merges",
            str(args.tokenizer_merges),
            "--prompt",
            args.prompt,
            "--max-new-tokens",
            str(args.steps),
            "--top-k",
            str(args.top_k),
            "--out-json",
            str(out_json),
            "--json-only",
        ]
        completed = subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
        if completed.returncode != 0:
            if completed.stdout:
                print(completed.stdout, file=sys.stderr, end="" if completed.stdout.endswith("\n") else "\n")
            if completed.stderr:
                print(completed.stderr, file=sys.stderr, end="" if completed.stderr.endswith("\n") else "\n")
            return completed.returncode

        payload = json.loads(out_json.read_text(encoding="utf-8"))
        generation = payload.get("generation", {})
        tokens = generation.get("q024_generated_token_ids", [])
        if args.tokens_only:
            print(" ".join(str(token) for token in tokens))
        else:
            print(generation.get("q024_decoded_text", ""))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
