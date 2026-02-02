#!/usr/bin/env python3
import torch
from torch_mlir.fx import export_and_import
from transformers import AutoModelForCausalLM, AutoTokenizer

# 1) Load GPT2 (PyTorch)
MODEL_ID = "gpt2"

tokenizer = AutoTokenizer.from_pretrained(MODEL_ID)

# use_cache=False → simpler graph, avoids KV cache complications
model = AutoModelForCausalLM.from_pretrained(
    MODEL_ID,
    use_cache=False,
    attn_implementation="eager",   # avoid fused kernels / flash attention variants
).eval()

total_params = sum(p.numel() for p in model.parameters())
# print("Total parameters:")
# print(total_params)


# 2) Wrap to have a clean forward (logits only)
class GPT2Wrapper(torch.nn.Module):
    def __init__(self, core):
        super().__init__()
        self.core = core

    def forward(self, input_ids: torch.Tensor):
        # input_ids: (batch, seq_len), dtype=torch.long
        out = self.core(input_ids)
        return out.logits

wrapped = GPT2Wrapper(model).eval()

# 3) Dummy input with static shape
prompt = "Hello world"
encoded = tokenizer(prompt, return_tensors="pt")
input_ids = encoded["input_ids"]        # shape [1, seq_len], dtype long

# 4) Export to torch.export ExportedProgram
exported = torch.export.export(
    wrapped,
    (input_ids,),
    strict=False,       # important: GPT2 uses many aten ops / shape logic
)

# 5) Convert ExportedProgram → Torch-MLIR module
mlir_module = export_and_import(exported)

# 6) Print and save MLIR (torch dialect)
print(mlir_module)

with open("gpt2_torch.mlir", "w") as f:
    f.write(str(mlir_module))
