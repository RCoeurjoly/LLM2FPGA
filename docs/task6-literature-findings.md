# Task 6 Literature Findings

Prepared in the `task6-paper-review` lane on 2026-04-17.

This note is intentionally narrow: StreamTensor first, then a short list of
recent FPGA LLM papers that look relevant to Task 6 resource reduction. Paper
claims below are taken from the primary papers and are not yet validated in
this repo.

## Baseline anchor for this lane

Reference bundle:

- [`../artifacts/task6/baselines/tiny-stories-1m-baseline-float-selftest-all-memory-utilization`](../artifacts/task6/baselines/tiny-stories-1m-baseline-float-selftest-all-memory-utilization)

Current fit failure from
[`summary.txt`](../artifacts/task6/baselines/tiny-stories-1m-baseline-float-selftest-all-memory-utilization/summary.txt)
and
[`stat.json`](../artifacts/task6/baselines/tiny-stories-1m-baseline-float-selftest-all-memory-utilization/stat.json):

- LUTs: 40,416,086 / 298,600 (13,535.19%)
- FFs: 58,072,527 / 597,200 (9,724.13%)
- BRAM36: 0 / 955
- DSP: 0 / 1920
- dominant cell type: 58,071,781 `FDRE`

Implication for paper triage:

- the immediate bottleneck here is LUT/FF explosion, not exhausted DSPs or
  BRAM
- ideas that only raise throughput, or that mainly spend more LUT-based memory,
  are lower value here
- ideas that shrink intermediate storage, compress weights, or shift compute
  and storage into BRAM/DSP are the most promising

## StreamTensor first

### StreamTensor: Make Tensors Stream in Dataflow Accelerators for LLMs

- Citation: Hanchen Ye and Deming Chen, "StreamTensor: Make Tensors Stream in
  Dataflow Accelerators for LLMs," MICRO 2025.
- Link: https://arxiv.org/abs/2509.13694
- Venue DOI: https://doi.org/10.1145/3725843.3762817
- Year: 2025
- Exact dates: arXiv v1 submitted 2025-09-17; accepted to MICRO 2025
  (2025-10-18 to 2025-10-22).
- Optimization idea: automatic stream-based kernel fusion, layout conversion,
  tiling/resource exploration, and LP-based FIFO sizing so intermediate tensors
  stay on-chip as streams instead of being materialized through external or
  large local buffers.
- Claimed resource or efficiency gain: on-chip intermediate-memory usage drops
  to 14.8%-16.8% of the unfused design; StreamTensor also reports 0.76x lower
  total latency than Allo on GPT-2 and up to 1.99x higher energy efficiency
  than A100 on Qwen.
- Claimed metric type: on-chip memory reduction, plus latency/energy.
- Why this matters against the local baseline: this is the strongest direct hit
  on the current symptom. Our baseline blows up LUT/FF usage while using zero
  BRAM and zero DSP, which is consistent with over-materialized intermediates
  and fabricized storage.
- Transplantability here: `direct`
- Repo-local follow-up candidate: use the imported Task 6 measurement helpers
  to identify the largest generated intermediate arrays in the baseline flow,
  then prototype one fusion/streaming rewrite around a single transformer block
  so adjacent linear, elementwise, and normalization steps communicate through
  BRAM-backed FIFOs or small ping-pong buffers instead of full-width register
  storage.

## Focused newer paper shortlist

### FlightLLM: Efficient Large Language Model Inference with a Complete Mapping Flow on FPGAs

- Citation: Shulin Zeng et al., "FlightLLM: Efficient Large Language Model
  Inference with a Complete Mapping Flow on FPGAs," FPGA 2024.
- Link: https://arxiv.org/abs/2401.03868
- Venue DOI: https://doi.org/10.1145/3626202.3637562
- Year: 2024
- Exact dates: arXiv v1 submitted 2024-01-08; FPGA 2024 ran 2024-03-03 to
  2024-03-05.
- Optimization idea: configurable sparse DSP chain, always-on-chip decode, and
  length-adaptive compilation. The key hardware idea is to keep decode-stage
  activations in on-chip buffers and fuse nearby non-matmul work so the decode
  path stops round-tripping small vectors through off-chip memory.
- Claimed resource or efficiency gain: compute efficiency improves 1.6x with
  block-wise/N:M sparsity; decode-stage off-chip bandwidth utilization rises
  from 35.6% to 65.9%; instruction-storage overhead drops by 500 GB; end-to-end
  energy efficiency is 6.0x higher than V100S.
