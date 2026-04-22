#!/usr/bin/env python3
from __future__ import annotations

"""Locate the first representative-core L1 GEMV candidate in Linalg MLIR."""

import argparse
import json
import re
from pathlib import Path


TARGET_RE = re.compile(
    r"(?P<result>%[A-Za-z0-9_]+) = linalg\.batch_matmul "
    r"ins\((?P<lhs>%[A-Za-z0-9_]+), (?P<rhs>%[A-Za-z0-9_]+) : "
    r"tensor<1x1x4xf32>, tensor<1x4x16xf32>\) "
    r"outs\((?P<out>%[A-Za-z0-9_]+) : tensor<1x1x16xf32>\) "
    r"-> tensor<1x1x16xf32>"
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    lines = args.input.read_text(encoding="utf-8").splitlines()
    candidates: list[dict[str, object]] = []

    for idx, line in enumerate(lines, start=1):
        match = TARGET_RE.search(line)
        if match is None:
            continue
        context_start = max(1, idx - 6)
        context_end = min(len(lines), idx + 6)
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
                    "lhs": "tensor<1x1x4xf32>",
                    "rhs": "tensor<1x4x16xf32>",
                    "out": "tensor<1x1x16xf32>",
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
        raise SystemExit("no L1 candidate with tensor<1x1x4xf32> x tensor<1x4x16xf32> found")

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
