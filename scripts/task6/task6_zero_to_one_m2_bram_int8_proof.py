#!/usr/bin/env python3
"""Create the minimal int8 BRAM-only M2 chip proof artifact.

This helper keeps the proof path intentionally narrow:

- generate fixed-token + embedding + live-context TB data for the one-block int8 model
- run the BAR-visible M2 gate with those vectors
- merge board output with checkpoint-hash parity checks into a single proof artifact
"""

from __future__ import annotations

import argparse
from pathlib import Path
import subprocess


ROOT = Path(__file__).resolve().parents[2]

DEFAULT_OUT_DIR = ROOT / "artifacts" / "task6" / "runs" / "m2-bram-int8-proof"
DEFAULT_CHECKPOINT_HASH = ROOT / "artifacts" / "zero-to-one" / "m2-bram-checkpoint-hashes.json"

CONTRACT_MANIFEST = ROOT / "artifacts" / "task6" / "parallel-hypotheses" / "h2-tinystories-1m-m2-one-block-contract" / "manifest.json"
WEIGHT_MANIFEST = ROOT / "artifacts" / "task6" / "weights_pack" / "tiny-stories-1m-m2-block0-int8" / "manifest.json"
POST_GELU_PROOF = ROOT / "artifacts" / "task6" / "parallel-hypotheses" / "h2-full-tinystories-1m-block0-c-fc-post-gelu-pwl-requant-rtl-proof.json"
C_PROJ_PROOF = ROOT / "artifacts" / "task6" / "parallel-hypotheses" / "h2-full-tinystories-1m-block0-pwl-mlp-chain-c-proj-requant-rtl-proof.json"
RESIDUAL_ADD_PROOF = ROOT / "artifacts" / "task6" / "parallel-hypotheses" / "h2-full-tinystories-1m-block0-pwl-mlp-chain-residual-add-rtl-proof.json"
SCORE_ARTIFACT = ROOT / "artifacts" / "task6" / "parallel-hypotheses" / "h2-tinystories-1m-m2-full-block-lowering-score.json"


def run(cmd: list[str], *, cwd: Path | None = None) -> None:
    subprocess.run(cmd, check=True, cwd=cwd)


