#!/usr/bin/env python3
"""Export the M2 one-full-block TinyStories contract.

M2 moves from host-supplied hidden vectors to a token-driven board boundary:
the host supplies token IDs/control, and the board is expected to compute one
complete transformer block. This exporter records the CPU/f32 oracle and simple
per-vector int8 references for block 0 over the existing TinyStories prompt
reference contexts.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
from typing import Any

import torch
from transformers import GPT2TokenizerFast


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_MODEL = ROOT / "TinyStories"
DEFAULT_ADAPTER = DEFAULT_MODEL / "model_adapter.py"
DEFAULT_VOCAB = DEFAULT_MODEL / "gpt2-vocab.json"
DEFAULT_MERGES = DEFAULT_MODEL / "gpt2-merges.txt"
DEFAULT_REFERENCE = (
    ROOT
    / "artifacts"
    / "task6"
    / "parallel-hypotheses"
    / "h2-tinystories-1m-prompt-output-head-q024-reference.json"
)
DEFAULT_MANIFEST = (
    ROOT
    / "artifacts"
    / "task6"
    / "parallel-hypotheses"
    / "h2-tinystories-1m-m2-one-block-contract"
    / "manifest.json"
)
QMAX = 127


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model-path", required=True, type=Path)
    parser.add_argument("--adapter-path", type=Path, default=DEFAULT_ADAPTER)
    parser.add_argument("--tokenizer-vocab", type=Path, default=DEFAULT_VOCAB)
    parser.add_argument("--tokenizer-merges", type=Path, default=DEFAULT_MERGES)
    parser.add_argument("--reference-json", type=Path, default=DEFAULT_REFERENCE)
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_MANIFEST.parent)
    parser.add_argument("--block-index", type=int, default=0)
    parser.add_argument("--max-steps", type=int, default=None)
    parser.add_argument("--model-label", default="tiny-stories-1m")
    return parser.parse_args()


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def first_tensor(value: Any) -> torch.Tensor:
    if isinstance(value, torch.Tensor):
        return value
    if isinstance(value, (tuple, list)):
        for item in value:
            if isinstance(item, torch.Tensor):
                return item
    raise TypeError(f"expected tensor-like output, got {type(value)!r}")


def load_adapter_build_model(adapter_path: Path) -> Any:
    sys.path.insert(0, str(adapter_path.parent))
    spec = importlib.util.spec_from_file_location("task6_m2_adapter", adapter_path)
    if spec is None or spec.loader is None:
        raise SystemExit(f"unable to load adapter from {adapter_path}")
    module = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(module)
    finally:
        try:
            sys.path.remove(str(adapter_path.parent))
        except ValueError:
            pass
    if not hasattr(module, "build_model"):
        raise SystemExit(f"adapter has no build_model function: {adapter_path}")
    return module.build_model


def tensor_to_file(path: Path, tensor: torch.Tensor) -> dict[str, Any]:
    detached = tensor.detach().cpu().contiguous()
    raw = detached.numpy().tobytes(order="C")
    path.write_bytes(raw)
    return {
        "filename": path.name,
        "dtype": str(detached.dtype).replace("torch.", ""),
        "shape": [int(dim) for dim in detached.shape],
        "numel": int(detached.numel()),
        "byte_length": len(raw),
        "sha256": sha256_bytes(raw),
    }


def quantize_symmetric_i8(tensor: torch.Tensor) -> tuple[torch.Tensor, float]:
    tensor = tensor.detach().cpu().to(torch.float64)
    max_abs = float(torch.max(torch.abs(tensor)).item())
    if max_abs == 0.0:
        return torch.zeros_like(tensor, dtype=torch.int8), 0.0
    scale = max_abs / QMAX
    q = torch.round(tensor / scale).clamp(-QMAX, QMAX).to(torch.int8)
    return q, scale


def token_text(tokenizer: GPT2TokenizerFast, token_id: int) -> str:
    return tokenizer.decode([token_id], clean_up_tokenization_spaces=False)


def context_steps(reference: dict[str, Any], max_steps: int | None) -> list[dict[str, Any]]:
    steps = reference.get("steps")
    if not isinstance(steps, list) or not steps:
        raise SystemExit(f"reference has no steps: {reference.get('artifact_name')}")
    selected = steps if max_steps is None else steps[:max_steps]
    contexts: list[dict[str, Any]] = []
    for index, step in enumerate(selected):
        token_ids = step.get("q024_context_token_ids") or step.get("f32_context_token_ids")
        if not isinstance(token_ids, list) or not token_ids:
            raise SystemExit(f"reference step {index} has no context token ids")
        contexts.append(
            {
                "step": int(step.get("step", index)),
                "context_token_ids": [int(token) for token in token_ids],
                "expected_next_token": int((step.get("q024_topk_token_ids") or [step.get("f32_topk_token_ids", [None])[0]])[0]),
            }
        )
    return contexts


def get_block(model: Any, block_index: int) -> Any:
    try:
        return model.transformer.h[block_index]
    except Exception as exc:
        raise SystemExit(f"model does not expose transformer.h[{block_index}]") from exc


def capture_block_tensors(model: Any, block: Any, token_ids: list[int]) -> dict[str, torch.Tensor]:
    captured: dict[str, torch.Tensor] = {}

    def block_hook(_module: Any, inputs: tuple[Any, ...], output: Any) -> None:
        captured["block_input_f32"] = first_tensor(inputs).detach().cpu()
        captured["block_output_f32"] = first_tensor(output).detach().cpu()

    handle = block.register_forward_hook(block_hook)
    try:
        input_ids = torch.tensor([token_ids], dtype=torch.long)
        with torch.no_grad():
            model(input_ids)
    finally:
        handle.remove()
    if "block_input_f32" not in captured or "block_output_f32" not in captured:
        raise SystemExit("block hook did not capture input/output tensors")
    return captured


def main() -> int:
    args = parse_args()
    if args.block_index < 0:
        raise SystemExit("--block-index must be non-negative")
    if args.max_steps is not None and args.max_steps <= 0:
        raise SystemExit("--max-steps must be positive")

    reference = load_json(args.reference_json)
    tokenizer = GPT2TokenizerFast(
        vocab_file=str(args.tokenizer_vocab),
        merges_file=str(args.tokenizer_merges),
        unk_token="<|endoftext|>",
        bos_token="<|endoftext|>",
        eos_token="<|endoftext|>",
    )
    build_model = load_adapter_build_model(args.adapter_path)
    model = build_model(str(args.model_path))
    model.eval()
    block = get_block(model, args.block_index)

    args.out_dir.mkdir(parents=True, exist_ok=True)
    steps_out: list[dict[str, Any]] = []
    for item in context_steps(reference, args.max_steps):
        step_index = int(item["step"])
        token_ids = item["context_token_ids"]
        captured = capture_block_tensors(model, block, token_ids)
        block_input = captured["block_input_f32"]
        block_output = captured["block_output_f32"]
        last_input = block_input[0, -1, :]
        last_output = block_output[0, -1, :]
        last_input_q, last_input_scale = quantize_symmetric_i8(last_input)
        last_output_q, last_output_scale = quantize_symmetric_i8(last_output)

        prefix = f"step{step_index:02d}"
        tensors = {
            "block_input_f32": tensor_to_file(args.out_dir / f"{prefix}-block-input-f32.bin", block_input.to(torch.float32)),
            "block_output_f32": tensor_to_file(args.out_dir / f"{prefix}-block-output-f32.bin", block_output.to(torch.float32)),
            "last_input_i8": tensor_to_file(args.out_dir / f"{prefix}-last-input-i8.bin", last_input_q),
            "last_output_i8": tensor_to_file(args.out_dir / f"{prefix}-last-output-i8.bin", last_output_q),
        }
        steps_out.append(
            {
                "step": step_index,
                "context_token_ids": token_ids,
                "context_text": tokenizer.decode(token_ids, clean_up_tokenization_spaces=False),
                "expected_next_token": item["expected_next_token"],
                "expected_next_text": token_text(tokenizer, item["expected_next_token"]),
                "sequence_length": len(token_ids),
                "last_input_i8_scale": last_input_scale,
                "last_output_i8_scale": last_output_scale,
                "tensors": tensors,
            }
        )

    manifest = {
        "schema_version": 1,
        "artifact_name": "h2-tinystories-1m-m2-one-block-contract",
        "status": "PASS",
        "date": dt.datetime.now(dt.timezone.utc).isoformat(),
        "stage": "M2-one-full-block",
        "model_label": args.model_label,
        "model_path": str(args.model_path),
        "adapter_path": str(args.adapter_path),
        "reference_json": str(args.reference_json),
        "block_index": args.block_index,
        "contract": {
            "host_input": ["prompt token ids", "generation control", "PCIe lifecycle"],
            "fpga_compute": [
                "token and position embeddings through block input",
                "one full transformer block",
                "downstream output-head check in later board gate",
            ],
            "acceptance": "block output tensors match this CPU/f32 contract after the chosen fixed-point lowering",
        },
        "quantization": {
            "last_token_vectors": "symmetric int8 per vector",
            "note": "Full RTL fixed-point lowering must choose per-stage quantization before M2 board acceptance.",
        },
        "steps": steps_out,
    }
    manifest_path = args.out_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(manifest_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
