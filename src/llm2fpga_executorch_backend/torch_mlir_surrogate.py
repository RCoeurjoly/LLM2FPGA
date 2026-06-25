from __future__ import annotations

from typing import Any


def backend_surrogate_value(manifest: dict[str, Any]) -> int:
    """Return a compact scalar summary for the backend-owned compiler surrogate."""

    unmatched = manifest.get("unmatched_core_ops", [])
    if unmatched:
        raise ValueError(f"cannot build FPGA backend surrogate with unmatched core ops: {unmatched!r}")
    ops = manifest.get("ops", [])
    if not isinstance(ops, list) or not ops:
        raise ValueError("cannot build FPGA backend surrogate without captured backend ops")
    return len(ops)


def build_torch_surrogate_module(manifest: dict[str, Any]):
    """Create a tiny torch module whose structure is derived from the backend manifest.

    This is intentionally a compiler surrogate, not a semantic TinyStories implementation.
    It gives the Nix pipeline a backend-owned artifact to lower while the real FPGA
    kernel contracts are still being developed.
    """

    import torch

    value = backend_surrogate_value(manifest)

    class Llm2FpgaBackendSurrogate(torch.nn.Module):
        def forward(self, input_ids: torch.Tensor) -> torch.Tensor:
            zero = input_ids.to(torch.int64) * 0
            return zero + value

    return Llm2FpgaBackendSurrogate().eval()
