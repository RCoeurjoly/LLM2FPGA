# Task 6 Architecture Decision

Date: 2026-06-20

## Decision Need

Task 1 selected a fully open compiler route:

```text
PyTorch -> Torch-MLIR -> CIRCT -> Verilog -> Yosys
```

Task 3 proved that TinyStories-1M can be lowered to RTL, but Task 6 evidence
shows that the naive all-fabric design is not board-fit. The copied baseline at
`artifacts/task6/baselines/tiny-stories-1m-baseline-float-selftest-all-memory-utilization`
uses about `40,416,086` LUTs and `58,072,527` FFs, or about `13535%` LUT and
`9724%` FF of the target device. The later `top34-memory` compiler shell
completed as a toolchain-frontier result, but still mapped to `56,899,009` LUTs
and `58,496,710` FFs with `0` DSP and `0` BRAM improvement.

The current M2 path has drifted into a hand-authored TinyStories-1M staged
transformer accelerator. That is useful engineering evidence, but it is not an
acceptable long-term architecture unless it becomes model-independent RTL with
model-specific behavior supplied only by generated artifacts.

Hard constraint:

- no manual custom RTL per model.

Valid architecture candidates:

1. **Automatic compiler-to-RTL**: input PyTorch model is automatically lowered
   to per-model RTL, after quantization and memory externalization.
2. **Common-kernel v2**: input PyTorch model is compiled into manifests,
   quantized weights, schedules, DDR3 layouts, configs, and oracles consumed by
   reusable FPGA kernels. The RTL is common across the supported model family.

The target model scope for this decision is decoder-only GPT/GPT-Neo-like LLMs,
not arbitrary model families.

## Current Evidence

### Representative-Core POC Target

The required fast-loop target is `tiny-stories-1m-representative-core`. It is a
synthetic GPT-Neo core derived from the TinyStories-1M config and seeded with
`torch.manual_seed(0)`.

Default minimum profile:

| key | vocab | layers | hidden | heads | positions | window |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `tiny-stories-1m-representative-core` | 32 | 2 | 2 | 1 | 4 | 2 |

Registered sweep points scale this through:

| key | vocab | layers | hidden | heads | positions | window |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `tiny-stories-1m-representative-core-v64-h4` | 64 | 2 | 4 | 1 | 8 | 4 |
| `tiny-stories-1m-representative-core-v128-h8` | 128 | 2 | 8 | 2 | 16 | 8 |
| `tiny-stories-1m-representative-core-v256-h16` | 256 | 2 | 16 | 4 | 32 | 16 |
| `tiny-stories-1m-representative-core-v512-h32` | 512 | 2 | 32 | 4 | 64 | 32 |
| `tiny-stories-1m-representative-core-v1024-h64` | 1024 | 2 | 64 | 8 | 128 | 64 |

The minimum core is mandatory for first POC smoke tests. It is not automatically
accepted as representative. The first implementation step must compare its
Torch/CF op coverage and memory shape against the full baseline and promote the
smallest sweep point that preserves relevant operators.

Initial audit result:

- `nix build .#tiny-stories-1m-representative-core-sweep-manifest --no-link --print-out-paths`
  passed and emitted the registered representative-core and reduced-vocab sweep
  manifest.
- `nix build .#tiny-stories-1m-baseline-float-vs-representative-core-op-coverage --no-link --print-out-paths -L`
  passed.
- Torch coverage was complete: `36` distinct baseline ops and `36` distinct
  representative-core ops; no missing or extra ops/dialects.
- CF coverage was complete: `32` distinct baseline ops and `32` distinct
  representative-core ops; no missing or extra ops/dialects.
- The minimum core is therefore accepted as the first architecture POC smoke
  target for operator coverage. It remains a scale and fidelity proxy, not a
  substitute for full TinyStories-1M checkpoint evidence.

### Kernelized Evidence

Bounded int8 kernel work already changed the resource signature in the desired
direction:

| artifact | scope | LUT | FF | DSP | BRAM36-eq | status |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| copied float baseline | full TinyStories all-memory shell | 40,416,086 | 58,072,527 | 0 | 0 | does not fit |
| board-validated H2 selftest | `tiny-stories-v1k-h64-l1` MLP/residual slice | 10,733 | 6,530 | 10 | 11 | fits |
| bare refreshed MLP proof | same MLP/residual kernel | 4,875 | 6,422 | 10 | 11 | sim pass |

