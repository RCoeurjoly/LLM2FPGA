from __future__ import annotations

"""Native-FX quantized attention-block reproducer for the cleaner standard path."""

import math

import torch

from native_fx_quant_utils import build_native_fx_raw_mlir


class QuantAttentionBlock(torch.nn.Module):
    def __init__(self, hidden_size: int = 8, num_heads: int = 2) -> None:
        super().__init__()
        self.hidden_size = hidden_size
        self.num_heads = num_heads
        self.head_dim = hidden_size // num_heads
        self.layer_norm = torch.nn.LayerNorm(hidden_size)
        self.q_proj = torch.nn.Linear(hidden_size, hidden_size, bias=False)
        self.k_proj = torch.nn.Linear(hidden_size, hidden_size, bias=False)
        self.v_proj = torch.nn.Linear(hidden_size, hidden_size, bias=False)
        self.out_proj = torch.nn.Linear(hidden_size, hidden_size, bias=False)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        x = self.layer_norm(x)
        q = self.q_proj(x)
        k = self.k_proj(x)
        v = self.v_proj(x)

        batch, seq, _ = q.shape
        q = q.view(batch, seq, self.num_heads, self.head_dim).transpose(1, 2)
        k = k.view(batch, seq, self.num_heads, self.head_dim).transpose(1, 2)
        v = v.view(batch, seq, self.num_heads, self.head_dim).transpose(1, 2)

        scores = torch.matmul(q, k.transpose(-2, -1)) / math.sqrt(self.head_dim)
        probs = torch.softmax(scores, dim=-1)
        attn = torch.matmul(probs, v)
        attn = attn.transpose(1, 2).contiguous().view(batch, seq, self.hidden_size)
        return self.out_proj(attn)


def example_inputs() -> tuple[torch.Tensor, ...]:
    return (torch.randn(1, 4, 8),)


def build_mlir_module(model_path: str | None, output_type: str) -> str:
    del model_path
    return build_native_fx_raw_mlir(
        QuantAttentionBlock().eval(),
        example_inputs(),
        output_type=output_type,
    )
