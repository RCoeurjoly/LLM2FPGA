# Task 6 StreamTensor Lite Lane Results

Date opened: 2026-04-22
Branch: `task6-streamtensor-lite`

## Active Scorecard

| Check | Threshold | Status |
| --- | --- | --- |
| DSP use | `DSP > 0` in the kernel or one-block-top Yosys stat | pending |
| Weight placement | packed or ROM-style external weights, not giant RTL constants | pass-L0 |
| LUT ceiling | `<= 29,860` LUT | pending pre-map |
| FF ceiling | `<= 59,720` FF | pending pre-map |
| Verilator | kernel test passes | pending |
| Micro-proof runtime | kernel Yosys stat completes in `< 30 s` | pass-L0 (`9.23 s`) |
| Whole-model dependency | no whole-model lowering required | pass-L0/L1 |

## Benchmark Budgets

| Stage | Budget | Last measured | Status |
| --- | --- | --- | --- |
| Python export + weight pack | `< 30 s` | `2.42 s` on `export_weights_pack.py` for `transformer.h.0.mlp.c_fc` | pass-L1-pack |
| Task-graph generation | `< 10 s` | `0.03 s` on `build_task_graph.py` for the selected `c_fc` site | pass-L1-graph |
| Verilator kernel test | `< 20 s` | n/a | pending |
| Yosys stat for kernel | `< 30 s` | `9.23 s` on `task6-l0-gemv64-yosys-stat` | pass-L0 |
| Yosys stat for one-block top | `< 2 min` | n/a | pending |

## Frozen Ladder

| Rung | Artifact class | Model target | Status | Notes |
| --- | --- | --- | --- | --- |
| `L0` | synthetic `64x64` GEMV smoke | `task6-l0-gemv64` external-weight kernel | running | built through `yosys-stat`; first rerun passes runtime budget |
| `L1` | TinyStories-derived single linear cutout | block-0 `mlp.c_fc` extracted from `tiny-stories-1m-representative-core-v64-h4` | running | candidate finder selected line `363`; two total candidates across the core |
| `L2` | reduced-vocab single-block replay | planned `tiny-stories-v1k-h64-l1` | planned | first reduced-vocab micro-fit rung |
| `L3` | reduced-vocab replay | planned `tiny-stories-v4k-h64-l1` | planned | promotion only after `L2` passes |
| `L4` | representative-core replay | existing `tiny-stories-1m-representative-core-v64-h4` | reserve | replay only after reduced-vocab structural win |

## Deferred Extensions

| Rung | Model target | Status | Notes |
| --- | --- | --- | --- |
| `X1` | planned `tiny-stories-v10k-h64-l1` | planned | later fidelity step, not part of the default fast loop |
| `X2` | planned `tiny-stories-v10k-h64-l2` | planned | later reuse step if `X1` is still too small |
| `X3` | existing `tiny-stories-1m-baseline-float` | reserve | final replay only after `L4` remains believable |

## Current Decisions

| Question | Current answer | Evidence | Status |
| --- | --- | --- | --- |
| What first artifact should this lane inspect? | Representative-core artifacts, starting from `tiny-stories-1m-representative-core-v64-h4` | Shared ChatGPT plan plus lane plan | decided |
| What is the exact first insertion point? | Block-0 MLP expansion linear, `transformer.h.0.mlp.c_fc` | Lane feedback pass on 2026-04-22 | decided |
| At what representation level is that boundary frozen? | `linalg` on tensors immediately after Torch-MLIR backend-to-Linalg lowering | Lane feedback pass on 2026-04-22 | decided |
| What is the first target class? | One reused GEMV kernel boundary around that block-0 MLP linear | Shared ChatGPT plan plus lane plan | decided |
| What first transformation should be implemented? | Redirect one linear proof toward a small reused kernel with external weights and DSP-backed arithmetic | Shared ChatGPT plan plus lane plan | decided |
| What is the first success metric? | Move the resource signature away from `0 DSP / 0 BRAM`, with `DSP > 0` mandatory | Shared ChatGPT plan plus baseline summary | decided |
| What replay target is required before merge-back? | Representative-core replay after the reduced-vocab ladder is structurally credible; larger `v10k` and full-baseline steps are deferred extensions | Lane plan in `docs/task6-lane.md` | decided |
| What is the stop rule for the whole-model lane? | Keep it as comparison only once a reduced-vocab `h64` rung exists | Lane feedback pass on 2026-04-22 | decided |