def _resolve_path(value: str | None, fallback: Path, *, root_relative: bool) -> Path:
    if value is None or value == "":
        return fallback
    path = Path(value)
    if path.is_absolute():
        return path
    return ROOT / path if root_relative else fallback.parent / path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bdf", help="PCI BDF to run hardware probe/gate against")
    parser.add_argument("--out-dir", default=str(DEFAULT_OUT_DIR))
    parser.add_argument("--board-summary-json", default=None)
    parser.add_argument("--checkpoint-hash-json", default=None)
    parser.add_argument("--chip-pass-json", default=None)
    parser.add_argument("--timeout", type=float, default=2.0)
    parser.add_argument("--poll-interval", type=float, default=0.001)
    parser.add_argument("--contract-manifest", default=str(CONTRACT_MANIFEST))
    parser.add_argument("--weight-manifest", default=str(WEIGHT_MANIFEST))
    parser.add_argument("--post-gelu-proof-json", default=str(POST_GELU_PROOF))
    parser.add_argument("--c-proj-proof-json", default=str(C_PROJ_PROOF))
    parser.add_argument("--residual-add-proof-json", default=str(RESIDUAL_ADD_PROOF))
    parser.add_argument("--score-artifact", default=str(SCORE_ARTIFACT))
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    board_summary_json = _resolve_path(
        args.board_summary_json,
        out_dir / "m2-full-block-board-summary.json",
        root_relative=False,
    )
    checkpoint_hash_json = _resolve_path(
        args.checkpoint_hash_json,
        DEFAULT_CHECKPOINT_HASH,
        root_relative=True,
    )
    chip_pass_json = _resolve_path(
        args.chip_pass_json,
        out_dir / "m2-bram-chip-pass-int8-proof.json",
        root_relative=False,
    )
    contract_manifest = _resolve_path(args.contract_manifest, CONTRACT_MANIFEST, root_relative=True)
    weight_manifest = _resolve_path(args.weight_manifest, WEIGHT_MANIFEST, root_relative=True)
    post_gelu_proof_json = _resolve_path(args.post_gelu_proof_json, POST_GELU_PROOF, root_relative=True)
    c_proj_proof_json = _resolve_path(args.c_proj_proof_json, C_PROJ_PROOF, root_relative=True)
    residual_add_proof_json = _resolve_path(args.residual_add_proof_json, RESIDUAL_ADD_PROOF, root_relative=True)
    score_artifact = _resolve_path(args.score_artifact, SCORE_ARTIFACT, root_relative=True)

    required_inputs = [
        contract_manifest,
        weight_manifest,
        post_gelu_proof_json,
        c_proj_proof_json,
        residual_add_proof_json,
        score_artifact,
    ]
    for path in required_inputs:
        if not path.exists():
            raise SystemExit(f"required artifact missing: {path}")

    full_block_tb_sv = out_dir / "full_block_tb_data.sv"
    full_block_tb_json = out_dir / "full_block_tb_data_summary.json"
    embedding_tb_sv = out_dir / "task6_m2_embedding_block_input_tb_data.sv"
    embedding_tb_json = out_dir / "task6_m2_embedding_block_input_tb_data_summary.json"
    context_tb_sv = out_dir / "task6_m2_ln_attn_live_kv_all_heads_context_tb_data.sv"
    context_tb_json = out_dir / "task6_m2_ln_attn_live_kv_all_heads_context_tb_data_summary.json"

    run(
        [
            "python3",
            "scripts/task6/task6_zero_to_one_m2_checkpoint_hashes.py",
            "--quantization",
            "int8",
            "--contract-manifest",
            str(contract_manifest),
            "--score-artifact",
            str(score_artifact),
            "--out-json",
            str(checkpoint_hash_json),
        ]
    )

    run(
        [
            "python3",
            "sim/gen_task6_m2_full_block_replay_selftest_tb_data.py",
            "--contract-manifest",
            str(contract_manifest),
            "--weight-manifest",
            str(weight_manifest),
            "--post-gelu-proof-json",
            str(post_gelu_proof_json),
            "--c-proj-proof-json",
            str(c_proj_proof_json),
            "--residual-add-proof-json",
            str(residual_add_proof_json),
            "--out-sv",
            str(full_block_tb_sv),
            "--out-json",
            str(full_block_tb_json),
        ]
    )

    run(
        [
            "python3",
            "sim/gen_task6_m2_ln_attn_live_kv_all_heads_context_tb_data.py",
            "--contract-manifest",
            str(contract_manifest),
            "--weight-manifest",
            str(weight_manifest),
            "--num-heads",
            "16",
            "--out-sv",
            str(context_tb_sv),
            "--out-json",
            str(context_tb_json),
        ]
    )

    run(
        [
            "python3",
            "sim/gen_task6_m2_embedding_block_input_tb_data.py",
            "--contract-manifest",
            str(contract_manifest),
            "--weight-manifest",
            str(weight_manifest),
            "--full-block-tb-data-sv",
            str(full_block_tb_sv),
            "--context-tb-data-sv",
            str(context_tb_sv),
            "--out-sv",
            str(embedding_tb_sv),
            "--out-json",
            str(embedding_tb_json),
        ]
    )

    run(
        [
            "python3",
            "scripts/task6/task6_pcie_m2_full_block_gate.py",
            args.bdf,
            "--tb-data-sv",
            str(full_block_tb_sv),
            "--embedding-tb-data-sv",
            str(embedding_tb_sv),
            "--context-tb-data-sv",
            str(context_tb_sv),
            "--json-out",
            str(board_summary_json),
            "--timeout",
            str(args.timeout),
            "--poll-interval",
            str(args.poll_interval),
        ]
    )

    run(
        [
            "python3",
            "scripts/task6/task6_m2_bram_chip_pass_artifact.py",
            "--quantization",
            "int8",
            "--board-summary-json",
            str(board_summary_json),
            "--checkpoint-hash-json",
            str(checkpoint_hash_json),
            "--out-json",
            str(chip_pass_json),
        ]
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
