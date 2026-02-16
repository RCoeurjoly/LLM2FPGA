import torch
from torch import fx
from torch_mlir.fx import export_and_import

from matmul import DotModule

m = DotModule().eval()

a = torch.randint(0, 10, (16,), dtype=torch.int32)
b = torch.randint(0, 10, (16,), dtype=torch.int32)

exported = torch.export.export(m, (a, b))
mlir_module = export_and_import(exported)

print(mlir_module)
