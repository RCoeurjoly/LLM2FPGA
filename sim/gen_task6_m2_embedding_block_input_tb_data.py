#!/usr/bin/env python3
"""Generate embedding+position-add constants for the M2 token boundary."""

from __future__ import annotations

import argparse
from array import array
import json
from pathlib import Path
import re


SV_1D_RE = re.compile(
    r"^\s*(?P<name>[A-Za-z0-9_]+)\[(?P<i0>\d+)\]\s*=\s*"
    r"(?P<sign>-?)(?P<bits>\d+)'sd(?P<value>\d+)\s*;"
)
SV_2D_RE = re.compile(
    r"^\s*(?P<name>[A-Za-z0-9_]+)\[(?P<i0>\d+)\]\[(?P<i1>\d+)\]\s*=\s*"
    r"(?P<sign>-?)(?P<bits>\d+)'sd(?P<value>\d+)\s*;"
)

Q20 = 1 << 20
Q12_SHIFT = 8
BLOCK_MUL_SHIFT = 20


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--contract-manifest", required=True, type=Path)
    parser.add_argument("--weight-manifest", required=True, type=Path)
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


def parse_1d_optional(path: Path, name: str, count: int) -> list[int] | None:
    values: dict[int, int] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        match = SV_1D_RE.match(line)
        if match and match.group("name") == name:
            values[int(match.group("i0"))] = parse_sv_value(match)
    missing = [index for index in range(count) if index not in values]
    if missing:
        return None
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


def read_f32(path: Path) -> list[float]:
    values = array("f")
    values.frombytes(path.read_bytes())
    if values.itemsize != 4:
        raise SystemExit("platform float array is not 32-bit")
    return [float(value) for value in values]


def tensor(manifest: dict, name: str) -> dict:
    for item in manifest["tensors"]:
        if item["name"] == name:
            return item
    raise SystemExit(f"missing tensor {name}")


def round_shift_signed(value: int, shift: int) -> int:
    if shift == 0:
        return value
    half = 1 << (shift - 1)
    if value >= 0:
        return (value + half) >> shift
    return -(((-value) + half) >> shift)


def clamp_i8(value: int) -> int:
    return max(-127, min(127, int(value)))


def sv_i8(value: int) -> str:
    return f"-8'sd{abs(value)}" if value < 0 else f"8'sd{value}"


def sv_i16(value: int) -> str:
    return f"-16'sd{abs(value)}" if value < 0 else f"16'sd{value}"


def sv_i32(value: int) -> str:
    return f"-32'sd{abs(value)}" if value < 0 else f"32'sd{value}"


def checksum_u8(values: list[int]) -> int:
    return sum((value & 0xFF) * (index + 1) for index, value in enumerate(values)) & 0xFFFFFFFF


