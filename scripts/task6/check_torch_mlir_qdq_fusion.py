#!/usr/bin/env python3
"""Check Torch-MLIR QDQ fusion leaves the expected number of float matmuls."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
import tempfile
from pathlib import Path


FLOAT_MATMUL_RE = re.compile(
    r"torch\.aten\.(?:matmul|mm)\b[^\n]*:\s*[^\n]*\bf32\b[^\n]*->\s*[^\n]*\bf32\b"
)
QINT_MATMUL_RE = re.compile(
    r"torch\.aten\.(?:matmul|mm)\b[^\n]*:\s*[^\n]*\bqint[0-9]+\b"
)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--torch-mlir-opt", required=True, type=Path)
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--expect-f32-matmul-count", required=True, type=int)
    args = parser.parse_args()

    with tempfile.TemporaryDirectory(prefix="task6-qdq-fusion-") as tmpdir:
        output = Path(tmpdir) / "fused.mlir"
        cmd = [
            str(args.torch_mlir_opt),
            str(args.input),
            "--torch-fuse-quantized-ops",
            "-canonicalize",
            "-o",
            str(output),
        ]
        proc = subprocess.run(cmd, text=True, capture_output=True)
        if proc.returncode != 0:
            sys.stderr.write(proc.stderr)
            return proc.returncode

        fused = output.read_text()

    float_matmuls = FLOAT_MATMUL_RE.findall(fused)
    qint_matmuls = QINT_MATMUL_RE.findall(fused)
    print(f"float_matmul_count={len(float_matmuls)}")
    print(f"qint_matmul_count={len(qint_matmuls)}")
    if len(float_matmuls) != args.expect_f32_matmul_count:
        print(
            "expected "
            f"{args.expect_f32_matmul_count} float matmul(s), "
            f"found {len(float_matmuls)}",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