- Claimed metric type: mixed throughput/bandwidth/compilation efficiency, not a
  direct whole-design LUT/FF reduction claim.
- Why this matters against the local baseline: the on-chip decode idea is
  relevant because this branch currently uses no BRAM at all. The sparse DSP
  chain is also directionally attractive because the board has 1920 idle DSPs.
  However, FlightLLM does not prove that these changes alone solve a design that
  is already 135x over LUT capacity.
- Transplantability here: `adaptable`
- Repo-local follow-up candidate: after the baseline path is measurable, try a
  narrow "always-on-chip" rewrite for per-token activations or residual vectors
  using BRAM-backed buffers; keep the sparse DSP-chain idea in reserve until a
  quantized or sparse kernel path is available.

### AccLLM: Accelerating Long-Context LLM Inference Via Algorithm-Hardware Co-Design

- Citation: Yanbiao Liang et al., "AccLLM: Accelerating Long-Context LLM
  Inference Via Algorithm-Hardware Co-Design," arXiv preprint.
- Link: https://arxiv.org/abs/2505.03745
- Year: 2025
- Exact dates: arXiv v1 submitted 2025-04-07.
- Optimization idea: combine pruning, Lambda-shaped attention, and W2A8KV4
  quantization (2-bit weights, 8-bit activations, 4-bit KV cache) with a
  reconfigurable FPGA engine that supports dense/sparse kernels and mixed
  bit-widths.
- Claimed resource or efficiency gain: the paper frames the algorithm as
  reducing model memory and bandwidth demand, and reports 4.07x energy
  efficiency plus 2.98x throughput relative to FlightLLM on U280.
- Claimed metric type: mixed compression and throughput/energy; the abstract
  does not give a direct LUT/FF delta.
- Why this matters against the local baseline: the long-context and KV-cache
  pieces are not the main issue for TinyStories 1M, but the aggressive low-bit
  weight path is relevant. If the baseline remains far over LUT/FF capacity
  after 8-bit routes, the next meaningful lever is more aggressive weight
  compression or pruning rather than more scheduling alone.
- Transplantability here: `adaptable`
- Repo-local follow-up candidate: use the already imported quantized TinyStories
  routes first, then consider a second-stage experiment that combines structured
  pruning with sub-8-bit weights only if int8-class routes still miss fit by a
  large margin.

### TerEffic: Highly Efficient Ternary LLM Inference on FPGA

- Citation: Chenyang Yin et al., "TerEffic: Highly Efficient Ternary LLM
  Inference on FPGA," arXiv preprint.
- Link: https://arxiv.org/abs/2502.16473
- Year: 2025
- Exact dates: arXiv v1 submitted 2025-02-23; revised 2025-05-01.
- Optimization idea: ternary quantization with 1.6-bit packed weights, a
  custom ternary matmul unit, and explicit compute-memory alignment so weights
  live in dedicated on-chip memories while intermediates use separate buffers.
- Claimed resource or efficiency gain: 1.6-bit packing gives a 20% memory
  reduction versus ordinary 2-bit storage and stores/transfers 25% more data;
  the custom ternary matmul unit reduces LUT usage by 40%; the fully on-chip
  design reaches 12,700 tokens/s on a 370M model.
- Claimed metric type: direct storage and LUT reduction, plus throughput.
- Why this matters against the local baseline: this is one of the few recent
  papers with an explicit LUT-reduction claim. The local design is dominated by
  LUT/FF usage and uses no DSPs, so packing weights harder than int8 is a real
  lever if the model can tolerate it.
- Limits for this repo: the paper leans on U280-era URAM-heavy memory planning,
  while the local XC7K480T target does not have URAM. That blocks direct
  adoption of the full memory architecture.
- Transplantability here: `adaptable`
- Repo-local follow-up candidate: prototype packed low-bit weight storage for a
  single TinyStories layer with BRAM-friendly packing, then compare Yosys
  LUT/FF/BRAM deltas against the copied float baseline before attempting a full
  ternary path.

### Hummingbird: A Smaller and Faster Large Language Model Accelerator on Embedded FPGA

- Citation: Jindong Li et al., "Hummingbird: A Smaller and Faster Large
  Language Model Accelerator on Embedded FPGA," ICCAD 2025.
- Link: https://arxiv.org/abs/2507.03308
- Year: 2025
- Exact dates: arXiv v1 submitted 2025-07-04; revised 2025-10-17; accepted to
  ICCAD 2025.
