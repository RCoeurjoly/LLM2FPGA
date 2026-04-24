# Task 6 StreamTensor Lite Lane Results

Date opened: 2026-04-22
Branch: `task6-streamtensor-lite`

## Active Scorecard

| Check | Threshold | Status |
| --- | --- | --- |
| DSP use | `DSP > 0` in the kernel or one-block-top Yosys stat | pass-L0/L1/L2 (`4 DSP48E1`) |
| Weight placement | packed or ROM-style external weights, not giant RTL constants | pass-L0/L1-pack/L1-kernel/L2-pack/L2-kernel/L2-tiled |
| LUT ceiling | `<= 29,860` LUT | pass-L1 fail-L0/L2 (`32,449` LUT / `29,778` LUT best validated `L1` / `31,611` LUT best validated `L1 c_proj` / `31,907` LUT best validated tiled `L2` / `50,235` LUT base `L2` / `51,622` LUT aligned replay / `51,832` LUT downstream out-buffer probe); diagnostic `ui64` buffer-lite reaches `20,725` LUT but fails Verilator |
| FF ceiling | `<= 59,720` FF | pass-L0/L1/L2 (`46,736` FF / `46,352` FF / `50,864` FF best validated `L1 c_proj` / `45,932` FF best validated tiled `L2` / `65,523` FF base `L2` / `64,873` FF aligned replay / `64,743` FF downstream out-buffer probe) |
| Verilator | kernel test passes | pass-L0/L1-kernel/L1-cproj/L2-kernel/L2-tiled |
| Micro-proof runtime | kernel Yosys stat completes in `< 30 s` | pass-L0/L1/L1-cproj/L2 (`9.23 s` / `4.07 s` / `17.52 s` / `9.13 s` base `L2` / `16.09 s` tiled `L2`) |
| Whole-model dependency | no whole-model lowering required | pass-L0/L1/L2 |

## Benchmark Budgets

| Stage | Budget | Last measured | Status |
| --- | --- | --- | --- |
| Python export + weight pack | `< 30 s` | `2.38 s` on `export_weights_pack.py` for `tiny-stories-v1k-h64-l1` `transformer.h.0.mlp.c_fc` | pass-L2-pack |
| L1/L2 contract capture | `< 30 s` | `2.40 s` on `export_l1_contract.py` for `tiny-stories-v1k-h64-l1` | pass-L2-contract |
| L1/L2 pack replay check | `< 10 s` | `0.92 s` on `verify_l1_contract.py` for `tiny-stories-v1k-h64-l1` | pass-L2-check |
| Task-graph generation | `< 10 s` | `0.03 s` on `build_task_graph.py` with the `tiny-stories-v1k-h64-l1` contract attached | pass-L2-graph |
| Verilator kernel test | `< 20 s` | `0.55 s` on direct `task6-l0-gemv64-sim-main` execution | pass-L0 |
| Yosys stat for kernel | `< 30 s` | `9.23 s` on `task6-l0-gemv64-yosys-stat` | pass-L0 |
| Yosys stat for one-block top | `< 2 min` | `99.26 s` on `tiny-stories-v1k-h64-l1-selftest-top4-memory-yosys-json` | pass-L2-top-gate |

## Frozen Ladder

