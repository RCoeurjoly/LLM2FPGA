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
