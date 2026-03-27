from __future__ import annotations

"""Integer-only TinyStories adapter for the shared PyTorch export entrypoint.

This stays model-specific because the integer rewrite is model-specific, but the
compile driver is shared across models now.
"""

import torch
from transformers import AutoModelForCausalLM


EXPORT_STRICT = False


def quantize_i8(tensor: torch.Tensor) -> torch.Tensor:
    if not tensor.is_floating_point():
        return tensor.to(torch.int8)
    max_abs = tensor.detach().abs().max()
    if max_abs.numel() == 0 or max_abs.item() == 0.0:
        return torch.zeros_like(tensor, dtype=torch.int8)
    scale = max_abs / 127.0
    return torch.clamp(torch.round(tensor / scale), -127, 127).to(torch.int8)


def quantize_i32(
    tensor: torch.Tensor | None, scale: int = 1024
) -> torch.Tensor | None:
    if tensor is None:
        return None
    if not tensor.is_floating_point():
        return tensor.to(torch.int32)
    return torch.round(tensor.detach() * scale).to(torch.int32)


def projection_weight(proj: torch.nn.Module) -> torch.Tensor:
    weight = proj.weight.detach()
    if isinstance(proj, torch.nn.Linear):
        return weight.transpose(0, 1).contiguous()
    return weight.contiguous()


class IntProject(torch.nn.Module):
    def __init__(self, proj: torch.nn.Module, out_shift: int = 7):
        super().__init__()
        self.register_buffer("weight_i8", quantize_i8(projection_weight(proj)))
        self.register_buffer(
            "bias_i32",
            quantize_i32(getattr(proj, "bias", None), scale=16),
        )
        self.out_shift = int(out_shift)

    def forward(self, x_i32: torch.Tensor) -> torch.Tensor:
        x_shape = x_i32.shape
        y = torch.matmul(
            x_i32.reshape(-1, x_shape[-1]).to(torch.int32),
            self.weight_i8.to(torch.int32),
        )
        if self.bias_i32 is not None:
            y = y + self.bias_i32
        if self.out_shift:
            y = y >> self.out_shift
        return y.reshape(*x_shape[:-1], y.shape[-1]).to(torch.int32)


class IntLayerNorm(torch.nn.Module):
    NORM_SHIFT = 10

    def __init__(self, layer_norm: torch.nn.LayerNorm):
        super().__init__()
        width = int(layer_norm.normalized_shape[0])
        if width <= 0:
            raise RuntimeError("LayerNorm width must be positive")
        self.mean_shift = max(0, width.bit_length() - 1)
        self.center_shift = 2
        self.register_buffer(
            "gamma_i32",
            quantize_i32(
                layer_norm.weight.detach(), scale=(1 << self.NORM_SHIFT)
            ),
        )
        self.register_buffer(
            "beta_i32", quantize_i32(layer_norm.bias.detach(), scale=16)
        )

    def forward(self, x_i32: torch.Tensor) -> torch.Tensor:
        mean = torch.sum(x_i32, dim=-1, keepdim=True, dtype=torch.int32)
        centered = x_i32 - (mean >> self.mean_shift)
        norm = centered >> self.center_shift
        return (((norm * self.gamma_i32) >> self.NORM_SHIFT) + self.beta_i32).to(
            torch.int32
        )


class IntMLP(torch.nn.Module):
    def __init__(self, mlp: torch.nn.Module):
        super().__init__()
        self.c_fc = IntProject(mlp.c_fc, out_shift=6)
        self.c_proj = IntProject(mlp.c_proj, out_shift=7)

    def forward(self, x_i32: torch.Tensor) -> torch.Tensor:
        h = self.c_fc(x_i32)
        h = torch.clamp(h, min=0) + (torch.clamp(h, max=0) >> 3)
        return self.c_proj(h)


class IntSelfAttention(torch.nn.Module):
    SOFTMAX_SHIFT = 12

    def __init__(self, attn_mod: torch.nn.Module):
        super().__init__()
        core = attn_mod.attention if hasattr(attn_mod, "attention") else attn_mod
        self.q_proj = IntProject(core.q_proj, out_shift=6)
        self.k_proj = IntProject(core.k_proj, out_shift=6)
        self.v_proj = IntProject(core.v_proj, out_shift=6)
        self.out_proj = IntProject(core.out_proj, out_shift=7)
        self.num_heads = int(core.num_heads)
        self.head_dim = int(core.head_dim)

    def forward(self, x_i32: torch.Tensor) -> torch.Tensor:
        bsz, seq, hidden = x_i32.shape

        def reshape_heads(x: torch.Tensor) -> torch.Tensor:
            x = x.reshape(bsz, seq, self.num_heads, self.head_dim)
            return x.permute(0, 2, 1, 3).contiguous()

        q = reshape_heads(self.q_proj(x_i32))
        k = reshape_heads(self.k_proj(x_i32))
        v = reshape_heads(self.v_proj(x_i32))

        scores = torch.matmul(q, k.transpose(-1, -2)) >> 1
        idx = torch.arange(seq, device=scores.device)
        causal = idx.view(1, 1, seq, 1) >= idx.view(1, 1, 1, seq)
        masked = torch.where(causal, scores, torch.full_like(scores, -(1 << 20)))
        masked = masked - torch.amax(masked, dim=-1, keepdim=True)
        attn = torch.clamp(masked + 256, min=0, max=(1 << self.SOFTMAX_SHIFT) - 1)

        context = torch.matmul(attn, v) >> self.SOFTMAX_SHIFT
        context = (
            context.permute(0, 2, 1, 3).contiguous().reshape(bsz, seq, hidden)
        )
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
        return (x_i32 + self.mlp(self.ln_2(x_i32))).to(torch.int32)


class QuantizedTinyStoriesCausalLM(torch.nn.Module):
    def __init__(self, core: torch.nn.Module):
        super().__init__()
        if not hasattr(core, "transformer") or not hasattr(core, "lm_head"):
            raise RuntimeError(
                "Expected GPT-Neo style model with transformer + lm_head."
            )

        tr = core.transformer
        self.register_buffer("wte_q", quantize_i8(tr.wte.weight.detach()))
        self.register_buffer("wpe_q", quantize_i8(tr.wpe.weight.detach()))
        self.blocks = torch.nn.ModuleList(IntGPTNeoBlock(block) for block in tr.h)
        self.ln_f = IntLayerNorm(tr.ln_f)
        self.lm_head = IntProject(core.lm_head, out_shift=0)

    def forward(self, input_ids: torch.Tensor) -> torch.Tensor:
        bsz, seq = input_ids.shape
        pos_ids = torch.arange(seq, device=input_ids.device, dtype=torch.long)
        pos_ids = pos_ids.unsqueeze(0).expand(bsz, seq)

        hidden = self.wte_q[input_ids].to(torch.int32)
        hidden = hidden + self.wpe_q[pos_ids].to(torch.int32)
        for block in self.blocks:
            hidden = block(hidden)
        return self.lm_head(self.ln_f(hidden)).to(torch.int32)


def build_model(model_path: str | None) -> torch.nn.Module:
    if model_path is None:
        raise RuntimeError("TinyStories adapter requires --model-path")
    model_fp = AutoModelForCausalLM.from_pretrained(
        model_path,
        use_cache=False,
        attn_implementation="eager",
        local_files_only=True,
    ).eval()
    return QuantizedTinyStoriesCausalLM(model_fp).eval()


def example_inputs() -> tuple[torch.Tensor, ...]:
    return (torch.zeros((1, 1), dtype=torch.long),)