| Rung | Artifact class | Model target | Status | Notes |
| --- | --- | --- | --- | --- |
| `L0` | synthetic `64x64` GEMV smoke | `task6-l0-gemv64` external-weight kernel | running | `yosys-stat`, Verilator, and mapped utilization now pass the DSP/FF proof, but direct `abc9` slightly worsened LUT (`32,478`), so the kernel still misses the ceiling |
| `L1` | TinyStories-derived single linear cutout | block-0 `mlp.c_fc` extracted from `tiny-stories-1m-representative-core-v64-h4` | running | kernel-only redirected proof now passes weight placement, Verilator, `yosys-stat`, and mapped DSP; the current reference is `task6-l1-c-fc-redirect-index-ring3-postbranch-outbuf-fifo2-abc9` at `29,778` LUT / `46,352` FF after the downstream post-branch `ui64` buffer clusters (`264..271` then `279..280`) proved to be the first non-selector lever that clears the `L1` LUT ceiling. The reserve `mlp.c_proj` fallback is now structurally live too, but its untouched redirected kernel only reaches `32,393` LUT / `50,864` FF (`31,611` LUT under direct `abc9`), so it remains reserve-only rather than replacing the frozen `c_fc` reference |
| `L2` | reduced-vocab single-block replay | `tiny-stories-v1k-h64-l1` | running | kernel-only redirected proof now passes weight placement, Verilator, `yosys-stat`, and mapped DSP; the repo one-block-top Yosys gate also completes in `99.26 s`, the old local `L2 c_fc` micro-surgery branch is closed after misses at `51,622` and `51,832` LUT, the tiled seam split shows the wrapper adds only about `18` LUT beyond the reusable `64 -> 64` tile, and one bounded tile-kernel post-branch/output probe improves the tiled wrapper to `31,907` LUT / `45,932` FF / `4 DSP` / `0 BRAM`. This is the new `L2` reference, but it still misses the LUT ceiling by `2,047`, so `L3` remains blocked |
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
| What is the current mainline execution order? | Freeze StreamTensor-lite references as the comparison harness; treat the first baseline `top4-memory` rerun after the upstream CIRCT switch as blocked on LLVM/MLIR/CIRCT bootstrap rather than as new shell evidence; keep the LSQ A/B recorded as spent negative; keep the broader PT2E-static full-model route as reference-only because the direct extracted-op parity slice is a no-op; require a new quant/storage hypothesis before any new kernel design or heavier replay | Deep research audits plus the 2026-04-24 LSQ/PT2E-static passes and the 2026-04-24 upstream-toolchain reentry run | decided |
| Which quantized route stays active under the amended plan? | Only `tiny-stories-1m` PT2E-static stays alive, and only as a full-model reference surface; the direct external-weight `L1` extracted-op parity slice is rejected because it collapses to the same float `aten.matmul` export | Existing Task 6 quant notes plus the 2026-04-24 bounded replay and extracted-op parity pass | decided |
| What did the bounded alternate-lowering pass show? | The LSQ same-contract `L1 c_fc` A/B can beat the frozen float reference on mapped LUT (`29,329` vs `29,778`) while keeping `4 DSP / 0 BRAM`, but it times out under the same redirected Verilator contract, so the one-pass alternate-lowering slice is closed as not drop-in-safe | 2026-04-24 LSQ `L1` alternate-lowering proof | decided |
| What did the PT2E-static extracted-op parity pass show? | On the direct external-weight `L1 c_fc` GEMV, PT2E-static is a no-op: the prepared graph, converted graph, and re-exported `torch` MLIR all remain plain float `aten.matmul`, and the final `torch` export is byte-identical to the frozen float reference | 2026-04-24 PT2E-static extracted-op parity proof | decided |

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
| L0 Verilator harness | `task6-l0-gemv64-sim-main` / `task6-l0-gemv64-sv-sim` | ready |
| L0 mapped utilization | `task6-l0-gemv64-json` / `task6-l0-gemv64-utilization` | ready |
| L0 `abc9` mapped utilization | `task6-l0-gemv64-abc9-json` / `task6-l0-gemv64-abc9-utilization` | ready |
| L0 int16 mapped variant | `task6-l0-gemv64-int16-json` / `task6-l0-gemv64-int16-utilization` | ready |
| L1 candidate finder | `scripts/task6/find_l1_gemv_candidate.py` | ready |
| L1 `abc9` mapped utilization | `task6-l1-c-fc-redirect-abc9-json` / `task6-l1-c-fc-redirect-abc9-utilization` | ready |
| L1 `ui64` buffer-lite probe | `task6-l1-c-fc-redirect-ui64-buffer-lite-json` / `task6-l1-c-fc-redirect-ui64-buffer-lite-utilization` / `task6-l1-c-fc-redirect-ui64-buffer-lite-sv-sim` | experimental |
| L1 class-wide `ui64` FIFO2 probe | `task6-l1-c-fc-redirect-ui64-buffer-fifo2-json` / `task6-l1-c-fc-redirect-ui64-buffer-fifo2-utilization` / `task6-l1-c-fc-redirect-ui64-buffer-fifo2-sv-sim` | rejected |
| L1 selective `buffer165` FIFO2 probe | `task6-l1-c-fc-redirect-buffer165-fifo2-json` / `task6-l1-c-fc-redirect-buffer165-fifo2-utilization` / `task6-l1-c-fc-redirect-buffer165-fifo2-sv-sim` | experimental |
| L1 selective index-spine FIFO2 probe | `task6-l1-c-fc-redirect-index-spine-fifo2-json` / `task6-l1-c-fc-redirect-index-spine-fifo2-utilization` / `task6-l1-c-fc-redirect-index-spine-fifo2-sv-sim` | experimental |
| L1 selective index-spine FIFO2 `abc9` probe | `task6-l1-c-fc-redirect-index-spine-fifo2-abc9-json` / `task6-l1-c-fc-redirect-index-spine-fifo2-abc9-utilization` | experimental |
| L1 selective index-fanout FIFO2 `abc9` probe | `task6-l1-c-fc-redirect-index-fanout-fifo2-abc9-json` / `task6-l1-c-fc-redirect-index-fanout-fifo2-abc9-utilization` / `task6-l1-c-fc-redirect-index-fanout-fifo2-sv-sim` | experimental |
| L1 selective index ring-2 FIFO2 `abc9` probe | `task6-l1-c-fc-redirect-index-ring2-fifo2-abc9-json` / `task6-l1-c-fc-redirect-index-ring2-fifo2-abc9-utilization` / `task6-l1-c-fc-redirect-index-ring2-fifo2-sv-sim` | experimental |
| L1 selective index ring-3 FIFO2 `abc9` probe | `task6-l1-c-fc-redirect-index-ring3-fifo2-abc9-json` / `task6-l1-c-fc-redirect-index-ring3-fifo2-abc9-utilization` / `task6-l1-c-fc-redirect-index-ring3-fifo2-sv-sim` | experimental |
| L1 selective index ring-3 control/merge FIFO2 `abc9` probe | `task6-l1-c-fc-redirect-index-ring3-ctrlmerge-fifo2-json` / `task6-l1-c-fc-redirect-index-ring3-ctrlmerge-fifo2-abc9-utilization` / `task6-l1-c-fc-redirect-index-ring3-ctrlmerge-fifo2-sv-sim` | experimental |
| L1 selective index ring-3 `ui1` selector buffer FIFO2 `abc9` probe | `task6-l1-c-fc-redirect-index-ring3-ui1buf263-fifo2-abc9-json` / `task6-l1-c-fc-redirect-index-ring3-ui1buf263-fifo2-abc9-utilization` / `task6-l1-c-fc-redirect-index-ring3-ui1buf263-fifo2-sv-sim` | experimental |
| L1 selective index ring-3 `fork49` statevec `abc9` probe | `task6-l1-c-fc-redirect-index-ring3-fork49-statevec-abc9-json` / `task6-l1-c-fc-redirect-index-ring3-fork49-statevec-abc9-utilization` / `task6-l1-c-fc-redirect-index-ring3-fork49-statevec-sv-sim` | experimental |
| L1 selective index ring-3 selector cluster FIFO2 `abc9` probe | `task6-l1-c-fc-redirect-index-ring3-selectcluster-fifo2-abc9-json` / `task6-l1-c-fc-redirect-index-ring3-selectcluster-fifo2-abc9-utilization` / `task6-l1-c-fc-redirect-index-ring3-selectcluster-fifo2-sv-sim` | experimental |
| L1 selective index ring-3 post-branch FIFO2 `abc9` probe | `task6-l1-c-fc-redirect-index-ring3-postbranch-fifo2-abc9-json` / `task6-l1-c-fc-redirect-index-ring3-postbranch-fifo2-abc9-utilization` / `task6-l1-c-fc-redirect-index-ring3-postbranch-fifo2-sv-sim` | experimental |
| L1 selective index ring-3 post-branch out-buffer FIFO2 `abc9` probe | `task6-l1-c-fc-redirect-index-ring3-postbranch-outbuf-fifo2-abc9-json` / `task6-l1-c-fc-redirect-index-ring3-postbranch-outbuf-fifo2-abc9-utilization` / `task6-l1-c-fc-redirect-index-ring3-postbranch-outbuf-fifo2-sv-sim` | experimental |
| L1 frozen reference `yosys-stat` | `task6-l1-c-fc-redirect-index-ring3-postbranch-outbuf-fifo2-yosys-stat` | ready |
| L2 aligned post-branch FIFO2 `abc9` replay | `task6-l2-c-fc-redirect-postbranch-fifo2-abc9-json` / `task6-l2-c-fc-redirect-postbranch-fifo2-abc9-utilization` / `task6-l2-c-fc-redirect-postbranch-fifo2-sv-sim` | experimental |
| L2 downstream out-buffer FIFO2 `abc9` probe | `task6-l2-c-fc-redirect-downstream-outbuf-fifo2-abc9-json` / `task6-l2-c-fc-redirect-downstream-outbuf-fifo2-abc9-utilization` / `task6-l2-c-fc-redirect-downstream-outbuf-fifo2-sv-sim` | experimental |
| L2 tiled `64x64` kernel Yosys stat | `task6-l2-c-fc-redirect-tile64-yosys-stat` | experimental |
| L2 tiled `4x64` wrapper proof surfaces | `task6-l2-c-fc-redirect-tile4x64-sim-main` / `task6-l2-c-fc-redirect-tile4x64-sv-sim` / `task6-l2-c-fc-redirect-tile4x64-abc9-json` / `task6-l2-c-fc-redirect-tile4x64-abc9-utilization` | experimental |
| L2 tiled `64x64` kernel post-branch out-buffer FIFO2 `abc9` probe | `task6-l2-c-fc-redirect-tile64-postbranch-outbuf-fifo2-abc9-json` / `task6-l2-c-fc-redirect-tile64-postbranch-outbuf-fifo2-abc9-utilization` | experimental |
| L2 active tiled reference `yosys-stat` | `task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2-yosys-stat` | ready |
| L2 tiled `64x64` kernel store-path fork/control seam probe | `task6-l2-c-fc-redirect-tile64-storepath-forkctrl-sim-main` / `task6-l2-c-fc-redirect-tile64-storepath-forkctrl-sv-sim` / `task6-l2-c-fc-redirect-tile64-storepath-forkctrl-abc9-json` / `task6-l2-c-fc-redirect-tile64-storepath-forkctrl-abc9-utilization` | experimental |
| L2 tiled `64x64` kernel store-path fork-only seam probe | `task6-l2-c-fc-redirect-tile64-storepath-forks-sim-main` / `task6-l2-c-fc-redirect-tile64-storepath-forks-sv-sim` / `task6-l2-c-fc-redirect-tile64-storepath-forks-abc9-json` / `task6-l2-c-fc-redirect-tile64-storepath-forks-abc9-utilization` | experimental |
| L2 tiled `4x64` wrapper post-branch out-buffer FIFO2 `abc9` probe | `task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2-sim-main` / `task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2-sv-sim` / `task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2-abc9-json` / `task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2-abc9-utilization` | experimental |
| Task 6 `ui64` FIFO2 probe plumbing | `nix/task6-ui64-fifo2-site-map.nix` / `mkTask6Ui64Fifo2SitePatchSv` / `mkTask6Ui64Fifo2WholeClassSv` | ready |
| `c_proj` fallback boundary artifacts | `artifacts/task6/streamtensor-lite/l1/representative-core-v64-h4-c_proj-*` / `artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_proj-*` | ready |
| L1 `c_proj` redirected kernel | `task6-l1-c-proj-redirect` | experimental |
| L1 `c_proj` redirected kernel proof surfaces | `task6-l1-c-proj-redirect-tb-data-sv` / `task6-l1-c-proj-redirect-sim-main` / `task6-l1-c-proj-redirect-json` / `task6-l1-c-proj-redirect-utilization` / `task6-l1-c-proj-redirect-sv-sim` | experimental |
| L1 `c_proj` redirected kernel `abc9` mapped utilization | `task6-l1-c-proj-redirect-abc9-json` / `task6-l1-c-proj-redirect-abc9-utilization` | experimental |
| L1 staged `abc9` mapped utilization | `task6-l1-c-fc-redirect-staged-abc9-json` / `task6-l1-c-fc-redirect-staged-abc9-utilization` | experimental |
| L2 one-block-top Yosys gate | `tiny-stories-v1k-h64-l1-selftest-top4-memory-yosys-json` | ready |
| Weight pack export | `scripts/task6/export_weights_pack.py` | ready |
| L1/L2 contract export | `scripts/task6/export_l1_contract.py` | ready |
| L1/L2 pack replay check | `scripts/task6/verify_l1_contract.py` | ready |
| Task-graph build | `scripts/task6/build_task_graph.py` | ready |
| Packed-weight artifacts | `artifacts/task6/weights_pack/<model-rung>/` | running |
| Contract artifacts | `artifacts/task6/streamtensor-lite/<rung>/<contract-dir>/` | running |
| Stage-local runner | `just task6-l0` / `task6-l1` / `task6-l2` via `scripts/task6/run_stage_local.py` with blocked-rung summaries still available on demand | frozen status surface |