- Optimization idea: a DSP-optimized hybrid GEMV engine, embedding offload, and
  a GQA-specific dataflow that reduces cache buffering pressure. The most useful
  idea for this repo is the compute engine, which deliberately trades LUT/FF
  pressure for DSP use by pushing more of the datapath into DSP primitives.
- Claimed resource or efficiency gain: compared with prior embedded-FPGA work,
  Hummingbird reports 67% LUT, 39% DSP, and 42% power savings. Inside its
  compute-engine table, the optimized Hybrid+ version drops from 6570 LUT /
  11856 FF / 160 DSP to 1962 LUT / 4355 FF / 148 DSP while adding activation
  reuse and AXPY support.
- Claimed metric type: direct resource reduction plus throughput.
- Why this matters against the local baseline: the board currently has 1920
  unused DSPs while LUTs and FFs are blown out. A compute path that explicitly
  shifts work from fabric into DSPs is therefore attractive.
- Limits for this repo: the paper uses UltraScale+ DSP48E2-specific primitive
  tricks, while XC7K480T uses DSP48E1. The embedding-offload and GQA sections
  are also less relevant to TinyStories 1M than the compute-engine section.
- Transplantability here: `adaptable`
- Repo-local follow-up candidate: identify the dominant matvec/matmul kernel in
  the generated RTL and prototype a DSP-first lowering for that kernel only,
  with a cell-mix comparison against the current all-fabric baseline.

### LUT-LLM: Efficient Large Language Model Inference with Memory-based Computations on FPGAs

- Citation: Zifan He et al., "LUT-LLM: Efficient Large Language Model
  Inference with Memory-based Computations on FPGAs," FCCM 2026.
- Link: https://arxiv.org/abs/2511.06174
- Year: 2026
- Exact dates: arXiv v1 submitted 2025-11-09; revised 2026-03-22; marked FCCM
  2026 on arXiv.
- Optimization idea: replace part of arithmetic execution with vector-quantized,
  table-lookup-based inference so the design spends more effort on memory-based
  computation and less on arithmetic datapaths.
- Claimed resource or efficiency gain: arithmetic operations are reduced 4x;
  generation speed is 1.10x-3.29x faster than GPUs; energy efficiency is
  3.05x-6.60x higher than GPUs.
- Claimed metric type: arithmetic reduction plus throughput/energy.
- Why this matters against the local baseline: the paper is interesting as a
  research direction, but it does not map cleanly onto the current failure mode.
  The local design already overuses LUT/FF fabric while leaving BRAM and DSPs
  untouched, and LUT-LLM leans into memory-based lookup structures plus a
  model-conversion recipe that is far outside the current validated flow.
- Transplantability here: `not useful`
- Repo-local follow-up candidate: none for the immediate Task 6 path. Revisit
  only if the project explicitly opens a separate model-retraining and
  lookup-compute track.

## Prioritized follow-up ideas

1. Stream intermediate tensors and legalize them into BRAM-backed FIFOs or
   small ping-pong buffers.
   This is the most direct response to the copied baseline, which currently
   consumes 40.4M LUT and 58.1M FF while using zero BRAM and zero DSP. The key
   StreamTensor result is the 14.8%-16.8% residual intermediate-memory footprint
   after fusion.

2. Run the existing Task 6 quantized TinyStories routes and compare them against
   the copied float baseline before inventing new kernels.
   The repo already contains `tiny-stories-1m-dynamic-int8` and
   `tiny-stories-1m-torchao`. AccLLM and TerEffic both suggest that stronger
   compression, not just scheduling, will probably be required if the fit gap
   remains large.

3. Shift the dominant compute kernel toward DSP-backed implementations.
   Hummingbird and FlightLLM both reinforce the same point: if the design keeps
   burning LUT/FF for arithmetic while 1920 DSPs sit idle, the resource mix is
   wrong for this board.

4. Explore packed sub-8-bit or ternary weight storage only after item 2 is
   measured.
   TerEffic is promising because it offers explicit memory and LUT savings, but
   it is a bigger algorithm/hardware step and its URAM-centric memory plan does
   not transfer directly to XC7K480T.

5. Do not prioritize LUT-LLM-style lookup compute for the current branch.
   It is a plausible separate research path, but it does not obviously reduce
   the limiting resource in this baseline and would broaden the lane beyond the
   requested scope.
