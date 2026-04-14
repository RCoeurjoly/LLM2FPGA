#!/usr/bin/env python3
import argparse
import json
from pathlib import Path


DEFAULT_OPS = [
    "linalg.matmul",
    "linalg.batch_matmul",
    "linalg.quantized_batch_matmul",
    "arith.minimumf",
    "arith.maximumf",
    "arith.divf",
    "arith.fptosi",
    "arith.sitofp",
    "math.rsqrt",
    "math.exp",
]


def parse_args():
    parser = argparse.ArgumentParser(
        description="Count selected MLIR op spellings in an artifact."
    )
    parser.add_argument("input", help="Input MLIR file")
    parser.add_argument(
        "--op",
        dest="ops",
        action="append",
        help="Operation spelling to count. May be repeated.",
    )
    parser.add_argument("--json-out", help="Optional JSON output path")
    parser.add_argument("--text-out", help="Optional text summary output path")
    return parser.parse_args()


def main():
    args = parse_args()
    input_path = Path(args.input)
    text = input_path.read_text(encoding="utf-8")
    ops = args.ops or DEFAULT_OPS
    counts = {op: text.count(op) for op in ops}

    payload = {
        "input": str(input_path),
        "counts": counts,
    }

    print(json.dumps(payload, indent=2, sort_keys=True))

    if args.json_out:
        Path(args.json_out).write_text(
            json.dumps(payload, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )

    if args.text_out:
        summary = "\n".join(f"{op}: {counts[op]}" for op in ops) + "\n"
        Path(args.text_out).write_text(summary, encoding="utf-8")


if __name__ == "__main__":
    main()