## Experiment Ledger

| Date | Artifact | Insertion point | Representation level | DSP | BRAM | LUT | FF | Wall-clock | Peak RAM | Verdict | Next action |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-04-22 | planning | not fixed yet | not fixed yet | n/a | n/a | n/a | n/a | n/a | n/a | open | tighten the lane around one exact GEMV proof |
| 2026-04-22 | planning | `transformer.h.0.mlp.c_fc` | `linalg` on tensors | n/a | n/a | n/a | n/a | n/a | n/a | decided | implement the weight-pack path and validate `L0` then `L1` |
| 2026-04-22 | planning | `transformer.h.0.mlp.c_fc` | `linalg` on tensors | n/a | n/a | n/a | n/a | n/a | n/a | decided | keep the primary fast loop at `L0` to `L4`, defer `v10k` and full-baseline replay |
| 2026-04-22 | `task6-l0-gemv64-yosys-stat` first attempt | synthetic external-weight `64x64` GEMV | full pipeline to `sv` | n/a | n/a | n/a | n/a | `14.75 s` | `560,856 KB` | fixed blocker | reuse TinyStories float-extern wiring after `sv` export failed on `arith_addf` / `arith_mulf` externs |
| 2026-04-22 | `task6-l0-gemv64-yosys-stat` rerun | synthetic external-weight `64x64` GEMV | `linalg -> yosys-stat` | pending pre-map | pending pre-map | pending pre-map | pending pre-map | `9.23 s` | `560,684 KB` | pass-runtime | inspect mapped resource signature and add Verilator kernel coverage |
| 2026-04-22 | `task6-l0-gemv64-sim-main` | synthetic external-weight `64x64` GEMV | `sv -> Verilator` | pending pre-map | pending pre-map | pending pre-map | pending pre-map | `0.55 s` | `4,852 KB` | pass-sim | inspect mapped resource signature and confirm whether the kernel maps any DSPs |
| 2026-04-22 | `task6-l0-gemv64-utilization` | synthetic external-weight `64x64` GEMV | `sv -> synth_xilinx -> mapped JSON` | `4` | `0` | `32,449` | `46,736` | `57.95 s` | `851,592 KB` | pass-dsp fail-lut | reduce LUT footprint before treating `L0` as a fully scorecard-cleared micro-proof |
| 2026-04-22 | `task6-l0-gemv64-int16-utilization` | synthetic external-weight `64x64` GEMV | `sv -> synth_xilinx -> mapped JSON` | `1` | `0` | `35,737` | `59,276` | `54.57 s` | `873,180 KB` | reject-alt | stop spending slices on datatype-only int16 substitution because it weakens the DSP signal and worsens LUT pressure |
| 2026-04-22 | local `task6-l0-gemv64-int8` probe | synthetic external-weight `64x64` GEMV | `torch -> linalg` | n/a | n/a | n/a | n/a | n/a | n/a | blocked-tooling | do not promote an int8 `L0` package until torch-mlir fixes the byte/char lowering crash on `torch.aten.mm` |
| 2026-04-22 | `representative-core-v64-h4-c_fc-candidate.json` | `transformer.h.0.mlp.c_fc` candidate | `linalg` | n/a | n/a | n/a | n/a | `0.05 s` | `13,024 KB` | selected | use line `363` / `%75` as the first L1 cutout and begin weight-pack extraction around the first `4 -> 16` site |
| 2026-04-22 | `export_weights_pack.py` for `transformer.h.0.mlp.c_fc` | `transformer.h.0.mlp.c_fc` | `pytorch-state-dict` | n/a | n/a | n/a | n/a | `2.42 s` | `336,816 KB` | pass-pack | use `weight.bin` / `bias.bin` plus `manifest.json` as the first external pack backing the selected L1 site |
| 2026-04-22 | `representative-core-v64-h4-c_fc-contract/manifest.json` | `transformer.h.0.mlp.c_fc` | `pytorch-module-hook` | n/a | n/a | n/a | n/a | `2.42 s` | `342,280 KB` | pass-contract | treat `activation_in.bin` plus `activation_out.bin` as the first deterministic `L1` sample contract tied to line `363` / `%75` |
| 2026-04-22 | `representative-core-v64-h4-c_fc-contract-check.json` | `transformer.h.0.mlp.c_fc` | packed replay | n/a | n/a | n/a | n/a | `0.93 s` | `226,472 KB` | pass-check | use exact `max_abs_error = 0.0` replay as the first executable proof that the packed `c_fc` tensors reproduce the captured output |
| 2026-04-22 | `representative-core-v64-h4-c_fc-task-graph.json` | `transformer.h.0.mlp.c_fc` | `linalg` | n/a | n/a | n/a | n/a | `0.02 s` | `14,396 KB` | pass-graph | keep the minimal graph pointed at the selected site, packed weights, and captured sample contract while deferring the heavier Verilator path |
| 2026-04-22 | folded-bias `task6-l1-c-fc-redirect` replay | `transformer.h.0.mlp.c_fc` | `sv -> Verilator` | n/a | n/a | n/a | n/a | n/a | n/a | reject-folded-bias | stop treating algebraic bias folding as an exact replay because all `16` outputs drift at `q16.16` scale |
| 2026-04-22 | explicit-bias `task6-l1-c-fc-redirect` inspection | `transformer.h.0.mlp.c_fc` | `torch -> hw-clean` | n/a | n/a | n/a | n/a | n/a | n/a | reject-external-bias | count this as the one externalization failure for bias because the top-level load interface disappeared and fallback to the kernel-only pre-bias site |
| 2026-04-22 | `task6-l1-c-fc-redirect-yosys-stat` | `transformer.h.0.mlp.c_fc` pre-bias kernel | `linalg -> yosys-stat` | pending pre-map | pending pre-map | pending pre-map | pending pre-map | `4.07 s` | `564,032 KB` | pass-runtime | close the mapped resource and Verilator proof on the accepted kernel-only variant |
| 2026-04-22 | `task6-l1-c-fc-redirect-utilization` | `transformer.h.0.mlp.c_fc` pre-bias kernel | `sv -> synth_xilinx -> mapped JSON` | `4` | `0` | `33,116` | `51,296` | `64.82 s` | `562,944 KB` | pass-dsp fail-lut | accept `L1` as a structural redirected-kernel proof but move on because LUT cost still exceeds the ceiling |
| 2026-04-22 | `task6-l1-c-fc-redirect-sv-sim` | `transformer.h.0.mlp.c_fc` pre-bias kernel | `sv -> Verilator` | pending pre-map | pending pre-map | pending pre-map | pending pre-map | `61.91 s` | `437,820 KB` | pass-sim-tol | keep the kernel-only proof with `ABS_TOL = 1.0e-4` and carry the redirect pattern to `L2` |
| 2026-04-22 | `tiny-stories-v1k-h64-l1-c_fc-candidate.json` | `transformer.h.0.mlp.c_fc` candidate | `linalg` | n/a | n/a | n/a | n/a | `0.03 s` | `15,644 KB` | selected | use line `357` / `%81` as the first reduced-vocab `h64` replay of the `c_fc` boundary |
| 2026-04-22 | `export_weights_pack.py` for `tiny-stories-v1k-h64-l1` | `transformer.h.0.mlp.c_fc` | `pytorch-state-dict` | n/a | n/a | n/a | n/a | `2.38 s` | `337,536 KB` | pass-pack | keep the reduced-vocab rung on externalized `256 x 64` weights rather than re-embedding constants |
| 2026-04-22 | `tiny-stories-v1k-h64-l1-c_fc-contract/manifest.json` | `transformer.h.0.mlp.c_fc` | `pytorch-module-hook` | n/a | n/a | n/a | n/a | `2.40 s` | `342,932 KB` | pass-contract | use one deterministic single-token sample at the reduced-vocab `h64` rung as the first micro-fit contract |
| 2026-04-22 | `tiny-stories-v1k-h64-l1-c_fc-contract-check.json` | `transformer.h.0.mlp.c_fc` | packed replay | n/a | n/a | n/a | n/a | `0.92 s` | `226,720 KB` | pass-check | accept the reduced-vocab rung as structurally faithful because the packed replay matches exactly with `max_abs_error = 0.0` |
| 2026-04-22 | `tiny-stories-v1k-h64-l1-c_fc-task-graph.json` | `transformer.h.0.mlp.c_fc` | `linalg` | n/a | n/a | n/a | n/a | `0.03 s` | `14,268 KB` | pass-graph | keep `L2` active and defer `L3` until the next slice decides whether to widen to `v4k` or add kernel-level synthesis |
| 2026-04-22 | `task6-l2-c-fc-redirect-yosys-stat` | `transformer.h.0.mlp.c_fc` pre-bias kernel | `linalg -> yosys-stat` | pending pre-map | pending pre-map | pending pre-map | pending pre-map | `9.13 s` | `563,512 KB` | pass-runtime | use the aligned `64 -> 256` redirected kernel as the first reduced-vocab structural proof before spending on mapped utilization |
| 2026-04-22 | `task6-l2-c-fc-redirect-utilization` | `transformer.h.0.mlp.c_fc` pre-bias kernel | `sv -> synth_xilinx -> mapped JSON` | `4` | `0` | `50,235` | `65,523` | `88.93 s` | `562,776 KB` | pass-dsp fail-fit | do not promote `L2` as the fit-first lane because both LUT and FF counts regress relative to `L1` |
| 2026-04-22 | `task6-l2-c-fc-redirect-sv-sim` | `transformer.h.0.mlp.c_fc` pre-bias kernel | `sv -> Verilator` | pending pre-map | pending pre-map | pending pre-map | pending pre-map | `47.06 s` | `437,352 KB` | pass-sim-tol | keep the `L2` redirect as a valid functional proof, but move fit-reduction work back to the cheaper `L1` rung |
| 2026-04-23 | `task6-l2-c-fc-redirect-postbranch-fifo2-sv-sim` | `transformer.h.0.mlp.c_fc` pre-bias kernel | `sv selective override -> Verilator` | pending pre-map | pending pre-map | pending pre-map | pending pre-map | `77.00 s` | `437,400 KB` | pass-sim | the aligned `L2` replay that replaces only the still-matching post-branch `ui64` buffers `264/265/266/270/271` preserves the kernel contract, so mapped `abc9` can decide whether the `L1` fit lever survives on the reduced-vocab rung |
| 2026-04-23 | `task6-l2-c-fc-redirect-postbranch-fifo2-abc9-utilization` | `transformer.h.0.mlp.c_fc` pre-bias kernel | `sv selective override -> synth_xilinx -abc9 -> mapped JSON` | `4` | `0` | `51,622` | `64,873` | `255.15 s` | `563,416 KB` | reject-replay | the aligned `L2` replay keeps external weights, `4 DSP48E1`, and the kernel contract, but it regresses LUT by `1,387` against the existing `L2` kernel while still missing the fit ceiling badly, so close this exact replay path and do not promote `L2` to `L3` |
| 2026-04-23 | `task6-l2-c-fc-redirect-downstream-outbuf-fifo2-sv-sim` | `transformer.h.0.mlp.c_fc` pre-bias kernel | `sv selective override -> Verilator` | pending pre-map | pending pre-map | pending pre-map | pending pre-map | `80.01 s` | `437,188 KB` | pass-sim | the first `L2`-native downstream `ui64` out-buffer cluster `272/273/274/275/276/278` preserves the kernel contract, so mapped `abc9` can decide whether the changed `272..280` neighborhood is a better fit lever than the aligned replay |
| 2026-04-23 | `task6-l2-c-fc-redirect-downstream-outbuf-fifo2-abc9-utilization` | `transformer.h.0.mlp.c_fc` pre-bias kernel | `sv selective override -> synth_xilinx -abc9 -> mapped JSON` | `4` | `0` | `51,832` | `64,743` | `261.04 s` | `563,320 KB` | reject-l2-native | the first `L2`-native downstream probe trims FF and estimated mapped LCs, but the official scorecard metric is CLB LUTs and those worsen again, so stop `L2 c_fc` micro-surgery here and pivot the lane fallback to `mlp.c_proj` |
| 2026-04-23 | `representative-core-v64-h4-c_proj-contract-check.json` | `transformer.h.0.mlp.c_proj` fallback boundary | `linalg -> pack -> contract replay` | n/a | n/a | n/a | n/a | `1.83 s` | `226,384 KB` | pass-fallback | the reserve `L1` fallback boundary is real: the selected representative-core `c_proj` site at line `418` / `%88` replays exactly from packed weights and captured activations, so the next slice can start a redirected `c_proj` kernel without more `L1` boundary scouting |
| 2026-04-23 | `tiny-stories-v1k-h64-l1-c_proj-contract-check.json` | `transformer.h.0.mlp.c_proj` fallback boundary | `linalg -> pack -> contract replay` | n/a | n/a | n/a | n/a | `1.83 s` | `226,016 KB` | pass-fallback | the same reserve fallback boundary survives on the reduced-vocab rung at line `412` / `%94`, so `c_proj` is now ready for the same redirected-kernel path on `L1` before any replay back onto `L2` |
| 2026-04-23 | `task6-l1-c-proj-redirect-yosys-stat` | `transformer.h.0.mlp.c_proj` pre-bias kernel | `linalg -> yosys-stat` | pending pre-map | pending pre-map | pending pre-map | pending pre-map | `17.52 s` | `563,732 KB` | pass-runtime | the first redirected `c_proj` kernel compiles through the inherited float-extern flow, keeps one `$mul` plus one `arith_mulf` / `arith_addf`, and stays inside the micro-proof budget, so the next slice is Verilator plus mapped utilization rather than more fallback-boundary scouting |
| 2026-04-23 | `task6-l1-c-proj-redirect-sv-sim` | `transformer.h.0.mlp.c_proj` pre-bias kernel | `sv -> Verilator` | pending pre-map | pending pre-map | pending pre-map | pending pre-map | `106.74 s` | `437,244 KB` | pass-sim | the untouched `L1 c_proj` redirected kernel passes the captured contract with `PASS: stores 4 outputs 4`, so the fallback boundary is now a real executable RTL proof and mapped utilization can judge whether it is lane-worthy |
| 2026-04-23 | `task6-l1-c-proj-redirect-utilization` | `transformer.h.0.mlp.c_proj` pre-bias kernel | `sv -> synth_xilinx -> mapped JSON` | `4` | `0` | `32,393` | `50,864` | `97.85 s` | `562,712 KB` | pass-dsp fail-lut | the first mapped `L1 c_proj` redirect is structurally valid and slightly better than raw `L1 c_fc`, but it still misses the LUT ceiling by `2,533` and trails the frozen `L1 c_fc` reference by `2,615` LUT, so only one cheap mapper-only check is justified before keeping it reserve-only |
| 2026-04-23 | `task6-l1-c-proj-redirect-abc9-utilization` | `transformer.h.0.mlp.c_proj` pre-bias kernel | `sv -> synth_xilinx -abc9 -> mapped JSON` | `4` | `0` | `31,611` | `50,864` | `143.08 s` | `563,156 KB` | reserve-only | direct `abc9` buys a real `782` LUT reduction on the untouched `L1 c_proj` redirect, but it still misses the ceiling by `1,751` and remains worse than the frozen `L1 c_fc` reference, so keep `c_proj` as a validated reserve fallback rather than switching the main lane to it |
| 2026-04-23 | `task6-l0-gemv64-abc9-utilization` | synthetic external-weight `64x64` GEMV | `sv -> synth_xilinx -abc9 -> mapped JSON` | `4` | `0` | `32,478` | `46,736` | `94.83 s` | `561,388 KB` | reject-mapper | stop treating direct `abc9` as an `L0` fit path because it slightly worsens LUT while leaving the rest of the signature unchanged |
| 2026-04-23 | `task6-l1-c-fc-redirect-abc9-utilization` | `transformer.h.0.mlp.c_fc` pre-bias kernel | `sv -> synth_xilinx -abc9 -> mapped JSON` | `4` | `0` | `32,236` | `51,296` | `94.27 s` | `561,892 KB` | pass-dsp fail-lut | keep direct `abc9` as the best mapped `L1` result so far, but move on because the kernel still misses the LUT ceiling by `2,376` |
| 2026-04-23 | `task6-l1-c-fc-redirect-staged-abc9-utilization` | `transformer.h.0.mlp.c_fc` pre-bias kernel | `il -> staged synth_xilinx -abc9` | n/a | n/a | n/a | n/a | `15.14 s` | `564,392 KB` | reject-staged-mapper | stop the staged `abc9` path after one failure because stage8 dies on `FDRE` parameter handling before any mapped JSON is produced |
| 2026-04-23 | `task6-l1-c-fc-redirect-ui64-buffer-lite-sv-sim` | `transformer.h.0.mlp.c_fc` pre-bias kernel | `sv override -> Verilator` | pending pre-map | pending pre-map | pending pre-map | pending pre-map | `22.69 s` | `437,508 KB` | reject-functional | the `ui64` one-slot buffer override is not a valid drop-in because both tested variants timed out the kernel-only contract |
| 2026-04-23 | `task6-l1-c-fc-redirect-ui64-buffer-lite-utilization` | `transformer.h.0.mlp.c_fc` pre-bias kernel | `sv override -> synth_xilinx -> mapped JSON` | `4` | `0` | `20,725` | `15,731` | `53.61 s` | `562,884 KB` | fit-diagnostic-only | treat this as an upper-bound fit signal only: `ui64` buffer state dominates area, but the current low-state override fails the Verilator contract |
| 2026-04-23 | `task6-l1-c-fc-redirect-ui64-buffer-fifo2-sv-sim` | `transformer.h.0.mlp.c_fc` pre-bias kernel | `sv override -> Verilator` | pending pre-map | pending pre-map | pending pre-map | pending pre-map | `42.50 s` | `437,644 KB` | reject-functional | count this as the third same-class whole-buffer failure and stop class-wide `ui64` replacement after the lean FIFO2 override also times out the kernel contract |
| 2026-04-23 | `task6-l1-c-fc-redirect-buffer165-fifo2-sv-sim` | `transformer.h.0.mlp.c_fc` pre-bias kernel | `sv selective override -> Verilator` | pending pre-map | pending pre-map | pending pre-map | pending pre-map | `56.13 s` | `437,056 KB` | pass-sim | one central loop-index buffer can be replaced with the lean FIFO2 implementation without breaking the kernel contract |
| 2026-04-23 | `task6-l1-c-fc-redirect-buffer165-fifo2-utilization` | `transformer.h.0.mlp.c_fc` pre-bias kernel | `sv selective override -> synth_xilinx -> mapped JSON` | `4` | `0` | `33,020` | `51,292` | `66.21 s` | `562,608 KB` | pass-dsp fail-lut | selective replacement is structurally viable but the single-instance win is small, so widen only around the same index spine if the next slice stays simulation-safe |
| 2026-04-23 | `task6-l1-c-fc-redirect-index-spine-fifo2-sv-sim` | `transformer.h.0.mlp.c_fc` pre-bias kernel | `sv selective override -> Verilator` | pending pre-map | pending pre-map | pending pre-map | pending pre-map | `58.30 s` | `437,376 KB` | pass-sim | the local `160..165` loop-index spine still satisfies the kernel contract, so the next gate is mapped utilization rather than more simulation-only widening |
| 2026-04-23 | `task6-l1-c-fc-redirect-index-spine-fifo2-utilization` | `transformer.h.0.mlp.c_fc` pre-bias kernel | `sv selective override -> synth_xilinx -> mapped JSON` | `4` | `0` | `32,808` | `50,642` | `64.88 s` | `563,044 KB` | pass-dsp fail-lut | the safe `160..165` local cluster trims `308` LUT and `654` FF versus accepted base `L1`, but it is still short of the ceiling, so the next cheapest slice is to test whether this safe reduction stacks with `abc9` before widening further |
| 2026-04-23 | `task6-l1-c-fc-redirect-index-spine-fifo2-abc9-utilization` | `transformer.h.0.mlp.c_fc` pre-bias kernel | `sv selective override -> synth_xilinx -abc9 -> mapped JSON` | `4` | `0` | `32,036` | `50,642` | `92.79 s` | `562,772 KB` | pass-dsp fail-lut | safe local FIFO2 reduction and `abc9` do stack, so this is the best `L1` result so far and the next bounded slice is one more adjacent local cluster under the same `abc9` recipe |
| 2026-04-23 | `task6-l1-c-fc-redirect-index-fanout-fifo2-sv-sim` | `transformer.h.0.mlp.c_fc` pre-bias kernel | `sv selective override -> Verilator` | pending pre-map | pending pre-map | pending pre-map | pending pre-map | `65.50 s` | `436,664 KB` | pass-sim | widening from the index spine into the immediate `173..182` branch-output fanout still satisfies the kernel contract, so the cluster is valid enough to score under `abc9` |
| 2026-04-23 | `task6-l1-c-fc-redirect-index-fanout-fifo2-abc9-utilization` | `transformer.h.0.mlp.c_fc` pre-bias kernel | `sv selective override -> synth_xilinx -abc9 -> mapped JSON` | `4` | `0` | `31,309` | `49,342` | `93.49 s` | `563,372 KB` | pass-dsp fail-lut | the adjacent fanout ring is still productive, dropping another `727` LUT and `1,300` FF versus the prior best, so one more bounded local hop remains justified before declaring the selective path exhausted |
| 2026-04-23 | `task6-l1-c-fc-redirect-index-ring2-fifo2-sv-sim` | `transformer.h.0.mlp.c_fc` pre-bias kernel | `sv selective override -> Verilator` | pending pre-map | pending pre-map | pending pre-map | pending pre-map | `69.90 s` | `436,804 KB` | pass-sim | extending the same local recipe through `185..192` still preserves the kernel contract, so the safe selective region reaches the second downstream ring |
| 2026-04-23 | `task6-l1-c-fc-redirect-index-ring2-fifo2-abc9-utilization` | `transformer.h.0.mlp.c_fc` pre-bias kernel | `sv selective override -> synth_xilinx -abc9 -> mapped JSON` | `4` | `0` | `30,762` | `48,302` | `93.67 s` | `563,284 KB` | pass-dsp fail-lut | the second downstream ring still buys a meaningful step, reducing another `547` LUT and `1,040` FF and leaving the lane only `902` LUT over the ceiling, so one final adjacent hop is now defensible |
| 2026-04-23 | `task6-l1-c-fc-redirect-index-ring3-fifo2-sv-sim` | `transformer.h.0.mlp.c_fc` pre-bias kernel | `sv selective override -> Verilator` | pending pre-map | pending pre-map | pending pre-map | pending pre-map | `82.55 s` | `437,104 KB` | pass-sim | the connected `213..219` mux-return ring still preserves the kernel contract, so the safe local region extends one more hop without functional fallout |
| 2026-04-23 | `task6-l1-c-fc-redirect-index-ring3-fifo2-abc9-utilization` | `transformer.h.0.mlp.c_fc` pre-bias kernel | `sv selective override -> synth_xilinx -abc9 -> mapped JSON` | `4` | `0` | `30,320` | `47,392` | `93.19 s` | `563,112 KB` | pass-dsp fail-lut | the final local hop still helps but with smaller returns, leaving the lane only `460` LUT over the ceiling; this is the best `L1` point so far and a reasonable stop for blind widening |
| 2026-04-23 | `task6-l1-c-fc-redirect-index-ring3-ctrlmerge-fifo2-sv-sim` | `transformer.h.0.mlp.c_fc` pre-bias kernel | `sv selective override -> Verilator` | pending pre-map | pending pre-map | pending pre-map | pending pre-map | `149.22 s` | `436,284 KB` | pass-sim | the deliberate `194/220` and `229/237` control/merge hotspot still preserves the kernel contract, so mapped `abc9` can decide whether it beats the frozen ring-3 point |
| 2026-04-23 | `task6-l1-c-fc-redirect-index-ring3-ctrlmerge-fifo2-abc9-utilization` | `transformer.h.0.mlp.c_fc` pre-bias kernel | `sv selective override -> synth_xilinx -abc9 -> mapped JSON` | `4` | `0` | `30,360` | `47,384` | `156.72 s` | `562,952 KB` | reject-hotspot | the control/merge hotspot is safe but regresses LUT by `40` against frozen ring-3, so keep `task6-l1-c-fc-redirect-index-ring3-fifo2-abc9` as the reference and close this local branch |
| 2026-04-23 | `task6-l1-c-fc-redirect-index-ring3-ui1buf263-fifo2-sv-sim` | `transformer.h.0.mlp.c_fc` pre-bias kernel | `sv selective override -> Verilator` | pending pre-map | pending pre-map | pending pre-map | pending pre-map | `150.24 s` | `436,780 KB` | pass-sim | the selector-side `ui1` buffer263 trim still preserves the kernel contract, so mapped `abc9` can score whether local selector state is worth touching |
| 2026-04-23 | `task6-l1-c-fc-redirect-index-ring3-ui1buf263-fifo2-abc9-utilization` | `transformer.h.0.mlp.c_fc` pre-bias kernel | `sv selective override -> synth_xilinx -abc9 -> mapped JSON` | `4` | `0` | `30,370` | `47,388` | `150.20 s` | `561,796 KB` | reject-hotspot | the local `ui1` selector-buffer probe is safe but regresses LUT by `50` against frozen ring-3, so it does not beat the current `L1` reference |
| 2026-04-23 | `tiny-stories-v1k-h64-l1-selftest-top4-memory-yosys-json` | reduced-vocab one-block top | one-block top `yosys-json` gate | pending pre-map | pending pre-map | pending pre-map | pending pre-map | `99.26 s` | `564,340 KB` | pass-runtime-gate | the repo one-block-top gate now clears the `< 2 min` budget, but `L3`/`L4` stay blocked because frozen `L1` still misses the LUT ceiling |
| 2026-04-23 | `task6-l1-c-fc-redirect-index-ring3-fork49-statevec-sv-sim` | `transformer.h.0.mlp.c_fc` pre-bias kernel | `sv selective override -> Verilator` | pending pre-map | pending pre-map | pending pre-map | pending pre-map | `147.32 s` | `437,320 KB` | pass-sim | the local `fork49` statevec helper preserves the kernel contract, so mapped `abc9` can decide whether fork-side completion encoding is a better fit lever than buffer trimming |
| 2026-04-23 | `task6-l1-c-fc-redirect-index-ring3-fork49-statevec-abc9-utilization` | `transformer.h.0.mlp.c_fc` pre-bias kernel | `sv selective override -> synth_xilinx -abc9 -> mapped JSON` | `4` | `0` | `30,358` | `47,392` | `144.56 s` | `562,532 KB` | reject-hotspot | the local `fork49` statevec probe is safe and slightly better than the other hotspot misses, but it still regresses LUT by `38` against frozen ring-3, so this is the third deliberate post-ring-3 hotspot miss and the lane should move on from local hotspot surgery |
| 2026-04-23 | `task6-l1-c-fc-redirect-index-ring3-selectcluster-fifo2-sv-sim` | `transformer.h.0.mlp.c_fc` pre-bias kernel | `sv selective override -> Verilator` | pending pre-map | pending pre-map | pending pre-map | pending pre-map | `149.01 s` | `437,064 KB` | pass-sim | the local selector-cluster helper for `buffer255 -> fork46` preserves the kernel contract, so mapped `abc9` can decide whether this first real cluster cut beats the nearby one-site probes |
| 2026-04-23 | `task6-l1-c-fc-redirect-index-ring3-selectcluster-fifo2-abc9-utilization` | `transformer.h.0.mlp.c_fc` pre-bias kernel | `sv selective override -> synth_xilinx -abc9 -> mapped JSON` | `4` | `0` | `30,358` | `47,392` | `147.09 s` | `562,120 KB` | reject-cluster | the selector-cluster helper ties the `fork49` statevec miss and still loses by `38` LUT to frozen ring-3, so the selector-control tree is not the next fit lever |
| 2026-04-23 | `task6-l1-c-fc-redirect-index-ring3-postbranch-fifo2-sv-sim` | `transformer.h.0.mlp.c_fc` pre-bias kernel | `sv selective override -> Verilator` | pending pre-map | pending pre-map | pending pre-map | pending pre-map | `149.45 s` | `437,752 KB` | pass-sim | the downstream post-branch `ui64` buffer cluster `264..271` preserves the kernel contract, so this is the first non-selector follow-up worth scoring after the selector tree closed |
| 2026-04-23 | `task6-l1-c-fc-redirect-index-ring3-postbranch-fifo2-abc9-utilization` | `transformer.h.0.mlp.c_fc` pre-bias kernel | `sv selective override -> synth_xilinx -abc9 -> mapped JSON` | `4` | `0` | `29,967` | `46,612` | `149.96 s` | `562,980 KB` | pass-dsp fail-lut | the first downstream post-branch data-cluster probe is a real fit win, cutting `353` LUT and `780` FF versus frozen ring-3 and leaving the lane only `107` LUT over the ceiling, so one more bounded extension on the same cluster is justified |
| 2026-04-23 | `task6-l1-c-fc-redirect-index-ring3-postbranch-outbuf-fifo2-sv-sim` | `transformer.h.0.mlp.c_fc` pre-bias kernel | `sv selective override -> Verilator` | pending pre-map | pending pre-map | pending pre-map | pending pre-map | `133.51 s` | `437,680 KB` | pass-sim | extending the same post-branch fit lever through the immediate `ui64` output buffers `279..280` still preserves the kernel contract, so the mapped run can decide whether `L1` finally clears the ceiling |
| 2026-04-23 | `task6-l1-c-fc-redirect-index-ring3-postbranch-outbuf-fifo2-abc9-utilization` | `transformer.h.0.mlp.c_fc` pre-bias kernel | `sv selective override -> synth_xilinx -abc9 -> mapped JSON` | `4` | `0` | `29,778` | `46,352` | `149.06 s` | `562,936 KB` | pass-fit | the bounded post-branch out-buffer extension clears the `L1` ceiling by `82` LUT while preserving external weights, `4 DSP48E1`, and the kernel contract, so this becomes the new `L1` reference and the next replay should move to `L2` rather than widening `L1` again |
| 2026-04-23 | `task6-l2-c-fc-redirect-tile64-yosys-stat` | `transformer.h.0.mlp.c_fc` tiled `64 -> 64` kernel | `linalg -> yosys-stat` | pending pre-map | pending pre-map | pending pre-map | pending pre-map | `16.09 s` | `561,720 KB` | pass-runtime | the reusable tile kernel stays inside the micro-proof budget with the inherited float-extern path, so the bounded structural test can move to full-contract simulation and mapped `abc9` rather than more wrapper speculation |
| 2026-04-23 | `task6-l2-c-fc-redirect-tile4x64-sv-sim` | `transformer.h.0.mlp.c_fc` tiled `4 x 64` wrapper | `sv top-level sequencer -> Verilator` | pending pre-map | pending pre-map | pending pre-map | pending pre-map | `161.55 s` | `437,564 KB` | pass-sim | the new top-level sequencer preserves the full `L2` contract with `PASS: stores 256 outputs 256`, so the structural hypothesis is live enough for mapped scoring |
| 2026-04-23 | `task6-l2-c-fc-redirect-tile4x64-abc9-utilization` | `transformer.h.0.mlp.c_fc` tiled `4 x 64` wrapper | `sv top-level sequencer -> synth_xilinx -abc9 -> mapped JSON` | `4` | `0` | `32,460` | `46,740` | `153.09 s` | `563,056 KB` | pass-structural-hit | the bounded tiled-wrapper hypothesis is supported: reusing one external-weight `64 -> 64` kernel across four phases removes most of the monolithic `L2` overhead, cutting `17,775` LUT and `18,783` FF versus the base `L2` kernel while keeping `4 DSP48E1`, but it still misses the `29,860` LUT ceiling so `L3` remains blocked |
| 2026-04-23 | `task6-l2-c-fc-redirect-tile64-abc9-utilization` seam split | `transformer.h.0.mlp.c_fc` tiled `64 -> 64` kernel | `sv tile kernel -> synth_xilinx -abc9 -> mapped JSON` | `4` | `0` | `32,478` | `46,736` | `92.53 s` | `563,708 KB` | pass-instrumentation | the reusable tile kernel lands within `18` LUT / `4` FF of the full tiled wrapper, so the tile/wrapper seam is not the dominant remaining `L2` cost center and the next bounded probe must target the tile kernel itself |
| 2026-04-23 | `task6-l2-c-fc-redirect-tile64-postbranch-outbuf-fifo2-abc9-utilization` | `transformer.h.0.mlp.c_fc` tiled `64 -> 64` kernel | `sv selective override -> synth_xilinx -abc9 -> mapped JSON` | `4` | `0` | `31,968` | `45,928` | `93.06 s` | `563,328 KB` | pass-kernel-win | replacing the tile kernel's local post-branch/output `ui64` cluster trims `510` LUT and `808` FF versus the untouched tile kernel, so this is strong enough to justify one wrapper replay on the same bounded hypothesis |
| 2026-04-23 | `task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2-sv-sim` | `transformer.h.0.mlp.c_fc` tiled `4 x 64` wrapper with improved tile kernel | `sv top-level sequencer -> Verilator` | pending pre-map | pending pre-map | pending pre-map | pending pre-map | `85.86 s` | `437,444 KB` | pass-sim | the improved tile kernel still preserves the full `L2` contract with `PASS: stores 256 outputs 256`, so the kernel-local fit win survives replay into the tiled wrapper |
| 2026-04-23 | `task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2-abc9-utilization` | `transformer.h.0.mlp.c_fc` tiled `4 x 64` wrapper with improved tile kernel | `sv top-level sequencer -> synth_xilinx -abc9 -> mapped JSON` | `4` | `0` | `31,907` | `45,932` | `94.03 s` | `562,812 KB` | pass-structural-hit fail-lut | replaying the bounded tile-kernel post-branch/output cut trims the tiled `L2` wrapper by another `553` LUT and `808` FF (`32,460 -> 31,907`, `46,740 -> 45,932`) while keeping external weights and `4 DSP48E1`, so this becomes the new `L2` reference even though it still misses the LUT ceiling by `2,047` |
| 2026-04-23 | `task6-ui64-fifo2-probe-plumbing` validation | shared `ui64` FIFO2 probe surfaces | `flake + SV helper consolidation` | `4` | `0` | `23,161 / 29,778 / 31,907` | `27,591 / 46,352 / 45,932` | `3.12 s / 3.09 s / 3.12 s / 2.23 s` | `563,116 KB / 563,200 KB / 563,188 KB / 5,292 KB` | pass-no-regression | keep the canonical FIFO2 helper plus patch-map cleanup and spend the next bounded `L2` probe on the remaining mixed data/control store-path seam rather than another buffer-only rewrite |
| 2026-04-23 | `task6-l2-c-fc-redirect-tile64-storepath-forkctrl-sv-sim` | `transformer.h.0.mlp.c_fc` tiled `64 -> 64` kernel mixed store-path seam | `sv selective helper override -> Verilator` | pending pre-map | pending pre-map | pending pre-map | pending pre-map | `80.97 s` | `438,164 KB` | reject-functional | the first mixed seam helper is not a valid drop-in because the tiled `L2` contract aborts after only `64` observed stores, so if the seam is probed again the ctrl buffers must stay untouched and the fork-state helpers need to be isolated on their own |
| 2026-04-23 | `task6-l2-c-fc-redirect-tile64-storepath-forks-sv-sim` | `transformer.h.0.mlp.c_fc` tiled `64 -> 64` kernel fork-only store-path seam | `sv selective helper override -> Verilator` | pending pre-map | pending pre-map | pending pre-map | pending pre-map | `83.16 s` | `438,492 KB` | reject-functional | keeping the ctrl buffers untouched does not save the seam: the fork-only follow-up reproduces the same `64`-store abort, so the current store-path helper substitution line is closed and any further `L2 c_fc` work now needs a different structural hypothesis |
| 2026-04-24 | `just task6-l0` | synthetic external-weight `64x64` GEMV | cache-hit status replay on exact rung surface | `4` | `0` | `32,449` | `46,736` | `3.25 s / 2.26 s / 3.20 s` | `563,960 KB / 438,164 KB / 563,512 KB` | pass-surface fail-lut | keep the `L0` runner only as a cheap status replay; the timings are replay timings and the rung still fails only on LUT |
| 2026-04-24 | `just task6-l1` | block-0 `mlp.c_fc` extracted from `tiny-stories-1m-representative-core-v64-h4` | cache-hit status replay on exact frozen reference | `4` | `0` | `29,778` | `46,352` | `3.17 s / 2.28 s / 3.20 s` | `563,944 KB / 437,844 KB / 563,220 KB` | pass-surface | keep `task6-l1-c-fc-redirect-index-ring3-postbranch-outbuf-fifo2-abc9` as the `L1` gold reference; the cleaned runner now measures the exact same surface for Yosys, sim, and utilization |
| 2026-04-24 | `just task6-l2` | `tiny-stories-v1k-h64-l1` tiled `4 x 64` replay | cache-hit status replay on exact active reference | `4` | `0` | `31,907` | `45,932` | `3.17 s / 2.42 s / 3.16 s` | `564,112 KB / 437,840 KB / 563,344 KB` | pass-surface fail-lut | keep tiled `L2` as the active mainline, but treat the runner only as a status replay; it now measures the exact tiled wrapper reference while `L3` remains blocked |
| 2026-04-24 | `tiny-stories-1m-baseline-float-selftest-top4-memory-{external-memory-plan,utilization}` bounded pass | full TinyStories baseline shell | narrowed external-memory shell | pending mapped result | pending mapped result | pending mapped result | pending mapped result | `127.70 s` plan rebuild; utilization interrupted after staged re-entry | `8,935,948 KB` observed live Yosys RSS during `stage2` | pass-plan partial-shell | the reproducible top-four DDR3 target set rebuilt cleanly and still selects four `3216448 x 32` modules totaling `411,705,344` bits (`49.08 MiB`, `95.1%` of eligible memory), but the narrowed shell utilization did not produce a new mapped result inside the bounded pass; if this track gets another slice, rerun it under `monitor_build.sh` and otherwise move on to the PT2E-static quantized replay |
| 2026-04-24 | `tiny-stories-1m-baseline-float-selftest-top4-memory-external-memory-plan` first rerun after upstream CIRCT switch | full TinyStories baseline shell | narrowed external-memory shell | pending toolchain bootstrap | pending toolchain bootstrap | pending toolchain bootstrap | pending toolchain bootstrap | `77.96 s` before manual stop | no final target RSS; build log reached `llvm-tblgen` `[221/388]` | block-toolchain-reentry | this rerun never reached the `top4-memory` model stages because the branch first had to bootstrap upstream LLVM/MLIR/CIRCT after the `llvm/circt` switch, so record it as an environment/toolchain blocker rather than as a new DDR3 shell verdict |
| 2026-04-24 | `tiny-stories-1m-{cf-stats,cf,handshake}` bounded pass | full TinyStories quantized route | PT2E-static quantized frontend through LSQ handshake lowering | pending later-stage score | pending later-stage score | pending later-stage score | pending later-stage score | cache-hot replays: `1.60 s` for `cf-stats`, `0.26 s` for `handshake` | cache-hot replays: `294,732 KB` for `cf-stats`, `37,024 KB` for `handshake` | pass-quant-frontier | the surviving quantized route now reaches real `handshake`, not just `cf-stats`, and it does so through `cf_to_handshake_lsq.sh`; keep `tiny-stories-1m` active, keep `dynamic-int8` and `torchao` frozen, and use this as the seed for the bounded alternate-lowering comparison rather than widening quantization blindly |
| 2026-04-24 | `task6-l1-c-fc-redirect-lsq-index-ring3-postbranch-outbuf-fifo2-{yosys-stat,sv-sim,abc9-utilization}` | block-0 `mlp.c_fc` extracted from `tiny-stories-1m-representative-core-v64-h4` | same extracted contract, LSQ lowering, then the validated selective `ui64` FIFO2 override subset | `4` | `0` | `29,329` | `46,570` | `4.69 s` `yosys-stat`; `82.09 s` `sv-sim`; `89.23 s` utilization | `564,140 KB` `yosys-stat`; `437,484 KB` `sv-sim`; `563,056 KB` utilization | reject-drop-in | the bounded alternate-lowering slice is structurally interesting because it beats the frozen float reference on mapped LUT while preserving `4 DSP48E1`, but it is not a drop-in-safe replacement because the identical redirected `L1` contract times out in Verilator, so the one-pass A/B is recorded and closed negative |
| 2026-04-24 | `task6-l1-c-fc-redirect-pt2e-static-torch` plus direct graph inspection | block-0 `mlp.c_fc` extracted from `tiny-stories-1m-representative-core-v64-h4` | PT2E-static quantized extracted-op parity on the same external-weight `4 x 16` GEMV | n/a | n/a | n/a | n/a | `4.61 s` quantized `torch`; `4.24 s` float `torch`; `2.26 s` inspection | `276,128 KB` quantized `torch`; `276,464 KB` float `torch`; `341,772 KB` inspection | reject-quant-noop | the direct PT2E-static extracted-op route does not survive externalized weights on the minimal `L1` surface: the prepared, converted, and re-exported graphs all remain plain float `aten.matmul`, and the emitted `torch` MLIR is byte-identical to the frozen float reference, so this exact quant path is closed before any heavier replay |

