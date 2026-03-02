# TinyStories Task 3 Inputs

This folder contains Task 3 scripts and local artifacts for TinyStories-1M lowering.

`tinystories_1m_torch.mlir` is intentionally not committed because of size.

To provide it locally:

```bash
cp /home/roland/private_LLM2FPGA/TinyStories/tinystories_1m_torch.mlir TinyStories/
```

or regenerate it with:

```bash
nix develop -c python TinyStories/compile-pytorch.py
```

The flake package `.#tiny-stories-1m-torch` expects that file in this directory.
