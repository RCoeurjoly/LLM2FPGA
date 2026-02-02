import torch


class DotModule(torch.nn.Module):
    def forward(self, a, b):
        return torch.matmul(a, b)