This is not full inference evidence. It is strong evidence that quantized,
fixed-point, tiled kernels can avoid the all-fabric float shell failure mode.

Current M2.4/M2.5 evidence should be interpreted as staged boundary bring-up:
M2.4 is HIL-green for a focused attention/context slice; M2.5 is blocked at
PCIe recovery/lifecycle before the board gate. This validates the test ladder
and some arithmetic boundaries, but not the long-term architecture.

### Quantization Evidence

For the 10K output-head surface, the multi-sample result promoted int8 and
rejected lower precision for near-term RTL work:

| strategy | top1 | mean RMSE | max RMSE | promote |
| --- | ---: | ---: | ---: | --- |
| `int8_per_tensor` | 8/8 | 0.0110 | 0.0111 | yes |
| `int4_per_row` | 6/8 | 0.1075 | 0.1089 | no |
| `int3_per_row` | 6/8 | 0.2521 | 0.2560 | no |
| `ternary_per_row_t0.25_lsq` | 1/8 | 0.5174 | 0.5259 | no |

The saved `LLM Inference Limits.html` analysis argues that a compact 10K
TinyStories target can fit on-chip with int8/int4/ternary storage, but the repo
evidence says representative-core is a hardware-structure proxy with random
weights. Final fidelity claims still need full TinyStories-1M checkpoint
scoring.

## Quick Architecture Survey

This survey is bounded to architecture patterns that affect the Task 6 decision.
It uses the Task 1 survey, the Kintex-480T reclassification, the third-party
kernel survey, and the saved inference-limits analysis as inputs.

| pattern | examples | useful idea | blocker for this project |
| --- | --- | --- | --- |
| Full compiler/dataflow pipeline | Torch-MLIR/CIRCT demo, StreamTensor | Preserve PyTorch input; generate schedules, memories, kernels automatically | Current full-model lowering maps to massive LUT/FF use; StreamTensor code is not reusable; CIRCT/Handshake paths have crashes/OOM risk |
| Reusable kernel/overlay | MASE, XtraMAC, ITA-style attention kernels | Fixed RTL with model data/config; clear path to zero manual per-model RTL | Needs an explicit model artifact contract and envelope; some upstream RTL targets different devices or proprietary flows |
| HLS end-to-end systems | TeLLMe, HLSTransform, LoopLynx, Qwen2.5-on-KV260 | Good system organization and low-bit dataflow examples | Mostly Vitis/Vivado, often no public reusable code, frequently larger/HBM boards |
| External-memory streaming | FlightLLM, MEADOW, Spatial/Allo-style work, StreamTensor | Model weights live off-chip; compute is tiled and streamed | Must prove DDR3 bandwidth/latency and avoid giant handshake shells |
| Low-bit/table/ternary systems | TerEffic, MatMul-free LM, TeLLMe v2, LUT-LLM | Aggressive compression can reduce memory pressure | Current repo scoring rejects int4/int3/ternary for near-term output-head fidelity; many papers lack code |
| KV/prefill/memory-pipeline systems | FAST-Prefill, SkipOPU, disaggregated memory pipeline work | Separate prefill/decode/KV-cache bottlenecks; model bytes/token explicitly | Mostly reference-only for this board; useful for envelope metrics, not immediate implementation |

Survey takeaways:

- Most high-performing LLM-on-FPGA papers rely on proprietary HLS/Vivado,
  Alveo-class HBM boards, unpublished RTL, or multi-FPGA assumptions.
- The strongest reusable idea is not a monolithic per-model RTL blob. It is a
  compiler-managed memory/schedule layer feeding reusable quantized kernels.
- A pure compiler-to-RTL route remains aligned with Task 1, but it must beat
  the exact failure mode already observed: enormous fabric use, no DSP/BRAM
  movement, and unstable CIRCT lowering.
- Common-kernel v2 is the practical hybrid: keep PyTorch as input and keep a
  compiler pipeline, but make the compiler emit model artifacts and schedules
  instead of hand-edited model-specific RTL.

## Decision Framework

Apply hard gates first. Score only candidates that pass.

Hard gates:

