# Open RTL Kernel Candidates For Common-Kernel v2

Date: 2026-06-20

## Purpose

Common-kernel v2 should not assume that all reusable RTL must be written
locally. This artifact records open-source RTL candidates that could provide a
whole reusable kernel or stitchable components for a model-independent
TinyStories/GPT-Neo-like inference path.

This is a decision survey, not an integration step. Do not vendor third-party
RTL or connect it to Task 6 targets until a standalone oracle, simulation,
synthesis/resource report, license check, and board-facing integration gate are
defined.

## Acceptance Filter

Count as reusable implementation candidates only when the source is:

- open source;
- RTL written in Verilog, SystemVerilog, or VHDL;
- plausibly simulatable with open tools such as Verilator, iverilog, or GHDL;
- useful as either a whole inference kernel or a component that can be stitched
  behind a stable generated-artifact contract.

HLS-only, proprietary-flow-only, unpublished, ASIC-only, HBM-only, or no-code
projects may inform architecture but do not count as reusable common-kernel RTL.

## Candidate Table

| candidate | source shape | useful scope | classification | main risk |
| --- | --- | --- | --- | --- |
| `pulp-platform/ITA` | SystemVerilog RTL plus Python test generator | int8 MHA, integer softmax, attention dataflow | `adapt` | Bender/ModelSim/PULP wrapper assumptions; must isolate open-flow-compatible slices |
| `albertomarchisio/SwiftTron` | MIT VHDL | MatMul and nonlinear Transformer blocks | `reference-only` | thin repo and VHDL-only integration surface |
| `Xtra-Computing/XtraMAC` | Apache-2.0 Verilog MAC library and generated RTL/tb bundles | int8/mixed-precision MAC datapaths | `adapt-later` | UltraScale+ DSP48E2 target; current board uses Kintex-7 DSP48E1 |
| `AttentionLego` | claimed open Verilog attention/PIM reference | attention architecture ideas | `reference-only` | source repository and license must be verified before reuse |
| `DeepWok/mase` | PyTorch FX compiler plus hardware exploration stack | compiler/artifact-contract ideas | `reference-only` | not a direct RTL component unless reusable HDL modules are identified |
| `moneyally/yua-t16` | SystemVerilog LLM/GEMM accelerator with cocotb/host stack | whole-kernel/host-contract reference | `reference-only` | Versal/Vivado target, license/source maturity unknown, not Kintex-7/open-flow proven |
| `raulprtech/Pseudo-Softmax` | GPL-3.0 Verilog | softmax component reference | `reference-only` | very small repo and GPL integration constraints |

## Stitchable Component Search Space

If no whole reusable kernel is viable, search and classify components in this
order:

1. int8 GEMV/MAC/systolic datapath;
2. attention score and value-context kernels;
3. integer softmax;
4. LayerNorm and residual add;
5. GELU or PWL nonlinear block;
6. output-head top1/topK stream kernel;
7. DDR3 rowstream/DMA/control scheduler blocks.

Any stitched design must still satisfy the Task 6 constraint: no manual custom
RTL per model. Model-specific behavior must come from generated manifests,
weights, layouts, schedules, configs, and oracle vectors.

## Near-Term Recommendation

Use ITA as the first attention/softmax RTL candidate to evaluate after the
architecture decision pass. Use XtraMAC only as a datapath reference until a
Kintex-7 DSP48E1/open-flow-compatible subset is identified. Treat SwiftTron,
Pseudo-Softmax, MASE, AttentionLego, and yua-t16 as references unless a future
bounded prototype proves a specific reusable module under local open-flow
simulation and synthesis.
