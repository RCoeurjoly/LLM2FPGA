#!/usr/bin/env python3
"""Emit board selftest data for v4k residual-add plus output-head top1."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path
from typing import Any

from gen_task6_int8_l2_c_proj_from_post_gelu_tb_data import (
    addr_width,
    pack_i8,
    quantize_symmetric,
    saturate_i8,
    signed_hex,
)
from gen_task6_int8_l2_mlp_chain_residual_add_tb_data import (
    build_payload as build_residual_add_payload,
)
from gen_task6_int8_vocab_output_head_top1_tb_data import (
    build_payload as build_output_head_payload,
    load_representative_core_builder,
    set_representative_core_env,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--artifact-name",
        default="h2-v4k-int8-l2-residual-add-output-head-selftest",
    )
    parser.add_argument("--model-path", required=True, type=Path)
    parser.add_argument("--adapter-path", type=Path)
    parser.add_argument("--residual-contract-manifest", required=True, type=Path)
    parser.add_argument("--residual-boundary-json", required=True, type=Path)
    parser.add_argument("--c-fc-contract-manifest", required=True, type=Path)
    parser.add_argument("--c-fc-weight-pack-manifest", required=True, type=Path)
    parser.add_argument("--c-proj-contract-manifest", required=True, type=Path)
    parser.add_argument("--c-proj-weight-pack-manifest", required=True, type=Path)
    parser.add_argument("--post-gelu-requant-json", required=True, type=Path)
    parser.add_argument("--c-proj-output-boundary-json", required=True, type=Path)
    parser.add_argument("--c-proj-requant-rtl-proof-json", required=True, type=Path)
    parser.add_argument("--residual-add-rtl-proof-json", required=True, type=Path)
    parser.add_argument("--vocab-size", type=int, default=4096)
    parser.add_argument("--physical-vocab-size", type=int)
    parser.add_argument("--num-layers", type=int, default=1)
    parser.add_argument("--max-position-embeddings", type=int, default=128)
    parser.add_argument("--window-size", type=int, default=64)
    parser.add_argument("--hidden-size", type=int, default=64)
    parser.add_argument("--num-heads", type=int, default=16)
    parser.add_argument("--model-label", default="tiny-stories-v4k-h64-l1")
    parser.add_argument("--lanes", type=int, default=4)
    parser.add_argument("--tile-out-dim", type=int, default=64)
    parser.add_argument(
        "--weight-quantization",
        choices=("int8", "ternary2"),
        default="int8",
    )
    parser.add_argument("--normalized-rmse-threshold", type=float, default=0.02)
    parser.add_argument("--c-proj-output-requant-shift", type=int, default=24)
    parser.add_argument("--residual-add-requant-shift", type=int, default=24)
    parser.add_argument("--out-sv", type=Path)
    parser.add_argument("--out-vocab-mem", type=Path)
    parser.add_argument("--out-json", type=Path)
    return parser.parse_args()


def make_residual_args(args: argparse.Namespace) -> argparse.Namespace:
    return argparse.Namespace(
        residual_contract_manifest=args.residual_contract_manifest,
        residual_boundary_json=args.residual_boundary_json,
        c_fc_contract_manifest=args.c_fc_contract_manifest,
        c_fc_weight_pack_manifest=args.c_fc_weight_pack_manifest,
        c_proj_contract_manifest=args.c_proj_contract_manifest,
        c_proj_weight_pack_manifest=args.c_proj_weight_pack_manifest,
        post_gelu_requant_json=args.post_gelu_requant_json,
        c_proj_output_boundary_json=args.c_proj_output_boundary_json,
        c_proj_requant_rtl_proof_json=args.c_proj_requant_rtl_proof_json,
        artifact_name="h2-v4k-int8-l2-mlp-chain-residual-add-rtl-proof",
        out_sv=None,
        out_json=None,
        sim_result_json=None,
        yosys_stat_json=None,
        mapped_utilization_summary_json=None,
        normalized_rmse_threshold=args.normalized_rmse_threshold,
        c_proj_output_requant_shift=args.c_proj_output_requant_shift,
        residual_add_requant_shift=args.residual_add_requant_shift,
    )


def make_output_head_args(args: argparse.Namespace) -> argparse.Namespace:
    return argparse.Namespace(
        artifact_name="h2-v4k-int8-vocab-output-head-top1-rtl-proof",
        model_path=args.model_path,
        adapter_path=args.adapter_path,
        residual_add_rtl_proof_json=args.residual_add_rtl_proof_json,
        residual_contract_manifest=args.residual_contract_manifest,
        residual_boundary_json=args.residual_boundary_json,
        c_fc_contract_manifest=args.c_fc_contract_manifest,
        c_fc_weight_pack_manifest=args.c_fc_weight_pack_manifest,
        c_proj_contract_manifest=args.c_proj_contract_manifest,
        c_proj_weight_pack_manifest=args.c_proj_weight_pack_manifest,
        post_gelu_requant_json=args.post_gelu_requant_json,
        c_proj_output_boundary_json=args.c_proj_output_boundary_json,
        c_proj_requant_rtl_proof_json=args.c_proj_requant_rtl_proof_json,
        vocab_size=args.vocab_size,
        physical_vocab_size=args.physical_vocab_size,
        num_layers=args.num_layers,
        max_position_embeddings=args.max_position_embeddings,
        window_size=args.window_size,
        hidden_size=args.hidden_size,
        num_heads=args.num_heads,
        model_label=args.model_label,
        out_sv=None,
        out_json=None,
        sim_result_json=None,
        yosys_stat_json=None,
        mapped_utilization_summary_json=None,
        lanes=args.lanes,
        tile_out_dim=args.tile_out_dim,
        weight_quantization=args.weight_quantization,
        c_proj_output_requant_shift=args.c_proj_output_requant_shift,
        residual_add_requant_shift=args.residual_add_requant_shift,
    )


VOCAB_WEIGHT_ASSIGNMENT_RE = re.compile(
    r"^  packed_weight_values\[(?P<index>\d+)\] = 32'h(?P<value>[0-9a-fA-F]+);$"
)
RESIDUAL_OUTPUT_ASSIGNMENT_RE = re.compile(
    r"^  expected_residual_add_output_q_values\[(?P<index>\d+)\] = 8'sh(?P<value>[0-9a-fA-F]+);$"
)


def extract_vocab_weight_values(output_sv: str, expected_words: int) -> list[int]:
    values: list[int | None] = [None] * expected_words
    for line in output_sv.splitlines():
        match = VOCAB_WEIGHT_ASSIGNMENT_RE.match(line)
        if match is None:
            continue
        index = int(match.group("index"))
        if index < 0 or index >= expected_words:
            raise SystemExit(
                f"output-head vocab weight index {index} outside 0..{expected_words - 1}"
            )
        values[index] = int(match.group("value"), 16)
    if all(value is None for value in values):
        raise SystemExit("output-head data did not contain packed vocab weights")
    missing = [str(index) for index, value in enumerate(values) if value is None]
    if missing:
        sample = ", ".join(missing[:8])
        raise SystemExit(f"output-head data missed vocab weight words: {sample}")
    return [int(value) for value in values]


def extract_expected_residual_values(residual_sv: str, expected_words: int) -> list[int]:
    values: list[int | None] = [None] * expected_words
    for line in residual_sv.splitlines():
        match = RESIDUAL_OUTPUT_ASSIGNMENT_RE.match(line)
        if match is None:
            continue
        index = int(match.group("index"))
        if index < 0 or index >= expected_words:
            raise SystemExit(
                f"expected residual index {index} outside 0..{expected_words - 1}"
            )
        values[index] = int(match.group("value"), 16) & 0xFF
    missing = [str(index) for index, value in enumerate(values) if value is None]
    if missing:
        sample = ", ".join(missing[:8])
        raise SystemExit(f"residual data missed expected output bytes: {sample}")
    return [int(value) for value in values]


def byte_checksum(values: list[int]) -> int:
    return sum(value & 0xFF for value in values) & 0xFFFFFFFF


def load_embedding_probe(args: argparse.Namespace) -> dict[str, Any]:
    residual_contract = json.loads(args.residual_contract_manifest.read_text())
    sample_input_ids = residual_contract.get("sample_input_ids", [[0]])
    token_id = int(sample_input_ids[0][0])
    position_id = 0

    set_representative_core_env(args)
    build_model = load_representative_core_builder(args.adapter_path)
    model = build_model(str(args.model_path))
    token_embedding = model.transformer.wte.weight.detach().cpu().contiguous()
    position_embedding = model.transformer.wpe.weight.detach().cpu().contiguous()

    physical_vocab_size = args.physical_vocab_size or args.vocab_size
    if list(token_embedding.shape) != [physical_vocab_size, args.hidden_size]:
        raise SystemExit(
            "unexpected token embedding shape "
            f"{list(token_embedding.shape)}"
        )
    if list(position_embedding.shape) != [
        args.max_position_embeddings,
        args.hidden_size,
    ]:
        raise SystemExit(
            "unexpected position embedding shape "
            f"{list(position_embedding.shape)}"
        )
    if token_id < 0 or token_id >= args.vocab_size:
        raise SystemExit(
            f"token id {token_id} outside logical vocab size {args.vocab_size}"
        )

    vocab_weight_f32 = [float(value) for value in token_embedding.flatten().tolist()]
    vocab_weight_q, vocab_weight_scale = quantize_symmetric(vocab_weight_f32, 8)
    token_q = vocab_weight_q[
        token_id * args.hidden_size:(token_id + 1) * args.hidden_size
    ]
    position_row_f32 = [
        float(value)
        for value in position_embedding[position_id].flatten().tolist()
    ]
    position_q = [
        saturate_i8(round(value / vocab_weight_scale))
        for value in position_row_f32
    ]
    combined_q = [
        saturate_i8(token + position)
        for token, position in zip(token_q, position_q, strict=True)
    ]

    return {
        "token_id": token_id,
        "position_id": position_id,
        "vocab_weight_scale": vocab_weight_scale,
        "token_q": token_q,
        "position_q": position_q,
        "combined_q": combined_q,
        "token_checksum": byte_checksum(token_q),
        "position_checksum": byte_checksum(position_q),
        "combined_checksum": byte_checksum(combined_q),
        "token_q_sha256": hashlib.sha256(pack_i8(token_q)).hexdigest(),
        "position_q_sha256": hashlib.sha256(pack_i8(position_q)).hexdigest(),
        "combined_q_sha256": hashlib.sha256(pack_i8(combined_q)).hexdigest(),
    }


def inject_vocab_data(
    residual_sv: str,
    output_payload: dict[str, Any],
    output_sv: str,
    embedding_probe: dict[str, Any],
) -> tuple[str, str]:
    lines = residual_sv.strip().splitlines()
    try:
        initial_index = lines.index("initial begin")
    except ValueError as exc:
        raise SystemExit("residual data did not contain an initial block") from exc
    if not lines or lines[-1] != "end":
        raise SystemExit("residual data did not end with the expected initial block")

    contract = output_payload["rtl_contract"]
    top1 = output_payload["top1"]
    vocab_size = int(contract["vocab_size"])
    valid_vocab_size = int(contract.get("valid_vocab_size", vocab_size))
    in_dim = int(contract["in_dim"])
    lanes = int(contract["lanes"])
    tile_out_dim = int(contract["tile_out_dim"])
    packed_weight_words = int(contract["packed_weight_words"])
    acc_width = 32
    packed_weight_addr_width = addr_width(packed_weight_words)
    activation_addr_width = addr_width(in_dim)
    vocab_addr_width = addr_width(vocab_size)
    top_index = int(top1["fixed_int8_top_index"])
    top_acc = int(top1["fixed_int8_top_acc"])
    values = extract_vocab_weight_values(output_sv, packed_weight_words)
    expected_residual_values = extract_expected_residual_values(residual_sv, in_dim)
    vocab_checksum = sum(values) & 0xFFFFFFFF
    activation_byte_checksum = sum(expected_residual_values) & 0xFFFFFFFF
    embed_token_id = int(embedding_probe["token_id"])
    embed_position_id = int(embedding_probe["position_id"])
    embed_word_addr_width = addr_width(in_dim)
    embed_token_group = embed_token_id // lanes
    embed_token_lane = embed_token_id % lanes
    embed_token_base_word_addr = embed_token_group * in_dim

    declarations = [
        f"localparam int VOCAB_IN_DIM = {in_dim};",
        f"localparam int VOCAB_SIZE = {vocab_size};",
        f"localparam int VOCAB_VALID_SIZE = {valid_vocab_size};",
        f"localparam int VOCAB_TILE_OUT_DIM = {tile_out_dim};",
        f"localparam int VOCAB_LANES = {lanes};",
        f"localparam int VOCAB_ACC_WIDTH = {acc_width};",
        f"localparam int VOCAB_PACKED_WEIGHT_WORDS = {packed_weight_words};",
        f"localparam int VOCAB_PACKED_WEIGHT_ADDR_WIDTH = {packed_weight_addr_width};",
        f"localparam int VOCAB_ACTIVATION_ADDR_WIDTH = {activation_addr_width};",
        f"localparam int VOCAB_ADDR_WIDTH = {vocab_addr_width};",
        f"localparam int VOCAB_WEIGHT_MODE = {int(contract.get('weight_dtype') == 'ternary2-per-tensor-symmetric')};",
        (
            "localparam logic [VOCAB_ADDR_WIDTH - 1:0] "
            f"EXPECTED_TOP_INDEX = {vocab_addr_width}'d{top_index};"
        ),
        (
            "localparam logic signed [VOCAB_ACC_WIDTH - 1:0] "
            f"EXPECTED_TOP_ACC = {acc_width}'sh{signed_hex(top_acc, acc_width)};"
        ),
        (
            "localparam logic [31:0] EXPECTED_VOCAB_WEIGHT_CHECKSUM = "
            f"32'h{vocab_checksum:08x};"
        ),
        (
            "localparam logic [31:0] EXPECTED_VOCAB_FIRST_WORD = "
            f"32'h{values[0]:08x};"
        ),
        (
            "localparam logic [31:0] EXPECTED_VOCAB_LAST_WORD = "
            f"32'h{values[-1]:08x};"
        ),
        (
            "localparam logic [31:0] EXPECTED_HEAD_ACTIVATION_BYTE_CHECKSUM = "
            f"32'h{activation_byte_checksum:08x};"
        ),
        f"localparam int EMBED_TOKEN_ID = {embed_token_id};",
        f"localparam int EMBED_POSITION_ID = {embed_position_id};",
        f"localparam int EMBED_WORDS = {in_dim};",
        f"localparam int EMBED_WORD_ADDR_WIDTH = {embed_word_addr_width};",
        f"localparam int EMBED_TOKEN_LANE = {embed_token_lane};",
        (
            "localparam logic [VOCAB_PACKED_WEIGHT_ADDR_WIDTH - 1:0] "
            f"EMBED_TOKEN_BASE_WORD_ADDR = "
            f"{packed_weight_addr_width}'d{embed_token_base_word_addr};"
        ),
        (
            "localparam logic [31:0] EXPECTED_EMBED_TOKEN_CHECKSUM = "
            f"32'h{embedding_probe['token_checksum']:08x};"
        ),
        (
            "localparam logic [31:0] EXPECTED_EMBED_POSITION_CHECKSUM = "
            f"32'h{embedding_probe['position_checksum']:08x};"
        ),
        (
            "localparam logic [31:0] EXPECTED_EMBED_COMBINED_CHECKSUM = "
            f"32'h{embedding_probe['combined_checksum']:08x};"
        ),
        "logic signed [7:0] token_embedding_q_values [0:EMBED_WORDS - 1];",
        "logic signed [7:0] position_embedding_q_values [0:EMBED_WORDS - 1];",
    ]
    assignments = (
        [
            f"  token_embedding_q_values[{index}] = 8'sh{signed_hex(value, 8)};"
            for index, value in enumerate(embedding_probe["token_q"])
        ]
        + [
        f"  position_embedding_q_values[{index}] = 8'sh{signed_hex(value, 8)};"
        for index, value in enumerate(embedding_probe["position_q"])
        ]
    )
    sv_text = (
        "\n".join(
            lines[:initial_index]
            + declarations
            + lines[initial_index:-1]
            + assignments
            + lines[-1:]
        )
        + "\n"
    )
    mem_text = "\n".join(f"{value:08x}" for value in values) + "\n"
    return sv_text, mem_text


def write_phase_banked_vocab_mem_files(
    out_vocab_mem: Path,
    vocab_mem_text: str,
    *,
    vocab_size: int,
    tile_out_dim: int,
) -> None:
    values = [line for line in vocab_mem_text.splitlines() if line]
    if vocab_size % tile_out_dim != 0:
        raise SystemExit(
            f"vocab_size {vocab_size} is not divisible by tile_out_dim {tile_out_dim}"
        )
    phases = vocab_size // tile_out_dim
    if len(values) % phases != 0:
        raise SystemExit(
            f"packed vocab word count {len(values)} is not divisible by phases {phases}"
        )
    words_per_phase = len(values) // phases
    phase_paths: list[Path] = []
    for phase in range(phases):
        phase_path = out_vocab_mem.parent / f"vocab_packed_weights_phase_{phase:02d}.mem"
        phase_values = values[
            phase * words_per_phase:(phase + 1) * words_per_phase
        ]
        phase_path.write_text("\n".join(phase_values) + "\n", encoding="utf-8")
        phase_paths.append(phase_path)

    init_lines: list[str] = []
    for phase, phase_path in enumerate(phase_paths):
        init_lines.extend(
            [
                f"      if (weight_phase == {phase}) begin : gen_readmemh_phase_{phase:02d}",
                "        initial begin",
                f"          $readmemh(\"{phase_path}\", vocab_packed_weight_phase_rom);",
                "        end",
                "      end",
            ]
        )
    (out_vocab_mem.parent / "vocab_loader_phase_readmemh_cases.sv").write_text(
        "\n".join(init_lines) + "\n",
        encoding="utf-8",
    )


def build_payload(args: argparse.Namespace) -> tuple[dict[str, Any], str, str]:
    residual_payload, residual_sv = build_residual_add_payload(
        make_residual_args(args)
    )
    output_payload, output_sv = build_output_head_payload(make_output_head_args(args))
    embedding_probe = load_embedding_probe(args)
    combined_sv, vocab_mem = inject_vocab_data(
        residual_sv,
        output_payload,
        output_sv,
        embedding_probe,
    )

    residual_pass = residual_payload.get("status") in {"PASS", "partial"}
    output_pass = output_payload.get("status") in {"PASS", "partial"}
    top1 = output_payload["top1"]
    output_weight_quantization = output_payload.get("quantization", {}).get(
        "vocab_weight_quantization", "int8"
    )
    top_quality_ok = (
        top1.get("int8_top_matches_f32_top") is True
        if output_weight_quantization == "int8"
        else True
    )
    status = (
        "partial"
        if residual_pass
        and output_pass
        and top_quality_ok
        else "FAIL"
    )

    payload = {
        "artifact_name": args.artifact_name,
        "status": status,
        "source_artifacts": {
            "residual_contract_manifest": str(args.residual_contract_manifest),
            "residual_boundary_json": str(args.residual_boundary_json),
            "c_fc_contract_manifest": str(args.c_fc_contract_manifest),
            "c_fc_weight_pack_manifest": str(args.c_fc_weight_pack_manifest),
            "c_proj_contract_manifest": str(args.c_proj_contract_manifest),
            "c_proj_weight_pack_manifest": str(args.c_proj_weight_pack_manifest),
            "post_gelu_requant_json": str(args.post_gelu_requant_json),
            "c_proj_output_boundary_json": str(args.c_proj_output_boundary_json),
            "c_proj_requant_rtl_proof_json": str(args.c_proj_requant_rtl_proof_json),
            "residual_add_rtl_proof_json": str(args.residual_add_rtl_proof_json),
            "model_path": str(args.model_path),
        },
        "residual_add": {
            "status": residual_payload.get("status"),
            "final_output_q_sha256": residual_payload.get("quantization", {}).get(
                "final_output_q_sha256"
            ),
            "expected_final_output_q_sha256": residual_payload.get(
                "quantization", {}
            ).get("expected_final_output_q_sha256"),
            "metrics": residual_payload.get("metrics", {}),
        },
        "output_head_top1": {
            "status": output_payload.get("status"),
            "weight_quantization": output_weight_quantization,
            "fixed_int8_top_index": top1["fixed_int8_top_index"],
            "fixed_int8_top_acc": top1["fixed_int8_top_acc"],
            "f32_reference_top_index": top1["f32_reference_top_index"],
            "int8_top_matches_f32_top": top1["int8_top_matches_f32_top"],
            "normalized_rmse": output_payload["metrics"][
                "int8_logits_vs_f32_logits"
            ]["normalized_rmse"],
            "packed_weight_words": output_payload["rtl_contract"][
                "packed_weight_words"
            ],
        },
        "embedding_lookup_probe": {
            "token_id": embedding_probe["token_id"],
            "position_id": embedding_probe["position_id"],
            "quantization": "shared-scale-int8-for-token-plus-position-add",
            "vocab_weight_scale": embedding_probe["vocab_weight_scale"],
            "token_checksum": embedding_probe["token_checksum"],
            "position_checksum": embedding_probe["position_checksum"],
            "combined_checksum": embedding_probe["combined_checksum"],
            "token_q_sha256": embedding_probe["token_q_sha256"],
            "position_q_sha256": embedding_probe["position_q_sha256"],
            "combined_q_sha256": embedding_probe["combined_q_sha256"],
        },
        "rtl_contract": {
            "top_name": "task6_int8_v4k_l2_residual_add_output_head_selftest_top",
            "residual_top_name": "task6_int8_l2_mlp_chain_residual_add_kernel",
            "output_head_top_name": "task6_int8_vocab_output_head_top1_kernel",
            "output": "led_pass_after_residual_vector_and_output_head_top1_check",
            "vocab_size": args.vocab_size,
            "physical_vocab_size": args.physical_vocab_size or args.vocab_size,
            "hidden_size": args.hidden_size,
            "lanes": args.lanes,
            "local_tied_vocab_weight_memory": True,
            "embedding_lookup_probe": True,
            "vocab_loader_memory_file": "vocab_packed_weights.mem",
        },
        "decision": {
            "verdict": "build-board-selftest" if status == "partial" else "stop",
            "next_gate": (
                "run SV simulation, mapped utilization, and bitstream build"
                if status == "partial"
                else "fix combined selftest data before RTL integration"
            ),
        },
    }
    return payload, combined_sv, vocab_mem


def main() -> None:
    args = parse_args()
    payload, sv_text, vocab_mem_text = build_payload(args)
    if args.out_sv is not None:
        args.out_sv.parent.mkdir(parents=True, exist_ok=True)
        args.out_sv.write_text(sv_text, encoding="utf-8")
    if args.out_vocab_mem is not None:
        args.out_vocab_mem.parent.mkdir(parents=True, exist_ok=True)
        args.out_vocab_mem.write_text(vocab_mem_text, encoding="utf-8")
        write_phase_banked_vocab_mem_files(
            args.out_vocab_mem,
            vocab_mem_text,
            vocab_size=args.physical_vocab_size or args.vocab_size,
            tile_out_dim=args.tile_out_dim,
        )
    if args.out_json is not None:
        args.out_json.parent.mkdir(parents=True, exist_ok=True)
        args.out_json.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    if args.out_sv is None and args.out_json is None:
        print(sv_text, end="")


if __name__ == "__main__":
    main()
