#!/usr/bin/env python3
"""Interactive and single-shot prompt CLI for Task 6 board inference.

This is a lightweight host-facing front end over ``task6_prompt_infer.py`` that
focuses on prompt->answer behavior.
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PROMPT_INFER = ROOT / "scripts" / "task6" / "task6_prompt_infer.py"
DEFAULT_BDF = "0000:42:00.0"
DEFAULT_MODEL = ROOT / "TinyStories"
DEFAULT_VOCAB = DEFAULT_MODEL / "gpt2-vocab.json"
DEFAULT_MERGES = DEFAULT_MODEL / "gpt2-merges.txt"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("prompt", nargs="?", help="Single-shot prompt. Omit to start interactive mode.")
    parser.add_argument("--bdf", default=DEFAULT_BDF, help="PCIe endpoint BDF (default: 0000:42:00.0)")
    parser.add_argument("--engine", choices=("top1", "mlp"), default="top1", help="Inference engine to invoke")
    parser.add_argument("--steps", type=int, default=1, help="Tokens to generate in --prompt mode")
    parser.add_argument("--top-k", type=int, default=5, help="Top-k width for reference generation")
    parser.add_argument("--model-path", type=Path, default=DEFAULT_MODEL, help="TinyStories checkpoint path")
    parser.add_argument("--tokenizer-vocab", type=Path, default=DEFAULT_VOCAB, help="GPT-2 tokenizer vocab.json")
    parser.add_argument("--tokenizer-merges", type=Path, default=DEFAULT_MERGES, help="GPT-2 tokenizer merges.txt")
    parser.add_argument("--reference-json", type=Path, help="Optional precomputed reference file (skips model replay)")
    parser.add_argument(
        "--load-image",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Load rowstream before top1 execution. Use --no-load-image when DDR3 already holds the rowstream.",
    )
    parser.add_argument(
        "--mlp-answer-format",
        choices=("checksum", "output", "both"),
        default="both",
        help="For engine=mlp, control answer-only output payload.",
    )
    parser.add_argument(
        "--show-meta",
        action="store_true",
        help="Print command exit status in interactive mode in addition to answer text",
    )
    parser.add_argument(
        "--poll-timeout",
        type=float,
        default=2.0,
        help="Board BAR poll timeout in seconds",
    )
    parser.add_argument(
        "--top1-timeout",
        type=float,
        default=20.0,
        help="Top1 execution timeout in seconds",
    )
    parser.add_argument(
        "--packet-ack-mode",
        choices=("auto", "require", "off"),
        default="auto",
        help="Top1 rowstream packet commit wait policy.",
    )
    parser.add_argument(
        "--packet-settle",
        type=float,
        default=0.001,
        help="Seconds to wait after rowstream packet commits when ACK counters are unavailable/inactive.",
    )
    return parser.parse_args()


def run_prompt_infer(prompt: str, args: argparse.Namespace) -> tuple[int, str, str]:
    cmd = [os.environ.get("PYTHON", "python3"), str(PROMPT_INFER), args.bdf]
    cmd += [
        "--engine",
        args.engine,
        "--steps",
        str(args.steps),
        "--top-k",
        str(args.top_k),
        "--poll-timeout",
        str(args.poll_timeout),
        "--top1-timeout",
        str(args.top1_timeout),
        "--packet-ack-mode",
        args.packet_ack_mode,
        "--packet-settle",
        str(args.packet_settle),
        "--answer-only",
    ]
    if not args.load_image:
        cmd += ["--no-load-image"]
    if args.engine == "mlp":
        cmd += ["--mlp-answer-format", args.mlp_answer_format]

    if args.reference_json is not None:
        cmd += ["--reference-json", str(args.reference_json)]
    else:
        cmd += [
            "--prompt",
            prompt,
            "--model-path",
            str(args.model_path),
            "--tokenizer-vocab",
            str(args.tokenizer_vocab),
            "--tokenizer-merges",
            str(args.tokenizer_merges),
        ]

    with tempfile.NamedTemporaryFile(prefix="task6_prompt_", suffix=".json", delete=False) as tmp:
        json_out = tmp.name
    cmd += ["--json-out", json_out]
    try:
        proc = subprocess.run(
            cmd,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        return proc.returncode, proc.stdout.strip(), proc.stderr.strip()
    finally:
        Path(json_out).unlink(missing_ok=True)


def run_loop(args: argparse.Namespace) -> int:
    if args.prompt is None:
        if args.reference_json is not None:
            print(
                "reference-json mode is single-shot. Omit --reference-json for interactive prompt entry, "
                "or provide a prompt argument for one-shot execution.",
                file=sys.stderr,
            )
            return 1
        print("Task 6 prompt CLI. Type /quit or /exit to leave.")
        while True:
            try:
                line = input("prompt> ").strip()
            except EOFError:
                print()
                return 0
            if not line:
                continue
            normalized = line.lower()
            if normalized in {"/quit", "quit", "/exit", "exit"}:
                return 0
            if line == "/help":
                print("Commands: /help, /quit, /exit")
                continue

            rc, out, err = run_prompt_infer(line, args)
            if out:
                print(out)
            if rc != 0:
                print(f"[error] exit={rc}")
            if args.show_meta and err:
                print(f"[stderr] {err}")
            if rc != 0 and not args.show_meta:
                print(err)
        return 0

    rc, out, err = run_prompt_infer(args.prompt, args)
    if out:
        print(out)
    if rc != 0:
        if err:
            print(err, file=sys.stderr)
    return rc


def main() -> int:
    args = parse_args()
    if args.reference_json is not None and not args.reference_json.exists():
        print(f"reference-json not found: {args.reference_json}", file=sys.stderr)
        return 1
    return run_loop(args)


if __name__ == "__main__":
    raise SystemExit(main())
