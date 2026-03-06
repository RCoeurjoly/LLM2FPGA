# TinyStories Task 3 Inputs

This folder contains Task 3 scripts for TinyStories-1M lowering.

The only supported TinyStories export path is fully quantized integer-only:

```bash
nix build .#tiny-stories-1m-quant-int8-torch -L
```

Policy constraints:
- No dequantization fallback modes are supported.
- No floating-point compute fallback modes are supported.
- Downstream lowering must not proceed unless quantized CF is float-free.

To materialize a local copy in this directory:

```bash
cp result TinyStories/tinystories_1m_torch.mlir
```
