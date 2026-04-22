#!/usr/bin/env python3
from __future__ import annotations

"""Locate the first TinyStories GEMV candidate in Linalg MLIR."""

import argparse
import json
from pathlib import Path
import re


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--lhs-shape", default="tensor<1x1x4xf32>")
    parser.add_argument("--rhs-shape", default="tensor<1x4x16xf32>")
    parser.add_argument("--out-shape", default="tensor<1x1x16xf32>")
    parser.add_argument("--context-radius", type=int, default=6)
    parser.add_argument(
        "--site-label",
        default="L1",
        help="Label used in the no-candidate error message",
    )
    return parser.parse_args()


def compile_target_re(lhs_shape: str, rhs_shape: str, out_shape: str) -> re.Pattern[str]:
    return re.compile(
        r"(?P<result>%[A-Za-z0-9_]+) = linalg\.batch_matmul "
        r"ins\((?P<lhs>%[A-Za-z0-9_]+), (?P<rhs>%[A-Za-z0-9_]+) : "
        + re.escape(lhs_shape)
        + r", "
        + re.escape(rhs_shape)
        + r"\) "
        r"outs\((?P<out>%[A-Za-z0-9_]+) : "
        + re.escape(out_shape)
        + r"\) "
        r"-> "
        + re.escape(out_shape)
    )


def main() -> None:
    args = parse_args()
    lines = args.input.read_text(encoding="utf-8").splitlines()
    candidates: list[dict[str, object]] = []
    target_re = compile_target_re(args.lhs_shape, args.rhs_shape, args.out_shape)

    for idx, line in enumerate(lines, start=1):
        match = target_re.search(line)
        if match is None:
            continue
        context_start = max(1, idx - args.context_radius)
        context_end = min(len(lines), idx + args.context_radius)
        candidates.append(
            {
                "candidate_index": len(candidates),
                "line_number": idx,
                "result_value": match.group("result"),
                "lhs_value": match.group("lhs"),
                "rhs_value": match.group("rhs"),
                "out_value": match.group("out"),
                "representation_level": "linalg",
                "shape_contract": {
                    "lhs": args.lhs_shape,
                    "rhs": args.rhs_shape,
                    "out": args.out_shape,
                },
                "context": [
                    {
                        "line_number": line_no,
                        "text": lines[line_no - 1],
                    }
                    for line_no in range(context_start, context_end + 1)
                ],
            }
        )

    if not candidates:
        raise SystemExit(
            f"no {args.site_label} candidate with {args.lhs_shape} x {args.rhs_shape} found"
        )

    payload = {
        "artifact": str(args.input),
        "candidate_count": len(candidates),
        "selected_candidate": candidates[0],
        "all_candidates": candidates,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
