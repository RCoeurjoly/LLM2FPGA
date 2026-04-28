#!/usr/bin/env python3
"""Score lightweight streaming-contract estimates for Task 6 GEMV rungs."""

from __future__ import annotations

import argparse
import csv
from dataclasses import dataclass
import json
import math
from pathlib import Path
from typing import Any


FIELDNAMES = [
    "rung",
    "scope",
    "layers",
    "hidden_size",
    "vocab_size",
    "in_features",
    "out_features",
    "macs_per_token",
    "dsp_lanes",
    "min_compute_cycles",
    "weight_f32_bytes",
    "bias_f32_bytes",
    "input_f32_bytes",
    "output_f32_bytes",
    "min_f32_bytes_per_token",
    "min_int8_weight_bytes_per_token",
    "min_int4_weight_bytes_per_token",
    "f32_bytes_per_cycle",
    "int8_weight_bytes_per_cycle",
    "int4_weight_bytes_per_cycle",
    "notes",
]


@dataclass(frozen=True)
class LinearRow:
    rung: str
    scope: str
    layers: int
    hidden_size: int
    vocab_size: int
    in_features: int
    out_features: int
    weight_numel: int
    weight_f32_bytes: int
    bias_f32_bytes: int
    input_f32_bytes: int
    output_f32_bytes: int
    dsp_lanes: int
    notes: str

    @property
    def macs_per_token(self) -> int:
        return self.in_features * self.out_features

    @property
    def min_compute_cycles(self) -> int:
        return math.ceil(self.macs_per_token / self.dsp_lanes)

    @property
    def min_f32_bytes_per_token(self) -> int:
        return (
            self.weight_f32_bytes
            + self.bias_f32_bytes
            + self.input_f32_bytes
            + self.output_f32_bytes
        )

    @property
    def min_int8_weight_bytes_per_token(self) -> int:
        return (
            self.weight_numel
            + self.bias_f32_bytes
            + self.input_f32_bytes
            + self.output_f32_bytes
        )

    @property
    def min_int4_weight_bytes_per_token(self) -> int:
        return (
            math.ceil(self.weight_numel / 2)
            + self.bias_f32_bytes
            + self.input_f32_bytes
            + self.output_f32_bytes
        )

    def as_dict(self) -> dict[str, Any]:
        cycles = self.min_compute_cycles
        return {
            "rung": self.rung,
            "scope": self.scope,
            "layers": self.layers,
            "hidden_size": self.hidden_size,
            "vocab_size": self.vocab_size,
            "in_features": self.in_features,
            "out_features": self.out_features,
            "macs_per_token": self.macs_per_token,
            "dsp_lanes": self.dsp_lanes,
            "min_compute_cycles": cycles,
            "weight_f32_bytes": self.weight_f32_bytes,
            "bias_f32_bytes": self.bias_f32_bytes,
            "input_f32_bytes": self.input_f32_bytes,
            "output_f32_bytes": self.output_f32_bytes,
            "min_f32_bytes_per_token": self.min_f32_bytes_per_token,
            "min_int8_weight_bytes_per_token": self.min_int8_weight_bytes_per_token,
            "min_int4_weight_bytes_per_token": self.min_int4_weight_bytes_per_token,
            "f32_bytes_per_cycle": round(self.min_f32_bytes_per_token / cycles, 6),
            "int8_weight_bytes_per_cycle": round(
                self.min_int8_weight_bytes_per_token / cycles,
                6,
            ),
            "int4_weight_bytes_per_cycle": round(
                self.min_int4_weight_bytes_per_token / cycles,
                6,
            ),
            "notes": self.notes,
        }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--manifest",
        action="append",
        required=True,
        type=Path,
        help="Weight-pack manifest JSON. Repeat for each linear layer.",
    )
    parser.add_argument("--out-csv", required=True, type=Path)
    parser.add_argument("--out-json", required=True, type=Path)
    parser.add_argument("--dsp-lanes", type=int, default=4)
    return parser.parse_args()


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def tensor_by_name(manifest: dict[str, Any], name: str) -> dict[str, Any]:
    for tensor in manifest["tensors"]:
        if tensor["name"] == name:
            return tensor
    raise SystemExit(f"{manifest.get('module_name', '<unknown>')} has no {name} tensor")


