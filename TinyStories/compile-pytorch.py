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

model_fp = AutoModelForCausalLM.from_pretrained(
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


def quantize_tensor_int32_affine(tensor: torch.Tensor, scale: int = 1024) -> torch.Tensor:
    if tensor is None:
        return None
    if not tensor.is_floating_point():
        return tensor.to(torch.int32)
    return torch.round(tensor.detach() * scale).to(torch.int32)


class IntProject(torch.nn.Module):
    """Integer projection with int8 weights and int32 accumulations."""

    def __init__(self, proj: torch.nn.Module, out_shift: int = 7):
        super().__init__()
        weight = proj.weight.detach()

        if isinstance(proj, torch.nn.Linear):
            # Linear stores [out, in], we run x[in] @ w[in, out].
            weight_io = weight.transpose(0, 1).contiguous()
        else:
            # transformers Conv1D stores [in, out].
            weight_io = weight.contiguous()

        self.register_buffer("weight_i8", quantize_tensor_int8_no_scale(weight_io))

        bias = getattr(proj, "bias", None)
        if bias is not None:
            self.register_buffer("bias_i32", quantize_tensor_int32_affine(bias, scale=16))
        else:
            self.register_buffer("bias_i32", None)

        self.out_shift = int(out_shift)

    def forward(self, x_i32: torch.Tensor) -> torch.Tensor:
        x_shape = x_i32.shape
        x2d = x_i32.reshape(-1, x_shape[-1]).to(torch.int32)
        y = torch.matmul(x2d, self.weight_i8.to(torch.int32))
        if self.bias_i32 is not None:
            y = y + self.bias_i32
        if self.out_shift > 0:
            y = y >> self.out_shift
        return y.reshape(*x_shape[:-1], y.shape[-1]).to(torch.int32)


class IntLayerNorm(torch.nn.Module):
    """Integer-only LayerNorm approximation (L1-style normalization)."""

    NORM_SHIFT = 10

    def __init__(self, layer_norm: torch.nn.LayerNorm):
        super().__init__()
        width = int(layer_norm.normalized_shape[0])
        if width <= 0:
            raise RuntimeError("LayerNorm width must be positive")
        # TinyStories uses width=64, so mean can be computed with >> 6.
        self.mean_shift = max(0, width.bit_length() - 1)
        self.center_shift = 2
        self.register_buffer(
            "gamma_i32",
            quantize_tensor_int32_affine(layer_norm.weight.detach(), scale=(1 << self.NORM_SHIFT)),
        )
        self.register_buffer(
            "beta_i32",
            quantize_tensor_int32_affine(layer_norm.bias.detach(), scale=16),
        )

    def forward(self, x_i32: torch.Tensor) -> torch.Tensor:
        mean = torch.sum(x_i32, dim=-1, keepdim=True, dtype=torch.int32) >> self.mean_shift
        centered = x_i32 - mean
        norm = centered >> self.center_shift
        out = (norm * self.gamma_i32) >> self.NORM_SHIFT
        out = out + self.beta_i32
        return out.to(torch.int32)


class IntMLP(torch.nn.Module):
    def __init__(self, mlp: torch.nn.Module):
        super().__init__()
        self.c_fc = IntProject(mlp.c_fc, out_shift=6)
        self.c_proj = IntProject(mlp.c_proj, out_shift=7)

    @staticmethod
    def _gelu_like_i32(x: torch.Tensor) -> torch.Tensor:
        # Integer-friendly GELU approximation: leaky-ReLU shape.
        pos = torch.clamp(x, min=0)
        neg = torch.clamp(x, max=0)
        return pos + (neg >> 3)

    def forward(self, x_i32: torch.Tensor) -> torch.Tensor:
        h = self.c_fc(x_i32)
        h = self._gelu_like_i32(h)
        return self.c_proj(h)


class IntSelfAttention(torch.nn.Module):
    SOFTMAX_SHIFT = 12

    def __init__(self, attn_mod: torch.nn.Module):
        super().__init__()
        # GPT-Neo wraps q/k/v under attn.attention.
        core = attn_mod.attention if hasattr(attn_mod, "attention") else attn_mod

        self.q_proj = IntProject(core.q_proj, out_shift=6)
        self.k_proj = IntProject(core.k_proj, out_shift=6)
        self.v_proj = IntProject(core.v_proj, out_shift=6)
        self.out_proj = IntProject(core.out_proj, out_shift=7)

        self.num_heads = int(core.num_heads)
        self.head_dim = int(core.head_dim)

    def _reshape_heads(self, x: torch.Tensor) -> torch.Tensor:
        bsz, seq, hidden = x.shape
        x = x.reshape(bsz, seq, self.num_heads, self.head_dim)
        return x.permute(0, 2, 1, 3).contiguous()

    def _softmax_like_i32(self, scores: torch.Tensor) -> torch.Tensor:
        # Integer-only softmax-like approximation with no division.
        scores = scores - torch.amax(scores, dim=-1, keepdim=True)
        return torch.clamp(scores + 256, min=0, max=(1 << self.SOFTMAX_SHIFT) - 1)

    def forward(self, x_i32: torch.Tensor) -> torch.Tensor:
        q = self._reshape_heads(self.q_proj(x_i32))
        k = self._reshape_heads(self.k_proj(x_i32))
        v = self._reshape_heads(self.v_proj(x_i32))

        scores = torch.matmul(q, k.transpose(-1, -2))
        scores = scores >> 1

        seq = scores.shape[-1]
        idx = torch.arange(seq, device=scores.device)
        causal = idx.view(1, 1, seq, 1) >= idx.view(1, 1, 1, seq)
        masked = torch.where(causal, scores, torch.full_like(scores, -(1 << 20)))

        attn_weights = self._softmax_like_i32(masked)
        context = torch.matmul(attn_weights, v) >> self.SOFTMAX_SHIFT

        bsz = x_i32.shape[0]
        hidden = x_i32.shape[-1]
        context = context.permute(0, 2, 1, 3).contiguous().reshape(bsz, seq, hidden)

        return self.out_proj(context)


class IntGPTNeoBlock(torch.nn.Module):
    def __init__(self, block: torch.nn.Module):
        super().__init__()
        self.ln_1 = IntLayerNorm(block.ln_1)
        self.attn = IntSelfAttention(block.attn)
        self.ln_2 = IntLayerNorm(block.ln_2)
        self.mlp = IntMLP(block.mlp)

    def forward(self, x_i32: torch.Tensor) -> torch.Tensor:
        x_i32 = x_i32 + self.attn(self.ln_1(x_i32))
        x_i32 = x_i32 + self.mlp(self.ln_2(x_i32))
        return x_i32.to(torch.int32)


class QuantizedTinyStoriesCausalLM(torch.nn.Module):
    """Whole-model TinyStories quantized path (no surrogate bypass)."""

    def __init__(self, core: torch.nn.Module):
        super().__init__()
        if not hasattr(core, "transformer") or not hasattr(core, "lm_head"):
            raise RuntimeError("Expected GPT-Neo style model with transformer + lm_head.")

        tr = core.transformer
        self.register_buffer("wte_q", quantize_tensor_int8_no_scale(tr.wte.weight.detach()))
        self.register_buffer("wpe_q", quantize_tensor_int8_no_scale(tr.wpe.weight.detach()))

        self.blocks = torch.nn.ModuleList([IntGPTNeoBlock(b) for b in tr.h])
        self.ln_f = IntLayerNorm(tr.ln_f)
        self.lm_head = IntProject(core.lm_head, out_shift=0)

    def forward(self, input_ids: torch.Tensor) -> torch.Tensor:
        bsz, seq = input_ids.shape

        token_embed_i32 = self.wte_q[input_ids].to(torch.int32)
        pos_ids = torch.arange(seq, device=input_ids.device, dtype=torch.long)
        pos_ids = pos_ids.unsqueeze(0).expand(bsz, seq)
        pos_embed_i32 = self.wpe_q[pos_ids].to(torch.int32)

        hidden = token_embed_i32 + pos_embed_i32

        for block in self.blocks:
            hidden = block(hidden)

        hidden = self.ln_f(hidden)
        logits = self.lm_head(hidden)
        return logits.to(torch.int32)


model = QuantizedTinyStoriesCausalLM(model_fp).eval()


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
    strict=False,
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
