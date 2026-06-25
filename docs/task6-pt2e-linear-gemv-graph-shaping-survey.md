# Task 6 PT2E Linear/GEMV Graph-Shaping Survey

Date: 2026-06-25

## Purpose

Survey maintained PyTorch-family options for turning the representative-core
PT2E graph into a more structural integer/fixed-point shape before Torch-MLIR,
starting from the `float_matmul_after_dequant` audit failure and the linear/GEMV
or MLP slice.

## Local Evidence

The current graph-shape audit target:

```bash
nix build .#tiny-stories-1m-representative-core-pt2e-static-w2a2-graph-shape-audit --no-link --print-out-paths -L
```

emits a failing report with:

- `float_matmul_after_dequant`;
- `float_layer_norm`;
- `float_gelu_or_tanh`;
- `98` `quantized_decomposed.dequantize_per_tensor` occurrences;
- `66` `quantized_decomposed.quantize_per_tensor` occurrences;
- `4` `aten.matmul` occurrences;
- `5` `aten.layer_norm` occurrences;
- `2` `aten.tanh` and `2` `aten.pow` occurrences.

The `float_matmul_after_dequant` failures are the attention score/value matmuls,
not the MLP linear projections. The graph around the first attention score
matmul is:

```text
dequantize_per_tensor(...)
aten._assert_tensor_metadata(... dtype: torch.float32 ...)
aten.to.dtype(..., torch.float32)
aten.transpose.int(...)
aten.matmul.default(...)
```

The MLP and projection paths show a related but distinct shape:

```text
dequantize_per_tensor(...)
aten.linear.default(...)
quantize_per_tensor(...)
```

So there are two work items:

1. attention matmul structuralization;
2. linear/GEMV/MLP structuralization.

This note focuses on maintained options for the second item, while keeping the
attention blocker visible because it is currently what the audit names.

## What "Good Shape" Means

For Task 6, a useful pre-Torch-MLIR shape is not just lower bit ranges. The
target is integer/fixed-point structural lowering:

- weights represented as integer storage plus scale/zero-point metadata;
- activations represented as integer storage at the compute boundary;
- linear/GEMV lowered to integer multiply-accumulate plus explicit accumulator
  width;
- requantization represented explicitly as scale, shift/multiply, clamp, and
  cast;
- no `aten.matmul` or `aten.linear` consuming dequantized `f32` operands on
  hardware-critical paths.

## Option 1: PT2E Custom Quantizer Annotation

This is the most maintained path for graph-shaping intent.

PyTorch AO's PT2E flow is explicitly:

```text
torch.export -> FX graph in ATen -> backend-specific quantizer
-> prepare_pt2e -> calibrate/train -> convert_pt2e -> lowering
```

The official PT2E quantizer guide says backend developers express quantization
intent by annotating graph edges or output nodes with `QuantizationAnnotation`
and `QuantizationSpec`. It also recommends pattern matching via
`SubgraphMatcherWithNameNodeMap` rather than hard-coding ATen IR directly,
because ATen decompositions can change when PyTorch changes.

For Task 6, this suggests a narrow maintained-tool experiment:

1. Build a small Task 6 quantizer that only annotates `linear`/GEMV-like
   patterns.
2. Use `QuantizationSpec` for activation and weight tensors.
3. Use `DerivedQuantizationSpec` for bias or accumulator-related scale when
   applicable.
4. Use `SharedQuantizationSpec` where residual/add boundaries must share
   parameters.
5. Run `prepare_pt2e`/calibration/`convert_pt2e`.
6. Gate on the post-convert graph: `aten.linear` or `aten.matmul` must no
   longer consume dequantized `f32` operands.

Expected risk: PT2E may still emit QDQ plus float `aten.linear` unless the
chosen backend quantizer and following lowering understand the pattern. The
custom quantizer can improve annotation coverage, but it is not by itself a
hardware lowering.

Verdict: **best first maintained experiment**, because it works at the official
PT2E intent boundary and can be scoped to one pattern.

## Option 2: Compose Existing PT2E Quantizers

The PT2E tutorial explicitly calls out quantizer composition, with an example
where one quantizer covers an embedding pattern and XNNPACK covers another
pattern. This matches the Task 6 preference to integrate maintained pieces.

For Task 6:

- keep `XNNPACKQuantizer` for patterns it handles well;
- add a second quantizer for missing representative-core patterns, starting with
  linear/GEMV or embedding if an official ExecuTorch quantizer covers it;
- inspect `quantization_capabilities()` or equivalent local APIs in the pinned
  environment before assuming coverage;
- compare post-`convert_pt2e` graph shape against the current audit report.

Expected risk: composition can improve which nodes are annotated, but it still
does not guarantee integer compute survives into the Torch-MLIR import boundary.

Verdict: **good integration-first variant** of Option 1.

## Option 3: TorchAO `quantize_` Linear APIs

TorchAO exposes maintained linear quantization configurations such as:

- `Int8WeightOnlyConfig`;
- `Int8DynamicActivationInt8WeightConfig`;
- `Int8DynamicActivationInt4WeightConfig`;
- integer helper primitives such as `safe_int_mm` and `int_scaled_matmul`.

