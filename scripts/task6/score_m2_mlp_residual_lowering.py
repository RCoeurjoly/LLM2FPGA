#!/usr/bin/env python3
"""Score the M2 ln_2 -> MLP/PWL GELU -> final residual lowering slice."""

from __future__ import annotations

import argparse
from array import array
import datetime as dt
import hashlib
import json
import math
from pathlib import Path
import struct
from typing import Iterable


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CONTRACT = (
    ROOT
    / "artifacts"
    / "task6"
    / "parallel-hypotheses"
    / "h2-tinystories-1m-m2-one-block-contract"
    / "manifest.json"
)
DEFAULT_WEIGHTS = (
    ROOT
    / "artifacts"
    / "task6"
    / "weights_pack"
    / "tiny-stories-1m-m2-block0-int8"
    / "manifest.json"
)
DEFAULT_POST_GELU = (
    ROOT
    / "artifacts"
    / "task6"
    / "parallel-hypotheses"
    / "h2-full-tinystories-1m-block0-c-fc-post-gelu-pwl-requant-rtl-proof.json"
)
DEFAULT_C_PROJ = (
    ROOT
    / "artifacts"
    / "task6"
    / "parallel-hypotheses"
    / "h2-full-tinystories-1m-block0-pwl-mlp-chain-c-proj-requant-rtl-proof.json"
)
DEFAULT_RESIDUAL = (
    ROOT
    / "artifacts"
    / "task6"
    / "parallel-hypotheses"
    / "h2-full-tinystories-1m-block0-pwl-mlp-chain-residual-add-rtl-proof.json"
)
DEFAULT_OUT = (
    ROOT
    / "artifacts"
    / "task6"
    / "parallel-hypotheses"
    / "h2-tinystories-1m-m2-mlp-residual-lowering-score.json"
)
QMAX = 127


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--contract-manifest", type=Path, default=DEFAULT_CONTRACT)
    parser.add_argument("--weight-manifest", type=Path, default=DEFAULT_WEIGHTS)
    parser.add_argument("--post-gelu-proof-json", type=Path, default=DEFAULT_POST_GELU)
    parser.add_argument("--c-proj-proof-json", type=Path, default=DEFAULT_C_PROJ)
    parser.add_argument("--residual-add-proof-json", type=Path, default=DEFAULT_RESIDUAL)
    parser.add_argument("--out-json", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--mlp-nrmse-threshold", type=float, default=0.08)
    parser.add_argument("--residual-nrmse-threshold", type=float, default=0.05)
    return parser.parse_args()


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def read_f32(path: Path) -> list[float]:
    values = array("f")
    values.frombytes(path.read_bytes())
    return [float(item) for item in values]


def read_i8(path: Path) -> list[int]:
    values = array("b")
    values.frombytes(path.read_bytes())
    return [int(item) for item in values]


def reshape2(values: list[float], rows: int, cols: int) -> list[list[float]]:
    if len(values) != rows * cols:
        raise SystemExit(f"length {len(values)} does not match shape [{rows}, {cols}]")
    return [values[row * cols : (row + 1) * cols] for row in range(rows)]


def flatten(rows: list[list[float]]) -> list[float]:
    return [item for row in rows for item in row]


def metrics(actual: Iterable[float], expected: Iterable[float]) -> dict[str, float]:
    actual_list = [float(item) for item in actual]
    expected_list = [float(item) for item in expected]
    if len(actual_list) != len(expected_list):
        raise SystemExit(f"metric length mismatch {len(actual_list)} vs {len(expected_list)}")
    if not actual_list:
        raise SystemExit("cannot score empty vector")
    sq_err = 0.0
    sq_sig = 0.0
    max_abs = 0.0
    mean_abs = 0.0
    for actual, expect in zip(actual_list, expected_list):
        err = actual - expect
        abs_err = abs(err)
        sq_err += err * err
        sq_sig += expect * expect
        max_abs = max(max_abs, abs_err)
        mean_abs += abs_err
    rmse = math.sqrt(sq_err / len(actual_list))
    signal_rms = math.sqrt(sq_sig / len(actual_list))
    return {
        "count": len(actual_list),
        "rmse": rmse,
        "signal_rms": signal_rms,
        "normalized_rmse": 0.0 if signal_rms == 0.0 else rmse / signal_rms,
        "max_abs_error": max_abs,
        "mean_abs_error": mean_abs / len(actual_list),
    }


def tensor_path(base: Path, tensor_meta: dict) -> Path:
    return base / tensor_meta["filename"]


def weight_tensor(weight_manifest: dict, name: str) -> dict:
    for tensor in weight_manifest["tensors"]:
        if tensor["name"] == name:
            return tensor
    raise SystemExit(f"missing weight tensor {name}")


def quantize_row_i8(row: list[float]) -> tuple[list[int], float]:
    max_abs = max(abs(item) for item in row)
    if max_abs == 0.0:
        return [0 for _ in row], 1.0
    scale = max_abs / QMAX
    return [max(-QMAX, min(QMAX, int(round(item / scale)))) for item in row], scale


def round_shift_signed(value: int, shift: int) -> int:
    if shift == 0:
        return value
    half = 1 << (shift - 1)
    if value >= 0:
        return (value + half) >> shift
    return -(((-value) + half) >> shift)


def saturate_i8(value: int) -> int:
    return max(-QMAX, min(QMAX, int(value)))


def fixed_post_gelu_pwl_q(x_q: int, x_nodes: list[int], y_nodes: list[int]) -> int:
    if len(x_nodes) != len(y_nodes):
        raise SystemExit("PWL GELU x/y node length mismatch")
    if len(x_nodes) != 16:
        raise SystemExit("RTL currently supports exactly 16 PWL GELU nodes")
    if x_q <= x_nodes[0]:
        return y_nodes[0]
    if x_q >= x_nodes[-1]:
        return y_nodes[-1]
    segment = 0
    for index in range(len(x_nodes) - 1):
        if x_nodes[index] <= x_q <= x_nodes[index + 1]:
            segment = index
            break
    x0 = x_nodes[segment]
    x1 = x_nodes[segment + 1]
    y0 = y_nodes[segment]
    y1 = y_nodes[segment + 1]
    numerator = (x_q - x0) * (y1 - y0)
    denominator = x1 - x0
    recip_shift = 16
    recip_q = ((1 << recip_shift) + (denominator // 2)) // denominator
    delta = round_shift_signed(numerator * recip_q, recip_shift)
    return saturate_i8(y0 + delta)


def pack_i8(values: list[int]) -> bytes:
    return bytes((int(value) & 0xFF) for value in values)


def pack_i32(values: list[int]) -> bytes:
    return b"".join(struct.pack("<i", int(value)) for value in values)


def dot_i8(row_q: list[int], weight_q: list[int], offset: int, in_features: int) -> int:
    acc = 0
    for index in range(in_features):
        acc += row_q[index] * weight_q[offset + index]
    return acc


def replay_mlp_row(
    ln2_row: list[float],
    c_fc_weight_q: list[int],
    c_fc_scales: list[float],
    c_fc_bias: list[float],
    c_proj_weight_q: list[int],
    c_proj_scales: list[float],
    c_proj_bias: list[float],
    fixed_point: dict,
    post_gelu_output_scale: float,
    c_proj_output_scale: float,
) -> tuple[list[float], dict]:
    c_fc_out_features = len(c_fc_scales)
    c_fc_in_features = len(ln2_row)
    c_proj_out_features = len(c_proj_scales)
    c_proj_in_features = c_fc_out_features
    ln2_q, ln2_scale = quantize_row_i8(ln2_row)

    x_frac = int(fixed_point["x_frac"])
    scale_shift = int(fixed_point["scale_shift"])
    c_proj_shift = int(fixed_point["c_proj_output_requant_shift"])
    x_nodes = [int(value) for value in fixed_point["gelu_pwl_x_nodes"]]
    y_nodes = [int(value) for value in fixed_point["gelu_pwl_y_nodes"]]

    c_fc_accs: list[int] = []
    c_fc_x_q: list[int] = []
    post_gelu_q: list[int] = []
    for out_index in range(c_fc_out_features):
        acc = dot_i8(ln2_q, c_fc_weight_q, out_index * c_fc_in_features, c_fc_in_features)
        scale_mul = round(ln2_scale * c_fc_scales[out_index] * (1 << (x_frac + scale_shift)))
        bias_q = round(c_fc_bias[out_index] * (1 << x_frac))
        x_q = round_shift_signed(acc * scale_mul, scale_shift) + bias_q
        c_fc_accs.append(acc)
        c_fc_x_q.append(x_q)
        post_gelu_q.append(fixed_post_gelu_pwl_q(x_q, x_nodes, y_nodes))

    c_proj_q: list[int] = []
    c_proj_accs: list[int] = []
    for out_index in range(c_proj_out_features):
        acc = dot_i8(post_gelu_q, c_proj_weight_q, out_index * c_proj_in_features, c_proj_in_features)
        scale_mul = round(
            (post_gelu_output_scale * c_proj_scales[out_index] / c_proj_output_scale)
            * (1 << c_proj_shift)
        )
        bias_q = round(c_proj_bias[out_index] / c_proj_output_scale)
        output_q = saturate_i8(round_shift_signed(acc * scale_mul, c_proj_shift) + bias_q)
        c_proj_accs.append(acc)
        c_proj_q.append(output_q)

    return [value * c_proj_output_scale for value in c_proj_q], {
        "ln2_scale": ln2_scale,
        "ln2_q_min": min(ln2_q),
        "ln2_q_max": max(ln2_q),
        "c_fc_accumulator_min": min(c_fc_accs),
        "c_fc_accumulator_max": max(c_fc_accs),
        "c_fc_x_q_min": min(c_fc_x_q),
        "c_fc_x_q_max": max(c_fc_x_q),
        "post_gelu_q_min": min(post_gelu_q),
        "post_gelu_q_max": max(post_gelu_q),
        "c_proj_accumulator_min": min(c_proj_accs),
        "c_proj_accumulator_max": max(c_proj_accs),
        "c_proj_q_min": min(c_proj_q),
        "c_proj_q_max": max(c_proj_q),
        "ln2_q": ln2_q,
        "post_gelu_q": post_gelu_q,
        "c_proj_q": c_proj_q,
        "c_fc_accs": c_fc_accs,
        "c_proj_accs": c_proj_accs,
    }


def read_weight_pack(weight_base: Path, weights: dict, name: str) -> tuple[list[int], list[float], int, int, dict]:
    tensor = weight_tensor(weights, name)
    out_features, in_features = [int(dim) for dim in tensor["shape"]]
    return (
        read_i8(weight_base / tensor["q_filename"]),
        read_f32(weight_base / tensor["scale_filename"]),
        out_features,
        in_features,
        tensor,
    )


def main() -> int:
    args = parse_args()
    contract = load_json(args.contract_manifest)
    weights = load_json(args.weight_manifest)
    post_gelu_proof = load_json(args.post_gelu_proof_json)
    c_proj_proof = load_json(args.c_proj_proof_json)
    residual_proof = load_json(args.residual_add_proof_json)
    contract_base = args.contract_manifest.parent
    weight_base = args.weight_manifest.parent

    c_fc_weight_q, c_fc_scales, c_fc_out, c_fc_in, c_fc_tensor = read_weight_pack(
        weight_base,
        weights,
        "transformer.h.0.mlp.c_fc.weight",
    )
    c_proj_weight_q, c_proj_scales, c_proj_out, c_proj_in, c_proj_tensor = read_weight_pack(
        weight_base,
        weights,
        "transformer.h.0.mlp.c_proj.weight",
    )
    if c_proj_in != c_fc_out:
        raise SystemExit(f"c_proj input {c_proj_in} does not match c_fc output {c_fc_out}")
    c_fc_bias = read_f32(weight_base / weight_tensor(weights, "transformer.h.0.mlp.c_fc.bias")["filename"])
    c_proj_bias = read_f32(weight_base / weight_tensor(weights, "transformer.h.0.mlp.c_proj.bias")["filename"])

    fixed_point = dict(c_proj_proof["fixed_point"])
    if fixed_point.get("gelu_approx_mode") != "pwl":
        raise SystemExit("M2 MLP scorer expects a PWL GELU proof")
    post_gelu_output_scale = float(post_gelu_proof["quantization"]["output_scale"])
    c_proj_output_scale = float(c_proj_proof["quantization"]["c_proj_output_scale"])

    all_mlp_actual: list[float] = []
    all_mlp_expected: list[float] = []
    all_residual_actual: list[float] = []
    all_residual_expected: list[float] = []
    all_ln2_q: list[int] = []
    all_post_gelu_q: list[int] = []
    all_c_proj_q: list[int] = []
    all_c_fc_accs: list[int] = []
    all_c_proj_accs: list[int] = []
    step_results: list[dict] = []

    for step in contract["steps"]:
        step_index = int(step["step"])
        seq_len = int(step["sequence_length"])
        hidden = int(step["tensors"]["ln2_output_f32"]["shape"][-1])
        ln2_rows = reshape2(read_f32(tensor_path(contract_base, step["tensors"]["ln2_output_f32"])), seq_len, hidden)
        mlp_expected = reshape2(read_f32(tensor_path(contract_base, step["tensors"]["mlp_output_f32"])), seq_len, hidden)
        block_input = reshape2(read_f32(tensor_path(contract_base, step["tensors"]["block_input_f32"])), seq_len, hidden)
        attention_output = reshape2(
            read_f32(tensor_path(contract_base, step["tensors"]["attention_output_f32"])),
            seq_len,
            hidden,
        )
        block_expected = reshape2(read_f32(tensor_path(contract_base, step["tensors"]["block_output_f32"])), seq_len, hidden)

        mlp_actual: list[list[float]] = []
        row_debug: list[dict] = []
        for row in ln2_rows:
            actual_row, debug = replay_mlp_row(
                row,
                c_fc_weight_q,
                c_fc_scales,
                c_fc_bias,
                c_proj_weight_q,
                c_proj_scales,
                c_proj_bias,
                fixed_point,
                post_gelu_output_scale,
                c_proj_output_scale,
            )
            mlp_actual.append(actual_row)
            row_debug.append({key: value for key, value in debug.items() if not isinstance(value, list)})
            all_ln2_q.extend(debug["ln2_q"])
            all_post_gelu_q.extend(debug["post_gelu_q"])
            all_c_proj_q.extend(debug["c_proj_q"])
            all_c_fc_accs.extend(debug["c_fc_accs"])
            all_c_proj_accs.extend(debug["c_proj_accs"])

        residual_actual = [
            [
                block_input[row][col] + attention_output[row][col] + mlp_actual[row][col]
                for col in range(hidden)
            ]
            for row in range(seq_len)
        ]

        mlp_result = metrics(flatten(mlp_actual), flatten(mlp_expected))
        residual_result = metrics(flatten(residual_actual), flatten(block_expected))
        all_mlp_actual.extend(flatten(mlp_actual))
        all_mlp_expected.extend(flatten(mlp_expected))
        all_residual_actual.extend(flatten(residual_actual))
        all_residual_expected.extend(flatten(block_expected))
        step_results.append(
            {
                "step": step_index,
                "sequence_length": seq_len,
                "mlp_output_replay": mlp_result,
                "final_residual_replay": residual_result,
                "row_quantization_ranges": {
                    "ln2_scale_min": min(item["ln2_scale"] for item in row_debug),
                    "ln2_scale_max": max(item["ln2_scale"] for item in row_debug),
                    "c_fc_x_q_min": min(item["c_fc_x_q_min"] for item in row_debug),
                    "c_fc_x_q_max": max(item["c_fc_x_q_max"] for item in row_debug),
                    "post_gelu_q_min": min(item["post_gelu_q_min"] for item in row_debug),
                    "post_gelu_q_max": max(item["post_gelu_q_max"] for item in row_debug),
                    "c_proj_q_min": min(item["c_proj_q_min"] for item in row_debug),
                    "c_proj_q_max": max(item["c_proj_q_max"] for item in row_debug),
                },
            }
        )

    aggregate = {
        "mlp_output_replay": metrics(all_mlp_actual, all_mlp_expected),
        "final_residual_replay": metrics(all_residual_actual, all_residual_expected),
    }
    verdict = (
        aggregate["mlp_output_replay"]["normalized_rmse"] <= args.mlp_nrmse_threshold
        and aggregate["final_residual_replay"]["normalized_rmse"] <= args.residual_nrmse_threshold
        and post_gelu_proof.get("status") == "PASS"
        and c_proj_proof.get("status") == "PASS"
        and residual_proof.get("status") == "PASS"
    )
    artifact = {
        "schema_version": 1,
        "artifact_name": "h2-tinystories-1m-m2-mlp-residual-lowering-score",
        "status": "PASS" if verdict else "FAIL",
        "date": dt.datetime.now(dt.timezone.utc).isoformat(),
        "stage": "M2-one-full-block-mlp-residual-lowering-replay",
        "milestone_target": "M2-one-full-block",
        "live_compute": False,
        "artifact_role": "offline-mlp-residual-lowering-score",
        "contract_manifest": str(args.contract_manifest),
        "weight_manifest": str(args.weight_manifest),
        "source_proofs": {
            "post_gelu": str(args.post_gelu_proof_json),
            "c_proj": str(args.c_proj_proof_json),
            "residual_add": str(args.residual_add_proof_json),
        },
        "policy": {
            "input_boundary": "oracle ln_2 tensors from the M2 one-block contract",
            "c_fc": "per-token symmetric int8 activations, rowwise symmetric int8 weights, f32 row scales, f32 bias converted to q12",
            "gelu": "existing 16-node fixed-point PWL GELU table producing int8 post-GELU activation",
            "c_proj": "rowwise symmetric int8 weights, fixed int8 output scale from the accepted c_proj proof",
            "final_residual": "oracle block input + oracle attention output + replayed MLP output, compared to block_output_f32",
            "isolation_note": "This gate isolates the MLP half. A later end-to-end gate should feed replayed attention residual into ln_2 and this MLP replay.",
        },
        "thresholds": {
            "mlp_output_normalized_rmse": args.mlp_nrmse_threshold,
            "final_residual_normalized_rmse": args.residual_nrmse_threshold,
        },
        "fixed_point": fixed_point,
        "quantization": {
            "post_gelu_output_scale": post_gelu_output_scale,
            "c_proj_output_scale": c_proj_output_scale,
            "c_fc_weight_quantization": c_fc_tensor["quantization"],
            "c_proj_weight_quantization": c_proj_tensor["quantization"],
            "ln2_q_min": min(all_ln2_q),
            "ln2_q_max": max(all_ln2_q),
            "post_gelu_q_min": min(all_post_gelu_q),
            "post_gelu_q_max": max(all_post_gelu_q),
            "c_proj_q_min": min(all_c_proj_q),
            "c_proj_q_max": max(all_c_proj_q),
            "c_fc_accumulator_min": min(all_c_fc_accs),
            "c_fc_accumulator_max": max(all_c_fc_accs),
            "c_proj_accumulator_min": min(all_c_proj_accs),
            "c_proj_accumulator_max": max(all_c_proj_accs),
            "ln2_q_sha256": hashlib.sha256(pack_i8(all_ln2_q)).hexdigest(),
            "post_gelu_q_sha256": hashlib.sha256(pack_i8(all_post_gelu_q)).hexdigest(),
            "c_proj_q_sha256": hashlib.sha256(pack_i8(all_c_proj_q)).hexdigest(),
            "c_fc_accumulator_sha256": hashlib.sha256(pack_i32(all_c_fc_accs)).hexdigest(),
            "c_proj_accumulator_sha256": hashlib.sha256(pack_i32(all_c_proj_accs)).hexdigest(),
        },
        "aggregate": aggregate,
        "steps": step_results,
        "next_stage": (
            "compose attention replay plus MLP replay into one full-block fixed-point gate"
            if verdict
            else "tighten MLP scale policy before RTL promotion"
        ),
    }
    args.out_json.parent.mkdir(parents=True, exist_ok=True)
    args.out_json.write_text(json.dumps(artifact, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(args.out_json)
    return 0 if verdict else 1


if __name__ == "__main__":
    raise SystemExit(main())
