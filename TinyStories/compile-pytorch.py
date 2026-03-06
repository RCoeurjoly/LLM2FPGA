#!/usr/bin/env python3
import os
from pathlib import Path

import torch
from torch_mlir.fx import export_and_import
from transformers import AutoModelForCausalLM

# 1) Load TinyStories-1M
MODEL_ID = "roneneldan/TinyStories-1M"
MODEL_PATH = os.environ.get("TINYSTORIES_MODEL_PATH", MODEL_ID)
LOCAL_ONLY = os.environ.get("TINYSTORIES_LOCAL_ONLY", "0") == "1"
QUANTIZATION = os.environ.get("TINYSTORIES_QUANTIZATION", "runtime-int8").strip().lower()

if QUANTIZATION != "runtime-int8":
    raise ValueError(
        "TINYSTORIES_QUANTIZATION must be 'runtime-int8'. "
        "Dequantization and floating-point fallback modes are removed by policy."
    )

model = AutoModelForCausalLM.from_pretrained(
    MODEL_PATH,
    use_cache=False,              # required for clean export
    attn_implementation="eager",  # avoid flash / fused attention
    local_files_only=LOCAL_ONLY,
).eval()


def quantize_tensor_int8_no_scale(tensor: torch.Tensor) -> torch.Tensor:
    if not tensor.is_floating_point():
        return tensor.to(torch.int8)
    max_abs = tensor.detach().abs().max()
    if max_abs.numel() == 0 or max_abs.item() == 0.0:
        return torch.zeros_like(tensor, dtype=torch.int8)
    scale = max_abs / 127.0
    return torch.clamp(torch.round(tensor / scale), -127, 127).to(torch.int8)


class TinyStoriesInt8Surrogate(torch.nn.Module):
    """Integer-only TinyStories model used for quantized lowering.

    This path intentionally contains no dequantization to floating-point compute.
    """

    def __init__(self, core: torch.nn.Module):
        super().__init__()
        if not hasattr(core, "transformer") or not hasattr(core, "lm_head"):
            raise RuntimeError("runtime-int8 expects a transformer + lm_head model.")
        transformer = core.transformer
        if not hasattr(transformer, "wte"):
            raise RuntimeError("runtime-int8 expects transformer.wte embedding.")

        wte_q = quantize_tensor_int8_no_scale(transformer.wte.weight.detach())
        self.register_buffer("wte_q", wte_q)

        if hasattr(transformer, "wpe"):
            wpe_q = quantize_tensor_int8_no_scale(transformer.wpe.weight.detach())
            self.register_buffer("wpe_q", wpe_q)
        else:
            self.register_buffer("wpe_q", None)

        lm_head_q = quantize_tensor_int8_no_scale(core.lm_head.weight.detach())
        self.register_buffer("lm_head_q", lm_head_q)
        lm_head_q_t_i32 = lm_head_q.transpose(0, 1).to(torch.int32)
        self.register_buffer("lm_head_q_t_i32", lm_head_q_t_i32)

        lm_bias = getattr(core.lm_head, "bias", None)
        if lm_bias is not None:
            self.register_buffer(
                "lm_head_bias_i32",
                torch.round(lm_bias.detach()).to(torch.int32),
            )
        else:
            self.register_buffer("lm_head_bias_i32", None)

        self.vocab_size = int(lm_head_q.shape[0])

    def forward(self, input_ids: torch.Tensor) -> torch.Tensor:
        token_embed_i32 = self.wte_q[input_ids].to(torch.int32)
        hidden_i32 = token_embed_i32

        if self.wpe_q is not None:
            seq_len = input_ids.shape[1]
            pos_ids = torch.arange(seq_len, device=input_ids.device, dtype=torch.long)
            pos_embed_i32 = self.wpe_q[pos_ids].to(torch.int32).unsqueeze(0)
            hidden_i32 = hidden_i32 + pos_embed_i32

        hidden_2d = hidden_i32.reshape(-1, hidden_i32.shape[-1])
        logits_2d = torch.matmul(hidden_2d, self.lm_head_q_t_i32)
        if self.lm_head_bias_i32 is not None:
            logits_2d = logits_2d + self.lm_head_bias_i32

        return logits_2d.reshape(*hidden_i32.shape[:-1], self.vocab_size)


model = TinyStoriesInt8Surrogate(model).eval()


# 2) Wrapper: logits only
class CausalLMWrapper(torch.nn.Module):
    def __init__(self, core: torch.nn.Module):
        super().__init__()
        self.core = core

    def forward(self, input_ids: torch.Tensor) -> torch.Tensor:
        out = self.core(input_ids)
        if hasattr(out, "logits"):
            return out.logits
        return out


wrapped = CausalLMWrapper(model).eval()

# 3) Static dummy input
B, S = 1, 1
input_ids = torch.zeros((B, S), dtype=torch.long)

# 4) torch.export
exported = torch.export.export(
    wrapped,
    (input_ids,),
    strict=False,   # GPT-Neo has dynamic shape logic
)

# 5) Torch-MLIR lowering
mlir_module = export_and_import(exported)

mlir_text = str(mlir_module)
print(mlir_text)

out_file = Path(
    os.environ.get(
        "TINYSTORIES_TORCH_MLIR_OUT",
        str(Path(__file__).with_name("tinystories_1m_torch.mlir")),
    )
)
with out_file.open("w", encoding="utf-8") as f:
    f.write(mlir_text)
