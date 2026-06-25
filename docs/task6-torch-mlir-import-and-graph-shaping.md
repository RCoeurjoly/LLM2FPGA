# Task 6 Torch-MLIR Import And Graph Shaping

Date: 2026-06-25

## Purpose

Clarify what the current LLM2FPGA PyTorch-to-Torch-MLIR interface imports, why
the representative-core W2A2 route still produced enormous SystemVerilog, and
which graph-shaping levers are worth testing before sending another model
through Torch-MLIR and CIRCT.

## Current Import Contract

The current entrypoint is `scripts/compile-pytorch.py`. It does not import an
arbitrary `.pt`, checkpoint, or ExecuTorch program directly. It imports a Python
adapter module and accepts one of three adapter contracts:

1. `build_mlir_module(model_path, output_type)`: the adapter owns the whole
   import and returns an MLIR module or text.
2. `export_program(model_path)`: the adapter returns a
   `torch.export.ExportedProgram`.
3. `build_model(model_path)` plus `example_inputs()`: the script calls
   `torch.export.export(model, tuple(example_inputs()), strict=...)`.

For the normal paths, the script then calls:

```python
from torch_mlir.fx import export_and_import

module = export_and_import(exported, output_type=args.output_type)
```

So the practical Torch-MLIR boundary in this repo is a statically captured
`torch.export`/FX-style ATen graph plus example-input-derived shape information,
not a PyTorch eager model by itself. This matches the Torch-MLIR FOSDEM 2025
presentation's simple import pattern, where a `torch.nn.Module` and example
input are imported through `torch_mlir.fx.export_and_import(...)`.

The representative-core PT2E adapter adds a quantization stage before this
boundary:

```text
TinyStories representative core
-> torch.export.export(...)
-> prepare_pt2e(...)
-> calibration
-> convert_pt2e(...)
-> optional graph rewrite/dump hooks
-> torch.export.export(quantized, ...)
-> torch_mlir.fx.export_and_import(...)
```

That means Torch-MLIR only sees whatever graph structure PT2E and any local
post-PT2E rewrites leave behind.

## What Went Wrong With W2A2

The W2A2 experiment expected low-bit quantization to make the PyTorch graph more
hardware-shaped before Torch-MLIR import. The evidence says that did not happen.

PT2E/XNNPACK changed quantized ranges and introduced quantize/dequantize
machinery, but the representative-core graph remained structurally float-heavy.
The current postmortem in `docs/task6-resource-usage-reduction-notes.md` records
the important signatures:

- many `quantize`, `int_repr`, `_make_per_tensor_quantized_tensor`, and
  `dequantize` operations;
- `matmul` paths that dequantize operands and compute in `f32`;
- float LayerNorm/GELU-style operations such as `rsqrt`, `tanh`, and `pow`;
- Linalg/CF IR that still contains float conversions and arithmetic;
- a large jump from CF to Handshake and then to a 1.6 GB to 1.66 GB SV bundle.

The root mistake was treating low-bit value ranges as equivalent to an integer
hardware architecture. They are not equivalent. A graph with `si8` tensors at
some boundaries but `f32` matmul, LayerNorm, GELU, or attention internals is
still a poor input for fine-grained tensor-to-Handshake hardware generation.

`reference_representation_rewrite` was a useful falsification experiment, not a
solution. In this repo it removed explicit QDQ operations at the Torch level and
exposed some integer matmul structure, but it still preserved float attention
matmuls and grew Linalg, CF, and Handshake IR. It should remain an experiment
knob, not a correctness or size guarantee.

## Graph-Shaping Toolbox

The next useful experiments should prove graph structure before Torch-MLIR sees
the graph. Another bit-width change is not meaningful unless it changes compute
type and operator shape.

The preference should be integration-first: use maintained PyTorch-family graph
and quantization tools as the rewriting substrate, then add only the smallest
Task 6-specific policy needed to select patterns, gate failures, and connect the
result to Nix artifacts. There does not appear to be an official, maintained
"make this transformer FPGA-integer" tool. The maintained pieces are lower-level
composition points:

- `torch.export` as the capture boundary for normalized ATen graphs;
- `torch.fx` graph APIs and `subgraph_rewriter.replace_pattern(...)` for
  structured graph substitution;
- PyTorch AO/PT2E and `torchao` quantizers for backend-oriented quantization
  intent and conversion;
