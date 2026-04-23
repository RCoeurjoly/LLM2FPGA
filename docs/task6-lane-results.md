# Task 6 StreamTensor Lite Lane Results

Date opened: 2026-04-22
Branch: `task6-streamtensor-lite`

## Active Scorecard

| Check | Threshold | Status |
| --- | --- | --- |
| DSP use | `DSP > 0` in the kernel or one-block-top Yosys stat | pass-L0/L1/L2 (`4 DSP48E1`) |
| Weight placement | packed or ROM-style external weights, not giant RTL constants | pass-L0/L1-pack/L1-kernel/L2-pack/L2-kernel |
| LUT ceiling | `<= 29,860` LUT | fail-L0/L1/L2 (`32,449` LUT / `32,236` LUT best validated `L1` / `50,235` LUT); diagnostic `ui64` buffer-lite reaches `20,725` LUT but fails Verilator |
| FF ceiling | `<= 59,720` FF | pass-L0/L1 fail-L2 (`46,736` FF / `51,296` FF / `65,523` FF) |
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
| Yosys stat for one-block top | `< 2 min` | n/a | pending |

## Frozen Ladder

| Rung | Artifact class | Model target | Status | Notes |
| --- | --- | --- | --- | --- |
| `L0` | synthetic `64x64` GEMV smoke | `task6-l0-gemv64` external-weight kernel | running | `yosys-stat`, Verilator, and mapped utilization now pass the DSP/FF proof, but direct `abc9` slightly worsened LUT (`32,478`), so the kernel still misses the ceiling |
| `L1` | TinyStories-derived single linear cutout | block-0 `mlp.c_fc` extracted from `tiny-stories-1m-representative-core-v64-h4` | running | kernel-only redirected proof now passes weight placement, Verilator, `yosys-stat`, and mapped DSP; direct `abc9` lowers mapped LUT from `33,116` to `32,236`, and a `ui64` buffer-lite diagnostic collapses fit to `20,725` LUT / `15,731` FF but times out the kernel proof |
| `L2` | reduced-vocab single-block replay | `tiny-stories-v1k-h64-l1` | running | kernel-only redirected proof now passes weight placement, Verilator, `yosys-stat`, and mapped DSP, but the mapped LUT and FF counts are both worse than `L1` |
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
| L1 staged `abc9` mapped utilization | `task6-l1-c-fc-redirect-staged-abc9-json` / `task6-l1-c-fc-redirect-staged-abc9-utilization` | experimental |
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
- The `ui64` buffer-lite override is not a valid `L1` drop-in:
  - both tested one-slot variants timed out the kernel-only Verilator proof, so
    the `20,725` LUT / `15,731` FF mapped result is diagnostic only, not an
    accepted fit proof
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
