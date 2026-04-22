# Task 6 StreamTensor Lite Lane Results

Date opened: 2026-04-22
Branch: `task6-streamtensor-lite`

## Active Scorecard

| Check | Threshold | Status |
| --- | --- | --- |
| DSP use | `DSP > 0` in the kernel or one-block-top Yosys stat | pending |
| Weight placement | packed or ROM-style external weights, not giant RTL constants | pending |
| LUT ceiling | `<= 29,860` LUT | pending |
| FF ceiling | `<= 59,720` FF | pending |
| Verilator | kernel test passes | pending |
| Whole-model dependency | no whole-model lowering required | pending |

## Benchmark Budgets

| Stage | Budget | Last measured | Status |
| --- | --- | --- | --- |
| Python export + weight pack | `< 30 s` | n/a | pending |
| Task-graph generation | `< 10 s` | n/a | pending |
| Verilator kernel test | `< 20 s` | n/a | pending |
| Yosys stat for kernel | `< 30 s` | n/a | pending |
| Yosys stat for one-block top | `< 2 min` | n/a | pending |

## Frozen Ladder

| Rung | Artifact class | Model target | Status | Notes |
| --- | --- | --- | --- | --- |
| `L0` | synthetic kernel smoke | existing `matmul` path | ready | first synthetic kernel scaffold |
| `L1` | TinyStories-derived single linear op | existing `tiny-stories-1m-representative-core-v64-h4` | ready | first cheap boundary check |
| `L2` | single linear replay | planned `tinystories_v1k_h64_l1` | planned | first reduced-vocab micro-fit rung |
| `L3` | one MLP subpath | planned `tinystories_v4k_h64_l1` | planned | promotion only after `L2` passes |
| `L4` | one transformer-block skeleton | planned `tinystories_v10k_h64_l1` | planned | first 10k-token rung |
| `L5` | repeated-block replay | planned `tinystories_v10k_h64_l2` | planned | first repeated-block rung |
| `L6` | one-token scorer with tiled `lm_head` | planned `tinystories_v10k_h64_l8` | planned | last reduced-vocab rung before full replay |
| `L7` | full baseline replay | existing `tiny-stories-1m-baseline-float` | reserve | replay only after structural win |

## Current Decisions

| Question | Current answer | Evidence | Status |
| --- | --- | --- | --- |
| What first artifact should this lane inspect? | Representative-core artifacts, starting from `tiny-stories-1m-representative-core-v64-h4` | Shared ChatGPT plan plus lane plan | decided |
| What is the exact first insertion point? | Block-0 MLP expansion linear, `transformer.h.0.mlp.c_fc`, or the equivalent first post-norm MLP linear in exported IR | Lane feedback pass on 2026-04-22 | decided |
| What is the first target class? | One reused GEMV kernel boundary around that block-0 MLP linear | Shared ChatGPT plan plus lane plan | decided |
| What first transformation should be implemented? | Redirect one linear proof toward a small reused kernel with external weights and DSP-backed arithmetic | Shared ChatGPT plan plus lane plan | decided |
| What is the first success metric? | Move the resource signature away from `0 DSP / 0 BRAM`, with `DSP > 0` mandatory | Shared ChatGPT plan plus baseline summary | decided |
| What replay target is required before merge-back? | Real TinyStories baseline only after the constrained proof is structurally credible through the reduced-vocab ladder | Lane plan in `docs/task6-lane.md` | decided |
| What is the stop rule for the whole-model lane? | Keep it as comparison only once a reduced-vocab `h64` rung exists | Lane feedback pass on 2026-04-22 | decided |

## Planned Operational Surface

| Item | Planned location or command | Status |
| --- | --- | --- |
| Weight pack export | `scripts/task6/export_weights_pack.py` | planned |
| Task-graph build | `scripts/task6/build_task_graph.py` | planned |
| Packed-weight artifacts | `artifacts/task6/weights_pack/<model-rung>/` | planned |
| Stage-local runner | `just task6-l0` through `just task6-l7` | planned |

## Experiment Ledger

| Date | Artifact | Model rung | Insertion point | DSP | BRAM | LUT | FF | Compile time | Verdict | Next action |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-04-22 | Lane creation and plan freeze | planning | not fixed yet | n/a | n/a | n/a | n/a | n/a | open | tighten the lane around one exact GEMV proof |
| 2026-04-22 | Feedback-driven plan revision | planning | `transformer.h.0.mlp.c_fc` | n/a | n/a | n/a | n/a | n/a | decided | implement the weight-pack path and validate `L0` then `L1` |

## Rejections

None yet.
