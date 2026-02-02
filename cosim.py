import torch
import numpy as np

from esi_cosim import HandshakeCosimBase, get_cosim_port

from dot import DotModule

class DotProduct(HandshakeCosimBase):
  pytorch_dot = DotModule()

  def run(self, a, b):
    self.memories[0] = a
    self.memories[1] = b
    self.go()
    return self.read_result()

  def run_checked(self, a, b):
    print(f"Computing dot product of {a} and {b}")
    result = self.run(a, b)
    tensor_a = torch.IntTensor(a)
    tensor_b = torch.IntTensor(b)
    dot = self.pytorch_dot.forward(tensor_a, tensor_b)
    print(f"from cosim: {result}, from pytorch: {dot}")


def rand_vec():
  return [np.random.randint(0, 100) for _ in range(5)]


cosim = DotProduct(get_cosim_port())

cosim.run_checked(rand_vec(), rand_vec())
