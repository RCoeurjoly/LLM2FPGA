from __future__ import annotations

"""Shared native-FX quantized attention reproducers."""

import math

import torch


class QuantAttentionBlock(torch.nn.Module):
    def __init__(
        self,
        hidden_size: int = 8,
        num_heads: int = 2,
        *,
        use_layer_norm: bool = True,
        use_softmax: bool = True,
        use_score_scale: bool = True,
    ) -> None:
        super().__init__()
        self.hidden_size = hidden_size
        self.num_heads = num_heads
        self.head_dim = hidden_size // num_heads
        self.use_layer_norm = use_layer_norm
        self.use_softmax = use_softmax
        self.use_score_scale = use_score_scale
        if use_layer_norm:
            self.layer_norm = torch.nn.LayerNorm(hidden_size)
        self.q_proj = torch.nn.Linear(hidden_size, hidden_size, bias=False)
        self.k_proj = torch.nn.Linear(hidden_size, hidden_size, bias=False)
        self.v_proj = torch.nn.Linear(hidden_size, hidden_size, bias=False)
        self.out_proj = torch.nn.Linear(hidden_size, hidden_size, bias=False)

    def _split_heads(self, x: torch.Tensor) -> torch.Tensor:
        batch, seq, _ = x.shape
        return x.view(batch, seq, self.num_heads, self.head_dim).transpose(1, 2)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        if self.use_layer_norm:
            x = self.layer_norm(x)
        q = self._split_heads(self.q_proj(x))
        k = self._split_heads(self.k_proj(x))
        v = self._split_heads(self.v_proj(x))

        scores = torch.matmul(q, k.transpose(-2, -1))
        if self.use_score_scale:
            scores = scores / math.sqrt(self.head_dim)
        probs = torch.softmax(scores, dim=-1) if self.use_softmax else scores
        attn = torch.matmul(probs, v)
        batch, seq = x.shape[0], x.shape[1]
        attn = attn.transpose(1, 2).contiguous().view(batch, seq, self.hidden_size)
        return self.out_proj(attn)


class QuantProjection(torch.nn.Module):
    def __init__(self, hidden_size: int = 8) -> None:
        super().__init__()
        self.proj = torch.nn.Linear(hidden_size, hidden_size, bias=False)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.proj(x)


def attention_example_inputs() -> tuple[torch.Tensor, ...]:
    return (torch.randn(1, 4, 8),)


def projection_example_inputs() -> tuple[torch.Tensor, ...]:
    return (torch.randn(1, 4, 8),)
