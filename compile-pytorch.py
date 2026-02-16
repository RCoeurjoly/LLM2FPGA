import torch
from torch_mlir.fx import export_and_import

class MatmulModule(torch.nn.Module):
    def forward(self, a, b):
        return torch.matmul(a, b)

m = MatmulModule().eval()
a = torch.randint(0, 10, (16,), dtype=torch.int32)
b = torch.randint(0, 10, (16,), dtype=torch.int32)

exported = torch.export.export(m, (a, b))
module = export_and_import(exported)

print(module)
