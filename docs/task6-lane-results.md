# Task 6 StreamTensor Lite Lane Results

Date opened: 2026-04-22
Branch: `task6-streamtensor-lite`

## Active Scorecard

| Check | Threshold | Status |
| --- | --- | --- |
| DSP use | `DSP > 0` in the kernel or one-block-top Yosys stat | pass-L0/L1/L2 (`4 DSP48E1`) |
| Weight placement | packed or ROM-style external weights, not giant RTL constants | pass-L0/L1-pack/L1-kernel/L2-pack/L2-kernel |
| LUT ceiling | `<= 29,860` LUT | pass-L1 fail-L0/L2 (`32,449` LUT / `29,778` LUT best validated `L1` / `50,235` LUT); diagnostic `ui64` buffer-lite reaches `20,725` LUT but fails Verilator |
| FF ceiling | `<= 59,720` FF | pass-L0/L1 fail-L2 (`46,736` FF / `46,352` FF / `65,523` FF) |
| Verilator | kernel test passes | pass-L0/L1-kernel/L2-kernel |
| Micro-proof runtime | kernel Yosys stat completes in `< 30 s` | pass-L0/L1/L2 (`9.23 s` / `4.07 s` / `9.13 s`) |
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
| `L1` | TinyStories-derived single linear cutout | block-0 `mlp.c_fc` extracted from `tiny-stories-1m-representative-core-v64-h4` | running | kernel-only redirected proof now passes weight placement, Verilator, `yosys-stat`, and mapped DSP; the current reference is `task6-l1-c-fc-redirect-index-ring3-postbranch-outbuf-fifo2-abc9` at `29,778` LUT / `46,352` FF after the downstream post-branch `ui64` buffer clusters (`264..271` then `279..280`) proved to be the first non-selector lever that clears the `L1` LUT ceiling |
| `L2` | reduced-vocab single-block replay | `tiny-stories-v1k-h64-l1` | running | kernel-only redirected proof now passes weight placement, Verilator, `yosys-stat`, and mapped DSP; the repo one-block-top Yosys gate also completes in `99.26 s`, but the only measured mapped `L2` point is still the older kernel and remains worse than the current `L1` reference, so there is still no promotion to `L3` before replaying the new `L1` fit path on `L2` |
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
| L1 staged `abc9` mapped utilization | `task6-l1-c-fc-redirect-staged-abc9-json` / `task6-l1-c-fc-redirect-staged-abc9-utilization` | experimental |
| L2 one-block-top Yosys gate | `tiny-stories-v1k-h64-l1-selftest-top4-memory-yosys-json` | ready |
| Weight pack export | `scripts/task6/export_weights_pack.py` | ready |
| L1/L2 contract export | `scripts/task6/export_l1_contract.py` | ready |
| L1/L2 pack replay check | `scripts/task6/verify_l1_contract.py` | ready |
| Task-graph build | `scripts/task6/build_task_graph.py` | ready |
| Packed-weight artifacts | `artifacts/task6/weights_pack/<model-rung>/` | running |
| Contract artifacts | `artifacts/task6/streamtensor-lite/<rung>/<contract-dir>/` | running |
| Stage-local runner | `just task6-l0` through `just task6-l7` | planned |

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