- Zero manual per-model RTL.
- Fully open-source implementation path remains central.
- First POC uses `tiny-stories-1m-representative-core`.
- Claims compare against the copied baseline bundle, not a Nix store path.
- Candidate has a credible path from representative-core to full
  TinyStories-1M.
- Candidate produces durable artifacts: commands, logs, metrics, and decision
  output.

Scoring dimensions:

| dimension | what to measure |
| --- | --- |
| Scalability | LUT/FF/DSP/BRAM growth, DDR3 bytes/token, build RAM/time, fit path to full TinyStories-1M |
| Model portability | GPT/GPT-Neo-like decoder models supported by data/config changes only |
| Throughput and latency | cycles/token, token/sec estimate, DDR3 bandwidth pressure |
| Correctness and fidelity | int8 quality, fixed-point oracle pass, boundary coverage |
| Toolchain risk | Torch-MLIR/CIRCT crashes, OOM, synthesis/PnR instability, open-flow gaps |
| Maintainability | interface clarity, small debug surfaces, reusable kernels or disciplined generated RTL |

Decision rules:

- Reject automatic compiler-to-RTL as the Task 6 mainline if it cannot emit
  memory-externalized representative-core RTL without crash/OOM or giant
  embedded weight constants.
- Promote common-kernel v2 if the same RTL supports at least two
  representative-core/sweep shapes by generated artifacts/config only and the
  full TinyStories-1M envelope is plausible.
- If both pass, common-kernel v2 remains the default unless compiler-to-RTL has
  a decisive resource or throughput advantage.

## Required POCs

### POC A: Representative-Core Audit

Purpose: decide whether the default representative-core is representative enough
for architecture POCs.

Minimum commands:

```bash
nix build .#tiny-stories-1m-representative-core-sweep-manifest --no-link --print-out-paths
nix build .#tiny-stories-1m-baseline-float-vs-representative-core-op-coverage --no-link --print-out-paths -L
```

Evidence to record:

- smallest representative-core sweep point that preserves relevant Torch/CF ops;
- op/dialect coverage gaps versus baseline;
- artifact sizes and rough build/runtime cost;
- decision: keep `v32-l2-h2` for POC or promote to `v64-h4`, `v128-h8`, etc.

### POC B: Automatic Compiler-to-RTL with Int8 and Memory Externalization

Purpose: test whether the Task 1 route can survive the Task 6 minimization
requirements.

Steps:

1. Start from `tiny-stories-1m-representative-core-pt2e-static`.
2. Confirm PT2E/static quant reaches stable Torch/CF stats.
3. Apply or prototype memory externalization so weights are not emitted as
   giant RTL constants.
4. Attempt HW/SV generation and light synthesis/resource inspection.

Minimum evidence:

- pass/fail stage;
- peak RSS or best available memory proxy;
- emitted IR/SV size;
- count/size of externalized memories;
- whether DSP/BRAM appear in the mapped signature;
- whether the route remains automatic from PyTorch/model config.

### POC C: Common-Kernel v2 Envelope

Purpose: test whether the current kernelized path can become model-independent.

Steps:

1. Define the generated artifact contract:
   - model manifest;
   - quantized weight packs;
   - DDR3 row layout;
   - kernel config;
   - schedule/control stream;
   - fixed-point oracle vectors.
2. Select one existing boundary first, preferably MLP/residual or output-head,
   because there is already int8 evidence.
3. Prove the same RTL accepts at least two model shapes through generated
   artifacts/config only.
4. Estimate full TinyStories-1M bytes/token, cycles/token, and DDR3 bandwidth.

Minimum evidence:

- no RTL edit between tested model shapes;
- oracle match for the selected boundary;
- resource report for the reusable kernel wrapper;
- scaling estimate for full TinyStories-1M;
- list of unsupported decoder-only GPT features that would require kernel
  changes.

## Immediate Recommendation

Treat common-kernel v2 as the default hypothesis for Task 6. Run the automatic
compiler-to-RTL POC anyway, because it is the cleanest way to consciously
validate or reject the original Task 1 route after applying int8 quantization
and memory externalization.

Pause additional manual M2.5 model-specific RTL growth except for preserving
current evidence and fixing transport/lifecycle regressions needed by existing
gates. New RTL should be justified as reusable kernel infrastructure or as a
bounded diagnostic, not as TinyStories-only architecture.
