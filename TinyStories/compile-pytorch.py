#!/usr/bin/env python3
import torch
from torch_mlir.fx import export_and_import
from transformers import AutoModelForCausalLM, AutoTokenizer

# 1) Load TinyStories-1M
MODEL_ID = "roneneldan/TinyStories-1M"
TOKENIZER_ID = "EleutherAI/gpt-neo-125M"

tokenizer = AutoTokenizer.from_pretrained(TOKENIZER_ID)

model = AutoModelForCausalLM.from_pretrained(
    MODEL_ID,
    use_cache=False,              # required for clean export
    attn_implementation="eager",  # avoid flash / fused attention
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
prompt = "Once upon a time there was"
encoded = tokenizer(prompt, return_tensors="pt")
input_ids = encoded["input_ids"]  # [1, seq_len], torch.long


# Fixed-shape dummy input: batch=1, seq_len=1 (or 4/8)
# B, S = 1, 1
# input_ids = torch.zeros((B, S), dtype=torch.long)  # token id 0 is valid

# 4) torch.export
exported = torch.export.export(
    wrapped,
    (input_ids,),
    strict=False,   # GPT-Neo has dynamic shape logic
)

# 5) Torch-MLIR lowering
mlir_module = export_and_import(exported)

print(mlir_module)

with open("tinystories_1m_torch.mlir", "w") as f:
    f.write(str(mlir_module))
