# Official ExecuTorch Backend HW MLIR Survey Spec

## Goal

Evaluate official ExecuTorch backends as semantic, tested frontend graph-shaping paths for the existing LLM2FPGA Torch-MLIR/CIRCT pipeline before writing any custom FPGA ExecuTorch backend semantics.

## Problem

The current local FPGA backend spike proved that the Nix target can be wired into the compiler pipeline, but it also demonstrated a dangerous failure mode: a backend can produce a small HW MLIR/Yosys artifact without preserving model semantics. That is not an acceptable proof of correctness.

The safer approach is to use official ExecuTorch backend infrastructure first. Official backends already define partitioners, preprocessors, serialization/runtime conventions, and tests. The project should learn whether any official backend lowering produces an exported graph shape that Torch-MLIR can lower into useful HW MLIR. If so, LLM2FPGA can adapt the existing MLIR pipeline around that graph shape instead of inventing a semantic FPGA backend from scratch.

## References

- ExecuTorch backend test RFC: https://github.com/pytorch/executorch/discussions/11140
- Official ExecuTorch backend tree: https://github.com/pytorch/executorch/tree/main/backends
- XNNPACK backend README: https://github.com/pytorch/executorch/tree/main/backends/xnnpack
- Backend test infrastructure tree: https://github.com/pytorch/executorch/tree/main/backends/test

## Scope

This phase is an experiment and evidence-gathering phase for TinyStories representative-core PT2E static W2A2.

The phase must evaluate official ExecuTorch backends as graph-shaping frontends and report whether their lowered/exported graphs can enter the existing MLIR pipeline.

## In scope

- Inventory official ExecuTorch backends under `backends/`.
- Classify each backend by local usability, SDK/hardware requirements, Python entrypoints, quantization support, and runtime/test support.
- Add a local runner that attempts a TinyStories representative-core PT2E W2A2 export through selected official backend recipes.
- Capture backend artifacts and graph summaries.
- Attempt Torch-MLIR import and existing pipeline lowering to at least `torch`, `linalg`, `cf`, and `hw` where possible.
- Record metrics in a machine-readable report.
- Reject opaque delegate-only paths unless there is an inspectable graph or a feasible lowering hook.

## Out of scope

- Writing semantic FPGA kernels.
- Writing a new FPGA ExecuTorch runtime delegate.
- Claiming correctness from Yosys success alone.
- Board/HIL tests.
- Nextpnr fit.
- Full TinyStories-1M token-generation acceptance.
- Proprietary SDK setup unless the backend has a pure local preprocessing path.

## Backend candidate order

Evaluate in this order:

1. `xnnpack`: most relevant local CPU delegate and already used by PT2E quantization flows.
2. `example` and `test`: useful for understanding official backend contracts and railguards.
3. `vulkan`: useful if preprocessing is local and graph artifacts are inspectable.
4. `cadence`: relevant because it is quantization/backend-oriented and may preserve useful patterns.
5. `arm` and `cortex_m`: relevant to fixed-point embedded lowering.
6. `openvino`: relevant if it exports inspectable graph artifacts.
7. `aoti`, `cuda`, `webgpu`, `mlx`: inspect for graph-shaping value; likely less directly useful for HW MLIR.
8. `apple`, `mediatek`, `nxp`, `qualcomm`, `samsung`: inventory first, run only if pure local preprocessing is available without vendor SDK/hardware.

## Experiment pipeline

For each candidate backend:

```text
TinyStories representative-core PT2E static W2A2 adapter
-> official backend partition/lowering recipe
-> collect partition metrics and lowered graph/delegate artifacts
-> determine if lowered representation is transparent or opaque
-> attempt Torch-MLIR import when transparent
-> attempt existing LLM2FPGA stages: torch, linalg, cf, hw
-> collect size/op-count/failure metrics
```

## Metrics

Each backend report entry must include:

- `backend`: backend name.
- `status`: `pass`, `skip`, or `fail`.
- `skip_reason`: present when skipped.
- `requires_sdk`: boolean.
- `requires_hardware`: boolean.
- `python_entrypoints`: import paths discovered or attempted.
- `partitioned_ops`: list of delegated op names if available.
- `unpartitioned_ops`: list of remaining core op names if available.
- `delegate_blob_count`: integer or null.
- `delegate_blob_bytes`: integer or null.
- `graph_transparency`: `transparent`, `mixed`, `opaque`, or `unknown`.
- `torch_mlir_status`: `pass`, `skip`, or `fail`.
- `linalg_status`: `pass`, `skip`, or `fail`.
- `cf_status`: `pass`, `skip`, or `fail`.
- `hw_status`: `pass`, `skip`, or `fail`.
- `torch_mlir_bytes`: integer or null.
- `hw_mlir_bytes`: integer or null.
- `hw_mlir_lines`: integer or null.
- `failure_signature`: short string for the first concrete failure.

## Acceptance criteria

This phase succeeds when it produces a report that answers:

- Which official backends are locally runnable in this environment?
- Which official backends produce opaque delegate blobs only?
- Which official backends produce a graph representation that Torch-MLIR can inspect?
- Which official backend, if any, produces materially better HW MLIR than the current PT2E W2A2 baseline?
- Which backend test harness pieces should be reused as railguards for any future FPGA backend?

A backend is promising only if:

- It uses official ExecuTorch backend partition/lowering APIs.
- It does not depend on a local semantic mock.
- Its lowered graph is transparent enough for Torch-MLIR or exposes a feasible lowering hook.
- Its HW MLIR is smaller or cleaner than the current PT2E W2A2 baseline.
- It has a clear path to reference-output comparison using ExecuTorch-style tolerances.

## Explicit rejection criteria

Reject a backend for this phase if:

- It requires unavailable proprietary SDKs for preprocessing.
- It requires hardware for all useful lowering steps.
- It emits only opaque delegate calls with no inspectable tensor graph and no practical lowering hook.
- Torch-MLIR cannot import the lowered representation and no adapter path is evident.
- It reproduces the same huge PT2E W2A2 HW MLIR shape as the baseline.

## Correctness railguard

No backend path may be accepted because Yosys passes. Yosys success is a synthesis smoke result only. The required correctness direction is official ExecuTorch-style testing:

```text
eager/PT2 reference output
-> backend partition/lower
-> exported/lowered program execution or equivalent simulator
-> output comparison with backend-specific tolerances
-> partition/delegate/artifact metrics
```