## Rejections

- The alternate `task6-l0-gemv64-int16` kernel is reproducible but not useful
  as the next lane step:
  - mapped utilization worsens to `35,737` LUT and weakens the DSP signal to
    `1 DSP48E1`, so it is worse than the float `L0` proof on the metrics that
    currently matter
- A local `task6-l0-gemv64-int8` probe is blocked by toolchain support:
  - `torch-mlir-opt` crashes during `torch` to `linalg` lowering on
    `torch.aten.mm` with `si8`, so that path is not ready to become a flake
    package or a lane default
- The folded-bias `L1` redirect is not exact enough to keep:
  - all `16` outputs drifted by up to `0.000075929` after lowering through the
    current float primitive path, so it is not a bit-exact replay of the
    captured site
- The explicit-bias `L1` redirect failed the externalization rule:
  - the bias tensor survived through `linalg`, but the top-level external load
    interface disappeared by `hw-clean`, so that path is stopped after one
    externalization attempt
- The `L2` redirected kernel is not a promotion candidate for fit-first work:
  - even though it keeps `4 DSP48E1` and passes Verilator, mapped utilization
    rises to `50,235` LUT and `65,523` FF, which is worse than the accepted
    `L1` structural proof
- The aligned `L2` replay of the new `L1` post-branch fit lever is also not a promotion candidate:
  - replacing the still-matching post-branch `ui64` buffers
    `264/265/266/270/271` preserves Verilator and `4 DSP48E1`, but mapped
    utilization still worsens to `51,622` LUT while only trimming FFs to
    `64,873`, so this exact replay path is closed
