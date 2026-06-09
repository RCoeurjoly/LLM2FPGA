# LLM2FPGA Open-Source-Flow Survey (Kintex-480T-focused)

## Goal and constraints
- Inference must run on board-level Kintex-480T-class FPGA
- Fully open-source toolchain only (no dependency on proprietary synthesis/placement tool flows)
- Prefer end-to-end LLM inference feasibility on FPGA

## Survey basis
This is a constrained reclassification of papers in [1a-survey.org](/home/roland/LLM2FPGA/deliverables/1a-survey.org), reviewed through three lenses:
- Open-source source availability (code + model assets)
- Toolchain openness (usable with OSS FPGA flow)
- Likely Kintex-480T practicality (single-board, on-board resources, single/mid-size models)

| ID | Paper | Open Source Code | OSS Toolflow Feasibility | Kintex-480T Practicality | Why (high-level)
|---|---|---|---|---|---|
| 1 | TeLLMe (2504.16266) | No (artifact only) | No | Low | 1.58-bit-only FPGA design; no public design artifacts sufficient for rebuild.
| 2 | FPGA-Based Tiled MatMul on KV260 (2503.16731v3) | Yes | Low (Vitis HLS + board-specific) | Low-Medium | Open repo exists but uses commercial-flow-centric tooling and KV260-class platform assumptions.
| 3 | TerEffic (2502.16473) | No | Low | Low | Multi-accelerator/HBM design and no public repo.
| 4 | MEADOW (2503.11663) | No | Low | Low | Single-workflow implementation with Vivado + Vitis; no open RTL package in paper.
| 5 | FlightLLM (2401.03868) | No | Low | Low | Alveo/Versal-oriented and no code release.
| 6 | SECDA-LLM (2408.00462) | No | Low | Low | No repo + SECDA-specific flow.
| 7 | MatMul-free LM (2406.02528) | No | Low | Low | Promised repo absent; architecture likely heavy for tiny board target.
| 8 | LoopLynx (2504.09561) | Yes | Low | Low | Strongly tied to multi-FPGA+HLS tooling and explicit U50/U280 setup.
| 9 | MASE (2307.15517v2) | Yes | Medium-High | Medium | Open RTL + task-specific; full RTL style is the most reusable path toward OSS synthesis if model sizes stay tiny.
| 10 | On-Device Qwen2.5 (2504.17376) | No | Low | Low | No public RTL/repo.
| 11 | HLSTransform (2405.00738) | Yes | Low | Low-Medium | Open-source repo and documented flow, but explicitly uses Vitis HLS.
| 12 | Spatial acceleration (2312.15159) | Yes | Medium | Medium-Low | Open examples and HLS path; no pure-OSS flow and heavy evaluation setup.
| 13 | AccLLM (2505.03745) | No | Low | Low | Multi-FPGA + no repo.
| 14 | HLS with MLIR/CIRCT | Yes (framework-style) | Medium-High | Low | Not an LLM accelerator itself; relevant methodology for LLVM/CIRCT-based flow generation.
| 15 | StreamTensor (2509.13694) | No (private/no link) | No | Medium-Low | Strongly relevant architecture but code availability is broken/unclear.
| 16 | FAST-Prefill (2602.20515) | No | Low | Medium-Low | Strong prefill insight; no code and no OSS flow details.
| 17 | FlexLLM (2601.15710) | No | Low | Low-Medium | Good design ideas; lacks public implementation.
| 18 | SkipOPU (2603.14785) | No | Low | Low | Interesting dynamic compute scheme; no repo.
| 19 | Memory Pipeline Disaggregation (2603.29002) | No | Low | Low | System-level GPU+FPGA decomposition; repository not provided.
| 20 | LLM-Driven DSE of FPGA Accelerators (2605.05920) | No | Low | Low | Useful meta-method but not reusable without code.
| 21 | XtraMAC (2605.06052) | Yes | Medium-High | Medium | Smallest practical design style in survey for OSS reuse: RTL-only MAC focus and explicit public repo.
| 22 | SpecMamba (2509.19873) | No | Low | Low | No repo; proprietary flow likely.
| 23 | TeLLMe v2 (2510.15926) | No | Low | Low-Medium | Full prefill+decode framework but no public code.
| 24 | LUT-LLM (2511.06174) | No | Low | Low | No code; relies on dedicated V80 memory and full-system stack details.
| 25 | Efficient Kernel Mapping on CGLA (2512.00335) | No | Low | Low-Medium | Good system-level framing for small-power inference; not directly portable without repo.
| 26 | PD-Swap (2512.11550) | No | Low | Low | No repo; DPR flow adds board-specialization burden.
| 27 | FPGA Co-Design for N:M Sparse/Quantized Inference (2512.24713) | No | No (withdrawn) | Low | Withdrawn paper; cannot be used as reliable reference.

## Shortlist for immediate Kintex-480T + OSS work
1. **XtraMAC** (`2605.06052`) — best direct reusable RTL artifact.
2. **MASE** (`2406.02528`) — open RTL and architecture direction, though no vendor-independent implementation path was provided.
3. **Spatial acceleration (2312.15159)** — open examples and transformer kernels are useful for dataflow patterns.
4. **HLSTransform (2405.00738)** / **HLS with MLIR/CIRCT (14)** — useful architectural and compiler references if rebuilding with OSS tools, but not direct plug-and-play.

## Non-obvious blockers under fully OSS + Kintex-480T constraints
- Most high-performing papers are optimized for large data-center-class cards (U280/U55C/U50, HBM), and do not publish reusable RTL.
- Vitis/Vivado appears in the majority of implementation descriptions; this is incompatible with strict OSS-only flow.
- Board-scale mismatch: many designs target 1B+/multi-B model behavior that exceeds Kintex-480T practical limits without aggressive pruning/quantization and custom re-architecture.

