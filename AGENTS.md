# LLM2FPGA Purpose And Non-Negotiables

## Project Purpose
LLM2FPGA exists to lower an LLM end-to-end, starting with small models (for example TinyStories), all the way to a physical FPGA implementation.

## Non-Negotiable Deliverable Criteria
- The compilation flow must target a complete FPGA-realizable implementation.
- Generated SystemVerilog must be complete and self-contained for synthesis.
- Extern ops / blackbox dependencies are not acceptable as final outputs.
- If CIRCT lowering emits extern modules or unresolved functionality, treat that as a pipeline failure to fix, not as a successful result.

## Practical Policy For Codex Sessions
- Prefer transformations/lowerings that eliminate unsupported ops, rather than adding more extern fallbacks.
- Keep quantized and non-quantized pipelines aligned with the same end goal: full synthesizable RTL with no missing module implementations.
- When reporting progress, distinguish clearly between:
  - "SV emitted" and
  - "SV complete for synthesis without external blackboxes" (required).

## Task 3 Functional Requirement (TinyStories)
- Task 3 is to lower TinyStories to RTLIL (for Yosys) while preserving whole-model functionality.
- The produced design must be functionally meaningful for TinyStories inference (or at minimum preserve a real path to full functionality), even if full hardware validation is not yet run.
- Surrogate models that skip major TinyStories functionality are not acceptable as Task 3 completion.

## Quantization Expectation For Task 3
- Quantization is the path to remove floating-point compute by converting it to integer/fixed-point compute.
- If a "quantized" MLIR still contains floating-point logic, that quantization is insufficient for Task 3.
- In that case, continue improving/replacing quantization until the relevant lowered IR no longer depends on floating-point operations.

## TinyStories Quantization Policy (Hard Constraint)
- TinyStories must use a full quantization path only.
- Dequantization-based modes are forbidden (including Q/DQ fallback patterns that restore float compute).
- Do not keep multiple TinyStories variants where some allow float/dequant behavior.
- Do not attempt TinyStories lowering to Handshake/HW/SV/RTLIL until quantized CF is verified float-free.
- If quantized CF contains any float/math ops, fail the build and continue quantization work; do not bypass with extern or blackbox strategies.
