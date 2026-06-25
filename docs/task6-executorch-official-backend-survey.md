# Task 6 Official ExecuTorch Backend Survey

This note tracks the official ExecuTorch backend survey for TinyStories representative-core PT2E static W2A2.

## Purpose

Use official ExecuTorch backends as semantic graph-shaping frontends before writing custom FPGA backend semantics.

## Current acceptance rule

A backend is not accepted because Yosys runs. A backend is promising only when it uses official ExecuTorch lowering APIs and produces a graph or artifact that can be connected to reference-output comparison.

## Initial candidate order

1. xnnpack
2. example
3. test
4. vulkan
5. cadence
6. arm
7. cortex_m
8. openvino
9. aoti
10. cuda
11. webgpu
12. mlx
13. apple
14. mediatek
15. nxp
16. qualcomm
17. samsung

## Importability findings

The current survey package records which official backend Python entrypoints are importable in the local Nix environment. Backends that are not importable are skipped before any lowering attempt. Backends that require proprietary SDKs remain inventory-only unless a pure local preprocessing API is available.
