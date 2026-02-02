#!/usr/bin/env python3
import torch
from torch_mlir.fx import export_and_import
from transformers import AutoModelForCausalLM, AutoTokenizer

# 1) Load Mistral 7B
MODEL_ID = "mistralai/Mistral-7B-v0.1"

# Tokenizer should match the model
tokenizer = AutoTokenizer.from_pretrained(MODEL_ID, use_fast=True)

# If you later use padding/batching, Mistral often benefits from setting pad_token
# (not strictly required for the single-example export below)
if tokenizer.pad_token is None:
    tokenizer.pad_token = tokenizer.eos_token

model = AutoModelForCausalLM.from_pretrained(
    MODEL_ID,
    use_cache=False,                 # required for clean export
    attn_implementation="eager",     # avoid flash/sdpa/fused attention paths
    dtype=torch.float16,
).eval()

# 2) Wrapper: logits only (and explicit attention_mask)
class CausalLMWrapper(torch.nn.Module):
    def __init__(self, core):
        super().__init__()
        self.core = core

    def forward(self, input_ids: torch.Tensor, attention_mask: torch.Tensor):
        out = self.core(input_ids=input_ids, attention_mask=attention_mask, use_cache=False)
        return out.logits

wrapped = CausalLMWrapper(model).eval()

# 3) Static dummy input (prefer fixed shape for export)
# Keep seq_len small during bring-up; increase later if it works.
B, S = 1, 8
input_ids = torch.zeros((B, S), dtype=torch.long)
attention_mask = torch.ones((B, S), dtype=torch.long)

# (Optional) use a real prompt instead; still keep attention_mask explicit:
# prompt = "Once upon a time there was"
# enc = tokenizer(prompt, return_tensors="pt")
# input_ids = enc["input_ids"]
# attention_mask = enc["attention_mask"]

# 4) torch.export
exported = torch.export.export(
    wrapped,
    (input_ids, attention_mask),
    strict=False,
)

# 5) Torch-MLIR lowering
mlir_module = export_and_import(exported)

print(mlir_module)

with open("mistral_7b_torch.mlir", "w") as f:
    f.write(str(mlir_module))