def row_from_manifest(path: Path, dsp_lanes: int) -> LinearRow:
    manifest = load_json(path)
    config = manifest["config"]
    weight = tensor_by_name(manifest, "weight")
    bias = tensor_by_name(manifest, "bias")
    out_features, in_features = weight["shape"]
    module_name = manifest["module_name"]
    return LinearRow(
        rung=manifest["model_label"],
        scope=module_name,
        layers=int(config["num_layers"]),
        hidden_size=int(config["hidden_size"]),
        vocab_size=int(config["vocab_size"]),
        in_features=int(in_features),
        out_features=int(out_features),
        weight_numel=int(weight["numel"]),
        weight_f32_bytes=int(weight["byte_length"]),
        bias_f32_bytes=int(bias["byte_length"]),
        input_f32_bytes=int(in_features) * 4,
        output_f32_bytes=int(out_features) * 4,
        dsp_lanes=dsp_lanes,
        notes=f"from {path}",
    )


def aggregate_rows(rows: list[LinearRow]) -> list[dict[str, Any]]:
    grouped: dict[str, list[LinearRow]] = {}
    for row in rows:
        grouped.setdefault(row.rung, []).append(row)

    aggregates: list[dict[str, Any]] = []
    for rung, group in sorted(grouped.items()):
        if len(group) < 2:
            continue
        layers = group[0].layers
        per_block = {
            "rung": rung,
            "scope": "per_block_mlp",
            "layers": layers,
            "hidden_size": group[0].hidden_size,
            "vocab_size": group[0].vocab_size,
            "in_features": "",
            "out_features": "",
            "macs_per_token": sum(row.macs_per_token for row in group),
            "dsp_lanes": group[0].dsp_lanes,
            "min_compute_cycles": sum(row.min_compute_cycles for row in group),
            "weight_f32_bytes": sum(row.weight_f32_bytes for row in group),
            "bias_f32_bytes": sum(row.bias_f32_bytes for row in group),
            "input_f32_bytes": sum(row.input_f32_bytes for row in group),
            "output_f32_bytes": sum(row.output_f32_bytes for row in group),
            "min_f32_bytes_per_token": sum(
                row.min_f32_bytes_per_token for row in group
            ),
            "min_int8_weight_bytes_per_token": sum(
                row.min_int8_weight_bytes_per_token for row in group
            ),
            "min_int4_weight_bytes_per_token": sum(
                row.min_int4_weight_bytes_per_token for row in group
            ),
            "notes": "sum of available c_fc/c_proj manifests",
        }
        add_rates(per_block)
        aggregates.append(per_block)

        full_stack = dict(per_block)
        full_stack["scope"] = "full_mlp_stack"
        full_stack["macs_per_token"] *= layers
        full_stack["min_compute_cycles"] *= layers
        full_stack["weight_f32_bytes"] *= layers
        full_stack["bias_f32_bytes"] *= layers
        full_stack["input_f32_bytes"] *= layers
        full_stack["output_f32_bytes"] *= layers
        full_stack["min_f32_bytes_per_token"] *= layers
        full_stack["min_int8_weight_bytes_per_token"] *= layers
        full_stack["min_int4_weight_bytes_per_token"] *= layers
        full_stack["notes"] = "per_block_mlp multiplied by layer count"
        add_rates(full_stack)
        aggregates.append(full_stack)

    return aggregates


def add_rates(row: dict[str, Any]) -> None:
    cycles = int(row["min_compute_cycles"])
    row["f32_bytes_per_cycle"] = round(row["min_f32_bytes_per_token"] / cycles, 6)
    row["int8_weight_bytes_per_cycle"] = round(
        row["min_int8_weight_bytes_per_token"] / cycles,
        6,
    )
    row["int4_weight_bytes_per_cycle"] = round(
        row["min_int4_weight_bytes_per_token"] / cycles,
        6,
    )


def write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDNAMES, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def main() -> None:
    args = parse_args()
    if args.dsp_lanes <= 0:
        raise SystemExit("--dsp-lanes must be positive")

    linear_rows = [row_from_manifest(path, args.dsp_lanes) for path in args.manifest]
    rows = [row.as_dict() for row in linear_rows]
    rows.extend(aggregate_rows(linear_rows))
    rows.sort(key=lambda row: (row["rung"], row["scope"]))

    write_csv(args.out_csv, rows)
    args.out_json.parent.mkdir(parents=True, exist_ok=True)
    args.out_json.write_text(
        json.dumps(
            {
                "dsp_lanes": args.dsp_lanes,
                "rows": rows,
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