- The first `L2`-native downstream out-buffer probe is not a promotion candidate either:
  - replacing the changed `ui64` neighborhood
    `272/273/274/275/276/278` preserves Verilator and `4 DSP48E1`, and it
    lowers the mapped `Estimated number of LCs` to `47,802`, but the lane
    scorecard uses official CLB LUTs and those still worsen to `51,832` while
    FF only trims to `64,743`, so `L2 c_fc` micro-surgery is closed and the
    next fallback boundary is `mlp.c_proj`
- The untouched `L1 c_proj` redirect is not a mainline replacement for the frozen `L1 c_fc` proof:
  - the base mapped proof reaches `32,393` LUT / `50,864` FF and direct `abc9`
    improves that to `31,611` LUT / `50,864` FF while preserving Verilator and
    `4 DSP48E1`, but both still trail the accepted `29,778` LUT / `46,352` FF
    `c_fc` reference, so `c_proj` stays as a validated reserve fallback rather
    than the primary fit-first lane
- The direct `abc9` mapper variant is not enough to clear the lane:
  - it improves the accepted `L1` proof to `32,236` LUT, but that still misses
    the ceiling by `2,376`, and the same mapper slightly worsens `L0` to
    `32,478` LUT
- The staged `abc9` micro-flow is currently broken on the accepted `L1` kernel:
  - `task6-l1-c-fc-redirect-staged-abc9-utilization` fails at `stage8` with
    `ERROR: Module \`FDRE' is used with parameters but is not parametric!`, so
    that path is stopped after one failure