## Fixed First Proof Record

| Field | Value |
| --- | --- |
| Insertion point | `transformer.h.0.mlp.c_fc` |
| Representation level | `linalg` on tensors immediately after `torch_to_linalg.sh` output |
| Shape contract | `[1, hidden_size] x [hidden_size, 4 * hidden_size]` |
| Discovery rung shape | `[1, 4] x [4, 16]` on `tiny-stories-1m-representative-core-v64-h4` |
| Reduced-vocab rung shape | `[1, 64] x [64, 256]` on `tiny-stories-v*k*-h64-l*` |
| Why chosen | plain static-shape linear, repeats across blocks, avoids attention-specific control |

## Planned Operational Surface

| Item | Planned location or command | Status |
| --- | --- | --- |
| L0 kernel model | `task6-l0-gemv64` | ready |
| L1 candidate finder | `scripts/task6/find_l1_gemv_candidate.py` | ready |
| Weight pack export | `scripts/task6/export_weights_pack.py` | ready |
| Task-graph build | `scripts/task6/build_task_graph.py` | ready |
| Packed-weight artifacts | `artifacts/task6/weights_pack/<model-rung>/` | running |
| Stage-local runner | `just task6-l0` through `just task6-l7` | planned |

## Experiment Ledger

| Date | Artifact | Insertion point | Representation level | DSP | BRAM | LUT | FF | Wall-clock | Peak RAM | Verdict | Next action |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-04-22 | planning | not fixed yet | not fixed yet | n/a | n/a | n/a | n/a | n/a | n/a | open | tighten the lane around one exact GEMV proof |
| 2026-04-22 | planning | `transformer.h.0.mlp.c_fc` | `linalg` on tensors | n/a | n/a | n/a | n/a | n/a | n/a | decided | implement the weight-pack path and validate `L0` then `L1` |
| 2026-04-22 | planning | `transformer.h.0.mlp.c_fc` | `linalg` on tensors | n/a | n/a | n/a | n/a | n/a | n/a | decided | keep the primary fast loop at `L0` to `L4`, defer `v10k` and full-baseline replay |
| 2026-04-22 | `task6-l0-gemv64-yosys-stat` first attempt | synthetic external-weight `64x64` GEMV | full pipeline to `sv` | n/a | n/a | n/a | n/a | `14.75 s` | `560,856 KB` | fixed blocker | reuse TinyStories float-extern wiring after `sv` export failed on `arith_addf` / `arith_mulf` externs |
| 2026-04-22 | `task6-l0-gemv64-yosys-stat` rerun | synthetic external-weight `64x64` GEMV | `linalg -> yosys-stat` | pending pre-map | pending pre-map | pending pre-map | pending pre-map | `9.23 s` | `560,684 KB` | pass-runtime | inspect mapped resource signature and add Verilator kernel coverage |
| 2026-04-22 | `representative-core-v64-h4-c_fc-candidate.json` | `transformer.h.0.mlp.c_fc` candidate | `linalg` | n/a | n/a | n/a | n/a | `0.05 s` | `13,024 KB` | selected | use line `363` / `%75` as the first L1 cutout and begin weight-pack extraction around the first `4 -> 16` site |
| 2026-04-22 | `export_weights_pack.py` for `transformer.h.0.mlp.c_fc` | `transformer.h.0.mlp.c_fc` | `pytorch-state-dict` | n/a | n/a | n/a | n/a | `2.42 s` | `336,816 KB` | pass-pack | use `weight.bin` / `bias.bin` plus `manifest.json` as the first external pack backing the selected L1 site |
| 2026-04-22 | `representative-core-v64-h4-c_fc-task-graph.json` | `transformer.h.0.mlp.c_fc` | `linalg` | n/a | n/a | n/a | n/a | `0.03 s` | `13,456 KB` | pass-graph | use the minimal graph as the first consumer contract for the packed `c_fc` tensors and decide whether the next slice is graph refinement or an L0 sim harness |

## Rejections

- None yet.
- Resolved blocker:
  - the first `task6-l0-gemv64` `sv` export failed until the model reused the
    baseline float extern wiring (`allowHwExterns`, per-file extern import, and
    `fpPrimsSv`)