def main() -> None:
    args = parse_args()
    contract = json.loads(args.contract_manifest.read_text(encoding="utf-8"))
    int8_weights = json.loads(args.weight_manifest.read_text(encoding="utf-8"))
    f32_manifest_path = Path(int8_weights["source_manifest"])
    f32_weights = json.loads(f32_manifest_path.read_text(encoding="utf-8"))
    f32_base = f32_manifest_path.parent

    step = contract["steps"][args.step_index]
    token_ids = [int(token) for token in step["context_token_ids"]]
    seq_len = len(token_ids)
    hidden = int(step["tensors"]["block_input_f32"]["shape"][-1])
    if seq_len != 6 or hidden != 64:
        raise SystemExit(f"expected M2 seq=6 hidden=64, got seq={seq_len} hidden={hidden}")

    wte_tensor = tensor(f32_weights, "transformer.wte.weight")
    wpe_tensor = tensor(f32_weights, "transformer.wpe.weight")
    wte = read_f32(f32_base / wte_tensor["filename"])
    wpe = read_f32(f32_base / wpe_tensor["filename"])
    vocab_rows, vocab_cols = [int(value) for value in wte_tensor["shape"]]
    pos_rows, pos_cols = [int(value) for value in wpe_tensor["shape"]]
    if vocab_cols != hidden or pos_cols != hidden or pos_rows < seq_len:
        raise SystemExit("embedding tensor shapes do not match M2 contract")

    expected_block_q = parse_1d_optional(args.full_block_tb_data_sv, "out_proj_block_input_q", hidden)
    expected_ln_q12 = parse_2d(args.context_tb_data_sv, "ln_input_q12_by_token", seq_len, hidden)
    block_input_scale = float(step["last_input_i8_scale"])
    block_requant_mul_q20 = round((1.0 / (Q20 * block_input_scale)) * (1 << BLOCK_MUL_SHIFT))

    token_embedding_q20: list[list[int]] = []
    position_embedding_q20: list[list[int]] = []
    observed_ln_q12: list[list[int]] = []
    observed_block_q: list[int] = []
    for pos, token_id in enumerate(token_ids):
        if token_id < 0 or token_id >= vocab_rows:
            raise SystemExit(f"token id {token_id} outside vocab rows {vocab_rows}")
        token_row: list[int] = []
        position_row: list[int] = []
        ln_row: list[int] = []
        for dim in range(hidden):
            token_q20 = round(wte[token_id * hidden + dim] * Q20)
            position_q20 = round(wpe[pos * hidden + dim] * Q20)
            sum_q20 = token_q20 + position_q20
            token_row.append(token_q20)
            position_row.append(position_q20)
            ln_row.append(round_shift_signed(sum_q20, Q12_SHIFT))
            if pos == seq_len - 1:
                observed_block_q.append(
                    clamp_i8(round_shift_signed(sum_q20 * block_requant_mul_q20, BLOCK_MUL_SHIFT))
                )
        token_embedding_q20.append(token_row)
        position_embedding_q20.append(position_row)
        observed_ln_q12.append(ln_row)

    if observed_ln_q12 != expected_ln_q12:
        max_abs = max(
            abs(actual - expected)
            for actual_row, expected_row in zip(observed_ln_q12, expected_ln_q12)
            for actual, expected in zip(actual_row, expected_row)
        )
        raise SystemExit(f"embedding Q20 add does not reproduce LN Q12 input: max_abs={max_abs}")

    if expected_block_q is None:
        expected_block_q = observed_block_q
    elif observed_block_q != expected_block_q:
        max_abs = max(abs(actual - expected) for actual, expected in zip(observed_block_q, expected_block_q))
        raise SystemExit(f"embedding Q20 add does not reproduce last input i8: max_abs={max_abs}")

    lines = [
        "localparam int EMBED_BLOCK_SEQ = 6;",
        "localparam int EMBED_BLOCK_DIM = 64;",
        "localparam int EMBED_BLOCK_Q_FRAC = 20;",
        "localparam int EMBED_BLOCK_TO_LN_Q12_SHIFT = 8;",
        "localparam int EMBED_BLOCK_REQUANT_SHIFT = 20;",
        f"localparam logic signed [31:0] EMBED_BLOCK_REQUANT_MUL_Q20 = {sv_i32(block_requant_mul_q20)};",
        "logic [15:0] embed_block_expected_token_ids [0:EMBED_BLOCK_SEQ-1];",
        "logic signed [31:0] embed_block_token_embedding_q20 [0:EMBED_BLOCK_SEQ-1][0:EMBED_BLOCK_DIM-1];",
        "logic signed [31:0] embed_block_position_embedding_q20 [0:EMBED_BLOCK_SEQ-1][0:EMBED_BLOCK_DIM-1];",
        "logic signed [15:0] embed_block_expected_ln_input_q12_by_token [0:EMBED_BLOCK_SEQ-1][0:EMBED_BLOCK_DIM-1];",
        "logic signed [7:0] embed_block_expected_last_input_q [0:EMBED_BLOCK_DIM-1];",
        "initial begin",
    ]
    for index, token_id in enumerate(token_ids):
        lines.append(f"  embed_block_expected_token_ids[{index}] = 16'd{token_id};")
    for token_index, row in enumerate(token_embedding_q20):
        for dim, value in enumerate(row):
            lines.append(f"  embed_block_token_embedding_q20[{token_index}][{dim}] = {sv_i32(value)};")
    for token_index, row in enumerate(position_embedding_q20):
        for dim, value in enumerate(row):
            lines.append(f"  embed_block_position_embedding_q20[{token_index}][{dim}] = {sv_i32(value)};")
    for token_index, row in enumerate(expected_ln_q12):
        for dim, value in enumerate(row):
            lines.append(f"  embed_block_expected_ln_input_q12_by_token[{token_index}][{dim}] = {sv_i16(value)};")
    for index, value in enumerate(expected_block_q):
        lines.append(f"  embed_block_expected_last_input_q[{index}] = {sv_i8(value)};")
    lines.append("end")

    args.out_sv.parent.mkdir(parents=True, exist_ok=True)
    args.out_sv.write_text("\n".join(lines) + "\n", encoding="utf-8")
    args.out_json.write_text(
        json.dumps(
            {
                "artifact_name": "task6-m2-embedding-block-input-tb-data",
                "status": "PASS",
                "step": int(step["step"]),
                "token_ids": token_ids,
                "embedding_source": "transformer.wte.weight-q20-selected-token-rows",
                "position_source": "transformer.wpe.weight-q20-selected-position-rows",
                "q_frac": 20,
                "block_requant_mul_q20": block_requant_mul_q20,
                "block_input_checksum": checksum_u8(expected_block_q),
                "ln_input_rows": seq_len,
                "ln_input_cols": hidden,
                "matches_contract_ln_q12": True,
                "matches_contract_last_input_i8": True,
            },
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