- The whole-class `ui64` buffer replacement path is exhausted for `L1`:
  - the strict one-slot, fall-through one-slot, and class-wide FIFO2 overrides
    all timed out the kernel-only Verilator proof, so the `20,725` LUT /
    `15,731` FF mapped result remains diagnostic only and the lane should not
    spend more slices on full-class buffer swaps
- A selective `ui64` buffer replacement is viable but still modest:
  - replacing only `handshake_buffer165` trims mapped utilization to `33,020`
    LUT / `51,292` FF, and widening to the local `160..165` spine improves that
    to `32,808` LUT / `50,642` FF while keeping the kernel proof intact
  - combining that safe local spine with `abc9` improves again to `32,036` LUT
    while keeping `4 DSP48E1`, so the selective path is real and composable
  - extending one more hop into the immediate `173..182` branch-output fanout
    improves again to `31,309` LUT / `49,342` FF with `4 DSP48E1`
  - extending through the next downstream `185..192` ring improves again to
    `30,762` LUT / `48,302` FF with `4 DSP48E1`
  - extending through the connected `213..219` mux-return ring improves again
    to `30,320` LUT / `47,392` FF with `4 DSP48E1`
  - at only `460` LUT over the ceiling, the next step should be chosen
    deliberately rather than by another blind local expansion, because the
    marginal gains are now tapering
