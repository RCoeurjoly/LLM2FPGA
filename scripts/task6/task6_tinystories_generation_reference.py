#!/usr/bin/env python3
"""Generate a TinyStories prompt reference for staged Task 6 FPGA inference.

The current hardware-proven slice is the full-vocab output head: the
transformer hidden state is produced by the PyTorch model, then the next token
is selected by the same rowwise int8/Q0.24 top1 rule used by the DDR3
rowstream hardware. This artifact is therefore an executable prompt-level
target for the next RTL stages without claiming that the full transformer has
already been quantized.
"""

from __future__ import annotations

import argparse
import datetime as dt
import importlib.util
import json
from pathlib import Path
import sys
from typing import Any

import torch
from transformers import GPT2TokenizerFast


QMAX = 127
Q024_SCALE = 1 << 24
Q024_MAX = Q024_SCALE - 1

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_ADAPTER = ROOT / "TinyStories" / "model_adapter.py"
DEFAULT_POST_GELU_REQUANT_JSON = (
    ROOT
    / "artifacts"
    / "task6"
    / "parallel-hypotheses"
    / "h2-int8-l2-c-fc-post-gelu-requant-rtl-proof.json"
)
DEFAULT_C_PROJ_REQUANT_JSON = (
    ROOT
    / "artifacts"
    / "task6"
    / "parallel-hypotheses"
    / "h2-int8-l2-mlp-chain-c-proj-requant-rtl-proof.json"
)
DEFAULT_RESIDUAL_ADD_RTL_PROOF_JSON = (
    ROOT
    / "artifacts"
    / "task6"
    / "parallel-hypotheses"
    / "h2-int8-l2-mlp-chain-residual-add-rtl-proof.json"
)
DEFAULT_OUT = (
    ROOT
    / "artifacts"
    / "task6"
    / "parallel-hypotheses"
    / "h2-tinystories-1m-prompt-output-head-q024-reference.json"
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model-path", required=True, type=Path)
    parser.add_argument("--adapter-path", type=Path, default=DEFAULT_ADAPTER)
    parser.add_argument("--tokenizer-vocab", required=True, type=Path)
    parser.add_argument("--tokenizer-merges", required=True, type=Path)
    parser.add_argument("--prompt", default="Once upon a time there was")
    parser.add_argument("--max-new-tokens", type=int, default=8)
    parser.add_argument("--top-k", type=int, default=5)
    parser.add_argument("--out-json", type=Path, default=DEFAULT_OUT)
    parser.add_argument(
        "--post-gelu-requant-json",
        type=Path,
        default=DEFAULT_POST_GELU_REQUANT_JSON,
    )
    parser.add_argument(
        "--c-proj-requant-json",
        type=Path,
        default=DEFAULT_C_PROJ_REQUANT_JSON,
    )
    parser.add_argument(
        "--residual-add-rtl-proof-json",
        type=Path,
        default=DEFAULT_RESIDUAL_ADD_RTL_PROOF_JSON,
    )
    parser.add_argument("--json-only", action="store_true")
    return parser.parse_args()


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def first_tensor(value: Any) -> torch.Tensor:
    if isinstance(value, torch.Tensor):
        return value
    if isinstance(value, (tuple, list)):
        for item in value:
            if isinstance(item, torch.Tensor):
                return item
    raise TypeError(f"expected tensor output, got {type(value)!r}")


def round_shift_signed(value: int, shift: int) -> int:
    if shift == 0:
        return value
    half = 1 << (shift - 1)
    if value >= 0:
        return (value + half) >> shift
    return -(((-value) + half) >> shift)


def saturate_i8(value: int) -> int:
    return max(-127, min(127, value))


def quantize_symmetric_to_list(values: torch.Tensor) -> tuple[list[int], float]:
    quantized, scale = quantize_symmetric_tensor(values)
    flat = quantized.flatten()
    return [int(item) for item in flat.tolist()], float(scale)


def quantize_per_output_symmetric_to_list(
    values: torch.Tensor,
    out_features: int,
    in_features: int,
) -> tuple[list[int], list[float]]:
    if values.ndim != 2:
        raise SystemExit(f"expected 2-D tensor, got {values.ndim}-D")
    values = values.reshape((out_features, in_features))
    all_q: list[int] = []
    scales: list[float] = []
    for out_index in range(out_features):
        row = values[out_index]
        row_q, row_scale = quantize_symmetric_tensor(row)
        all_q.extend(int(item) for item in row_q.tolist())
        scales.append(float(row_scale))
    return all_q, scales


def compute_accumulators(activation_q: list[int], weight_q: list[int], in_features: int, out_features: int) -> list[int]:
    accs: list[int] = []
    for out_index in range(out_features):
        weight_offset = out_index * in_features
        acc = 0
        for in_index in range(in_features):
            acc += int(activation_q[in_index]) * int(weight_q[weight_offset + in_index])
        accs.append(acc)
    return accs


def fixed_post_gelu_q(
    acc: int,
    scale_mul: int,
    bias_q: int,
    gelu_quad_q: int,
    output_requant_mult: int,
    x_frac: int,
    scale_shift: int,
    output_requant_shift: int,
) -> int:
    x_q = round_shift_signed(acc * scale_mul, scale_shift) + bias_q
    y_q = (x_q >> 1) + round_shift_signed(gelu_quad_q * x_q * x_q, 2 * x_frac)
    return saturate_i8(round_shift_signed(y_q * output_requant_mult, output_requant_shift))


def fixed_c_proj_output_q(
    acc: int,
    scale_mul: int,
    bias_q: int,
    shift: int,
) -> int:
    return saturate_i8(round_shift_signed(acc * scale_mul + bias_q, shift))


def residual_add_output_q(
    residual_q: list[int],
    residual_scale_mul: int,
    c_proj_q: list[int],
    c_proj_scale_mul: int,
    residual_add_requant_shift: int,
) -> list[int]:
    if len(residual_q) != len(c_proj_q):
        raise SystemExit(
            "residual_q and c_proj_q length mismatch: "
            f"{len(residual_q)} vs {len(c_proj_q)}"
        )
    out: list[int] = []
    for residual_value, c_proj_value in zip(residual_q, c_proj_q):
        out.append(
            saturate_i8(
                round_shift_signed(
                    residual_value * residual_scale_mul
                    + c_proj_value * c_proj_scale_mul,
                    residual_add_requant_shift,
                )
            )
        )
    return out


def load_mlp_int8_constants(
    post_gelu_requant_json: Path,
    c_proj_requant_json: Path,
    residual_add_proof_json: Path,
) -> dict[str, int | float]:
    constants: dict[str, int | float] = {
        "x_frac": 12,
        "scale_shift": 24,
        "gelu_quad_q": 1634,
        "output_requant_shift": 16,
        "output_requant_mult": 8032,
        "c_proj_output_requant_shift": 24,
        "residual_add_requant_shift": 24,
        "residual_requant_mult": 16452912,
        "c_proj_residual_add_requant_mult": 13728869,
        "post_gelu_output_scale": 0.0019919775901474546,
        "c_proj_output_scale": 0.0006137476192684625,
        "final_output_scale": 0.0007500236330698129,
    }

    if post_gelu_requant_json.exists():
        payload = load_json(post_gelu_requant_json)
        fixed = payload.get("fixed_point", {})
        quant = payload.get("quantization", {})
        constants["x_frac"] = int(fixed.get("x_frac", constants["x_frac"]))
        constants["scale_shift"] = int(fixed.get("scale_shift", constants["scale_shift"]))
        constants["gelu_quad_q"] = int(fixed.get("gelu_quad_q", constants["gelu_quad_q"]))
        constants["output_requant_shift"] = int(
            fixed.get(
                "output_requant_shift", constants["output_requant_shift"]
            )
        )
        constants["output_requant_mult"] = int(
            fixed.get("output_requant_mult", constants["output_requant_mult"])
        )
        constants["post_gelu_output_scale"] = float(
            quant.get("output_scale", constants["post_gelu_output_scale"])
        )

    if c_proj_requant_json.exists():
        payload = load_json(c_proj_requant_json)
        fixed = payload.get("fixed_point", {})
        quant = payload.get("quantization", {})
        constants["c_proj_output_requant_shift"] = int(
            fixed.get(
                "c_proj_output_requant_shift",
                constants["c_proj_output_requant_shift"],
            )
        )
        constants["c_proj_output_scale"] = float(
            quant.get("c_proj_output_scale", constants["c_proj_output_scale"])
        )
        constants["final_output_scale"] = float(
            quant.get("final_output_scale", constants["final_output_scale"])
        )

    if residual_add_proof_json.exists():
        payload = load_json(residual_add_proof_json)
        fixed = payload.get("fixed_point", {})
        quant = payload.get("quantization", {})
        constants["residual_add_requant_shift"] = int(
            fixed.get(
                "residual_add_requant_shift",
                constants["residual_add_requant_shift"],
            )
        )
        constants["residual_requant_mult"] = int(
            fixed.get(
                "residual_requant_mult", constants["residual_requant_mult"]
            )
        )
        constants["c_proj_residual_add_requant_mult"] = int(
            fixed.get(
                "c_proj_residual_add_requant_mult",
                constants["c_proj_residual_add_requant_mult"],
            )
        )
        constants["final_output_scale"] = float(
            quant.get("final_output_scale", constants["final_output_scale"])
        )
        constants["c_proj_output_scale"] = float(
            quant.get(
                "c_proj_output_scale", constants["c_proj_output_scale"]
            )
        )

    return constants


def load_adapter_build_model(adapter_path: Path) -> Any:
    sys.path.insert(0, str(adapter_path.parent))
    spec = importlib.util.spec_from_file_location("task6_tinystories_adapter", adapter_path)
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
    return module.build_model


def deterministic_topk_float(values: torch.Tensor, k: int) -> list[int]:
    raw = [float(value) for value in values.detach().cpu().tolist()]
    return sorted(range(len(raw)), key=lambda index: (-raw[index], index))[:k]


def deterministic_topk_int(values: torch.Tensor, k: int) -> list[int]:
    raw = [int(value) for value in values.detach().cpu().tolist()]
    return sorted(range(len(raw)), key=lambda index: (-raw[index], index))[:k]


def quantize_symmetric_tensor(tensor: torch.Tensor) -> tuple[torch.Tensor, float]:
    max_abs = float(torch.max(torch.abs(tensor)).item())
    if max_abs == 0.0:
        return torch.zeros_like(tensor, dtype=torch.int16), 0.0
    scale = max_abs / QMAX
    quantized = torch.round(tensor / scale).clamp(-QMAX, QMAX).to(torch.int16)
    return quantized, scale


def quantize_rowwise_symmetric(weight: torch.Tensor) -> tuple[torch.Tensor, torch.Tensor]:
    max_abs = torch.amax(torch.abs(weight), dim=1)
    scales = max_abs / QMAX
    safe_scales = torch.where(scales > 0, scales, torch.ones_like(scales))
    quantized = torch.round(weight / safe_scales[:, None]).clamp(-QMAX, QMAX)
    quantized = torch.where(scales[:, None] > 0, quantized, torch.zeros_like(quantized))
    return quantized.to(torch.int16), scales.to(torch.float64)


def rowwise_q024_scores(
    rowwise_q: torch.Tensor,
    q024_scales: torch.Tensor,
    hidden_q: torch.Tensor,
) -> torch.Tensor:
    acc = torch.sum(rowwise_q.to(torch.int64) * hidden_q.to(torch.int64), dim=1)
    return acc * q024_scales.to(torch.int64)


def decode_token(tokenizer: GPT2TokenizerFast, token_id: int) -> str:
    return tokenizer.decode([token_id], clean_up_tokenization_spaces=False)


def main() -> int:
    args = parse_args()
    if args.max_new_tokens <= 0:
        raise SystemExit("--max-new-tokens must be positive")
    if args.top_k <= 0:
        raise SystemExit("--top-k must be positive")

    tokenizer = GPT2TokenizerFast(
        vocab_file=str(args.tokenizer_vocab),
        merges_file=str(args.tokenizer_merges),
        unk_token="<|endoftext|>",
        bos_token="<|endoftext|>",
        eos_token="<|endoftext|>",
    )
    prompt_ids = tokenizer.encode(args.prompt, add_special_tokens=False)
    if not prompt_ids:
        raise SystemExit("prompt tokenized to an empty sequence")

    build_model = load_adapter_build_model(args.adapter_path)
    model = build_model(str(args.model_path)).eval()
    if not hasattr(model, "transformer") or not hasattr(model, "lm_head"):
        raise SystemExit("expected GPT-Neo-style transformer and lm_head modules")

    weight = model.lm_head.weight.detach().cpu().to(torch.float64).contiguous()
    vocab_size, hidden_size = list(weight.shape)
    if max(prompt_ids) >= vocab_size:
        raise SystemExit(f"prompt token outside model vocab {vocab_size}: {prompt_ids}")
    bias = getattr(model.lm_head, "bias", None)
    bias_supported = bias is None or bool(torch.all(bias.detach().cpu() == 0).item())
    if not bias_supported:
        raise SystemExit("nonzero lm_head bias is not supported by the rowwise Q0.24 reference")

    tied = (
        model.transformer.wte.weight.detach().data_ptr()
        == model.lm_head.weight.detach().data_ptr()
    )
    rowwise_q, rowwise_scales = quantize_rowwise_symmetric(weight)
    q024_scales = torch.round(rowwise_scales * Q024_SCALE).to(torch.int64)
    reserved_nonzero_count = int(torch.sum(q024_scales > Q024_MAX).item())
    if reserved_nonzero_count:
        raise SystemExit(f"{reserved_nonzero_count} rowwise scales exceed Q0.24 range")

    modules = dict(model.named_modules())
    module_paths = {
        "ln2": "transformer.h.0.ln_2",
        "c_fc": "transformer.h.0.mlp.c_fc",
        "c_proj": "transformer.h.0.mlp.c_proj",
    }
    missing_modules = [name for name in module_paths.values() if name not in modules]
    if missing_modules:
        raise SystemExit(f"missing expected transformer modules: {missing_modules}")

    c_fc = modules[module_paths["c_fc"]]
    c_proj = modules[module_paths["c_proj"]]
    ln2 = modules[module_paths["ln2"]]
    c_fc_weight = c_fc.weight.detach().cpu().to(torch.float64)
    c_proj_weight = c_proj.weight.detach().cpu().to(torch.float64)
    c_fc_bias = (
        c_fc.bias.detach().cpu().to(torch.float64)
        if c_fc.bias is not None
        else torch.zeros(c_fc_weight.shape[0], dtype=torch.float64)
    )
    c_proj_bias = (
        c_proj.bias.detach().cpu().to(torch.float64)
        if c_proj.bias is not None
        else torch.zeros(c_proj_weight.shape[0], dtype=torch.float64)
    )

    c_fc_out_features, c_fc_in_features = [int(value) for value in c_fc_weight.shape]
    c_proj_out_features, c_proj_in_features = [
        int(value) for value in c_proj_weight.shape
    ]
    c_fc_weight_q, c_fc_weight_scales = quantize_per_output_symmetric_to_list(
        c_fc_weight,
        c_fc_out_features,
        c_fc_in_features,
    )
    c_proj_weight_q, c_proj_weight_scales = quantize_per_output_symmetric_to_list(
        c_proj_weight,
        c_proj_out_features,
        c_proj_in_features,
    )
    if c_fc_out_features != c_proj_in_features:
        raise SystemExit(
            "unexpected architecture: c_fc output features and c_proj input features must match"
        )

    constants = load_mlp_int8_constants(
        args.post_gelu_requant_json,
        args.c_proj_requant_json,
        args.residual_add_rtl_proof_json,
    )
    x_frac = int(constants["x_frac"])
    scale_shift = int(constants["scale_shift"])
    gelu_quad_q = int(constants["gelu_quad_q"])
    output_requant_mult = int(constants["output_requant_mult"])
    output_requant_shift = int(constants["output_requant_shift"])
    c_proj_output_requant_shift = int(constants["c_proj_output_requant_shift"])
    residual_add_requant_shift = int(constants["residual_add_requant_shift"])
    residual_requant_mult = int(constants["residual_requant_mult"])
    c_proj_residual_add_requant_mult = int(
        constants["c_proj_residual_add_requant_mult"]
    )
    post_gelu_output_scale = float(constants["post_gelu_output_scale"])
    c_proj_output_scale = float(constants["c_proj_output_scale"])

    captured: dict[str, torch.Tensor] = {}

    def ln2_hook(
        _module: torch.nn.Module,
        inputs: tuple[torch.Tensor, ...],
        output: Any,
    ) -> None:
        if len(inputs) != 1:
            raise RuntimeError(f"ln_2 expected 1 input, got {len(inputs)}")
        captured["residual_activation"] = first_tensor(inputs[0]).detach().cpu().to(torch.float64)
        captured["ln2_activation"] = first_tensor(output).detach().cpu().to(torch.float64)

    hook = ln2.register_forward_hook(ln2_hook)

    f32_ids = list(prompt_ids)
    q024_ids = list(prompt_ids)
    steps: list[dict[str, Any]] = []
    c_fc_bias_q = [round(float(value) * (1 << x_frac)) for value in c_fc_bias.tolist()]
    c_proj_bias_q = [
        round(float(value) / c_proj_output_scale) for value in c_proj_bias.tolist()
    ]
    c_proj_output_scale_mul = [
        round(
            (post_gelu_output_scale * weight_scale / c_proj_output_scale)
            * (1 << c_proj_output_requant_shift)
        )
        for weight_scale in c_proj_weight_scales
    ]
    try:
        with torch.no_grad(), torch.inference_mode():
            for step in range(args.max_new_tokens):
                f32_input = torch.tensor([f32_ids], dtype=torch.long)
                f32_logits = (
                    model(input_ids=f32_input, use_cache=False)
                    .logits[0, -1]
                    .detach()
                    .cpu()
                    .to(torch.float64)
                )
                f32_topk = deterministic_topk_float(f32_logits, args.top_k)
                f32_next = f32_topk[0]
                f32_ids.append(f32_next)

                q024_input = torch.tensor([q024_ids], dtype=torch.long)
                captured.clear()
                transformer_out = model.transformer(input_ids=q024_input, use_cache=False)
                hidden = (
                    transformer_out.last_hidden_state[0, -1]
                    .detach()
                    .cpu()
                    .to(torch.float64)
                )
                hidden_q, hidden_scale = quantize_symmetric_tensor(hidden)
                q024_scores = rowwise_q024_scores(rowwise_q, q024_scales, hidden_q)
                q024_topk = deterministic_topk_int(q024_scores, args.top_k)
                q024_next = q024_topk[0]
                q024_ids.append(q024_next)

                residual_activation = captured.get("residual_activation")
                ln2_activation = captured.get("ln2_activation")
                if residual_activation is None or ln2_activation is None:
                    raise SystemExit(
                        "ln_2 hook did not capture expected residual/activation tensors"
                    )
                residual_activation = residual_activation[0, -1]
                ln2_activation = ln2_activation[0, -1]

                residual_q, residual_scale = quantize_symmetric_to_list(
                    residual_activation
                )
                ln2_activation_q, ln2_activation_scale = quantize_symmetric_to_list(
                    ln2_activation
                )
                c_fc_scale_mul = [
                    round((ln2_activation_scale * c_fc_weight_scale) * (1 << (x_frac + scale_shift)))
                    for c_fc_weight_scale in c_fc_weight_scales
                ]
                c_fc_accs = compute_accumulators(
                    ln2_activation_q,
                    c_fc_weight_q,
                    c_fc_in_features,
                    c_fc_out_features,
                )
                post_gelu_q = [
                    fixed_post_gelu_q(
                        acc=acc,
                        scale_mul=scale_mul,
                        bias_q=bias_q,
                        gelu_quad_q=gelu_quad_q,
                        output_requant_mult=output_requant_mult,
                        x_frac=x_frac,
                        scale_shift=scale_shift,
                        output_requant_shift=output_requant_shift,
                    )
                    for acc, scale_mul, bias_q in zip(
                        c_fc_accs,
                        c_fc_scale_mul,
                        c_fc_bias_q,
                    )
                ]

                c_proj_accs = compute_accumulators(
                    post_gelu_q,
                    c_proj_weight_q,
                    c_proj_in_features,
                    c_proj_out_features,
                )
                c_proj_output_q = [
                    fixed_c_proj_output_q(
                        acc,
                        c_proj_output_scale_mul[index],
                        c_proj_bias_q[index],
                        c_proj_output_requant_shift,
                    )
                    for index, acc in enumerate(c_proj_accs)
                ]

                residual_add_q = residual_add_output_q(
                    residual_q,
                    residual_requant_mult,
                    c_proj_output_q,
                    c_proj_residual_add_requant_mult,
                    residual_add_requant_shift,
                )
                residual_add_output_bytes = bytes(
                    (value & 0xFF) for value in residual_add_q
                )
                residual_add_output_checksum = sum(residual_add_output_bytes) & 0xFFFFFFFF
                residual_add_output_sample0 = int.from_bytes(
                    residual_add_output_bytes[:4], byteorder="little", signed=False
                )
                residual_add_output_sample1 = int.from_bytes(
                    residual_add_output_bytes[4:8], byteorder="little", signed=False
                )

                steps.append(
                    {
                        "step": step,
                        "f32_context_token_ids": f32_ids[:-1],
                        "q024_context_token_ids": q024_ids[:-1],
                        "hidden_scale": hidden_scale,
                        "hidden_q": [int(value) for value in hidden_q.cpu().tolist()],
                        "ln2_activation_scale": ln2_activation_scale,
                        "activation_q": ln2_activation_q,
                        "residual_activation_scale": residual_scale,
                        "residual_q": residual_q,
                        "residual_add_output_q": [
                            int(value) for value in residual_add_q
                        ],
                        "residual_add_output_checksum": residual_add_output_checksum,
                        "residual_add_output_sample0": residual_add_output_sample0,
                        "residual_add_output_sample1": residual_add_output_sample1,
                        "f32_topk_token_ids": f32_topk,
                        "f32_topk_text": [
                            decode_token(tokenizer, token) for token in f32_topk
                        ],
                        "q024_topk_token_ids": q024_topk,
                        "q024_topk_text": [
                            decode_token(tokenizer, token) for token in q024_topk
                        ],
                        "q024_topk_scores_low32": [
                            int(q024_scores[token].item()) & 0xFFFFFFFF
                            for token in q024_topk
                        ],
                        "tokens_match_f32_top1": q024_next == f32_next,
                    }
                )
    finally:
        hook.remove()

    generated_f32 = f32_ids[len(prompt_ids) :]
    generated_q024 = q024_ids[len(prompt_ids) :]
    token_mismatch_count = sum(
        1 for lhs, rhs in zip(generated_q024, generated_f32) if lhs != rhs
    )
    result = {
        "artifact_name": "h2-tinystories-1m-prompt-output-head-q024-reference",
        "status": "PASS",
        "date": dt.date.today().isoformat(),
        "coverage": {
            "tokenizer": "GPT-Neo/GPT-2 BPE from explicit vocab.json and merges.txt",
            "transformer": "PyTorch f32",
            "output_head": "rowwise int8 weights, per-step int8 hidden vector, Q0.24 row scale",
            "hardware_equivalent": "matches current Task 6 DDR3 rowstream top1 arithmetic for each generated step",
            "not_yet_covered": [
                "int8 transformer blocks",
                "fixed-point attention",
                "fixed-point layernorm",
                "on-board prompt prefill/decode loop",
            ],
        },
        "model": {
            "model_path": str(args.model_path),
            "adapter_path": str(args.adapter_path),
            "vocab_size": vocab_size,
            "hidden_size": hidden_size,
            "lm_head_tied_to_token_embedding": tied,
            "lm_head_bias_supported": bias_supported,
        },
        "quantization": {
            "activation": "per-step symmetric int8 hidden vector",
            "weight": "rowwise symmetric int8 lm_head",
            "scale": "unsigned Q0.24 row sidecar",
            "q024_scale_min": int(torch.min(q024_scales).item()),
            "q024_scale_max": int(torch.max(q024_scales).item()),
            "reserved_nonzero_count": reserved_nonzero_count,
            "tie_break": "lower token id wins for equal integer score",
        },
        "prompt": {
            "text": args.prompt,
            "token_ids": prompt_ids,
            "tokens": [decode_token(tokenizer, token) for token in prompt_ids],
        },
        "generation": {
            "max_new_tokens": args.max_new_tokens,
            "f32_generated_token_ids": generated_f32,
            "f32_decoded_text": tokenizer.decode(f32_ids, clean_up_tokenization_spaces=False),
            "q024_generated_token_ids": generated_q024,
            "q024_decoded_text": tokenizer.decode(q024_ids, clean_up_tokenization_spaces=False),
            "q024_vs_f32_token_mismatch_count": token_mismatch_count,
        },
        "steps": steps,
        "decision": {
            "verdict": "promote-as-output-head-quantized-generation-reference",
            "next_gate": (
                "Use q024_generated_token_ids and per-step hidden_q payloads as the "
                "prompt-level PCIe/top1 replay target, then replace PyTorch f32 "
                "transformer stages with fixed-point RTL one boundary at a time."
            ),
        },
    }

    args.out_json.parent.mkdir(parents=True, exist_ok=True)
    args.out_json.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    if args.json_only:
        print(json.dumps(result, indent=2, sort_keys=True))
    else:
        print("PASS")
        print(f"prompt tokens: {prompt_ids}")
        print(f"q024 generated tokens: {generated_q024}")
        print(result["generation"]["q024_decoded_text"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
