#!/usr/bin/env python3
"""Prompt-aware Task 6 wrapper for rowstream and MLP accelerator paths.

Host-side prompt/tokenization/replay remains on the host; the board runs a
stage-appropriate accelerator.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import tempfile
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_BDF = "0000:42:00.0"
DEFAULT_ROWSTREAM = (
    ROOT
    / "artifacts"
    / "task6"
    / "parallel-hypotheses"
    / "h2-ddr3-row-stream-pack-replay"
    / "rowstream.bin"
)
DEFAULT_CONTRACT = (
    ROOT
    / "artifacts"
    / "task6"
    / "parallel-hypotheses"
    / "h2-ddr3-row-stream-interface-contract.json"
)
DEFAULT_REPLAY = (
    ROOT
    / "artifacts"
    / "task6"
    / "parallel-hypotheses"
    / "h2-full-vocab-rowwise-topk-replay.json"
)
DEFAULT_REFERENCE = (
    ROOT
    / "artifacts"
    / "task6"
    / "parallel-hypotheses"
    / "h2-tinystories-1m-prompt-output-head-q024-reference.json"
)
DEFAULT_OUT = ROOT / "artifacts" / "task6" / "runs" / "prompt-infer-board-summary.json"
TOP1_GATE = ROOT / "scripts" / "task6" / "task6_pcie_rowstream_top1_gate.py"
MLP_ACCEL_GATE = ROOT / "scripts" / "task6" / "task6_pcie_mlp_accel_gate.py"
REFERENCE_TOOL = ROOT / "scripts" / "task6" / "task6_tinystories_generation_reference.py"

MLP_REFERENCE_REQUIRED_FIELDS = (
    "activation_q",
    "residual_q",
    "residual_add_output_q",
)


def run(cmd: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        cmd,
        text=True,
        capture_output=True,
        check=check,
    )


def safe_decode_tokens(
    tokenizer: Any,
    tokens: list[int | None],
    token_to_text: dict[int, str] | None = None,
) -> str:
    if token_to_text is None:
        token_to_text = {}
    cleaned = [token for token in tokens if token is not None]
    if not cleaned:
        return ""
    if tokenizer is None:
        return "".join(token_to_text.get(token, f"<{token}>") for token in cleaned)
    try:
        return tokenizer.decode(cleaned, clean_up_tokenization_spaces=False)
    except Exception:
        return "".join(token_to_text.get(token, f"<{token}>") for token in cleaned)


def require_existing_file(path: Path | None, desc: str) -> Path:
    if path is None or not path.exists():
        raise SystemExit(f"{desc} does not exist: {path}")
    return path


def read_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as stream:
        return json.loads(stream.read())


def validate_reference_for_mlp(reference: dict[str, Any], reference_path: Path) -> None:
    steps = reference.get("steps")
    if not isinstance(steps, list) or not steps:
        raise SystemExit(f"MLP engine requires a non-empty steps list: {reference_path}")

    for index, step in enumerate(steps):
        if not isinstance(step, dict):
            raise SystemExit(f"reference step {index} in {reference_path} is not an object")
        missing = [field for field in MLP_REFERENCE_REQUIRED_FIELDS if field not in step]
        if missing:
            raise SystemExit(
                "MLP engine requires prompt-derived boundary fields that are missing from this reference:\n"
                f"  file: {reference_path}\n"
                f"  step: {index}\n"
                f"  missing: {', '.join(missing)}\n"
                "  action: regenerate reference with task6_tinystories_generation_reference.py, "
                "or pass --prompt plus --model-path/--tokenizer-vocab/--tokenizer-merges."
            )


CONTRACT_TOP1 = {
    "version": "task6-host-assisted-rowstream-top1-v1",
    "stage": "M0-host-assisted-rowstream-top1",
    "responsibilities": {
        "host": [
            "prompt handling and tokenizer/detokenizer flow",
            "transformer hidden-state generation from host reference",
            "PCIe lifecycle/recovery orchestration",
            "contract/replay/model artifact loading",
            "CLI/artifact orchestration",
        ],
        "fpga": [
            "rowstream load/read sequencing",
            "DDR3 transport and storage",
            "output-head top1 compute scan",
            "status/result/MMIO exposure",
        ],
    },
    "notes": "Top1 inference is host-assisted and uses board output-head kernel over DDR3",
}

CONTRACT_MLP = {
    "version": "task6-transformer-boundary-mlp-v1",
    "stage": "M1-transformer-boundary-mlp",
    "responsibilities": {
        "host": [
            "prompt/activation vector generation",
            "transformer replay orchestration",
            "PCIe lifecycle/recovery orchestration",
            "artifact logging and comparison",
        ],
        "fpga": [
            "int8 MLP/residual boundary execution",
            "prompt-derived vector ingress via BAR",
            "status/result/MMIO exposure",
        ],
    },
    "notes": "MLP boundary lane is a transformer-stage milestone; not full model inference",
}


def token_text_map_from_reference(reference: dict[str, Any]) -> dict[int, str]:
    mapping: dict[int, str] = {}
    for step in reference.get("steps", []):
        topk_tokens = step.get("q024_topk_token_ids") or []
        topk_text = step.get("q024_topk_text") or []
        for token_id, text in zip(topk_tokens, topk_text):
            try:
                token = int(token_id)
            except (TypeError, ValueError):
                continue
            if token not in mapping:
                mapping[token] = str(text)
    return mapping


def build_reference_json(
    prompt: str,
    model_path: Path,
    adapter_path: Path,
    tokenizer_vocab: Path,
    tokenizer_merges: Path,
    steps: int,
    top_k: int,
    out_json: Path,
) -> Path:
    cmd = [
        os.environ.get("PYTHON", "python3"),
        str(REFERENCE_TOOL),
        "--model-path",
        str(model_path),
        "--adapter-path",
        str(adapter_path),
        "--tokenizer-vocab",
        str(tokenizer_vocab),
        "--tokenizer-merges",
        str(tokenizer_merges),
        "--prompt",
        prompt,
        "--max-new-tokens",
        str(steps),
        "--top-k",
        str(top_k),
        "--out-json",
        str(out_json),
        "--json-only",
    ]
    run(cmd)
    return out_json


def run_top1_gate(args: argparse.Namespace, reference_json: Path) -> tuple[Path, dict[str, Any]]:
    out_json = Path(tempfile.mkdtemp()) / "rowstream-top1-summary.json"
    gate_cmd = [
        os.environ.get("PYTHON", "python3"),
        str(TOP1_GATE),
        args.bdf,
        "--reference-json",
        str(reference_json),
        "--image",
        str(args.image),
        "--contract-json",
        str(args.contract_json),
        "--replay-json",
        str(args.replay_json),
        "--verify-samples",
        str(args.verify_samples),
        "--poll-timeout",
        str(args.poll_timeout),
        "--top1-timeout",
        str(args.top1_timeout),
        "--packet-ack-mode",
        args.packet_ack_mode,
        "--packet-settle",
        str(args.packet_settle),
        "--json-out",
        str(out_json),
    ]
    if not args.load_image:
        gate_cmd.append("--no-load-image")
    if args.reference_max_samples is not None:
        gate_cmd.extend(["--sample-count", str(args.reference_max_samples)])
    run(gate_cmd)
    return out_json, read_json(out_json)


def run_mlp_gate(args: argparse.Namespace, reference_json: Path) -> tuple[Path, dict[str, Any]]:
    out_json = Path(tempfile.mkdtemp()) / "mlp-accel-summary.json"
    gate_cmd = [
        os.environ.get("PYTHON", "python3"),
        str(MLP_ACCEL_GATE),
        args.bdf,
        "--reference-json",
        str(reference_json),
        "--json-out",
        str(out_json),
    ]
    if args.mlp_reference_max_samples is not None:
        gate_cmd.extend(["--reference-max-samples", str(args.mlp_reference_max_samples)])
    if args.mlp_timeout is not None:
        gate_cmd.extend(["--timeout", str(args.mlp_timeout)])
    if args.mlp_poll_interval is not None:
        gate_cmd.extend(["--poll-interval", str(args.mlp_poll_interval)])
    if args.mlp_require_samples:
        gate_cmd.append("--require-samples")
    run(gate_cmd)
    return out_json, read_json(out_json)


def build_tokenizer(vocab_file: Path, merges_file: Path) -> Any:
    from transformers import GPT2TokenizerFast

    return GPT2TokenizerFast(
        vocab_file=str(vocab_file),
        merges_file=str(merges_file),
        unk_token="<|endoftext|>",
        bos_token="<|endoftext|>",
        eos_token="<|endoftext|>",
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bdf", nargs="?", default=DEFAULT_BDF, help="PCI BDF, for example 0000:42:00.0")
    parser.add_argument("--engine", choices=("top1", "mlp"), default="top1", help="Engine selection: rowstream top1 or MLP boundary lane")

    source = parser.add_mutually_exclusive_group()
    source.add_argument("--prompt", help="Prompt text to generate a fresh reference")
    source.add_argument("--reference-json", type=Path, help="Precomputed reference JSON")

    parser.add_argument("--model-path", type=Path, help="TinyStories checkpoint path")
    parser.add_argument("--adapter-path", type=Path, default=ROOT / "TinyStories" / "model_adapter.py")
    parser.add_argument("--tokenizer-vocab", type=Path, help="GPT-Neo tokenizer vocab.json")
    parser.add_argument("--tokenizer-merges", type=Path, help="GPT-Neo tokenizer merges.txt")
    parser.add_argument("--steps", type=int, default=1, help="Tokens to generate when --prompt is supplied")
    parser.add_argument("--top-k", type=int, default=5, help="Top-k width for reference generation")
    parser.add_argument(
        "--reference-max-samples",
        type=int,
        help="Limit the number of steps consumed from --reference-json (default: all)",
    )

    parser.add_argument("--json-out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--progress", action="store_true", help="Print per-step board status")
    parser.add_argument(
        "--answer-only",
        action="store_true",
        help="Print only the board-generated answer (plain text for top1, checksums for mlp)",
    )
    parser.add_argument(
        "--mlp-answer-format",
        choices=("checksum", "output", "both"),
        default="checksum",
        help="For engine=mlp, control answer-only output payload.",
    )

    parser.add_argument("--image", type=Path, default=DEFAULT_ROWSTREAM)
    parser.add_argument("--contract-json", type=Path, default=DEFAULT_CONTRACT)
    parser.add_argument("--replay-json", type=Path, default=DEFAULT_REPLAY)
    parser.add_argument("--load-image", action=argparse.BooleanOptionalAction, default=True)
    parser.add_argument("--verify-samples", type=int, default=0)
    parser.add_argument("--poll-timeout", type=float, default=2.0)
    parser.add_argument("--top1-timeout", type=float, default=20.0)
    parser.add_argument(
        "--packet-ack-mode",
        choices=("auto", "require", "off"),
        default="auto",
        help="Top1 rowstream packet commit wait policy.",
    )
    parser.add_argument(
        "--packet-settle",
        type=float,
        default=0.001,
        help="Seconds to wait after rowstream packet commits when ACK counters are unavailable/inactive.",
    )

    parser.add_argument("--mlp-reference-max-samples", type=int, default=None)
    parser.add_argument("--mlp-timeout", type=float, default=2.0)
    parser.add_argument("--mlp-poll-interval", type=float, default=0.001)
    parser.add_argument("--mlp-require-samples", action="store_true", help="Require checksum/sample checks when expected")

    return parser.parse_args()


def print_answer_only(
    engine: str,
    board_tokens: list[Any],
    board_samples: list[dict[str, Any]],
    board_answer_text: str,
    mlp_output_format: str,
) -> None:
    if engine == "top1":
        if board_answer_text:
            print(board_answer_text)
        else:
            print(" ".join(str(token) for token in board_tokens))
        return

    if not board_samples:
        return

    if mlp_output_format == "checksum":
        checksums = [
            sample.get("observed", {}).get("checksum")
            for sample in board_samples
        ]
        print(" ".join(str(item) for item in checksums if item is not None))
        return

    if mlp_output_format == "output":
        outputs = [
            sample.get("observed", {}).get("output_hex")
            for sample in board_samples
        ]
        print(" ".join(str(item) for item in outputs if item is not None))
        return

    for index, sample in enumerate(board_samples, start=1):
        observed = sample.get("observed", {})
        checksum = observed.get("checksum")
        output = observed.get("output_hex")
        if checksum is None and output is None:
            continue
        line = [f"sample={index}"]
        if checksum is not None:
            line.append(f"checksum={checksum}")
        if output is not None:
            line.append(f"output_hex={output}")
        print(" ".join(line))


def main() -> int:
    args = parse_args()

    if args.reference_max_samples is not None and args.reference_max_samples <= 0:
        raise SystemExit("--reference-max-samples must be positive")

    if args.reference_json is None and args.prompt is None:
        if DEFAULT_REFERENCE.exists():
            args.reference_json = DEFAULT_REFERENCE
        else:
            raise SystemExit(
                "one of --prompt or --reference-json is required (no default reference found: "
                f"{DEFAULT_REFERENCE})"
            )

    if args.prompt is not None and args.reference_json is not None:
        raise SystemExit("only one of --prompt or --reference-json can be supplied")

    if args.prompt is not None:
        if args.model_path is None:
            raise SystemExit("--model-path is required with --prompt")
        if args.tokenizer_vocab is None or args.tokenizer_merges is None:
            raise SystemExit("--tokenizer-vocab and --tokenizer-merges are required with --prompt")

        with tempfile.TemporaryDirectory() as tempdir:
            reference_json = build_reference_json(
                prompt=args.prompt,
                model_path=args.model_path,
                adapter_path=args.adapter_path,
                tokenizer_vocab=args.tokenizer_vocab,
                tokenizer_merges=args.tokenizer_merges,
                steps=args.steps,
                top_k=args.top_k,
                out_json=Path(tempdir) / "reference.json",
            )

            reference_payload = read_json(reference_json)
            if args.engine == "mlp":
                validate_reference_for_mlp(reference_payload, reference_json)
            reference_payload_prompt = reference_payload.get("prompt", {})
            reference_prompt_text = reference_payload_prompt.get("text", "<reference unavailable>")
            generation = reference_payload.get("generation", {})
            reference_generated_tokens = list(generation.get("q024_generated_token_ids", []))
            reference_generated_text = generation.get("q024_decoded_text", "")

            tokenizer = None
            if args.tokenizer_vocab is not None and args.tokenizer_merges is not None:
                try:
                    tokenizer = build_tokenizer(args.tokenizer_vocab, args.tokenizer_merges)
                except ModuleNotFoundError as exc:
                    raise SystemExit(
                        "transformers is required for prompt decoding. Install it or run with --reference-json and avoid decoder output."
                    ) from exc

            if args.engine == "top1":
                _, gate_result = run_top1_gate(args, reference_json)
                board_samples = gate_result.get("samples", [])
                board_tokens = [entry.get("top1_token") for entry in board_samples]
                board_answer_text = safe_decode_tokens(
                    tokenizer,
                    board_tokens,
                    token_text_map_from_reference(reference_payload),
                )
                if args.progress:
                    for index, sample in enumerate(board_samples):
                        expected = sample.get("expected_reference_top1_token")
                        status = sample.get("status")
                        if expected is None:
                            print(f"step {index + 1}: token={sample.get('top1_token')} status={status}")
                        else:
                            print(
                                f"step {index + 1}: token={sample.get('top1_token')} expected={expected} "
                                f"status={status}"
                            )
            else:
                _, gate_result = run_mlp_gate(args, reference_json)
                board_samples = gate_result.get("samples", [])
                board_tokens = []
                board_answer_text = ""
                if args.progress:
                    for index, sample in enumerate(board_samples):
                        status = sample.get("status")
                        print(f"sample {index + 1}: status={status} checks={sample.get('checks', {})}")
    else:
        reference_json = require_existing_file(args.reference_json, "reference-json")
        reference_payload = read_json(reference_json)
        if args.engine == "mlp":
            validate_reference_for_mlp(reference_payload, reference_json)
        reference_payload_prompt = reference_payload.get("prompt", {})
        reference_prompt_text = reference_payload_prompt.get("text", "<reference unavailable>")
        generation = reference_payload.get("generation", {})
        reference_generated_tokens = list(generation.get("q024_generated_token_ids", []))
        reference_generated_text = generation.get("q024_decoded_text", "")

        tokenizer = None
        if args.tokenizer_vocab is not None and args.tokenizer_merges is not None:
            try:
                tokenizer = build_tokenizer(args.tokenizer_vocab, args.tokenizer_merges)
            except ModuleNotFoundError as exc:
                raise SystemExit(
                    "transformers is required for prompt decoding. Install it or run with --reference-json and avoid decoder output."
                ) from exc

        if args.engine == "top1":
            _, gate_result = run_top1_gate(args, reference_json)
            board_samples = gate_result.get("samples", [])
            board_tokens = [entry.get("top1_token") for entry in board_samples]
            board_answer_text = safe_decode_tokens(tokenizer, board_tokens, token_text_map_from_reference(reference_payload))
            if args.progress:
                for index, sample in enumerate(board_samples):
                    expected = sample.get("expected_reference_top1_token")
                    status = sample.get("status")
                    if expected is None:
                        print(f"step {index + 1}: token={sample.get('top1_token')} status={status}")
                    else:
                        print(
                            f"step {index + 1}: token={sample.get('top1_token')} expected={expected} "
                            f"status={status}"
                        )
        else:
            _, gate_result = run_mlp_gate(args, reference_json)
            board_samples = gate_result.get("samples", [])
            board_tokens = []
            board_answer_text = ""
            if args.progress:
                for index, sample in enumerate(board_samples):
                    status = sample.get("status")
                    print(f"sample {index + 1}: status={status} checks={sample.get('checks', {})}")

    args.json_out.parent.mkdir(parents=True, exist_ok=True)
    token_map = token_text_map_from_reference(reference_payload)

    if args.engine == "top1":
        if args.answer_only:
            print_answer_only(
                args.engine,
                board_tokens,
                board_samples,
                board_answer_text,
                args.mlp_answer_format,
            )
        else:
            print(f"engine: {args.engine}")
            print(f"prompt: {reference_prompt_text}")
            print(f"prompt token ids: {reference_payload_prompt.get('token_ids', [])}")
            print(f"reference q024 generated tokens: {reference_generated_tokens}")
            if reference_generated_text:
                print(f"reference answer: {reference_generated_text}")
            print(f"board steps: {board_tokens}")
            print(f"board answer: {board_answer_text or '<unavailable>'}")
            print(f"status: {gate_result.get('status')} elapsed_seconds={gate_result.get('elapsed_seconds')}")
    else:
        if args.answer_only:
            print_answer_only(
                args.engine,
                board_tokens,
                board_samples,
                board_answer_text,
                args.mlp_answer_format,
            )
        else:
            print(f"engine: {args.engine}")
            print(f"prompt: {reference_prompt_text}")
            print(f"sample count: {len(board_samples)} status={gate_result.get('status')}")

    result_payload = {
        "prompt_infer_status": gate_result.get("status"),
        "engine": args.engine,
        "contract": CONTRACT_TOP1 if args.engine == "top1" else CONTRACT_MLP,
        "bdf": args.bdf,
        "reference_json": str(reference_json),
        "reference": {
            "artifact_name": reference_payload.get("artifact_name"),
            "status": reference_payload.get("status"),
            "prompt": reference_payload_prompt,
            "generated_tokens": reference_generated_tokens,
            "generated_text": reference_generated_text,
        },
        "board": {
            "status": gate_result.get("status"),
            "sample_count": len(board_samples),
            "out_json": str(args.json_out),
            "token_map": token_map,
        },
        "board_answer_text": board_answer_text,
        "board_tokens": board_tokens,
        "gate_summary": gate_result,
    }
    args.json_out.write_text(json.dumps(result_payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    return 0 if gate_result.get("status") == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