- The first deliberate post-ring-3 control/merge hotspot is not a better fit
  point:
  - replacing `handshake_buffer194`, `handshake_buffer220`,
    `handshake_buffer229`, and `handshake_buffer237` on top of the frozen
    ring-3 region still passes Verilator and keeps `4 DSP48E1`, but mapped
    `abc9` lands at `30,360` LUT / `47,384` FF, which is `40` LUT worse than
    the frozen `30,320` LUT point
  - freeze `task6-l1-c-fc-redirect-index-ring3-fifo2-abc9` as the current
    reference and stop widening this local control/merge path
- The first local `ui1` selector-buffer trim is also not a better fit point:
  - replacing only `handshake_buffer263`, the local compare result feeding
    `handshake_fork49`, still passes Verilator and keeps `4 DSP48E1`, but
    mapped `abc9` lands at `30,370` LUT / `47,388` FF, which is `50` LUT worse
    than the frozen `30,320` LUT point
  - treat this as another negative hotspot signal rather than a new lane
    direction
- The first local `fork49` statevec helper is also not a better fit point:
  - replacing only `handshake_fork49`, the five-way local `ui1` selector fork
    after `handshake_buffer263`, still passes Verilator and keeps `4 DSP48E1`,
    but mapped `abc9` lands at `30,358` LUT / `47,392` FF, which is `38` LUT
    worse than the frozen `30,320` LUT point
  - this is the third deliberate post-ring-3 hotspot miss, so move on from
    local hotspot surgery rather than stacking more buffer or fork micro-swaps
