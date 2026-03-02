#!/usr/bin/env python3
import os
import torch
from pathlib import Path
from torch_mlir.fx import export_and_import
from transformers import AutoModelForCausalLM

# 1) Load TinyStories-1M
MODEL_ID = "roneneldan/TinyStories-1M"
MODEL_PATH = os.environ.get("TINYSTORIES_MODEL_PATH", MODEL_ID)
LOCAL_ONLY = os.environ.get("TINYSTORIES_LOCAL_ONLY", "0") == "1"

model = AutoModelForCausalLM.from_pretrained(
    MODEL_PATH,
    use_cache=False,              # required for clean export
    attn_implementation="eager",  # avoid flash / fused attention
    local_files_only=LOCAL_ONLY,
).eval()

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
        return out.logits

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