- ExecuTorch backend partitioners/preprocessors for backend-oriented graph
  partitioning and delegate artifact generation;
- Torch-MLIR/CIRCT stage gates for checking whether the imported graph shape is
  actually improving.

Use those tools before writing local graph infrastructure. The local code should
mostly glue, configure, score, and reject bad shapes.

### 1. Maintained Model-Transformation Tools

For Task 6, "model rewriting" should mean using maintained transformation
interfaces first, not writing a new graph compiler:

- use `torch.export` to get a stable captured graph with explicit example-input
  shapes;
- use `torch.fx` graph manipulation or `subgraph_rewriter.replace_pattern(...)`
  for small, testable substitutions;
- use `torch.export`/ATen decompositions where a high-level op needs to become
  lower-level arithmetic before import;
- use PT2E/`torchao` quantizers when the change is quantization intent, observer
  placement, or backend capability;
- use ExecuTorch partitioners when the question is "which subgraphs belong to a
  backend?" rather than "how do I rewrite one ATen pattern?"

The Task 6-specific work should be limited to choosing the target patterns,
running the official transformation API, and checking whether the resulting
graph has the expected integer/fixed-point structure.

### 2. Model Rewrites Before Export

Replace model submodules with hardware-shaped equivalents before
`torch.export.export(...)`:

- fixed-point or integer LayerNorm approximations;
- lookup-table or piecewise-linear GELU;
- attention score/value paths that avoid reintroducing float matmul;
- explicit linear/GEMV modules that map to expected kernel contracts;
- smaller representative-core profiles only when they preserve operator
  coverage relevant to the failure.

This is the most direct way to prevent PyTorch export from capturing a float
architecture.

### 3. PT2E Quantizer Configuration And Custom Quantizers

PyTorch AO's PT2E flow is explicitly backend-oriented: export to ATen, apply a
backend-specific quantizer with `prepare_pt2e`, calibrate/train, run
`convert_pt2e`, then lower to ExecuTorch, Inductor, or another backend. The same
documentation says backend developers can write their own quantizer and expose
methods for how the model should be quantized.

For Task 6, that means the relevant question is not just "can XNNPACK quantize
this?" It is "can a quantizer express the integer/fixed-point operator patterns
the FPGA path needs?"

Useful knobs to test:

- compose quantizers instead of relying on a single global XNNPACK config;
- inspect quantizer capability APIs rather than assuming all modules are
  covered;
- dump the FX graph immediately after `convert_pt2e` and gate on operator
  structure;
- write a small Task 6 quantizer for one representative pattern, such as
  linear/GEMV with known accumulator and requantization semantics, only if
  maintained quantizers cannot express the needed pattern.

### 4. Post-Export / Post-PT2E FX Rewrites

When PT2E produces QDQ around float math, add explicit graph passes before the
second `torch.export.export(...)` or before Torch-MLIR import:

- fuse quantize/dequantize/matmul patterns into integer linear or GEMV forms;
- replace float approximations with fixed-point subgraphs;
- reject graphs with float compute in known quantized lanes;
- record op counts and first offending nodes in a machine-readable report.

This is safer than discovering the problem after CF, Handshake, or SV emission.

### 5. Torch-MLIR And Pipeline Gates

Torch-MLIR import success is not enough. Add cheap gates immediately after
Torch-MLIR and Linalg/CF emission:

- count `torch.aten.dequantize`, `torch.aten.quantize_per_tensor`, and
  quantized-decomposed equivalents;
- count `f32`, `arith.sitofp`, `arith.fptosi`, `math.rsqrt`, `math.tanh`, and
  float `linalg.matmul`/`torch.aten.matmul`;
- fail early when CF line count, Handshake line count, or HW-clean bytes cross a
  known bad threshold;
- compare every new strategy against the copied baseline bundle at
  `artifacts/task6/baselines/tiny-stories-1m-baseline-float-selftest-all-memory-utilization`.

The goal is to stop non-structural quantization before it becomes a huge
ready/valid network.

### 6. ExecuTorch Backend Probes

ExecuTorch should be treated as a backend/partitioning system, not as a magic
Torch-MLIR input format.

It may help if an official backend transforms the exported graph into a more
hardware-useful, still-inspectable form. It does not help Torch-MLIR if the
result is only an opaque delegate call plus a blob. In that case, the artifact
belongs to an ExecuTorch runtime delegate contract, not to the current
Torch-MLIR tensor lowering path.