- The first selector-cluster helper is also not a better fit point:
  - replacing the local `buffer255 -> handshake_fork46` selector leg with one
    helper still passes Verilator and keeps `4 DSP48E1`, but mapped `abc9`
    lands at `30,358` LUT / `47,392` FF, tying the `fork49` statevec miss and
    still losing by `38` LUT to the frozen `30,320` LUT point
  - this closes the selector-control tree as a fit lever; the next probe should
    move to a different non-selector area of the `L1` kernel
- The downstream post-branch `ui64` buffer cluster is the first productive
  non-selector lever after the selector tree closed:
  - replacing `handshake_buffer264`, `265`, `266`, `269`, `270`, and `271` on
    top of the frozen ring-3 reference still passes Verilator and keeps
    `4 DSP48E1`, while mapped `abc9` drops to `29,967` LUT / `46,612` FF
  - that trims `353` LUT and `780` FF versus the frozen `30,320` LUT /
    `47,392` FF point and leaves the lane only `107` LUT over the ceiling
- Extending the same post-branch fit lever through the immediate `ui64`
  out-buffers clears `L1`:
  - replacing `handshake_buffer279` and `280` on top of the first post-branch
    cut still passes Verilator and keeps external weights plus `4 DSP48E1`,
    while mapped `abc9` lands at `29,778` LUT / `46,352` FF
  - this is the first validated `L1` point under both the LUT and FF ceilings,
    so the next replay should move to `L2` rather than widening `L1` again
- Resolved blocker:
  - the first `task6-l0-gemv64` `sv` export failed until the model reused the
    baseline float extern wiring (`allowHwExterns`, per-file extern import, and
    `fpPrimsSv`)
  - the first `task6-l0-gemv64` flake build ignored the new simulation files
    until they were git-tracked, because the flake source snapshot omits
    untracked files
  - mapped `task6-l0-gemv64` utilization initially reported all zeros because
    `write_utilization_report.py` recursed into blackbox Xilinx primitive
    modules and counted only their `$specify*` internals until the script was
    fixed to treat blackbox modules as leaf cells
  - the first generalized `build_task_graph.py` attempt was still hardcoded to
    the `L1` `4 -> 16` tensor shapes until it was rewritten to derive weight
    and bias expectations from the selected candidate contract
  - the shared redirected-kernel testbench originally used a flat
    `TIMEOUT_CYCLES = 200000`, which was enough for `L1` but caused a false
    timeout on `L2` until the limit was scaled with total external traffic
