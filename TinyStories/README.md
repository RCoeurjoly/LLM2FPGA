# TinyStories Task 3 Inputs

This folder contains Task 3 scripts for TinyStories-1M lowering.

The flake package `.#tiny-stories-1m-torch` now generates the torch-MLIR
boundary artifact via a Nix derivation.

An additional quantized export path is available via
`.#tiny-stories-1m-quant-int8-torch`, which applies export-safe weight int8
quantize-dequant preprocessing before torch-MLIR export.
Model/tokenizer inputs are pinned to a fixed Hugging Face revision in
`flake.nix`:

```bash
nix build .#tiny-stories-1m-torch -L
nix build .#tiny-stories-1m-quant-int8-torch -L
```

To materialize a local copy in this directory:

```bash
cp result TinyStories/tinystories_1m_torch.mlir
```