The useful survey question is:

```text
Does this backend leave a transparent graph or feasible lowering hook that can
be compared against reference outputs?
```

Reject backend paths that only prove "Yosys can synthesize a small surrogate."
That is a wiring smoke test, not semantic model lowering.

Creating a Task 6 ExecuTorch backend remains a real option, but it should be
treated as a backend-contract project, not as proof that the model is lowered
correctly. The quick local backend surrogate showed that downstream CIRCT can
emit small SV when the graph is replaced by a tiny backend-owned surrogate. That
is useful for plumbing. The hard part is functional equivalence: the backend
must preserve the selected subgraph semantics, produce reference-comparable
artifacts, and expose enough structure for hardware generation or manifest
emission.

### 7. Manifest / Common-Kernel Boundary

If the desired hardware is a small set of reusable fixed-point kernels fed by
DDR3 weights, the full tensor-to-Handshake route may be the wrong abstraction.
In that architecture, PyTorch or ExecuTorch should produce:

- an operator manifest;
- quantized weights and scales;
- schedules and memory layouts;
- reference inputs/outputs;
- acceptance tolerances.

CIRCT/SystemVerilog should then build reusable kernels and integration logic,
not materialize the entire model graph as a fine-grained hardware network.

## Recommendations

1. Add a pre-Torch-MLIR graph-shaping gate for the representative-core PT2E
   path. The gate should inspect the post-`convert_pt2e` graph and fail unless
   core matmul/linear paths are structurally integer or fixed-point.
2. Stop treating W2A2 as meaningful hardware quantization unless the report
   includes both value range and compute type. "2-bit activations" with float
   matmul is not a resource-reduction claim for this pipeline.
3. Keep `reference_representation_rewrite` documented as a measured non-solution
   for this stack unless a future PyTorch/torch-mlir version changes the
   downstream evidence.
4. Use ExecuTorch official backends only as graph-shaping probes when their
   artifacts remain transparent or provide a real lowering hook. Opaque delegate
   blobs are not useful for our use case.
5. Prioritize one narrow structural-shaping experiment over broad backend
   hopping. Use the existing representative core, inspect one subgraph class at
   a time, and survey maintained tools/settings for producing the desired
   fixed-point or integer form before Torch-MLIR. Start with linear/GEMV or the
   MLP slice, then separately evaluate GELU, LayerNorm, attention score/value
   matmuls, and softmax-like pieces.
6. Use "integer/fixed-point structural lowering" as the precise target phrase.
   "Folding" may describe a specific optimization, and "quantization" may only
   describe value ranges. The actual requirement is to remove float compute from
   hardware-critical paths and expose bounded integer/fixed-point operators with
   explicit accumulator and requantization behavior.
7. Keep a custom Task 6 ExecuTorch backend on the option list, but judge it by
   semantic artifacts, not by small SV size. It is promising only if it captures
   backend-owned partitions, preserves functional equivalence against reference
   outputs, and emits inspectable manifests or hardware-lowering inputs.
8. If structural rewrites become a growing pile of special cases, promote the
   manifest/common-kernel path. That is likely closer to the Task 6 DDR3 and
   reusable-kernel direction than general-purpose Handshake lowering.

## Source Anchors

- Local importer: `scripts/compile-pytorch.py`.
- Local representative-core PT2E adapter:
  `TinyStories/model_adapter_representative_core_pt2e_static_quant.py`.
- Local W2A2 postmortem:
  `docs/task6-resource-usage-reduction-notes.md`.
- Local ExecuTorch survey design:
  `docs/superpowers/specs/2026-06-25-official-executorch-backend-hw-mlir-survey.md`.
- FOSDEM 2025 Torch-MLIR introduction:
  `https://archive.fosdem.org/2025/events/attachments/fosdem-2025-6643-an-introduction-to-torch-mlir/slides/237934/An_Introd_nnOMKYo.pdf`.
- PyTorch AO PT2E post-training quantization tutorial:
  `https://docs.pytorch.org/ao/stable/tutorials_source/pt2e_quant_ptq.html`.
- PyTorch FX graph transformation and subgraph rewriting documentation:
  `https://docs.pytorch.org/docs/2.12/fx.html`.
- PyTorch AO guide for writing PT2E quantizers:
  `https://docs.pytorch.org/ao/stable/tutorials_source/pt2e_quantizer.html`.
