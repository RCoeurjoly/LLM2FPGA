import torch

class DotModule(torch.nn.Module):
    def forward(self, a, b):
        # Elementwise multiply then sum → scalar
        return torch.sum(a * b)
