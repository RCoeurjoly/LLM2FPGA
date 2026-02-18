import torch
from torch_mlir.fx import export_and_import

from sim_utils import load_matmul_module


MatmulModule = load_matmul_module()

m = MatmulModule().eval()
a = torch.zeros((16,), dtype=torch.int32)
b = torch.zeros((16,), dtype=torch.int32)

exported = torch.export.export(m, (a, b))
module = export_and_import(exported)

print(module)
