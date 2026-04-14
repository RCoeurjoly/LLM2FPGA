from __future__ import annotations

"""TorchAO attention-block reproducer without softmax."""

import math

import torch
from torchao.quantization import Int8DynamicActivationInt8WeightConfig, quantize_


EXPORT_STRICT = False


class QuantAttentionBlockNoSoftmax(torch.nn.Module):
    def __init__(self, hidden_size: int = 64, num_heads: int = 4) -> None:
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
        attn = torch.matmul(scores, v)
        attn = attn.transpose(1, 2).contiguous().view(batch, seq, self.hidden_size)
        return self.out_proj(attn)


def example_inputs() -> tuple[torch.Tensor, ...]:
    return (torch.randn(1, 4, 64),)


def _is_linear(module: torch.nn.Module, fqn: str) -> bool:
    del fqn
    return isinstance(module, torch.nn.Linear)


def export_program(model_path: str | None) -> torch.export.ExportedProgram:
    del model_path
    model = QuantAttentionBlockNoSoftmax().eval()
    quantize_(
        model,
        Int8DynamicActivationInt8WeightConfig(),
        filter_fn=_is_linear,
    )
    return torch.export.export(
        model,
        tuple(example_inputs()),
        strict=EXPORT_STRICT,
    )
