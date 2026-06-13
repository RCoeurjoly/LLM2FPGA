#!/usr/bin/env python3
"""Generate token-controlled block-input constants for the M2 composed block."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


SV_1D_RE = re.compile(
    r"^\s*(?P<name>[A-Za-z0-9_]+)\[(?P<i0>\d+)\]\s*=\s*"
    r"(?P<sign>-?)(?P<bits>\d+)'sd(?P<value>\d+)\s*;"
)
SV_2D_RE = re.compile(
    r"^\s*(?P<name>[A-Za-z0-9_]+)\[(?P<i0>\d+)\]\[(?P<i1>\d+)\]\s*=\s*"
    r"(?P<sign>-?)(?P<bits>\d+)'sd(?P<value>\d+)\s*;"
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--contract-manifest", required=True, type=Path)
    parser.add_argument("--full-block-tb-data-sv", required=True, type=Path)
    parser.add_argument("--context-tb-data-sv", required=True, type=Path)
    parser.add_argument("--out-sv", required=True, type=Path)
    parser.add_argument("--out-json", required=True, type=Path)
    parser.add_argument("--step-index", type=int, default=0)
    return parser.parse_args()


def parse_sv_value(match: re.Match[str]) -> int:
    value = int(match.group("value"))
    return -value if match.group("sign") == "-" else value


def parse_1d(path: Path, name: str, count: int) -> list[int]:
    values: dict[int, int] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        match = SV_1D_RE.match(line)
        if match and match.group("name") == name:
            values[int(match.group("i0"))] = parse_sv_value(match)
    missing = [index for index in range(count) if index not in values]
    if missing:
        raise SystemExit(f"{path} missing {name} index(es): {missing[:8]}")
    return [values[index] for index in range(count)]


def parse_2d(path: Path, name: str, rows: int, cols: int) -> list[list[int]]:
    values: dict[tuple[int, int], int] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        match = SV_2D_RE.match(line)
        if match and match.group("name") == name:
            values[(int(match.group("i0")), int(match.group("i1")))] = parse_sv_value(match)
    missing = [
        (row, col)
        for row in range(rows)
        for col in range(cols)
        if (row, col) not in values
    ]
    if missing:
        raise SystemExit(f"{path} missing {name} index(es): {missing[:8]}")
    return [[values[(row, col)] for col in range(cols)] for row in range(rows)]


def sv_i8(value: int) -> str:
    return f"-8'sd{abs(value)}" if value < 0 else f"8'sd{value}"


def sv_i16(value: int) -> str:
    return f"-16'sd{abs(value)}" if value < 0 else f"16'sd{value}"


def checksum_u8(values: list[int]) -> int:
    return sum((value & 0xFF) * (index + 1) for index, value in enumerate(values)) & 0xFFFFFFFF


def main() -> None:
    args = parse_args()
    contract = json.loads(args.contract_manifest.read_text(encoding="utf-8"))
    step = contract["steps"][args.step_index]
    token_ids = [int(token) for token in step["context_token_ids"]]
    if len(token_ids) != 6:
        raise SystemExit(f"expected 6 context token ids, got {len(token_ids)}")

    block_input_q = parse_1d(args.full_block_tb_data_sv, "out_proj_block_input_q", 64)
    ln_input_q12 = parse_2d(args.context_tb_data_sv, "ln_input_q12_by_token", len(token_ids), 64)

    lines = [
        "localparam int TOKEN_BLOCK_SEQ = 6;",
        "localparam int TOKEN_BLOCK_DIM = 64;",
        "logic [15:0] token_block_expected_token_ids [0:TOKEN_BLOCK_SEQ-1];",
        "logic signed [7:0] token_block_last_input_q [0:TOKEN_BLOCK_DIM-1];",
        "logic signed [15:0] token_block_ln_input_q12_by_token [0:TOKEN_BLOCK_SEQ-1][0:TOKEN_BLOCK_DIM-1];",
        "initial begin",
    ]
    for index, token_id in enumerate(token_ids):
        lines.append(f"  token_block_expected_token_ids[{index}] = 16'd{token_id};")
    for index, value in enumerate(block_input_q):
        lines.append(f"  token_block_last_input_q[{index}] = {sv_i8(value)};")
    for token_index, row in enumerate(ln_input_q12):
        for dim, value in enumerate(row):
            lines.append(f"  token_block_ln_input_q12_by_token[{token_index}][{dim}] = {sv_i16(value)};")
    lines.append("end")

    args.out_sv.parent.mkdir(parents=True, exist_ok=True)
    args.out_sv.write_text("\n".join(lines) + "\n", encoding="utf-8")
    args.out_json.write_text(
        json.dumps(
            {
                "artifact_name": "task6-m2-token-block-input-tb-data",
                "status": "PASS",
                "step": int(step["step"]),
                "token_ids": token_ids,
                "block_input_checksum": checksum_u8(block_input_q),
                "ln_input_rows": len(ln_input_q12),
                "ln_input_cols": len(ln_input_q12[0]),
            },
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
