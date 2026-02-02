import torch
import torch_mlir

from dot import DotModule

shape = torch_mlir.TensorPlaceholder([5], torch.int32)

module = torch_mlir.compile(
    DotModule(), [shape, shape], output_type="linalg-on-tensors"
)

print(module)
