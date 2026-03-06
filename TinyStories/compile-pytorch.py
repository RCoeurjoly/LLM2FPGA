#!/usr/bin/env python3
import os
import torch
from pathlib import Path
from torch_mlir.fx import export_and_import
from transformers import AutoModelForCausalLM
try:
    from transformers.pytorch_utils import Conv1D
except Exception:  # pragma: no cover - optional fallback for older transformers
    Conv1D = None

# 1) Load TinyStories-1M
MODEL_ID = "roneneldan/TinyStories-1M"
MODEL_PATH = os.environ.get("TINYSTORIES_MODEL_PATH", MODEL_ID)
LOCAL_ONLY = os.environ.get("TINYSTORIES_LOCAL_ONLY", "0") == "1"
QUANTIZATION = os.environ.get("TINYSTORIES_QUANTIZATION", "none").strip().lower()

model = AutoModelForCausalLM.from_pretrained(
    MODEL_PATH,
    use_cache=False,              # required for clean export
    attn_implementation="eager",  # avoid flash / fused attention
    local_files_only=LOCAL_ONLY,
).eval()


def apply_quantization(module: torch.nn.Module, mode: str) -> torch.nn.Module:
    def quantize_dequantize_int8(tensor: torch.Tensor) -> torch.Tensor:
        if not tensor.is_floating_point():
            return tensor
        max_abs = tensor.detach().abs().max()
        if max_abs.numel() == 0 or max_abs.item() == 0.0:
            return torch.zeros_like(tensor)
        scale = max_abs / 127.0
        q = torch.clamp(torch.round(tensor / scale), -127, 127)
        return (q * scale).to(dtype=tensor.dtype)

    def quantize_tensor_int8(tensor: torch.Tensor) -> tuple[torch.Tensor, torch.Tensor]:
        if not tensor.is_floating_point():
            return tensor.to(torch.int8), torch.tensor(1.0, device=tensor.device)
        max_abs = tensor.detach().abs().max()
        if max_abs.numel() == 0 or max_abs.item() == 0.0:
            scale = torch.tensor(1.0, dtype=torch.float32, device=tensor.device)
            return torch.zeros_like(tensor, dtype=torch.int8), scale
        scale = (max_abs / 127.0).to(dtype=torch.float32)
        q = torch.clamp(torch.round(tensor / scale), -127, 127).to(torch.int8)
        return q, scale

    def quantize_tensor_int8_no_scale(tensor: torch.Tensor) -> torch.Tensor:
        if not tensor.is_floating_point():
            return tensor.to(torch.int8)
        max_abs = tensor.detach().abs().max()
        if max_abs.numel() == 0 or max_abs.item() == 0.0:
            return torch.zeros_like(tensor, dtype=torch.int8)
        scale = max_abs / 127.0
        return torch.clamp(torch.round(tensor / scale), -127, 127).to(torch.int8)

    class Int8Linear(torch.nn.Module):
        def __init__(self, linear: torch.nn.Linear):
            super().__init__()
            weight_q, weight_scale = quantize_tensor_int8(linear.weight.detach())
            self.register_buffer("weight_q", weight_q)
            self.register_buffer("weight_scale", weight_scale)
            self.out_features = linear.out_features
            self.eps = torch.finfo(torch.float32).eps
            if linear.bias is not None:
                self.register_buffer("bias_fp32", linear.bias.detach().to(torch.float32))
            else:
                self.bias_fp32 = None

        def forward(self, x: torch.Tensor) -> torch.Tensor:
            x_shape = x.shape
            x2d = x.reshape(-1, x_shape[-1])
            x_abs_max = x2d.abs().amax(dim=1, keepdim=True)
            x_scale = torch.clamp(x_abs_max / 127.0, min=self.eps)
            x_q = torch.clamp(torch.round(x2d / x_scale), -127, 127).to(torch.int8)
            y_i32 = torch.matmul(
                x_q.to(torch.int32),
                self.weight_q.to(torch.int32).transpose(0, 1),
            )
            y = y_i32.to(torch.float32) * (x_scale * self.weight_scale)
            if self.bias_fp32 is not None:
                y = y + self.bias_fp32
            return y.reshape(*x_shape[:-1], self.out_features)

    class Int8Embedding(torch.nn.Module):
        def __init__(self, emb: torch.nn.Embedding):
            super().__init__()
            weight_q, weight_scale = quantize_tensor_int8(emb.weight.detach())
            self.register_buffer("weight_q", weight_q)
            self.register_buffer("weight_scale", weight_scale)

        def forward(self, input_ids: torch.Tensor) -> torch.Tensor:
            # Route i8 -> i32 -> f32 to avoid unsupported i8 sitofp lowerings.
            gathered = self.weight_q[input_ids].to(torch.int32).to(torch.float32)
            return gathered * self.weight_scale

    class Int8Conv1D(torch.nn.Module):
        def __init__(self, conv: Conv1D):
            super().__init__()
            weight_q, weight_scale = quantize_tensor_int8(conv.weight.detach())
            self.register_buffer("weight_q", weight_q)
            self.register_buffer("weight_scale", weight_scale)
            self.register_buffer("bias_fp32", conv.bias.detach().to(torch.float32))
            self.nf = conv.nf
            self.eps = torch.finfo(torch.float32).eps

        def forward(self, x: torch.Tensor) -> torch.Tensor:
            out_shape = x.size()[:-1] + (self.nf,)
            x2d = x.reshape(-1, x.size(-1))
            x_abs_max = x2d.abs().amax(dim=1, keepdim=True)
            x_scale = torch.clamp(x_abs_max / 127.0, min=self.eps)
            x_q = torch.clamp(torch.round(x2d / x_scale), -127, 127).to(torch.int8)
            y_i32 = torch.matmul(
                x_q.to(torch.int32),
                self.weight_q.to(torch.int32),
            )
            y = y_i32.to(torch.float32) * (x_scale * self.weight_scale)
            y = y + self.bias_fp32
            return y.view(out_shape)

    class TinyStoriesInt8Surrogate(torch.nn.Module):
        """Integer-only TinyStories surrogate for hardware flow bring-up.

        Uses int8 embeddings + int8 LM-head projection with int32 accumulation.
        No runtime floating-point ops are emitted in the exported graph.
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

    def replace_modules_with_runtime_int8(root: torch.nn.Module) -> torch.nn.Module:
        for name, child in list(root.named_children()):
            if isinstance(child, torch.nn.Linear):
                setattr(root, name, Int8Linear(child))
                continue
            if isinstance(child, torch.nn.Embedding):
                setattr(root, name, Int8Embedding(child))
                continue
            if Conv1D is not None and isinstance(child, Conv1D):
                setattr(root, name, Int8Conv1D(child))
                continue
            replace_modules_with_runtime_int8(child)
        return root

    if mode in ("", "none", "fp32"):
        return module
    if mode == "runtime-int8":
        return TinyStoriesInt8Surrogate(module)
    if mode == "runtime-int8-dequant":
        return replace_modules_with_runtime_int8(module)
    if mode == "dynamic-int8":
        # Dynamic quantization only targets supported module classes.
        return torch.ao.quantization.quantize_dynamic(
            module,
            {torch.nn.Linear},
            dtype=torch.qint8,
            inplace=False,
        )
    if mode == "weight-int8-dequant":
        # Export-safe post-training quantization:
        # quantize model weights to int8 and dequantize back to float tensors.
        with torch.no_grad():
            for _, param in module.named_parameters():
                param.copy_(quantize_dequantize_int8(param))
        return module
    raise ValueError(
        f"Unsupported TINYSTORIES_QUANTIZATION='{mode}'. "
        "Expected one of: none, runtime-int8, runtime-int8-dequant, dynamic-int8, weight-int8-dequant."
    )


model = apply_quantization(model, QUANTIZATION).eval()

# Optional sanity check
total_params = sum(p.numel() for p in model.parameters())
# print(total_params)  # ~1M

# 2) Wrapper: logits only
class CausalLMWrapper(torch.nn.Module):
    def __init__(self, core):
        super().__init__()
        self.core = core

    def forward(self, input_ids: torch.Tensor):
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
