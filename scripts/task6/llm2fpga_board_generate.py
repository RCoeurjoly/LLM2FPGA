#!/usr/bin/env python3
"""Board TinyStories generation CLI for LLM2FPGA CPU-vs-YPCB comparisons."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[2]
PROMPT_CLI = ROOT / "scripts" / "task6" / "task6_prompt_cli.py"
DEFAULT_BDF = "0000:42:00.0"
DEFAULT_MODEL = ROOT / "TinyStories"
DEFAULT_VOCAB = DEFAULT_MODEL / "gpt2-vocab.json"
DEFAULT_MERGES = DEFAULT_MODEL / "gpt2-merges.txt"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("prompt", nargs="?", default="Once upon a time there was")
    parser.add_argument("--bdf", default=DEFAULT_BDF)
    parser.add_argument("--model-path", type=Path, default=DEFAULT_MODEL)
    parser.add_argument("--tokenizer-vocab", type=Path, default=DEFAULT_VOCAB)
    parser.add_argument("--tokenizer-merges", type=Path, default=DEFAULT_MERGES)
    parser.add_argument("--steps", type=int, default=8)
    parser.add_argument("--engine", choices=("top1", "mlp"), default="top1")
    parser.add_argument("--reference-json", type=Path)
    parser.add_argument("--no-load-image", action="store_true")
    parser.add_argument("--packet-ack-mode", choices=("auto", "require", "off"), default="auto")
    parser.add_argument("--packet-settle", type=float, default=0.001)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    cmd = [
        os.environ.get("PYTHON", "python3"),
        str(PROMPT_CLI),
        "--bdf",
        args.bdf,
        "--engine",
        args.engine,
        "--steps",
        str(args.steps),
        "--model-path",
        str(args.model_path),
        "--tokenizer-vocab",
        str(args.tokenizer_vocab),
        "--tokenizer-merges",
        str(args.tokenizer_merges),
        "--packet-ack-mode",
        args.packet_ack_mode,
        "--packet-settle",
        str(args.packet_settle),
    ]
    if args.no_load_image:
        cmd.append("--no-load-image")
    if args.reference_json is not None:
        cmd.extend(["--reference-json", str(args.reference_json)])
    cmd.append(args.prompt)

    completed = subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    if completed.stdout:
        print(completed.stdout, end="" if completed.stdout.endswith("\n") else "\n")
    if completed.returncode != 0 and completed.stderr:
        print(completed.stderr, file=sys.stderr, end="" if completed.stderr.endswith("\n") else "\n")
    return completed.returncode


if __name__ == "__main__":
    raise SystemExit(main())