These are relevant because they are maintained, linear-focused, and closer to
GEMV/GEMM than a generic QDQ graph. They are especially useful for learning the
expected packed-weight and scaled-integer matmul shape.

For Task 6, use them as an import-shaping probe:

1. Create a tiny `nn.Linear` or representative MLP module.
2. Apply `torchao.quantization.quantize_` with one linear config.
3. Try `torch.export.export(...)`.
4. Try `torch_mlir.fx.export_and_import(...)`.
5. Compare graph shape against the PT2E W2A2 audit.

Expected risk: many TorchAO linear configs are designed for runtime backends,
tensor subclasses, or `torch.compile`/ExecuTorch paths, not necessarily for
Torch-MLIR import. The docs also note an ExecuTorch lowering gap for one dynamic
activation/int4-weight flow. If export/Torch-MLIR sees opaque tensor subclass
ops or dequantized float fallback, this is not the Task 6 path.

Verdict: **worth a small probe, not the default pipeline yet**.

## Option 4: FX Subgraph Rewrite After PT2E

`torch.fx` provides maintained graph manipulation APIs, including
`subgraph_rewriter.replace_pattern(...)` for find/replace graph substitutions.
The FX docs describe it as a way to automate graph edits that become tedious as
transformations grow.

For Task 6, this is the most direct way to convert a known QDQ pattern:

```text
dequantize(input_q)
dequantize(weight_q)
aten.linear(...)
quantize(output)
```

into a Task 6-owned structural placeholder:

```text
task6.quantized_linear_or_manifest(...)
```

or into an explicit integer/fixed-point reference subgraph:

```text
int_repr/input integer tensor
int_repr/weight integer tensor
integer matmul or explicit MAC pattern
requantize/clamp/cast
```

Expected risk: if the replacement is a custom op, Torch-MLIR will not
automatically lower it unless the importer and downstream pipeline know it. If
the replacement is an explicit integer subgraph, it may be verbose but still far
smaller and more meaningful than float QDQ.

Verdict: **best second experiment if PT2E quantizer annotation cannot produce
the desired post-convert graph**. Keep it pattern-specific and test it on one
linear/GEMV slice.

## Option 5: ExecuTorch Backend Partitioning

ExecuTorch partitioners can identify backend-owned subgraphs and produce
delegate/preprocess artifacts. This is useful if Task 6 wants a manifest or
backend contract rather than direct Torch-MLIR tensor lowering.

For linear/GEMV:

- use a partitioner to capture quantized linear/MLP subgraphs;
- emit a manifest with weights, scales, accumulator rules, and schedule hints;
- compare reference outputs before treating small SV as meaningful.

Expected risk: opaque delegate calls do not help Torch-MLIR import. They are a
different backend architecture.

Verdict: **promising for common-kernel/manifest direction, not a direct fix for
Torch-MLIR import**.

## Rejected As Primary Fixes

- **Changing W2A2 bit width only:** already disproven. It changes ranges, not
  compute structure.
- **`reference_representation_rewrite` as the main path:** measured locally; it
  removed some QDQ but grew downstream IR and left float attention.
- **Full custom graph compiler:** violates the integration-first constraint.
  Only use custom logic as thin policy around maintained PyTorch graph APIs.

## Recommended Next Experiment

Start with one synthetic or representative linear/GEMV slice, not the whole
TinyStories graph.

1. Add a local smoke adapter for a tiny `nn.Linear`/GEMV or reuse
   `task6_rect_gemv_pt2e_static_quant_adapter.py`.
2. Try PT2E custom/composed quantizer annotation for that pattern.
3. Dump the post-`convert_pt2e` graph.
4. Extend `pt2e_graph_shape_audit.py` to detect
   `float_linear_after_dequant` separately from `float_matmul_after_dequant`.
5. Accept the experiment only if the graph exposes integer/fixed-point
   structure before Torch-MLIR.
6. If PT2E cannot expose that shape, try an FX `replace_pattern(...)` rewrite
   for the single QDQ-linear pattern.

The success criterion is not model quality yet. It is structural:

```text
No hardware-critical aten.linear/aten.matmul consuming dequantized f32 operands.
Explicit integer/fixed-point accumulator and requantization behavior is visible
before Torch-MLIR import.
```

## Source Anchors

- Local graph audit:
  `.#tiny-stories-1m-representative-core-pt2e-static-w2a2-graph-shape-audit`.
- Local pipeline note:
  `docs/task6-torch-mlir-import-and-graph-shaping.md`.
- PyTorch AO PT2E post-training quantization tutorial:
  `https://docs.pytorch.org/ao/stable/tutorials_source/pt2e_quant_ptq.html`.
- PyTorch AO custom PT2E quantizer guide:
  `https://docs.pytorch.org/ao/stable/tutorials_source/pt2e_quantizer.html`.
- TorchAO quantization API reference:
  `https://docs.pytorch.org/ao/stable/api_ref_quantization.html`.
- PyTorch FX graph rewriting docs:
  `https://docs.pytorch.org/docs/2.12/fx.html`.
