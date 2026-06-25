# ExecuTorch FPGA Backend Representative-Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Build a real ExecuTorch-compatible FPGA backend/delegate spike that captures representative-core W2A2 QDQ transformer islands before CIRCT Handshake.

**Architecture:** Add a repo-local backend package shaped like an ExecuTorch backend. The backend partitions PT2E/exported graphs into FPGA logical ops, validates that representative-core core compute is captured, and emits a common-kernel manifest instead of allowing scalarized float/QDQ lowering.

**Tech Stack:** Python, PyTorch PT2E/export, ExecuTorch backend APIs when available, Nix flake lanes, existing Task 6 representative-core artifacts.

---

## File Structure

- Create `src/llm2fpga_executorch_backend/`: backend package with partitioner, backend details, op schema, manifest serialization, and CLI.
- Create `scripts/task6/test_llm2fpga_executorch_backend.py`: unit tests for pattern capture and failure reporting.
- Modify `flake.nix`: add representative-core backend-manifest derivation.
- Modify `docs/task6-resource-usage-reduction-notes.md`, `docs/task6-crisp-state.org`, and `docs/task6-crisp-state.json` only when implementation evidence changes.

## Tasks

- [x] Create the backend package skeleton with `__init__.py`, `manifest.py`, `patterns.py`, `partitioner.py`, `backend_details.py`, and `cli.py`.
- [x] Add manifest schema v1 with required fields: `schema_version`, `backend_id`, `model_label`, `representative_core_dimensions`, `ops`, `quant_params`, `tensor_metadata`, `tiling_hints`, `kernel_ids`, and `unmatched_core_ops`.
- [x] Write failing unit tests for the manifest validator: accepts a complete payload, rejects missing required fields, rejects unknown op families.
- [x] Implement the minimal manifest validator and serializer; run the manifest tests until passing.
- [x] Write failing unit tests for QDQ matmul/linear capture into `fpga.quantized_matmul`.
- [x] Implement the matmul/linear pattern matcher over FX/PT2E graph text.
- [x] Write failing tests for LayerNorm, GELU/tanh-form GELU, and attention softmax/value matmul capture.
- [x] Implement matchers for `fpga.layer_norm`, `fpga.gelu`, and `fpga.softmax_or_attention`.
- [x] Implement `Llm2FpgaPartitioner` with an ExecuTorch-style partition facade and repo-local test path.
- [x] Implement `Llm2FpgaBackendDetails.preprocess` so delegated subgraphs become serialized FPGA manifests.
- [x] Add a CLI that takes the representative-core W2A2 PT2E graph dump and writes `manifest.json` plus `unmatched_core_ops.json`.
- [x] Add negative tests: if a core `aten.matmul`, `aten.layer_norm`, GELU/tanh island, or attention island remains unmatched, the CLI exits nonzero and reports the exact unmatched op.
- [x] Add the Nix derivation `.#tiny-stories-1m-representative-core-pt2e-static-w2a2-executorch-fpga-backend-manifest`.
- [x] Wire the derivation to stop at manifest generation; it does not lower unmatched QDQ/float islands into CIRCT Handshake.
- [ ] Run final regression checks and record results in Task 6 notes/crisp state.

## Acceptance Criteria

- The representative-core W2A2 backend-manifest lane builds.
- The payload contains all four op families: `fpga.quantized_matmul`, `fpga.layer_norm`, `fpga.softmax_or_attention`, and `fpga.gelu`.
- `unmatched_core_ops` is empty for the representative-core acceptance path.
- If matching fails, the pipeline fails before Handshake with a clear unmatched report.
- No claim is made that this is full TinyStories-1M fidelity or board acceptance; it is only the minimized backend capture proof.

## Assumptions

- Representative-core W2A2 is the only v1 acceptance target.
- The backend lives locally in this repo but stays compatible with upstream ExecuTorch backend/delegate concepts.
- Cadence, Samsung, and Arm remain design references, not dependencies.
- `reference_representation_rewrite` stays diagnostic only.
- `docs/project-plan*` remain untouched.
