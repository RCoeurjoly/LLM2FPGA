# Task 6 Resource Usage Reduction Notes

This file is the working Task 6 note referenced from `AGENTS.md`. It is the
right place for Task 6 planning details while `docs/project-plan*` remain
reviewer-controlled.

## Current workspace snapshot

- Current branch: `task6`
- This branch currently contains the board/openXC7/matmul flow and the existing
  reviewer-facing docs, but it does not yet contain the TinyStories Task 3
  pipeline files that were present in other workspaces.
- Current hardware anchor in this repo:
  - board: `YPCB-00338-1P1`
  - FPGA: `XC7K480T`
  - there is already a documented board self-test pass in
    `deliverables/2d-fpga-bitstream.org`
- Known tooling context in this repo:
  - `flake.nix` already pins the openXC7 / nextpnr-xilinx path for
    `xc7k480tffg1156-1`
  - `docs/project-management.org` records prior nextpnr-xilinx segfault work,
    so Yosys-level resource evaluation and nextpnr viability should be tracked
    separately

### Durable baseline bundle

Use this copied baseline bundle for Task 6 comparisons:

- `artifacts/task6/baselines/tiny-stories-1m-baseline-float-selftest-all-memory-utilization`

Reason:

- it is copied out of `/nix/store`, so it survives `nix-collect-garbage`
- it is the stable reference bundle for strategy deltas in this branch

Expected baseline files:

- `summary.json`
- `summary.txt`
- `stat.json`

## Current execution program (2026-04-21)

This section is the live Task 6 operating contract. Use it to decide what to
run next, when to stop a lane, and what evidence must be recorded before a lane
earns more work.

### Goal and success bar

- Primary goal for the next 1-2 weeks:
  - produce a reproducible reduction in peak host memory pressure or mapped
    utilization relative to the copied baseline bundle above
- Primary success bar:
  - one lane produces a durable artifact bundle showing either:
    - lower peak memory / no OOM where baseline or a prior candidate OOMs, or
    - a better mapped resource result than the copied baseline bundle

### Operating rules

- Keep `task6` as the integration and notes branch.
- Run strategy work in separate worktrees or sibling branches derived from
  `task6`.
- Optimize for feedback-loop speed first:
  - prefer the smallest representative core and cheapest measurement artifact
    that still preserves relevant operator/structure coverage
  - prove that coverage with MLIR op stats before trusting the smaller core for
    Task 6 decisions
  - replay only the promising changes on the larger representative/full lanes
- Treat external memory / DDR3 as an allowed first-class strategy, not only as
  a fallback.
- Compare every result against
  `artifacts/task6/baselines/tiny-stories-1m-baseline-float-selftest-all-memory-utilization`.
- Record every evidence milestone in this file immediately after it lands.
- Treat every recorded Task 6 experiment as a checkpointed unit:
  - once its docs and artifact bundle are written, commit and push the branch
    before starting the next experiment
- Fast-prune a lane after 1-2 measured attempts unless it exposes a new,
  narrower bottleneck that is worth isolating.

### Evidence contract for every lane

Every active lane must leave behind:

- the exact flake output or command that was run
- the first failing or last completed stage
- the main output artifact path(s)
- the baseline delta being claimed
- the continue / prune decision

Minimum metrics to record when available:

- wall-clock time
- peak host memory or the best available proxy
- Yosys / mapped utilization delta
- size or count signals that explain the change
  - e.g. RTLIL size, selected module count, eligible memory bits

Preferred capture helper for future runs:

- `scripts/pipeline/monitor_build.sh`
  - wrap long `nix build ... -L` runs with it when host-RAM evidence matters
  - it records the raw build log, per-process `VmRSS` / `VmHWM` samples, and a
    short summary with the last emitted stage banner

### Active lane queue

0. Fast-iteration lane: representative TinyStories core
   - branch/worktree: `task6`
   - package family:
     - `tiny-stories-1m-representative-core-*`
     - `tiny-stories-1m-representative-core-selftest-all-memory-*`
   - current milestone:
     - use a reduced GPT-Neo core derived from the TinyStories-1M config to
       preserve the same model family and operator mix while cutting vocabulary
       table size and layer count for faster compile/debug cycles
   - current profile:
     - `vocab_size = 32`
     - `num_layers = 2`
     - `hidden_size = 2`
     - `num_heads = 1`
     - `max_position_embeddings = 4`
     - `window_size = 2`
   - intended use:
     - frontend/lowering iteration
     - stage-splitting experiments
     - quick checks of whether a flow or patch changes the shape of the
       synthesized design before spending hours on the full baseline
   - guardrail:
     - do not treat this as a replacement baseline; every real Task 6 claim
       still has to come back to the copied baseline bundle
     - treat MLIR op coverage against the baseline as the admission check for
       this lane; if the smaller core drops baseline ops/dialects, grow it back

1. Main lane: narrowed external-memory shell
   - branch/worktree: `task6` until the next structural branch split is needed
   - package family:
     - `tiny-stories-1m-baseline-float-selftest-top34-memory-*`
   - current milestone:
     - completed on 2026-04-28: the fixed `top34-memory` path clears
       `stage6a`, clears `stage8b`, completes `stage9 write_json`, and emits a
       final utilization bundle
     - current result is a toolchain-frontier win but a mapped-resource loss
       versus the copied all-memory baseline
   - continue only if:
     - a follow-up explains or removes the LUT growth from the current
       blackbox shell, or materially changes the board-memory contract
   - prune only if:
     - the next slice only widens externalization or adds a DDR3 controller
       without first addressing the current shell/resource inflation

2. Side lane A: quantization viability
   - preferred branch/worktree: `task6-quant`
   - package family:
     - `tiny-stories-1m-*`
   - current milestone:
     - classify the three quantized routes by earliest completed stage and keep
       investing only in the route that produces the best measurable shell
       reduction
   - current default:
     - continue only with `tiny-stories-1m` unless patched import work changes
       the frontier

3. Side lane B: alternate-dialect substitution
   - preferred branch/worktree:
     - `task6-alt-dialect`
   - current milestone:
     - identify one or two concrete non-handshake lowering families worth
       testing instead of treating "another dialect" as an open-ended research
       bucket
   - required first output:
     - candidate shortlist with:
       - candidate dialect / lowering family
       - plausible insertion point from the current `cf` or nearby pipeline
       - expected benefit versus handshake
       - expected patch burden
       - first narrow experiment to run
   - entry guardrail:
     - do not start by rewriting the whole flow
     - start by proving one alternative is concrete enough to compare against
       the current handshake path

4. Side lane C: structural lowering / eqmap / LSQ
   - preferred branch/worktrees:
     - `task6-eqmap`
     - `task6-lsq`
   - entry condition:
     - only after the main lane isolates a residual structural bottleneck that
       looks larger than a pure late-Yosys mapping problem
   - required evidence:
     - changed stage, changed RTLIL size or module count, and whether the
       mapped bottleneck moved

5. Side lane D: board RAM interface path
   - preferred branch/worktree: `task6-board-ram`
   - entry condition:
     - once the top4-memory shell numbers are stable enough to justify a board
       contract
   - required evidence:
     - what memories move off-chip, what stays on-chip, and whether the
       remaining shell becomes materially more synthesis-tractable

6. Side lane E: DOCC / feedback-driven compiler path
   - preferred branch/worktree:
     - `task6-docc`
   - current milestone:
     - decide whether Daisytuner DOCC is viable here as an actual toolchain
       lane, or whether only its SDFG plus feedback-loop ideas are reusable for
       Task 6
   - required first output:
     - a viability memo with:
       - what part is usable locally
       - what part depends on Daisy Cloud or external runners
       - what input artifact from this repo could feed the lane first
       - what measurable Task 6 question this lane would answer
   - entry guardrail:
     - do not start with account setup or cloud integration
     - first prove the lane can answer a Task 6 bottleneck question faster or
       better than the existing pipeline

7. Reference lanes only
   - `task6-paper-review`
   - `task6-moe`
   - use these only to justify a specific next experiment in another active
     lane

### Stage A import status

Status on 2026-04-16:

- Stage A has been imported into `task6`.
- The baseline TinyStories files, core pipeline library/scripts, CIRCT patch
  stack, and trimmed model registry are now present in this branch.
- Lightweight Nix evaluation confirms these package names resolve:
- `tiny-stories-1m-baseline-float-sv`
- `tiny-stories-1m-baseline-float-yosys.stat`
- `matmul-sv`
- Later LSQ/external-memory imports are still intentionally deferred.

### Stage B import status

Status on 2026-04-16:

- Stage B has been imported into `task6`.
- The three full-model TinyStories quantization routes are now wired:
  - `tiny-stories-1m`
  - `tiny-stories-1m-dynamic-int8`
  - `tiny-stories-1m-torchao`
- Optional patched `torch-mlir` support is exported separately while the default
  flow still points to unpatched `torch-mlir`.
- TorchAO-enabled Python environments are exported for later experiments.
- The larger quantization reproducer/debug adapter zoo under `src/` is still
  intentionally deferred.

Lightweight Nix evaluation currently resolves:

- `tiny-stories-1m-torch`
- `tiny-stories-1m-dynamic-int8-torch`
- `tiny-stories-1m-torchao-torch`
- `torch-mlir-patched`
- `python-with-tiny-stories-torchao`

### Donor branches that exist in this repo

- `origin/task3`
  - contains `TinyStories/`, `nix/models.nix`, `nix/pipeline.nix`, and the
    baseline pipeline scripts
- `origin/task3-rfp-sandbox`
  - contains TinyStories quantization adapters plus the LSQ handshake path and
    external-memory helper scripts
- `origin/task3-hybrid-sandbox-toolchain`
  - contains TinyStories quantization adapters plus `sv_memory_inventory.py`,
    `mlir_op_profile.py`, and Yosys-report helpers

User clarification:
- `origin/task3-hybrid-sandbox-toolchain` is intended as a landing branch for
  Task 3, with AI-generated content and experimental quantization work removed
  or reduced
- for Task 6, that makes it a weaker primary donor for quantization follow-up
  even if it still contains useful helpers

Current recommendation:
- prefer `task3-experiments` as the quantization donor branch if it exists or
  can be recovered/fetched into this clone
- use `origin/task3-rfp-sandbox` as the fallback donor for quantization, LSQ,
  and external-memory experiments if `task3-experiments` is not currently
  available here
- treat `origin/task3-hybrid-sandbox-toolchain` mainly as a reference for
  cleaner landing-state tooling and measurement helpers, not as the primary
  experimental branch

Availability update:
- `task3-experiments` is now available in this clone as both
  `origin/task3-experiments` and local branch `task3-experiments`

Implication:
- the Task 6 note must distinguish between work that can be prepared now in
  this branch and work that depends on later importing Task 3 artifacts

### Branch comparison result (2026-04-16)

Current conclusion after direct comparison:

- `task3-experiments` is the best primary donor for Task 6.
- `origin/task3-rfp-sandbox` is the best fallback donor for specific LSQ and
  external-memory pieces.
- `origin/task3-hybrid-sandbox-toolchain` is useful mainly as a reference for
  cleaner landing-state tooling and measurement helpers.

Why `task3-experiments` wins:

- It is the most recent Task 3 branch tip in this family.
- Relative to `origin/task3-rfp-sandbox`, it adds the later Task 3 hybrid
  snapshot plus the final Task 3 deliverable-gate updates.
- It keeps the quantization-heavy `torch-mlir` patch stack and the larger
  quantized model registry needed for Task 6 follow-up.
- In `nix/models.nix`, it explicitly repositions the work so
  `tiny-stories-1m-baseline-float` is the reviewer-facing Task 3 path while the
  quantized TinyStories routes are retained for follow-up experiments.
- It includes the profiling and measurement helpers that were absent from
  `origin/task3-rfp-sandbox`, notably:
  - `scripts/pipeline/mlir_op_profile.py`
  - `scripts/pipeline/sv_memory_inventory.py`
  - `scripts/pipeline/write_yosys_stat_report.py`

Why `origin/task3-rfp-sandbox` is still relevant:

- It already contains the LSQ handshake path and
  `scripts/pipeline/externalize_large_memories.py`.
- If Task 6 needs only the LSQ/external-memory pieces without importing the
  full experiments branch, this is the leaner fallback donor.

Why `origin/task3-hybrid-sandbox-toolchain` is not the primary donor:

- User clarification: it is a landing branch for Task 3 cleanup, with
  experiment-heavy quantization work reduced or removed.
- Direct diff shows `task3-experiments` is effectively hybrid plus the
  experiment-oriented model/pipeline choices and final Task 3 gate updates.

Practical rule:

- For Task 6 execution work, start from `task3-experiments`.
- Pull isolated helper ideas from `origin/task3-rfp-sandbox` or
  `origin/task3-hybrid-sandbox-toolchain` only when they are clearly narrower
  than importing the entire experiments branch.

### Minimal staged import set from `task3-experiments`

Goal:
- import only the files needed to re-establish the TinyStories baseline and the
  three full-model quantization routes for Task 6
- defer debugger helpers, reviewer docs, and board selftest extras until they
  are actually needed

Important finding:
- the full-model TinyStories quantization adapters are self-contained
- that means Task 6 does *not* need to import the large `src/native_fx_*`,
  `src/pt2e_static_quant_*`, and `src/torchao_*` reproducer zoo up front just
  to run the three full-model TinyStories routes

#### Stage A: baseline-float bootstrap

Import first:

- selective `flake.nix` hunks for:
  - TinyStories snapshot wiring
  - `nix/pipeline.nix` and `nix/models.nix` integration
  - `scripts/compile-pytorch.py`
  - `rtl/fp/circt_fp_primitives.sv`
  - the baseline-float model outputs and Yosys-stat packaging
- `torch-mlir.nix`
- `nix/pipeline.nix`
- `scripts/compile-pytorch.py`
- `TinyStories/model_adapter.py`
- `rtl/fp/circt_fp_primitives.sv`
- core pipeline scripts:
  - `scripts/pipeline/common.sh`
  - `scripts/pipeline/torch_to_linalg.sh`
  - `scripts/pipeline/linalg_to_cf.sh`
  - `scripts/pipeline/cf_stats.sh`
  - `scripts/pipeline/cf_to_handshake.sh`
  - `scripts/pipeline/handshake_to_hs_ext.sh`
  - `scripts/pipeline/hs_ext_to_hw0.sh`
  - `scripts/pipeline/hw0_to_hw.sh`
  - `scripts/pipeline/hw_to_hw_clean.sh`
  - `scripts/pipeline/hw_clean_to_sv.sh`
  - `scripts/pipeline/sv_to_il.sh`
  - `scripts/pipeline/sv_to_yosys_stat.sh`
  - `scripts/pipeline/sv_memory_inventory.py`
  - `scripts/pipeline/write_yosys_stat_report.py`
- CIRCT patch wiring and the referenced patch files currently used by the known
  working baseline-float path in `task3-experiments`

Do not import yet:

- `docs/project-plan*`
- reviewer-facing Task 3 deliverables/docs
- `scripts/dev/*`
- selftest wrapper generation and board-specific TinyStories top-level files
- the torch-mlir quantization patch stack
- quantization reproducer adapters under `src/`

Why this stage exists:
- re-establish the known `tiny-stories-1m-baseline-float` path first
- keep the first import focused on "baseline reaches SV / IL / yosys-stat"

#### Stage B: full-model TinyStories quantization routes

Import second:

- selective `flake.nix` and `nix/models.nix` hunks for these full-model routes:
  - `tiny-stories-1m`
  - `tiny-stories-1m-dynamic-int8`
  - `tiny-stories-1m-torchao`
  - `tiny-stories-1m-pt2e-static` alias, only if keeping the alias is useful
- TinyStories adapters:
  - `TinyStories/model_adapter_dynamic_quant.py`
  - `TinyStories/model_adapter_pt2e_static_quant.py`
  - `TinyStories/model_adapter_torchao.py`
- Python environment wiring from `flake.nix`:
  - `torchao`
  - `pythonWithTorchAO`
  - `pythonWithTinyStories`
  - `pythonWithTinyStoriesTorchAO`
- `torch-mlir.nix` support for optional quantization patches
- `patches/torch-mlir-task3-rfp/*.patch`

Do not import yet:

- the full reproducer zoo in `src/`
- native-FX experimental helpers
- task3 reviewer docs and milestone helpers

Why this stage exists:
- it enables the three real Task 6 quantization candidates without dragging in
  every local debugging artifact from `task3-experiments`

#### Stage C: LSQ and external-memory track

Import only when starting the handshake/minimization experiments:

- `scripts/pipeline/cf_to_handshake_lsq.sh`
- `scripts/pipeline/externalize_large_memories.py`
- selective `flake.nix` support for LSQ and external-memory plan outputs

Optional at the same time:

- `scripts/pipeline/filter_rtlil_modules.py` if a later flow actually needs it

Why this stage exists:
- LSQ and external-memory are Task 6-specific optimization tracks, not required
  just to re-establish the baseline and quantization candidates

#### Stage D: measurement and profiling helpers

Import when beginning side-by-side strategy comparison:

- `scripts/pipeline/mlir_op_profile.py`
- `scripts/pipeline/sv_memory_inventory.py` if not already imported in Stage A
- `scripts/pipeline/write_yosys_stat_report.py` if not already imported in
  Stage A

Why this stage exists:
- these files are high-value for Task 6 comparison, but they are not required
  to prove the first baseline build path

#### Stage E: quantization debug reproducers

Import only if the full-model quantization routes fail and the failure needs to
be reduced:

- `src/pt2e_quant_linear_adapter.py`
- `src/pt2e_static_quant_*`
- `src/torchao_*`
- `src/native_fx_*`
- `src/matmul_adapter.py`
- any matching `nix/models.nix` entries for the reproducer models

Why this stage exists:
- these files are valuable for isolating first failing operators
- they are *not* needed to attempt the three full-model TinyStories
  quantization routes

#### Stage F: selftest and board-handoff extras

Import only once a candidate is worth packaging for Task 4/5-style execution:

- `scripts/pipeline/gen_tiny_stories_selftest_top.py`
- `fpga/constraints/tiny_stories_selftest.xdc`
- selective `flake.nix` selftest and all-memory shell outputs

Why this stage exists:
- these files are for packaging and board-facing validation, not early Task 6
  minimization work

#### Explicitly defer these from the first import

- `docs/task3-*.org`
- `docs/task3-*.md`
- `deliverables/3*.org`
- `codex-night-prompt.txt`
- `scripts/dev/*`
- `AGENTS.md` from `task3-experiments`

#### First import recommendation

If doing the first cherry-pick/import pass now, aim for exactly:

1. Stage A
2. Stage B
3. Stage C only if LSQ or external-memory is the immediate next experiment

That gives Task 6:

- the baseline-float reference path
- the three full-model quantization candidates
- the option to add LSQ/external-memory next

without importing the entire experiments branch or all reviewer-facing docs.

## Current intent

Treat Task 6 as an execution task, not only as a survey.

- Primary objective: reduce resource usage enough that at least one real LLM
  configuration plausibly fits the target board envelope.
- Secondary objective: produce a reproducible comparison of strategies,
  including negative results, so dead ends are documented.
- If a candidate fits the board envelope and has no unresolved stubs or hidden
  blackboxes, stop broad exploration and hand off to board execution /
  equivalence testing.

## Overnight result snapshot (2026-04-17)

Results now exist in the strategy lanes and should guide the next round of
execution.

Quantization lane:

- `task6-quant` recorded results in `docs/task6-lane-results.md`.
- `tiny-stories-1m` is currently the strongest quantization route and is
  `conditional`.
- `tiny-stories-1m-dynamic-int8` is `reject` on the current default unpatched
  `torch-mlir` path.
- `tiny-stories-1m-torchao` is `reject` on the current default unpatched
  `torch-mlir` path.
- The strongest next quantization follow-up is to push the surviving
  `tiny-stories-1m` route farther downstream and classify whether it actually
  changes the LUT/FF story or only changes representation.

Board RAM lane:

- `task6-board-ram` recorded results in `docs/task6-lane-results.md`.
- The strongest DDR3 candidate is to move the four `3216448 x 32` vocab-sized
  tables off-chip first.
- Those four tables account for `411,705,344` bits (`49.08 MiB`), about `95.1%`
  of the modeled memory bits from the prior all-memory inventory.
- This is the narrowest credible DDR3 experiment and is currently
  `recommended`.

Paper-review lane:

- `task6-paper-review` recorded findings in `docs/task6-literature-findings.md`.
- `StreamTensor` is the strongest direct paper lead because it targets
  intermediate-memory materialization and streaming/fusion, which matches the
  local "all LUT/FF, zero BRAM/DSP" failure mode better than throughput-only
  ideas.
- `FlightLLM`, `AccLLM`, `TerEffic`, and `Hummingbird` are the best adaptable
  follow-ons.
- `LUT-LLM` is low priority for the current branch.

MoE lane:

- `task6-moe` recorded findings in `docs/task6-moe-feasibility.md`.
- Adapting TinyStories 1M into MoE is not currently a meaningful Task 6 path.
- MoE should remain only as a narrow side experiment with an existing small
  PyTorch MoE model, and only if it can be paired quickly with expert
  externalization or another clear off-chip resource-saving mechanism.

## Practical priority order (2026-04-17)

This priority order supersedes the earlier broad "explore everything equally"
stance.

1. Board RAM first: externalize the four giant vocab-sized tables to DDR3.
   Reason: this is the narrowest change with the largest modeled memory impact,
   and it does not require proving new quantized operators first.

2. Quantization second: continue only with `tiny-stories-1m`.
   Reason: it is the only quantized route that clearly gets past frontend
   lowering today. Do not spend more time on `dynamic-int8` or `torchao`
   unless the default compiler path changes or a narrow patched import becomes
   the explicit next experiment.

3. StreamTensor-style streaming/fusion third.
   Reason: the paper review strongly suggests the local failure mode is
   over-materialized intermediate storage in fabric. This is the strongest
   paper-driven direct lead after the DDR3 cut and the surviving quantized
   route are measured.

4. DSP-first kernel shift fourth.
   Reason: the board still has `1920` idle DSPs while the baseline uses
   `0` DSP and explodes in LUT/FF, so a targeted arithmetic shift out of fabric
   remains attractive after the simpler memory moves are classified.

5. LSQ and handshake alternatives fifth.
   Reason: LSQ is still worth keeping alive, but it should follow evidence that
   handshake/control structure is a dominant residual cost after the higher
   leverage memory steps above.

6. MoE last.
   Reason: it is promising in the abstract, but for this repo it is a model
   selection / architecture feasibility track, not a direct reduction path for
   the current TinyStories baseline.

## Board-RAM packaging update (2026-04-19)

Verification completed today:

- `tiny-stories-1m-baseline-float-selftest-all-memory-utilization` rebuilds in
  this branch and its generated `summary.json` / `stat.json` match the copied
  baseline bundle at
  `artifacts/task6/baselines/tiny-stories-1m-baseline-float-selftest-all-memory-utilization`
  byte-for-byte.
- The all-memory externalization plan still confirms the same dominant target:
  `326` eligible handshake-memory modules totaling `433,040,010` bits, with
  the top four modules accounting for `411,705,344` bits (`49.08 MiB`), about
  `95.1%` of the eligible memory bits.

New package family added for the narrower DDR3-first experiment:

- `tiny-stories-1m-baseline-float-selftest-top4-memory-top`
- `tiny-stories-1m-baseline-float-selftest-top4-memory-model-opt-il`
- `tiny-stories-1m-baseline-float-selftest-top4-memory-model-shell-il`
- `tiny-stories-1m-baseline-float-selftest-top4-memory-external-memory-plan`
- `tiny-stories-1m-baseline-float-selftest-top4-memory-json`
- `tiny-stories-1m-baseline-float-selftest-top4-memory-yosys-json`
- `tiny-stories-1m-baseline-float-selftest-top4-memory-utilization`

Current semantics:

- these outputs externalize only the largest four handshake memory modules from
  the baseline-float selftest shell
- the current selected modules are `\handshake_memory_out_f32_id342`,
  `\handshake_memory_out_f32_id341`, `\handshake_memory_out_f32_id340`, and
  `\handshake_memory_out_f32_id18`
- each of those modules is `3216448 x 32` bits (`102,926,336` bits each)
- the residual eligible memory tail after removing those four modules is
  `21,334,666` bits (`2.54 MiB`)
- the largest remaining tail candidates are:
  - one `131072 x 32` table: `4,194,304` bits
  - one `50257 x 32` table: `1,608,224` bits
  - twenty `16384 x 32` tables: `524,288` bits each

Status:

- the selector/reporting part of this lane is verified, including the new
  reproducible `*-external-memory-plan` and `*-model-shell-il` outputs
- the heavier narrowed-shell utilization build is the next measurement to
  record once the new derivation completes
- the narrowed external-memory bundles now use a split fine-stage flow so the
  bottleneck can be isolated without changing the stock all-memory baseline
  path
- current observed bottleneck: the narrowed-shell mapped-utilization build
  reaches `stage4`, emits a `2.4G` RTLIL artifact, clears `stage5a` through
  `stage5d`, and currently spends a long time in the targeted `stage6a`
  `cells_map` techmap pass

Follow-up update (2026-04-20):

- the earlier monolithic `stage6` (`synth_xilinx -run map_cells:map_cells`)
  path drove memory close to host exhaustion and was killed by the daemon
- the current narrowed-path `stage6a` replaces that with a targeted
  `techmap -map +/techmap.v -map +/xilinx/cells_map.v` over only modules that
  still contain internal `$...` cells
- the live `stage6a` run is holding around `9.48 GiB` RSS instead of the
  earlier near-OOM behavior, so the split is materially reducing peak memory
  pressure even though the derivation has not finished yet
- the next flake snapshot also splits the later `map_luts:check` block into
  persisted `stage8a`..`stage8h` sub-stages (`opt_expr`, `abc`, `clean`,
  targeted `ff_map`, `xilinx_srl`, targeted `lut_map`, `xilinx_dffopt`,
  `opt_lut_ins`) for narrowed external-memory bundles only
- baseline-safe behavior is preserved: the stock all-memory bundle still uses
  the original monolithic `synth_xilinx` late stages, and the copied baseline
  bundle remains the comparison reference

Implementation follow-up later on 2026-04-20:

- `mkSynthStageTargetedTechmapIl` originally emitted one `techmap` invocation
  per selected module using a `cd <module>; techmap ...; cd ..` loop.
- Inspection of the cached narrowed-shell `stage5d` input shows that the later
  `stage6a` selector still touches `472` modules, so the per-module loop was
  multiplying `techmap` overhead even after narrowing the memory set.
- The helper now builds one explicit module selection (`select -none` plus
  repeated `select -add <module>`) and runs a single `techmap ...` pass over
  that selection before restoring full-design selection for `write_rtlil`.
- The helper now also logs the selected-module count per stage so future runs
  show how wide each targeted pass really is.
- A fresh narrowed rebuild has already validated the new helper through
  `stage5c`, which reports `17` selected modules for the `arith_map` pass.
- The full narrowed utilization rebuild is still running past `stage5d`, so the
  next measurement to capture is whether the rewritten single-pass `stage6a`
  materially reduces wall-clock time in addition to the earlier RSS reduction.

Integration follow-up on 2026-04-21:

- The first 2026-04-21 narrowed-shell rebuild did not reach Yosys. It failed in
  the patched `circt` dependency during `checkPhase`, after CIRCT compiled
  successfully, with `18` `HandshakeToHW`-area regression failures.
- The immediate cause was the local CIRCT patch stack in `flake.nix`, not a new
  Task 6 OOM. A dry-run against the pinned `RCoeurjoly/circt` `task3` source
  showed that the older patches `0003`, `0004`, `0005`, `0008`, `0009`,
  `0013`, `0014`, and `0015` were already present upstream.
- Inspection of `0013-handle-memref-model-io-and-cache-submodule-lookups.patch`
  showed that it already supersedes the earlier `0010`..`0012`
  `FuncOpConversionPattern` / `HandshakeToHW` legality changes. Reapplying
  `0010`..`0012` on top of that source is what broke the `HandshakeToHW`
  regression tests.
- The active CIRCT patch stack is now reduced to the two patches that still
  look genuinely unapplied in this source snapshot:
  - `0006-add-lsq-memory-lowering.patch`
  - `0007-lower-lazy-fork-to-hw.patch`
- Continue decision:
  - keep the main narrowed-shell lane active
  - current gate is verifying that the reduced CIRCT stack clears `checkPhase`
    and allows the top4-memory utilization build to reach the actual Task 6
    staged flow again

Recovered side-lane status on 2026-04-21:

- Quant lane (`task6-quant`):
  - existing lane note:
    - `docs/task6-lane-results.md` in the `task6-quant` worktree records the
      latest measured classification from 2026-04-17
  - strongest route so far:
    - `tiny-stories-1m` remains the only quantized full-model route that has
      clearly reached past frontend export in this repo, with `cf-stats` as the
      farthest confirmed successful stage
  - current rejects:
    - `tiny-stories-1m-dynamic-int8` fails at `torch` on both the unpatched and
      lane-local patched `torch-mlir` path with the same illegal
      `torch.operator` legalization failure in the GPT-Neo `torch.nn.Linear`
      path
    - `tiny-stories-1m-torchao` also fails at `torch` with an illegal
      `torch.operator` rooted in `torch.nn.Embedding`
  - continue decision:
    - keep only `tiny-stories-1m` active for future quant follow-up
    - freeze `dynamic-int8` and `torchao` unless importer work changes the
      frontier materially

- Board-RAM lane (`task6-board-ram`):
  - existing lane note:
    - `docs/task6-lane-results.md` in the `task6-board-ram` worktree records
      the current board-facing recommendation from 2026-04-17
  - strongest candidate:
    - move the four `3216448 x 32` vocab-sized tables off-chip first
    - those four modules account for `411,705,344` modeled bits (`49.08 MiB`),
      about `95.1%` of the eligible memory bits in the prior all-memory
      inventory
  - prior shell evidence:
    - the broader all-memory threshold `>= 131072` bits reduced LUTs from
      `40,416,086` to `34,950,553` (`-5,465,533`, about `-13.5%`) while FFs
      stayed flat
  - continue decision:
    - keep this lane ready as the next architecture candidate once the current
      top4-memory shell run lands, because it already matches the same dominant
      memory picture

- Structural lanes:
  - `task6-eqmap` and `task6-lsq` already exist as separate worktrees, but they
    currently carry lane instructions rather than a newer measured result
  - keep both lanes parked until the main narrowed-shell run either completes
    or isolates a blocker that still looks structural after memory removal

- Alternate-dialect lane (`task6-alt-dialect`):
  - current lane status:
    - dedicated worktree created on 2026-04-21 to own non-handshake lowering
      exploration separately from generic lowering/LSQ experiments
  - current milestone:
    - identify one or two concrete dialect/lowering families that could replace
      the current handshake-centered path for a useful subset of the flow
  - current guardrail:
    - this lane is not allowed to become an unbounded "survey MLIR" thread
    - it must quickly narrow to a shortlist with a first real experiment
  - continue decision:
    - keep this lane in candidate-identification mode until the shortlist is
      written down and one first experiment is concrete enough to implement

- DOCC lane (`task6-docc`):
  - current lane status:
    - dedicated worktree created on 2026-04-21 to evaluate the FOSDEM 2026
      DOCC / Daisytuner idea as a Task 6 strategy lane rather than leaving it
      in paper-review limbo
  - current milestone:
    - determine whether this is a real executable lane in the current repo, or
      mainly a source of reusable SDFG / benchmarking / feedback-loop ideas
  - current guardrail:
    - reject any version of this lane that immediately depends on external
      cloud setup before it produces a concrete Task 6 measurement plan
  - continue decision:
    - keep this lane in viability-check mode until it names one concrete first
      artifact and one Task 6 question it can answer better than the stock flow

Live narrowed-shell rebuild update later on 2026-04-21:

- The repaired `tiny-stories-1m-baseline-float-selftest-top4-memory-utilization`
  rebuild is back in the staged Yosys flow for this branch.
- Build-log stages confirmed so far in this specific rerun:
  - `stage1 synth_xilinx begin:prepare`
  - `stage2 synth_xilinx coarse:map_memory`
  - `stage3 opt -fast -full`
  - `stage4 targeted memory_map`
  - `stage5a fine opt -full`
- Process sampling from the live Yosys child shows:
  - the `stage2`-era process completed after reaching about `20.9 GiB`
    `VmHWM`
  - a later live Yosys process, after the build log had already advanced into
    the post-`stage4` band, reached about `25.1 GiB` `VmHWM` while still
    running on CPU
- What is confirmed versus inferred:
  - confirmed from the build log: the rerun has cleared `stage5a`
  - inferred from process sampling only: the current active bottleneck is now
    somewhere in the late `stage5*` to pre-`stage7` region, but the exact
    sub-stage is not yet logged because this rerun was launched without a
    dedicated stage/memory wrapper and the Yosys stages run `-q`
- Process improvement made during this investigation:
  - future long Task 6 builds should use
    `scripts/pipeline/monitor_build.sh <output-dir> -- nix build ... -L`
    so stage banners, sampled `VmRSS` / `VmHWM`, and the final summary are
    captured in one artifact bundle
- Continue decision:
  - keep the narrowed-shell main lane active
  - if this rerun still dies late, treat the next immediate task as capturing a
    wrapped rerun with the new monitor helper before opening a structural lane

Fast-iteration core update on 2026-04-21:

- Added a new reduced model lane for quicker iteration:
  - pipeline model key: `tiny-stories-1m-representative-core`
  - selftest bundle prefix:
    - `tiny-stories-1m-representative-core-selftest-all-memory-*`
- The new model is intentionally synthetic and deterministic:
  - it derives its config from the real TinyStories-1M GPT-Neo config
  - it keeps the same model family, float path, and attention-style mix
  - it uses random weights with `torch.manual_seed(0)` instead of the real
    checkpoint
- Current default trim profile:
  - `vocab_size = 1024` instead of `50257`
  - `num_layers = 1` instead of `8`
  - `hidden_size = 32` instead of `2048`
  - `num_heads = 4` instead of `16`
  - `max_position_embeddings = 64` instead of `2048`
  - `window_size = 32` instead of `256`
- Intended use:
  - get faster answers on export/lowering/stage-shape questions
  - test whether future flow changes move the same synthesis bottlenecks in a
    structurally similar design
  - provide a cheaper target for the new `monitor_build.sh` wrapper
- Guardrail:
  - do not compare this synthetic core directly against the copied baseline
    bundle as a success claim
  - use it to accelerate iteration, then replay promising changes on the real
    TinyStories baseline path
- First verification in this branch:
  - `nix build .#tiny-stories-1m-representative-core-cf-stats --no-link`
    completes successfully
  - frontend artifact sizes versus the full baseline-float path:
    - `torch.mlir`: `3,061,503` bytes versus `30,091,456` bytes
    - `cf.mlir`: `3,221,259` bytes versus `30,664,646` bytes
    - `cf.mlir` line count: `4,218` versus `14,545`
  - the reduced core still preserves the same broad operator families in
    `cf.mlir`, including `arith.addf`, `arith.mulf`, `math.exp`, `math.tanh`,
    `cf.br`, and `cf.cond_br`
  - interpretation:
    - this is already a meaningful frontend/lowering acceleration target
    - it is not yet evidence about late Yosys behavior, because the selftest
      utilization path has not been run for this reduced core yet

Representative-core simplification follow-up later on 2026-04-21:

- The earlier representative-core profile was still too expensive to be the
  fast iteration loop:
  - the `abc9` lane reached `stage7` with roughly `29 GiB` resident Yosys
    memory even after the narrowed-shell and restart-batched `stage6a`
    improvements
- Action taken:
  - simplified the default representative-core profile again in place
  - current effective preset is now:
    - `vocab_size = 1024`
    - `num_layers = 1`
    - `hidden_size = 32`
    - `num_heads = 4`
    - `max_position_embeddings = 64`
    - `window_size = 32`
  - updated both:
    - `TinyStories/model_adapter_representative_core.py`
    - `nix/models.nix`
- Intended interpretation:
  - this no longer tries to be a mid-scale structural proxy
  - it is the fast-loop Task 6 synthesis target
  - if changes work here, replay them on the older representative-core shape or
    directly on the real narrowed-shell baseline as needed
- First rerun on the smaller preset:
  - frontend validation:
    - `nix build .#tiny-stories-1m-representative-core-cf-stats --no-link`
  - monitored synthesis run:
    - `artifacts/task6/runs/representative-core-v2-selftest-top4-memory-json-20260421-225531`
  - current confirmed frontier:
    - `stage1 synth_xilinx begin:prepare`
    - `stage2 synth_xilinx coarse:map_memory`
  - live staged memory shape so far:
    - active staged Yosys around `1.1 GiB` RSS when first entering staged
      synthesis
    - later live `stage2` Yosys around `3.7 GiB` RSS after ~30 seconds of work

Late-stage blocker update later on 2026-04-21:

- The narrowed-shell full-baseline rerun has now been localized precisely:
  - `tiny-stories-1m-baseline-float-selftest-top4-memory-utilization` reaches
    `stage6a targeted techmap cells_map`
  - the builder then dies with exit code `137`
  - the logged stage banner reports `473` selected modules at that point
- Interpretation:
  - the active main-lane blocker is no longer CIRCT
  - it is the late Yosys `cells_map` step on the narrowed shell
  - this is a tighter and more actionable frontier than the earlier generic
    OOM picture
- First mitigation attempted in `task6`:
  - split `stage6a` into batches of `32` selected modules
  - initial implementation only batched the `select`/`techmap` calls inside one
    long-lived Yosys process
- Follow-up correction:
  - batching inside one Yosys process is unlikely to reclaim pass-local memory
    aggressively enough, because the whole design and pass state stay resident
  - `mkSynthStageTargetedTechmapIl` now supports restart-per-batch mode so the
    process can fully exit between `stage6a` chunks
  - `stage6a` is now configured with:
    - `batchSize = 32`
    - `restartPerBatch = true`
- Fast-loop validation in progress:
  - current command family:
    - `tiny-stories-1m-representative-core-selftest-top4-memory-json`
  - current monitored run directory:
    - `artifacts/task6/runs/representative-core-selftest-top4-memory-json-restart-20260421-181333`
  - purpose:
    - confirm the restart-per-batch `stage6a` path is functionally valid on the
      representative core before spending another full-baseline run
- Monitoring update:
  - `monitor_build.sh` plus
    `MONITOR_GLOBAL_PGREP_PATTERN='default-builder.sh|yosys -q -s run.ys'`
    now captures the builder-side Yosys worker for daemonized Nix builds
  - the live representative-core `stage2` Yosys process has already reached
    about `6.45 GiB` `VmHWM` in this wrapped run
- Continue decision:
  - if the representative-core split path clears `stage6a`, replay the new
    restart-per-batch implementation on the full baseline narrowed-shell lane
  - if it still fails before or during `stage6a`, inspect batch semantics or
    reduce batch size further before launching another expensive full run

Restart-batched validation follow-up later on 2026-04-21:

- The first representative-core validation run against the new restart-per-batch
  path did reach `stage6a`, but failed for an implementation bug rather than a
  synthesis limit:
  - monitored run:
    - `artifacts/task6/runs/representative-core-selftest-top4-memory-json-restart-20260421-181333`
  - confirmed stages:
    - `stage1`
    - `stage2`
    - `stage3`
    - `stage4`
    - `stage5a`
    - `stage5b`
    - `stage5c`
    - `stage5d`
    - `stage6a targeted techmap cells_map`
  - failure cause:
    - malformed shell heredoc in the newly added restart-per-batch builder
      fragment
    - not a Yosys OOM and not a semantic hardware-lowering failure
- Follow-up fix:
  - replaced the nested restart-loop heredocs in `mkSynthStageTargetedTechmapIl`
    with `printf`-based `run.ys` generation so the staged builder script is no
    longer sensitive to indentation of nested `EOF` markers
- Second validation run after the fix:
  - monitored run:
    - `artifacts/task6/runs/representative-core-selftest-top4-memory-json-restart-fix-20260421-184404`
  - current confirmed behavior:
    - the run now re-enters `stage6a` cleanly
    - it emits per-batch banners
    - it has progressed through at least batch `6/8`
  - interpretation:
    - restart-per-batch `stage6a` is now real, not just syntactically present
    - the representative-core lane no longer dies immediately at the start of
      `stage6a`
    - each new Yosys worker restarts with a much lower RSS than the prior
      batch's high-water mark, which is the intended memory-shaping behavior
  - observed memory shape from the wrapped run:
    - earlier batches climbed into the low `3.3 GiB` range
    - later live batches have reached about `7.1 GiB` `VmRSS` / `VmHWM`
      without an immediate kill
- Continue decision:
  - keep the representative-core validation run active until it either clears
    `stage6a` or fails with a real synthesis/resource limit
  - if it clears `stage6a`, promote the same restart-per-batch approach to the
    full-baseline narrowed-shell main lane immediately
  - if it fails materially before batch `8/8` or before `stage7`, consider a
    smaller `batchSize` before spending another full-baseline run

Stage-measurement tooling follow-up later on 2026-04-21:

- Added a reusable stage-stats path for the RTLIL/Yosys synthesis stages.
- Purpose:
  - answer questions like:
    - what does `stage6a` look like in the baseline path?
    - what does `stage6a` look like in the experiment path?
  - using structural stage stats rather than only wall-clock or RSS evidence
- Implementation:
  - new report script:
    - `scripts/pipeline/write_rtlil_stage_stat_report.py`
  - new comparison script:
    - `scripts/pipeline/compare_stage_stats.py`
  - new flake outputs now expose:
    - per-bundle stage-stat directories
    - direct `stage6a` stat outputs for the top4-memory lanes
- New package families of interest:
  - `tiny-stories-1m-baseline-float-selftest-top4-memory-stage-stats`
  - `tiny-stories-1m-baseline-float-selftest-top4-memory-stage6a-stats`
  - `tiny-stories-1m-representative-core-selftest-top4-memory-stage-stats`
  - `tiny-stories-1m-representative-core-selftest-top4-memory-stage6a-stats`
- Current interpretation:
  - these are Yosys/RTLIL stats, not MLIR op stats
  - that is still the right measurement class for `stage6a` and later, because
    those stages no longer operate on MLIR
  - the earlier pipeline already has `cf-stats` for MLIR-level measurement
- Guardrail:
  - the bundled comparison output
    `tiny-stories-1m-top4-memory-stage-stats-baseline-vs-representative-core`
    is useful for structural trend inspection, but it is not an apples-to-apples
    resource comparison because the representative core is intentionally smaller
- Continue decision:
  - once the active representative-core late-stage run is no longer consuming
    the machine, build the new `stage6a` stat outputs and use them as the
    default artifact for baseline-versus-experiment structural inspection

ABC9 lane follow-up later on 2026-04-21:

- Trigger:
  - after confirming that the narrowed-shell representative-core lane had moved
    the blocker from `stage6a` to a very long single-process
    `stage8b abc -luts 2:2,3,6:5,10,20` run, we decided to stop the live plain
    `abc` run and try the Xilinx `abc9` flow explicitly
- Implementation:
  - `flake.nix` now supports `useAbc9 = true` in `mkSynthJsonStages`
  - for the split fine-stage path, `abc9` is entered through
    `synth_xilinx -family xc7 -top <top> -noiopad -abc9`
    at:
    - `stage7 map_ffs:map_ffs`
    - `stage8 map_luts:check`
  - this intentionally avoids replacing the old `stage8b` raw `abc` command
    with a standalone `abc9` call, because the supported Xilinx `abc9` flow
    changes the late-stage sequence beyond one command
- New package family:
  - `tiny-stories-1m-representative-core-selftest-top4-memory-abc9-json`
  - `tiny-stories-1m-representative-core-selftest-top4-memory-abc9-stage-stats`
- Current monitored run:
  - `artifacts/task6/runs/representative-core-selftest-top4-memory-abc9-json-20260421-220353`
  - current confirmed progress:
    - rebuilt `model-opt`
    - rebuilt `model-shell`
    - entered staged synthesis derivations
    - reached at least `stage1`
- Current interpretation:
  - this is a real `abc9` lane, not a documentation-only idea
  - it should let us compare the late Xilinx LUT-mapping path against the
    previous long-running plain `abc` frontier on the same representative-core
    shell
- Continue decision:
  - keep the `abc9` representative-core run active until it either:
    - reaches a later frontier than the old plain-`abc` run, or
    - fails in a way that clearly does not justify promotion
  - if it looks promising on runtime or peak memory, replay the same `abc9`
    option on the full baseline narrowed-shell lane

Full-baseline external-memory priority update on 2026-04-26:

- Current priority remains externalization of memory, specifically the
  full-baseline `top4-memory` shell that blackboxes the four
  `3216448 x 32` vocab-sized handshake memories.
- Latest repaired-CIRCT full-baseline rerun:
  - artifact directory:
    - `artifacts/task6/runs/2026-04-24T20-05-40+0200-baseline-top4-memory-utilization-repaired-circt`
  - command:
    - `nix build .#tiny-stories-1m-baseline-float-selftest-top4-memory-utilization --no-link --print-out-paths -L`
  - result:
    - failed in `stage6a targeted techmap cells_map`
    - reached restart batch `13/15`
    - exit status `137`
    - sampled peak `VmRSS` about `30.3 GiB`
- Interpretation:
  - the active blocker is still the Yosys `cells_map` pass after successful
    external-memory shell construction, not frontend lowering and not the CIRCT
    patch stack.
  - restart-per-batch is functioning, because the full-baseline run advanced
    through multiple independent `stage6a` batches, but `batchSize = 32` is
    still too wide for the larger late batches on this host.
- Immediate execution change:
  - keep the same memory-externalization target and comparison baseline.
  - reduce `stage6a` restart batch size from `32` to `8` for the split
    `top4-memory` synthesis path.
  - rerun the monitored
    `tiny-stories-1m-baseline-float-selftest-top4-memory-utilization` build.
- Success criterion for this slice:
  - first, clear `stage6a` without exit `137`.
  - second, record the next frontier or final utilization against the copied
    all-memory baseline bundle.

Batch-8 rerun result on 2026-04-26:

- Monitored run:
  - `artifacts/task6/runs/2026-04-26T00-34-00+0200-baseline-top4-memory-utilization-stage6a-batch8`
- Result:
  - failed in `stage6a targeted techmap cells_map`
  - reached batch `52/59`
  - exit status `137`
  - wall time `8393` seconds
  - sampled peak `VmRSS` `30,171,296 KiB`
  - sampled peak `VmHWM` `30,171,664 KiB`
- Interpretation:
  - `batchSize = 8` is materially better than `32`; it advanced into the
    heavy late module range and cleared several batches that previously sat
    inside the killed region.
  - it is still too wide for the heaviest late `cells_map` group on this host.
- Immediate follow-up:
  - reduce `stage6a` restart batch size again, from `8` to `4`.
  - rerun the same monitored
    `tiny-stories-1m-baseline-float-selftest-top4-memory-utilization` target.

Batch-4 rerun result on 2026-04-26:

- Monitored run:
  - `artifacts/task6/runs/2026-04-26T02-55-01+0200-baseline-top4-memory-utilization-stage6a-batch4`
- Result:
  - failed in `stage6a targeted techmap cells_map`
  - reached batch `103/118`
  - exit status `1`, with the Yosys worker killed by exit `137`
  - wall time `20566` seconds
  - sampled peak `VmRSS` `29,808,588 KiB`
  - sampled peak `VmHWM` `29,809,904 KiB`
- Interpretation:
  - `batchSize = 4` advanced deeper than `8`, but the heaviest late
    `cells_map` groups still reach the host memory ceiling.
  - this is still a memory-pressure / OOM-kill frontier, not a new frontend or
    external-memory-plan failure.
- Immediate follow-up:
  - reduce `stage6a` restart batch size from `4` to `2`.
  - rerun the same monitored
    `tiny-stories-1m-baseline-float-selftest-top4-memory-utilization` target.

Batch-2 rerun result on 2026-04-26:

- Monitored run:
  - `artifacts/task6/runs/2026-04-26T22-24-33+0200-baseline-top4-memory-utilization-stage6a-batch2`
- Result:
  - failed in `stage6a targeted techmap cells_map`
  - reached batch `205/236`
  - exit status `1`, with the Yosys worker killed by exit `137`
  - wall time `23229` seconds
  - sampled peak `VmRSS` `29,865,256 KiB`
  - sampled peak `VmHWM` `29,866,344 KiB`
- Failure localization:
  - batch `205/236` corresponds to residual modules
    `\handshake_memory_out_f32_id70` and
    `\handshake_memory_out_f32_id71`.
  - each module still contains a `16384 x 32` memory after the `top4-memory`
    shell externalizes only the four `3216448 x 32` vocab-sized tables.
- Interpretation:
  - uniform `stage6a` batch reduction improved progress from `13/15` to
    `205/236`, but the remaining OOM frontier is still a residual handshake
    memory mapping problem.
  - continuing to shrink only the batch size is now lower leverage than moving
    more of the residual memory tail out of the Yosys `cells_map` path.
- Immediate follow-up:
  - add a baseline-float `top32-memory` externalization target that keeps the
    same copied all-memory baseline comparison while selecting more of the
    residual handshake memory modules.
  - first build and inspect the `top32-memory` external-memory plan, confirming
    whether the failing `id70` / `id71` modules are selected before spending a
    full utilization run.

`top32-memory` plan check on 2026-04-27:

- Flake output:
  - `tiny-stories-1m-baseline-float-selftest-top32-memory-external-memory-plan`
- Output path:
  - `/nix/store/dgxg2chvf3ig5g779lp5iidc5ps5pyc9-tiny-stories-1m-baseline-float-selftest-top32-memory-external-memory-plan`
- Plan summary:
  - eligible modules: `326`
  - eligible memory bits: `433,040,010`
  - selected modules: `32`
  - selected memory bits: `428,780,064`
- Relevant selected modules:
  - `\handshake_memory_out_f32_id70`, `16384 x 32`
  - `\handshake_memory_out_f32_id71`, `16384 x 32`
- Decision:
  - continue with a monitored
    `tiny-stories-1m-baseline-float-selftest-top32-memory-utilization` run.
  - keep `stage6a` restart batch size at `2` for this first wider-memory run,
    because batch size `2` is the current most conservative surviving setting
    and the changed variable should be memory externalization breadth.

`top32-memory` utilization result on 2026-04-27:

- Monitored run:
  - `artifacts/task6/runs/2026-04-27T08-57-20+0200-baseline-top32-memory-utilization-stage6a-batch2`
- Command:
  - `nix build .#tiny-stories-1m-baseline-float-selftest-top32-memory-utilization --no-link --print-out-paths -L`
- Result:
  - failed in `stage8b abc -luts 2:2,3,6:5,10,20`
  - exit status `1`, with the Yosys worker killed by exit `137`
  - wall time `23890` seconds
  - sampled peak `VmRSS` `24,736,208 KiB`
  - sampled peak `VmHWM` `26,633,804 KiB`
- Important progress:
  - `stage6a targeted techmap cells_map` completed all `222/222` restart
    batches.
  - this crosses the previous `top4-memory` batch-size-2 failure point, which
    died at `stage6a` batch `205/236`.
  - around the old failure index, the `top32-memory` run sampled roughly
    `20 GiB` RSS instead of the previous `29.9 GiB` OOM-region RSS.
- Interpretation:
  - widening external memory from top 4 to top 32 selected modules fixed the
    immediate residual-memory `cells_map` frontier.
  - the new frontier is later ABC/LUT mapping in `stage8b`, not `stage6a`
    memory-module `cells_map`.
- Immediate follow-up:
  - keep the `top32-memory` target as the current main external-memory lane.
  - inspect the `stage8a` input to identify whether `stage8b` is dominated by
    a small number of residual memory modules before changing ABC itself.

`stage8b` frontier localization on 2026-04-27:

- Input inspected:
  - `/nix/store/vg7ls8jbswv1vaazvrp0ix19jawyhr77-tiny-stories-1m-baseline-float-selftest-top32-memory-stage8a.il`
- Largest residual `$_*` cell owners entering ABC:
  - `\handshake_memory_out_f32_id36`: `8,783,360` cells
  - `\handshake_memory_out_f32_id35`: `8,783,360` cells
  - next largest module:
    - `\handshake_memory_out_f32_id77`: `962,720` cells
- Original memory sizes:
  - `\handshake_memory_out_f32_id36`: `4096 x 32`
  - `\handshake_memory_out_f32_id35`: `4096 x 32`
- External-memory rank:
  - `id36` is rank `33`
  - `id35` is rank `34`
- Decision:
  - add a `top34-memory` target that externalizes exactly the two newly
    identified ABC-dominant residual memory modules beyond `top32`.
  - this keeps the lane focused on externalization of memory before adding an
    ABC-specific split or alternate mapping strategy.

`top34-memory` plan check on 2026-04-27:

- Flake output:
  - `tiny-stories-1m-baseline-float-selftest-top34-memory-external-memory-plan`
- Output path:
  - `/nix/store/0z3gaxjvp5843k9imlj3kcgxapl7qkl0-tiny-stories-1m-baseline-float-selftest-top34-memory-external-memory-plan`
- Plan summary:
  - eligible modules: `326`
  - eligible memory bits: `433,040,010`
  - selected modules: `34`
  - selected memory bits: `429,042,208`
- Relevant selected modules:
  - `\handshake_memory_out_f32_id36`, `4096 x 32`
  - `\handshake_memory_out_f32_id35`, `4096 x 32`
- Decision:
  - continue with a monitored
    `tiny-stories-1m-baseline-float-selftest-top34-memory-utilization` run.
  - keep `stage6a` restart batch size at `2`, because the next changed
    variable is only the two additional externalized memory modules.

`top34-memory` utilization interruption on 2026-04-27:

- Monitored run:
  - `artifacts/task6/runs/2026-04-27T15-43-36+0200-baseline-top34-memory-utilization-stage6a-batch2`
- Observed state:
  - run was no longer active when checked at `2026-04-27T16:28:57+02:00`
  - no `nix` or `yosys` process remained
  - artifact directory had process samples and a build log, but no generated
    completion summary
  - final logged synthesis line was `stage6a targeted techmap cells_map batch
    16/221`
- Interpretation:
  - treat this as an interrupted or abandoned run, not as evidence for or
    against `top34-memory`.
  - the last valid consolidated result remains the `top32-memory` run, which
    cleared `stage6a` and moved the blocker to `stage8b`.
- Immediate follow-up:
  - rerun `tiny-stories-1m-baseline-float-selftest-top34-memory-utilization`
    under the monitor before drawing conclusions from the top34 externalization
    target.

`top34-memory` utilization rerun result on 2026-04-27:

- Monitored run:
  - `artifacts/task6/runs/2026-04-27T16-35-00+0200-baseline-top34-memory-utilization-stage6a-batch2-rerun`
- Command:
  - `nix build .#tiny-stories-1m-baseline-float-selftest-top34-memory-utilization --no-link --print-out-paths -L`
- Result:
  - failed in `stage9 write_json`
  - exit status `1`
  - wall time `11367` seconds
  - sampled peak `VmRSS` `19,928,932 KiB`
  - sampled peak `VmHWM` `20,280,128 KiB`
  - final error:
    - `ERROR: Parser error in line 66916687: dangling attribute`
- Important progress:
  - `stage6a targeted techmap cells_map` completed all `221/221` restart
    batches.
  - this crosses the old `top4-memory` batch-size-2 failure point, which died
    at `stage6a` batch `205/236`.
  - `stage8b abc -luts 2:2,3,6:5,10,20` completed, crossing the prior
    `top32-memory` frontier.
  - the run also completed `stage8c`, `stage8d`, `stage8e`, `stage8f`,
    `stage8g`, and `stage8h`.
- Interpretation:
  - externalizing the rank-33/rank-34 memory owners `id36` and `id35` fixed the
    `top32-memory` ABC frontier.
  - the active blocker is now final JSON emission or parsing of the very large
    mapped design, not the previous residual-memory `cells_map` or ABC OOM
    frontier.
  - this strengthens the external-memory mainline and supports an
    owner-driven externalization loop.
- Immediate follow-up:
  - inspect the `stage8h` output or failed `stage9` input around line
    `66916687` to determine whether the dangling attribute is a Yosys writer
    issue, a malformed RTLIL attribute from a prior pass, or a scale/streaming
    artifact in `write_json`.
  - add a cheaper `stage9`-only replay or parser-check target so this new
    frontier can be debugged without rerunning the full utilization path.

`top34-memory` stage9-only replay result on 2026-04-27:

- New flake outputs:
  - `tiny-stories-1m-baseline-float-selftest-top34-memory-stage8h-il`
  - `tiny-stories-1m-baseline-float-selftest-top34-memory-stage9-debug`
- Cached replay input:
  - `/nix/store/v40xbypjmh5vyxyd6ic3wg7caqywb9cx-tiny-stories-1m-baseline-float-selftest-top34-memory-stage8h.il`
- Manual stage9-only replay bundle:
  - `/tmp/task6-stage9-debug-fixed`
- Result:
  - patched filter produced `66,915,339` RTLIL lines
  - Yosys completed `read_rtlil; proc; write_json`
  - `stage9-debug.json` was emitted successfully
  - Yosys wall time was `140.73` seconds
  - Yosys peak memory was `23,290.57 MB`
- Root cause:
  - the final-stage filter dropped selected blackbox modules but did not drop
    the top-level `attribute` lines immediately preceding those dropped
    modules.
  - after the final dropped module, the filtered RTLIL ended with orphan module
    attributes, which Yosys reported as `dangling attribute` at EOF.
- Fix:
  - `scripts/pipeline/filter_rtlil_modules.py` now buffers top-level attributes
    and emits them only when the following module is retained.
- Interpretation:
  - the `top34-memory` stage9 failure was a replayable boundary bug in the
    filtering step, not evidence against the external-memory synthesis path.
  - the feedback loop is now roughly minutes for this frontier instead of a
    full monitored utilization rerun.

`top34-memory` continuation plan after stage9 replay on 2026-04-27:

- Gate 1: rerun the real fixed `top34-memory` utilization target.
  - command:
    - `nix build .#tiny-stories-1m-baseline-float-selftest-top34-memory-utilization --no-link --print-out-paths -L`
  - expected value:
    - reuses the already successful staged derivations where possible
    - verifies that the committed filter fix carries through the production
      utilization output, not only the manual replay bundle
  - promotion rule:
    - if utilization completes, inspect LUT/FF/DSP/BRAM and largest remaining
      mapped cell owners.
    - if it fails, use the new failure stage as the next frontier before
      changing DDR3 or memory-shell variables.
- Gate 2: perform FPGA-fit accounting before implementing a DDR3 controller.
  - report selected external bits and expected off-chip capacity use.
  - estimate per-token read/write traffic, port width, clock assumptions,
    buffering BRAM, arbitration cost, and memory-interface LUT/FF overhead.
  - treat the current `top34-memory` `429,042,208` selected bits
    (`~51.2 MiB`) as a synthesis proof, not yet as a board implementation
    proof.
- Gate 3: define the external-memory shell contract.
  - determine whether the externalized memories expose many independent
    module-local ports or can be collapsed behind a smaller shared board-memory
    interface.
  - specify address width, data width, read latency, write behavior,
    valid/ready timing, initialization/loading path, and arbitration policy.
- Gate 4: choose or integrate DDR3 only after the shell contract is known.
  - GitHub DDR3 cores are useful candidates, but selecting one before the
    traffic shape and handshake contract are known risks optimizing the wrong
    interface.
  - pivot to DDR3 implementation once the fixed utilization output and memory
    shell accounting show that board RAM bandwidth/latency is the active
    blocker rather than synthesis fit.

Immediate execution:

- Run the fixed full `top34-memory` utilization target under the monitor.
- Record completed stage, peak RSS/HWM, final resource report or failing
  frontier, and whether any residual memory owners still dominate the mapped
  design.

## Int8 board self-test update on 2026-04-29

Current fast board lane:

- `task6-int8-l2-mlp-chain-residual-add-selftest-*`
- purpose:
  - keep using the small int8 L2 MLP chain as the board-facing debug lane
    before spending more time on the full TinyStories external-memory shell
  - validate that the generated int8 arithmetic and memories survive synthesis,
    place/route, bitstream generation, and physical FPGA execution

Physical diagnostic result:

- Bitstream tested:
  - `/nix/store/qg4wbb17a00v9212c3nny3ybgk7cpjhp-task6-int8-l2-mlp-chain-residual-add-selftest-c-proj-requant-debug.bit`
- Observed repeating LED sequence, ignoring the always-on board power/status
  LED:
  - all
  - green+orange
  - off
  - red+orange
  - green
  - red+green
  - all
  - red
  - off
- Decode:
  - final residual-add self-test still fails at output index `0`
  - the expected final residual-add byte is `0x0a`
  - the c_proj accumulator, c_proj requant scale multiplier, and c_proj bias
    value for index `0` match the generated constants
  - the observed c_proj requant output byte is still `0x7f`, while the expected
    c_proj output byte is `0x0a`
- Interpretation:
  - the board failure is no longer plausibly a load/order issue for the c_proj
    accumulator or constants
  - the fault is localized to the synthesized c_proj requant arithmetic path
  - this is useful progress: the diagnostic narrowed the bug from "self-test
    fails on board" to "c_proj requant saturates to `0x7f` even when its inputs
    match the expected fixture values"

Fix attempted:

- `rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_requant_kernel.sv`
  now explicitly sign-extends the 32-bit accumulator and scale multiplier to
  64 bits before multiplying.
- The change mirrors the style already used in the residual-add requant path
  and avoids relying on tool interpretation of the narrower `$signed(acc) *
  $signed(scale_mul)` expression.

Verification after the fix:

- Simulation:
  - command:
    - `nix build .#task6-int8-l2-mlp-chain-residual-add-selftest-sv-sim --no-link --print-out-paths -L`
  - result:
    - pass at cycle `18804`
  - output:
    - `/nix/store/c6wscp6nc5chixy3649nyc9rzfz1xm1j-task6-int8-l2-mlp-chain-residual-add-selftest-sv-sim.json`
- Synthesis JSON:
  - command:
    - `nix build .#task6-int8-l2-mlp-chain-residual-add-selftest-json --no-link --print-out-paths -L`
  - result:
    - Yosys completed with `0` reported structural problems
  - output:
    - `/nix/store/96rsc4lq7crzpnshj110j04yf80h7h7v-task6-int8-l2-mlp-chain-residual-add-selftest.json`
- Board bitstream:
  - command:
    - `nix build .#task6-int8-l2-mlp-chain-residual-add-selftest-bitstream --no-link --print-out-paths -L`
  - result:
    - completed
  - output:
    - `/nix/store/jkqn0blzj40rycb0gmx8h2ibvwgdxpjk-task6-int8-l2-mlp-chain-residual-add-selftest.bit`
  - post-route timing:
    - `136.37 MHz` maximum frequency, passing the `12.00 MHz` target
  - packed utilization:
    - `SLICE_LUTX`: `10998 / 597200`, about `1.84%`
    - `SLICE_FFX`: `718 / 597200`, about `0.12%`
    - `DSP48E1`: `36 / 1920`, `1.88%`
    - BRAM36-equivalent: `8 RAMB36E1 + 6 RAMB18E1`, equivalent to `11 / 955`,
      about `1.15%`

Next board action:

- Program the fixed normal self-test bitstream:
  - `/nix/store/jkqn0blzj40rycb0gmx8h2ibvwgdxpjk-task6-int8-l2-mlp-chain-residual-add-selftest.bit`
- Expected physical result:
  - ignore the board's always-on top green LED
  - design red LED blinks as heartbeat
  - design green LED stays on for pass
  - design orange LED stays off
- If the orange fail LED still turns on, rebuild/run the patched debug
  bitstream again and decode the new LED sequence before changing the memory
  shell or DDR3 direction.

Physical follow-up:

- The fixed normal self-test bitstream above still fails on board:
  - design red LED blinks
  - design orange LED stays on
- Rebuilt the c_proj requant diagnostic against the same patched RTL:
  - `/nix/store/2xd7pkyg8ydprgcaarfbphvmmswxask4-task6-int8-l2-mlp-chain-residual-add-selftest-c-proj-requant-debug.bit`
  - post-route timing: `145.82 MHz`, passing the `12.00 MHz` target
- Next diagnostic question:
  - whether the patched design still reports c_proj requant output `0x7f`, or
    whether the failure moved to a different byte/value
  - if it still reports `0x7f` while accumulator/scale/bias match, replace the
    c_proj requant multiply/shift path with a narrower or staged arithmetic
    implementation instead of continuing reset/load investigation

## Parallel strategy execution guidance

Use one lane per strategy, derived from `task6`.

Recommended lane names:

- `task6-quant`
- `task6-docc`
- `task6-alt-dialect`
- `task6-eqmap`
- `task6-board-ram`
- `task6-lsq`
- `task6-lowering`
- `task6-paper-review`

Recommended workspace layout:

- keep this repo as the canonical `task6` base
- prefer sibling `git worktree`s over deleting this repo and making full clones
- each worktree should check out one strategy branch derived from `task6`

Why prefer worktrees:

- they keep one shared git object store and remote config
- they avoid destructive repo replacement
- they are a better fit for parallel Codex threads, because each thread can own
  one working tree and one branch

Per-lane rules:

- compare every measurement against the copied baseline bundle in
  `artifacts/task6/baselines/...`
- keep strategy-specific edits isolated to that lane until they are worth
  merging back to `task6`
- if a new script, testbench, or helper file must be visible to `nix build`,
  make sure it is tracked by git first; untracked files are omitted from the
  flake source snapshot
- do not rebuild `tiny-stories-1m-baseline-float-sv` just to recreate the
  baseline reference if the copied baseline bundle already answers the
  comparison question

Suggested mapping:

- quantization lane: dynamic-int8, TorchAO, PT2E-static, and any follow-up from
  `task3-experiments`
- eqmap lane: RTL/Verilog simplification and post-lowering cleanup experiments
- board RAM lane: move suitable weights/buffers into on-board DDR3 and record
  capacity/bandwidth assumptions explicitly
- LSQ lane: compare standard handshake vs LSQ/external-memory variants
- paper-review lane: extract transplantable ideas from StreamTensor and newer
  FPGA LLM papers, with explicit resource-saving claims

Concurrency note:

- the Nix daemon can handle concurrent builds, but the real bottlenecks will be
  host CPU, RAM, disk I/O, and cache contention
- begin with at most two or three active strategy builds plus any lighter
  paper-review work
- stagger the most expensive builds if evaluation or patch rebuilds contend on
  the same large dependencies

## What can be done now vs later

### Work that can be done now in `task6`

- keep the Task 6 execution notes, hypotheses, and comparison templates current
- refine success criteria for "fits the board"
- review papers and extract only transplantable ideas
- identify the best donor branch for later TinyStories/pipeline import
- use the existing matmul/board path only as infrastructure sanity, not as a
  surrogate for Task 6 success

### Work that requires importing Task 3 artifacts later

- quantization continuation on TinyStories
- standard vs LSQ handshake comparison
- external-memory experiments driven by emitted TinyStories RTL/SV
- post-lowering RTL simplification on full-model artifacts
- any claim that a real LLM now fits or almost fits the board

## Guardrails

- Do not modify `docs/project-plan*` without explicit reviewer approval.
- Use on-board DDR3 as a first-class system resource, not only LUT/FF/BRAM/DSP.
- Confirm the exact usable DDR3 budget before making a final fit-to-board claim.
- Use the largest model that cleanly completes the scaling pipeline as the
  baseline. If scaling is still incomplete, use `tiny-stories-1m-baseline-float`
  as the provisional baseline.
- Track Yosys resource estimates and nextpnr outcomes separately. Given the
  documented nextpnr-xilinx instability in this repo, early Task 6 screening
  should not block on nextpnr success.
- Final claims must not rely on unresolved stubs or hidden blackboxes.

## Metrics to record for every strategy

- Functional status and first failing stage
- Delta LUT/FF/BRAM/DSP
- Delta Fmax or best available timing proxy
- Toolchain wall-clock time and peak host memory
- External DDR3 usage, what moved off-chip, and estimated bandwidth pressure
- Patch burden: standard flow, local script change, or compiler patch
- Viability status: recommended, conditional, or reject

Comparison rule:

- every strategy result must be compared against the copied baseline bundle
  above, not just against memory or intuition
- if a strategy uses a different measurement path, record that explicitly and
  explain why it is still comparable

## Success criteria and exit gates

### Provisional definition of "good enough to hand off"

A strategy stack is ready to hand off when all of the following are true:

- it improves the limiting resource relative to baseline in a measurable way
- it does not introduce unresolved stubs or hidden blackboxes
- it reaches at least the same downstream stage as baseline
- the required patch burden is understood and documented
- it has a plausible board story, including DDR3 assumptions where relevant

### Stop conditions for an individual strategy

Stop investing in a strategy if any of the following becomes true:

- it fails earlier than baseline without a clear path to recovery
- it shows negligible benefit in the primary limiting resource
- it requires turning Task 6 into a retraining or compiler-rewrite project
- its claimed benefit disappears once downstream stages are included
- it creates a memory or interface story that is clearly unrealistic for the
  board

## Strategy shortlist

| ID | Strategy | Can start in this branch now? | Depends on later Task 3 import? | Why it matters |
| --- | --- | --- | --- | --- |
| S0 | Measurement harness and result schema | Yes | No | Makes every later comparison reproducible |
| S1 | Define board-fit criterion | Yes | No | Prevents moving goalposts during experiments |
| S2 | DDR3 / external-memory path | Partly | Yes | Likely best way to relieve BRAM pressure |
| S3 | Quantization continuation | No | Yes | May reduce BRAM and DSP pressure materially |
| S4 | Handshake-cost reduction | No | Yes | Handshake may be the main area amplifier |
| S5 | RTL simplification / eqmap-style passes | Partly | Yes | Cheap post-lowering area reduction is worth testing |
| S6 | StreamTensor and recent-paper refresh | Yes | No | Can supply transferrable memory and scheduling ideas |
| S7 | MoE feasibility probe | Yes, at literature level | Yes, for implementation | Interesting but must stay gated |

## Main workstreams

### 1. Freeze baseline and measurement harness

- Lock the baseline model and exact pipeline path.
- Script one reproducible measurement path that emits stage status, Yosys stats,
  timing if available, host runtime, and peak host memory.
- Prepare a per-strategy comparison matrix before running experiments.

Concrete output expected from this workstream:

- one baseline row filled in the strategy comparison matrix
- one short command log showing how the row was generated
- one explicit statement of whether baseline fit is judged by Yosys only,
  Yosys-plus-nextpnr, or both reported separately

### 2. Direct resource-reduction tracks

Run these before architecture-heavy exploration.

#### DDR3 / external-memory track

- Move suitable memories off-chip instead of forcing them into FPGA BRAM.
- Separate weights, activations, and cache/state when reasoning about what can
  live in DDR3.
- Start from the existing memory inventory / externalization hooks once the
  TinyStories pipeline files are imported into this branch.

Questions that must be answered before claiming success:

- which memories move off-chip?
- what BRAM reduction results?
- what interface/control logic is added?
- what bandwidth assumption is required?
- is the result still realistic for this board?

#### Quantization continuation track

- First use the quantization experiments present in the donor Task 3 branches:
  - `TinyStories/model_adapter_dynamic_quant.py`
  - `TinyStories/model_adapter_pt2e_static_quant.py`
  - `TinyStories/model_adapter_torchao.py`
- Preferred donor order:
  - `task3-experiments` if/when available in this clone
  - `origin/task3-rfp-sandbox` as the current fallback
  - `origin/task3-hybrid-sandbox-toolchain` only for selected helpers or clean
    landing-state references
- Treat quantization as a bounded path:
  - standard routes first
  - focused follow-up second
  - no unbounded patch-stack revival without evidence of material gains

#### Handshake-cost reduction track

- Profile growth before and after handshake lowering.
- Compare the standard handshake path with the LSQ variant already present in
  the donor Task 3 branches.
- Inspect buffer insertion, fork/sink materialization, and memory lowering as
  likely area amplifiers.

Priority question:

- does area explode before handshake, during handshake, or after handshake when
  memory/interface lowering happens?

#### RTL simplification track

- Try equivalence-preserving RTL simplification after SV/IL emission.
- Check whether `eqmap`-style or similar Yosys simplification actually shrinks
  area instead of merely reshuffling logic.
- Avoid brittle text rewriting as the main method.

Note:
- this track can be prepared now at the planning level, but meaningful testing
  still depends on having full-model emitted RTL/SV in this branch

### 3. Research and architecture track

Run in parallel, but do not let it block the direct tracks.

#### StreamTensor and recent-paper refresh

For each paper, extract:

- What problem it attacks
- What efficiency or resource gain it claims
- Whether the gain comes from quantization, streaming, memory hierarchy,
  scheduling, sparsity, or architecture change
- Whether any part looks transplantable into this open-source pipeline

Read StreamTensor first, then refresh the FPGA-LLM paper survey with an eye for
small-model, external-memory, and quantization ideas.

#### MoE feasibility track

- Do not make "convert TinyStories-1M to MoE" the primary plan.
- Dense-to-MoE adaptation appears possible in the literature, but it is an
  upcycling / retraining problem, not a direct toggle on an existing dense
  checkpoint.
- Only pursue MoE as an implementation path if a small open MoE model in
  PyTorch / Transformers form can be exported with limited custom work.

Decision gate:
- if MoE requires new training or substantial model surgery before export, move
  it to future work and keep Task 6 focused on direct reduction strategies

## Failure-triage rules

- If failure happens before MLIR/SV emission:
  - treat it as a frontend/compiler support issue first, not a resource issue
- If full RTL/IL is emitted but area is far too large:
  - prioritize DDR3, quantization, handshake, and RTL simplification tracks
- If Yosys looks promising but nextpnr fails:
  - record it as a place-and-route/toolchain limitation separately from model
    lowering success
- If a strategy improves one resource but makes another dominant resource much
  worse:
  - keep it only if the new bottleneck is still more tractable than baseline

## Suggested order once Task 3 artifacts are imported

1. Freeze the baseline row and fill the measurement matrix.
2. Run one DDR3/external-memory experiment.
3. Run the three standard quantization variants.
4. Compare standard vs LSQ handshake paths.
5. Run one RTL simplification pass bundle on the best candidate from steps 2 to 4.
6. Stop broad exploration if one path clearly dominates.
7. Hand off immediately if the resulting candidate has a plausible board-fit story.

## Comparison templates

### Strategy comparison matrix

| Strategy ID | Input branch/artifact | Stage reached | LUT delta | FF delta | BRAM delta | DSP delta | Timing delta | Host runtime delta | Peak RAM delta | DDR3 assumption | Patch burden | Result |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Baseline | TBD | TBD | 0 | 0 | 0 | 0 | 0 | 0 | 0 | None | TBD | TBD |
| S2 | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD |
| S3 | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD |
| S4 | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD |
| S5 | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD |

### Paper review matrix

| Paper / repo | Claimed gain | Main idea | Memory relevance | Quantization relevance | Reusable here? | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| StreamTensor | TBD | TBD | High | Medium | TBD | First priority read |

### Donor-branch import checklist

| Item needed for Task 6 | Present in `origin/task3` | Present in `origin/task3-rfp-sandbox` | Present in `origin/task3-hybrid-sandbox-toolchain` | Preferred donor |
| --- | --- | --- | --- | --- |
| TinyStories base adapter | Yes | Yes | Yes | TBD |
| Quantization adapters | No | Yes | Yes | `task3-experiments` if available, else `origin/task3-rfp-sandbox` |
| `nix/models.nix` | Yes | Yes | Yes | TBD |
| `nix/pipeline.nix` | Yes | Yes | Yes | TBD |
| LSQ handshake script | No | Yes | Yes | `origin/task3-rfp-sandbox` |
| `externalize_large_memories.py` | No | Yes | Yes | `origin/task3-rfp-sandbox` |
| `sv_memory_inventory.py` | No | No | Yes | `origin/task3-hybrid-sandbox-toolchain` |
| `mlir_op_profile.py` | No | No | Yes | `origin/task3-hybrid-sandbox-toolchain` |

## Repo starting points

- Files already present in this branch now:
  - `flake.nix`
  - `deliverables/1a-survey.org`
  - `deliverables/1c-selected_route.org`
  - `deliverables/2d-fpga-bitstream.org`
  - `docs/project-management.org`
- Donor branches for later import/reference:
  - `task3-experiments` if it can be fetched or recovered into this clone
  - `origin/task3`
  - `origin/task3-rfp-sandbox`
  - `origin/task3-hybrid-sandbox-toolchain`

## Questions to resolve later

- What counts as Task 6 success: Yosys estimate only, or Yosys plus nextpnr
  viability?
- Can the DDR3 track use a temporary explicit shell/wrapper interface before
  full board integration?
- How much time should be allowed for the exploratory MoE path before it is cut
  as future work?
- Which donor branch should become the base for the TinyStories Task 6 execution
  work once Task 3 cleanup is far enough along?

## Feedback-loop-first update later on 2026-04-21

- New standing maxim for later sessions:
  - maximize iteration speed, learning speed, and feedback-loop speed first
  - use the cheapest artifact that answers the current question
  - only escalate to long synthesis runs after a smaller measurement path stops
    being informative
- Action taken:
  - shrank `tiny-stories-1m-representative-core` again to the current fast-loop
    profile:
    - `vocab_size = 32`
    - `num_layers = 2`
    - `hidden_size = 2`
    - `num_heads = 1`
    - `max_position_embeddings = 4`
    - `window_size = 2`
  - kept `num_layers = 2` specifically so the reduced core still exercises both
    the `global` and `local` GPT-Neo attention patterns
- New MLIR op-coverage tooling:
  - raw stats outputs:
    - `tiny-stories-1m-baseline-float-torch-stats`
    - `tiny-stories-1m-representative-core-torch-stats`
    - existing `*-cf-stats`
  - comparison outputs:
    - `tiny-stories-1m-baseline-float-vs-representative-core-torch-op-coverage`
    - `tiny-stories-1m-baseline-float-vs-representative-core-cf-op-coverage`
    - `tiny-stories-1m-baseline-float-vs-representative-core-op-coverage`
- Intended use:
  - baseline float is the witness
  - representative core is allowed to shrink only if it keeps the baseline op
    and dialect coverage we care about at `torch` and `cf`
  - this is the default admission check before another Task 6 synthesis loop
- Verification result from the current shrink sweep:
  - full op-name and dialect coverage is still intact against the baseline at
    both `torch` and `cf`
  - measured artifact reduction at the current floor:
    - `torch.mlir`: `30,091,456` bytes / `996` lines -> `36,485` bytes /
      `303` lines
    - `cf.mlir`: `30,664,646` bytes / `14,545` lines -> `194,052` bytes /
      `4,177` lines
    - `torch` op coverage: `36/36` distinct baseline ops retained
    - `cf` op coverage: `32/32` distinct baseline ops retained
- Current decision:
  - keep this as the default representative-core floor for fast iteration
  - do not spend more time shrinking it unless a later structural metric shows
    that the op-coverage check was not enough

Minimal representative-core synthesis follow-up later on 2026-04-21:

- Command under test:
  - `nix build .#tiny-stories-1m-representative-core-selftest-top4-memory-json --no-link --print-out-paths`
- Scope:
  - first narrowed-shell synthesis run on the new representative-core floor
    after the MLIR op-coverage admission check passed
- Confirmed stage progression so far:
  - `stage1`
  - `stage2`
  - `stage3`
  - `stage4`
  - `stage5a`
  - `stage5b`
  - `stage5c`
  - `stage5d`
  - `stage6a`
  - `stage6b`
  - `stage7`
  - `stage8a`
  - live in `stage8b` at the time of this note
- Measured live memory shape from direct `/proc` sampling:
  - `stage2` worker:
    - `VmPeak` about `6.6 GiB`
    - later current `VmRSS` dropped back toward `1.9-4.6 GiB` while still in
      the same stage
  - `stage5a` worker:
    - `VmPeak` about `6.27 GiB`
    - `VmHWM` about `4.81 GiB`
  - `stage6a` restart-batched worker family:
    - repeated fresh Yosys PIDs observed inside the same `stage6a` derivation
    - each fresh batch worker remained around `1.78-1.81 GiB` `VmRSS` /
      `VmHWM`
  - `stage8b` live split:
    - parent `yosys` around `2.05 GiB` RSS
    - child `yosys-abc` around `725 MiB` RSS after roughly `80` seconds
- Interpretation:
  - the minimal representative core is no longer just a frontend witness
  - it now clears the old `stage6a` frontier and reaches the late `stage8b`
    band with a much smaller memory envelope than the earlier
    representative-core presets
  - the restart-per-batch `stage6a` path is confirmed on this floor by direct
    observation of multiple fresh Yosys worker PIDs within one `stage6a`
    derivation
- Continue decision:
  - keep this run alive until `stage8b` clears or fails
  - if it clears late `stage8*`, promote this minimal floor as the default Task
    6 synthesis debug target
  - after the live run settles, rebuild the same target under
    `scripts/pipeline/monitor_build.sh` only if a wrapped artifact bundle is
    still needed for later comparison

Minimal representative-core synthesis completion on 2026-04-22:

- The unwrapped synthesis target completed successfully:
  - command:
    - `nix build .#tiny-stories-1m-representative-core-selftest-top4-memory-json --no-link --print-out-paths`
  - output:
    - `/nix/store/x71jisw24p9w10yhv93yxximas587pci-tiny-stories-1m-representative-core-selftest-top4-memory.json`
- Follow-up artifacts also completed successfully:
  - utilization:
    - `nix build .#tiny-stories-1m-representative-core-selftest-top4-memory-utilization --no-link --print-out-paths`
    - output:
      - `/nix/store/djnni1viapdqfs8n45vny1135zw9s53g-tiny-stories-1m-representative-core-selftest-top4-memory-utilization`
  - stage stats:
    - `nix build .#tiny-stories-1m-representative-core-selftest-top4-memory-stage-stats --no-link --print-out-paths`
    - output:
      - `/nix/store/f22qqhvhpxr7rhbnwv5y7qq201g7q56q-tiny-stories-1m-representative-core-selftest-top4-memory-stage-stats`
- Confirmed stage coverage:
  - the minimal representative-core floor now clears the full narrowed-shell
    synthesis path through `stage8h` and final `json` emission
- Useful structural checkpoints from the stage-stats bundle:
  - `stage6a`:
    - `641,719,733` RTLIL bytes
    - `9,256,137` RTLIL lines
    - `225` module definitions
    - `242` top cells
    - `0` memories / `0` memory bits
  - `stage8b`:
    - `473,231,814` RTLIL bytes
    - `6,601,755` RTLIL lines
    - `225` module definitions
    - `203` top cells
  - `stage8h`:
    - `996,246,572` RTLIL bytes
    - `12,031,729` RTLIL lines
    - `225` module definitions
    - `166` top cells
- Current interpretation:
  - the minimal representative core is now a real synthesis debug target, not
    just a frontend witness
  - it is suitable as the default fast Task 6 loop for flow debugging and lane
    comparison before replay on the full TinyStories baseline
- Current decision:
  - promote this representative-core floor as the default Task 6 synthesis
    debug target
  - use the full baseline only for replay once a change proves itself here

Main-lane replay start on 2026-04-22:

- Wrapped replay launched for the real narrowed-shell baseline path:
  - command:
    - `MONITOR_GLOBAL_PGREP_PATTERN="default-builder.sh|yosys -q -s run.ys|yosys-abc" scripts/pipeline/monitor_build.sh artifacts/task6/runs/baseline-float-selftest-top4-memory-json-20260422-075933 5 -- nix build .#tiny-stories-1m-baseline-float-selftest-top4-memory-json --no-link -L`
  - run directory:
    - `artifacts/task6/runs/baseline-float-selftest-top4-memory-json-20260422-075933`
- Current status at note time:
  - active
  - still in the model/shell build band before the first staged Yosys banner
- Current decision:
  - let this replay establish whether the restart-batched `stage6a` fix carries
    over from the minimal representative-core lane to the real TinyStories
    baseline path

Representative-core same-core pipeline comparison setup on 2026-04-22:

- Question being answered:
  - compare the same minimal representative core under the two Task 6 pipeline
    shapes:
    - `tiny-stories-1m-representative-core-selftest-all-memory-*`
    - `tiny-stories-1m-representative-core-selftest-top4-memory-*`
  - do not confuse this with the already-built baseline-vs-representative-core
    compare
- Fix landed first:
  - the monolithic all-memory stage-stats path was broken because the staged
    synth record exposed `stage5Monolithic` / `stage6Monolithic` but not the
    `stage5` / `stage6` attribute names that the stage-stats bundle expected
  - added explicit aliases for `stage5` and `stage6` so monolithic
    representative-core bundles can now materialize stage stats
- New direct compare outputs:
  - `tiny-stories-1m-representative-core-all-memory-vs-top4-memory-stage-stats`
  - `tiny-stories-1m-representative-core-all-memory-vs-top4-memory-utilization`
  - `tiny-stories-1m-representative-core-all-memory-vs-top4-memory-compare`
- Comparison alignment:
  - use exact same-stage compares for `stage1` through `stage4` and `stage7`
  - compare the monolithic all-memory milestones against the split top4-memory
    milestones at:
    - `stage5` vs `stage5d`
    - `stage6` vs `stage6b`
    - `stage8` vs `stage8h`
- Current status at note time:
  - direct same-core compare build launched
  - first fixed all-memory stage-stats artifact already materialized:
    - `/nix/store/5nsiy5rbp3w3cfsaxz8sp7j7a0iy5vkv-tiny-stories-1m-representative-core-selftest-all-memory-stage1-stats`
  - full compare bundle still in progress
- Current decision:
  - use this same-core compare as the default way to judge whether `top4-memory`
    is helping on the representative core before talking about the full
    baseline lane

Representative-core same-core pipeline comparison result later on 2026-04-22:

- Direct same-core compare outputs completed:
  - `tiny-stories-1m-representative-core-selftest-all-memory-stage-stats`
  - `tiny-stories-1m-representative-core-selftest-all-memory-utilization`
  - `tiny-stories-1m-representative-core-all-memory-vs-top4-memory-stage-stats`
  - `tiny-stories-1m-representative-core-all-memory-vs-top4-memory-utilization`
  - `tiny-stories-1m-representative-core-all-memory-vs-top4-memory-compare`
- Result:
  - on the current minimal representative core, `top4-memory` is worse than
    `all-memory` at every comparable stage and at final mapped utilization
- Stage-stat deltas, `all-memory` -> `top4-memory`:
  - `stage1`:
    - `163,087,589` -> `166,555,929` RTLIL bytes (`+2.13%`)
  - `stage5` vs `stage5d`:
    - `628,922,879` -> `632,085,438` RTLIL bytes (`+0.50%`)
  - `stage6` vs `stage6b`:
    - `628,922,846` -> `641,684,683` RTLIL bytes (`+2.03%`)
  - `stage7`:
    - `628,951,844` -> `641,898,669` RTLIL bytes (`+2.06%`)
  - `stage8` vs `stage8h`:
    - `622,447,688` -> `996,246,572` RTLIL bytes (`+60.05%`)
- Utilization delta, `all-memory` -> `top4-memory`:
  - `clb_luts`:
    - `9,181,200` -> `12,472,727` (`+35.85%`)
  - `clb_ffs`:
    - `12,837,053` -> `12,845,684` (`+0.07%`)
  - `slices_lower_bound`:
    - `1,604,632` -> `1,605,711` (`+0.07%`)
  - largest driver:
    - `LUT3` cells rise from `4,484,247` to `7,636,072` (`+70.29%`)
- Interpretation:
  - the current representative-core floor is too small to show the intended
    benefit of externalizing only the top four memories
  - on this floor, the extra shell/interface structure dominates and makes the
    narrowed path look strictly worse than the monolithic all-memory path
- Current decision:
  - do not use this minimal representative core to judge whether `top4-memory`
    helps
  - keep using it for fast general flow debugging only
  - evaluate `top4-memory` on a larger representative core or the real baseline

Main-lane replay result later on 2026-04-22:

- The wrapped full-baseline narrowed-shell replay failed in late `stage6a`:
  - last completed progress:
    - `stage6a targeted techmap cells_map batch 12/15`
  - failure mode:
    - `yosys` killed with exit `137`-class behavior during the batch loop
  - monitored peak memory:
    - about `29.1 GiB` `VmRSS`
- Interpretation:
  - restart-per-batch `stage6a` improved the baseline frontier substantially
  - but it is not enough to carry the real TinyStories baseline through the
    full narrowed-shell `stage6a` band

Representative-core sweep setup later on 2026-04-22:

- Decision:
  - because the minimal representative core is too small to judge when
    `top4-memory` helps, add a real representative-core sweep instead of
    arguing from one floor
- Sweep points currently registered through the model registry:
  - `tiny-stories-1m-representative-core`
    - `vocab=32 hidden=2 layers=2 heads=1 pos=4 win=2`
  - `tiny-stories-1m-representative-core-v64-h4`
    - `vocab=64 hidden=4 layers=2 heads=1 pos=8 win=4`
  - `tiny-stories-1m-representative-core-v128-h8`
    - `vocab=128 hidden=8 layers=2 heads=2 pos=16 win=8`
  - `tiny-stories-1m-representative-core-v256-h16`
    - `vocab=256 hidden=16 layers=2 heads=4 pos=32 win=16`
  - `tiny-stories-1m-representative-core-v512-h32`
    - `vocab=512 hidden=32 layers=2 heads=4 pos=64 win=32`
  - `tiny-stories-1m-representative-core-v1024-h64`
    - `vocab=1024 hidden=64 layers=2 heads=8 pos=128 win=64`
- Structural rule kept:
  - `num_layers = 2` across the sweep so both TinyStories GPT-Neo attention
    variants remain exercised
- New flake outputs:
  - cheap manifest:
    - `tiny-stories-1m-representative-core-sweep-manifest`
  - expensive aggregate summary:
    - `tiny-stories-1m-representative-core-sweep-all-memory-vs-top4-memory-summary`
  - per-sweep-point compare outputs:
    - `<key>-all-memory-vs-top4-memory-compare`
    - plus the corresponding `selftest-all-memory-*` and
      `selftest-top4-memory-*` bundles
- Verification:
  - the sweep manifest now builds cheaply on its own
  - a nondefault sweep point was validated through the normal derivation path:
    - `nix build .#tiny-stories-1m-representative-core-v64-h4-cf-stats --no-link --print-out-paths`
    - output:
      - `/nix/store/w71iwb04zs0gpiffkbcr46nx4xqp2a6p-tiny-stories-1m-representative-core-v64-h4-cf.stats`
- Current decision:
  - use the sweep to find the crossover where `top4-memory` stops being shell
    overhead and starts reducing the real design

## StreamTensor-lite lane start on 2026-04-22

- Priority shift:
  - new lane branch: `task6-streamtensor-lite`
  - new lane worktree: `/tmp/LLM2FPGA_task6_streamtensor_lite`
  - lane note: `docs/task6-lane.md` inside that worktree
- Actual shared-plan anchor:
  - shared thread:
    `https://chatgpt.com/s/t_69e8e80bdd388191bcc4279dc0e00fc4`
  - key conclusion:
    - `StreamTensor-lite / fit-first accelerator lane` is the most promising
      active path right now
- Purpose:
  - treat this as a fit-first accelerator lane, not a generic streaming survey
    and not a full StreamTensor port
  - keep Torch-MLIR / Linalg as the frontend
  - stop treating full-model RTL lowering as the target architecture for this
    lane
  - prove that one reused kernel with external weights can change the resource
    signature away from `0 DSP / 0 BRAM`
- Immediate plan:
  - start from representative-core artifacts rather than the `top4-memory`
    shell path
  - begin with `tiny-stories-1m-representative-core-v64-h4` unless it is too
    small for the first meaningful proof
  - identify one Linalg linear / GEMV region that can be redirected into a
    small reused kernel
  - model weights as external inputs in that proof
  - require the proof to consume DSPs or otherwise visibly change the current
    all-fabric signature before promoting the lane
- Required first output:
  - shortlist of candidate insertion points with:
    - targeted linear / GEMV region
    - expected resource-signature change
    - cheapest validation artifact
    - replay target if the result is helpful

### Feedback pass later on 2026-04-22

- The lane plan was tightened to add operational rejection structure, not just
  direction:
  - hard first-proof scorecard with fixed ceilings:
    - `DSP > 0`
    - large weights not emitted as RTL constants
    - `<= 29,860` LUT
    - `<= 59,720` FF
    - Verilator pass required
  - benchmark pack with explicit time budgets:
    - export + pack `< 30 s`
    - task-graph build `< 10 s`
    - Verilator kernel test `< 20 s`
    - kernel Yosys stat `< 30 s`
    - one-block-top Yosys stat `< 2 min`
  - fixed first insertion point:
    - block-0 MLP expansion linear
    - GPT-Neo path: `transformer.h.0.mlp.c_fc`
  - frozen model ladder:
    - keep the current `v64-h4` representative-core artifact for cheap boundary
      discovery
    - add reduced-vocab, `hidden_size = 64` lane variants next:
      - `tinystories_v1k_h64_l1`
      - `tinystories_v4k_h64_l1`
      - `tinystories_v10k_h64_l1`
      - `tinystories_v10k_h64_l2`
      - `tinystories_v10k_h64_l8`
  - canonical experiment ledger moved into `docs/task6-lane-results.md`
  - whole-model TinyStories lane is now explicitly comparison-only once any
    reduced-vocab `h64` rung exists

### Follow-up feedback pass later on 2026-04-22

- The lane plan was tightened again to match the requested fast-rejection shape
  more literally:
  - the first proof record is now frozen at:
    - insertion point:
      - `transformer.h.0.mlp.c_fc`
    - representation level:
      - `linalg` on tensors immediately after Torch-MLIR backend-to-Linalg
        lowering
    - shape contract:
      - `[1, hidden_size] x [hidden_size, 4 * hidden_size]`
      - representative-core discovery rung:
        - `[1, 4] x [4, 16]`
      - reduced-vocab `h64` ladder:
        - `[1, 64] x [64, 256]`
  - the rung ladder now makes the reduced-vocab path explicit before broader
    replay:
    - `L0`:
      - synthetic `64x64` GEMV harness
    - `L1`:
      - single-op cutout from
        `tiny-stories-1m-representative-core-v64-h4`
    - `L2`:
      - `tiny-stories-v1k-h64-l1`
    - `L3`:
      - `tiny-stories-v4k-h64-l1`
    - `L4`:
      - `tiny-stories-v10k-h64-l1`
    - optional bridge rung:
      - `tiny-stories-v10k-h64-l2`
    - `L5`:
      - representative-core replay
    - `L6`:
      - real TinyStories baseline replay
  - the results ledger schema was tightened to include:
    - rung
    - insertion point
    - representation level
    - `DSP`, `BRAM`, `LUT`, `FF`
    - wall-clock
    - peak RAM
    - verdict
    - next action

### Further refinement later on 2026-04-22

- The lane was tightened again to make it operational as a daily execution loop,
  not just a well-framed concept:
  - the first-proof scorecard now includes the micro-proof runtime directly:
    - kernel Yosys stat must finish in `< 30 s`
  - the primary ladder was shortened to the minimum fast-feedback path:
    - `L0`:
      - synthetic `64x64` GEMV harness
    - `L1`:
      - single-op TinyStories linear cutout
    - `L2`:
      - `tiny-stories-v1k-h64-l1`
    - `L3`:
      - `tiny-stories-v4k-h64-l1`
    - `L4`:
      - representative-core replay
  - the larger-fidelity steps were explicitly demoted to deferred extensions:
    - `tiny-stories-v10k-h64-l1`
    - `tiny-stories-v10k-h64-l2`
    - real TinyStories baseline replay
  - the experiment ledger was renamed toward artifact-centric logging and now
    has an explicit row recording that the fast loop stops at `L4` unless the
    earlier rungs justify widening

### L0 and L1 execution start later on 2026-04-22

- `L0` implementation:
  - added a new local model:
    - `task6-l0-gemv64`
  - shape:
    - activation input `tensor<1x64xf32>`
    - weight input `tensor<64x64xf32>`
    - result `tensor<1x64xf32>`
  - purpose:
    - make the synthetic kernel explicitly external-weighted rather than
      embedding a constant matrix
- `L0` first results:
  - `linalg` now contains the expected single op:
    - `linalg.matmul ins(%arg0, %arg1 : tensor<1x64xf32>, tensor<64x64xf32>)`
  - first `yosys-stat` attempt failed at `sv` export because float externs were
    not enabled for the new model
  - after reusing the baseline float-extern wiring
    (`allowHwExterns`, per-file extern import, `fpPrimsSv`), the rerun
    succeeded
  - measured rerun:
    - wall-clock:
      - `9.23 s`
    - peak RSS:
      - `560,684 KB`
    - Yosys design cells:
      - `11,471`
    - memory bits:
      - `2,048`
    - cell signal:
      - one `$mul`
      - one `arith_mulf_in_f32_f32_out_f32`
      - one `arith_addf_in_f32_f32_out_f32`
  - interpretation:
    - the micro-proof runtime budget is already satisfied on `L0`
    - externalized weights are present at `linalg` because the matrix is a
      function argument, not a dense resource constant
    - mapped DSP / LUT / FF conclusions are still pending because this is only
      the generic Yosys stat stage
- `L1` implementation:
  - added:
    - `scripts/task6/find_l1_gemv_candidate.py`
  - artifact:
    - `artifacts/task6/streamtensor-lite/l1/representative-core-v64-h4-c_fc-candidate.json`
- `L1` first results:
  - the representative-core `linalg` export contains exactly two matching
    `1x1x4` by `1x4x16` `linalg.batch_matmul` sites across the two-layer core
  - the selected first candidate is:
    - line `363`
    - value `%75`
  - immediate surrounding structure matches the intended cutout:
    - tensor materialization into `tensor<1x4x16xf32>`
    - `linalg.batch_matmul`
    - bias-add style `linalg.generic` immediately after
  - measured candidate-finder runtime:
    - wall-clock:
      - `0.05 s`
    - peak RSS:
      - `13,024 KB`
- Next execution step:
  - begin weight-pack extraction around the selected `%75` / line `363` `L1`
    site
  - add Verilator coverage for `L0`

### L1 weight-pack extraction later on 2026-04-22

- Added:
  - `scripts/task6/export_weights_pack.py`
- First packed artifact:
  - `artifacts/task6/weights_pack/tiny-stories-1m-representative-core-v64-h4/transformer.h.0.mlp.c_fc/`
- Exported tensors:
  - `weight.bin`
    - shape:
      - `(16, 4)`
    - bytes:
      - `256`
  - `bias.bin`
    - shape:
      - `(16,)`
    - bytes:
      - `64`
  - `manifest.json`
    - records:
      - module path
      - representative-core config
      - tensor shapes
      - raw-f32-le format
- Measured export:
  - wall-clock:
    - `2.42 s`
  - peak RSS:
    - `336,816 KB`
- Interpretation:
  - the lane now has a first real external pack artifact tied directly to the
    selected `L1` `c_fc` site
  - the export + pack budget is satisfied for the representative-core proof
- Immediate next choice:
  - either build the smallest task-graph consumer around this pack
  - or add the lightest possible Verilator harness for `task6-l0-gemv64`

### L1 minimal task-graph consumer later on 2026-04-22

- Added:
  - `scripts/task6/build_task_graph.py`
- First task-graph artifact:
  - `artifacts/task6/streamtensor-lite/l1/representative-core-v64-h4-c_fc-task-graph.json`
- Measured build:
  - wall-clock:
    - `0.03 s`
  - peak RSS:
    - `13,456 KB`
- Structure:
  - one activation input
  - one packed-weight reader
  - one packed-bias reader
  - one `gemv` node
  - one `bias-add` node
  - one activation output
- Key linkage:
  - selected site:
    - line `363`
    - value `%75`
  - pack source:
    - `transformer.h.0.mlp.c_fc/manifest.json`
- Interpretation:
  - the lane now has both:
    - a first packed-weight producer
    - and a first consumer-side task graph around the same `L1` site
  - the task-graph budget is satisfied comfortably
- Immediate next choice:
  - either refine this graph into a more explicit executable contract
  - or spend the next slice on the lightest possible `task6-l0-gemv64`
    simulation harness

### L1 contract capture and pack replay later on 2026-04-22

- Added:
  - `scripts/task6/export_l1_contract.py`
  - `scripts/task6/verify_l1_contract.py`
- First contract artifact:
  - `artifacts/task6/streamtensor-lite/l1/representative-core-v64-h4-c_fc-contract/`
- Captured tensors:
  - `activation_in.bin`
    - shape:
      - `(1, 1, 4)`
    - bytes:
      - `16`
  - `activation_out.bin`
    - shape:
      - `(1, 1, 16)`
    - bytes:
      - `64`
  - `manifest.json`
    - records:
      - module path
      - representative-core config
      - sample input ids `[[0]]`
      - selected-site linkage back to line `363` / `%75`
- Measured contract capture:
  - wall-clock:
    - `2.42 s`
  - peak RSS:
    - `342,280 KB`
- First replay-check artifact:
  - `artifacts/task6/streamtensor-lite/l1/representative-core-v64-h4-c_fc-contract-check.json`
- Measured replay check:
  - wall-clock:
    - `0.93 s`
  - peak RSS:
    - `226,472 KB`
- Replay result:
  - formula:
    - `activation_in @ weight.T + bias`
  - max absolute error:
    - `0.0`
  - mean absolute error:
    - `0.0`
  - verdict:
    - `pass`
- Task-graph follow-up:
  - the minimal `L1` task graph now points at:
    - the selected `linalg` site
    - the packed weight/bias manifest
    - the captured sample contract
- Interpretation:
  - `L1` now has a real executable proof path that stays below the heavier
    handshake-level simulation boundary
  - the packed tensors are no longer only exported; they are replayed against a
    captured module-level contract with exact agreement
- Immediate next choice:
  - either add the lightest honest Verilator harness for `L0`
  - or start `L2` with the reduced-vocab `h64` ladder now that `L1` has a
    pack-backed executable contract

### L2 reduced-vocab `h64` rung start later on 2026-04-22

- Added rung definitions:
  - `tiny-stories-v1k-h64-l1`
  - `tiny-stories-v4k-h64-l1`
- Supporting script change:
  - generalized `scripts/task6/find_l1_gemv_candidate.py`
    - it now accepts explicit `lhs`, `rhs`, and `out` tensor shapes so the same
      boundary finder can work on both `L1` and reduced-vocab `h64` rungs
- First `L2` build:
  - `nix build .#tiny-stories-v1k-h64-l1-linalg --no-link --print-out-paths`
  - artifact:
    - `/nix/store/x8lnd266sjig478x9b34bmlv8p0x4m61-tiny-stories-v1k-h64-l1-linalg.mlir`
- `L2` first boundary result:
  - artifact:
    - `artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_fc-candidate.json`
  - measured candidate-finder runtime:
    - wall-clock:
      - `0.03 s`
    - peak RSS:
      - `15,644 KB`
  - selected site:
    - line `357`
    - value `%81`
  - shape contract:
    - `tensor<1x1x64xf32>`
    - `tensor<1x64x256xf32>`
    - `tensor<1x1x256xf32>`
  - interpretation:
    - the same block-0 `transformer.h.0.mlp.c_fc` boundary survives cleanly at
      the first reduced-vocab `h64` rung
    - there is exactly one matching site because the rung uses one transformer
      layer
- `L2` first packed artifact:
  - `artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_fc/`
  - measured export:
    - wall-clock:
      - `2.38 s`
    - peak RSS:
      - `337,536 KB`
  - tensor shapes:
    - weight:
      - `(256, 64)`
    - bias:
      - `(256,)`
- `L2` first contract artifact:
  - `artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_fc-contract/`
  - measured capture:
    - wall-clock:
      - `2.40 s`
    - peak RSS:
      - `342,932 KB`
  - sample contract:
    - input ids:
      - `[[0]]`
    - activation in:
      - `(1, 1, 64)`
    - activation out:
      - `(1, 1, 256)`
- `L2` replay check:
  - artifact:
    - `artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_fc-contract-check.json`
  - measured replay:
    - wall-clock:
      - `0.92 s`
    - peak RSS:
      - `226,720 KB`
  - replay result:
    - formula:
      - `activation_in @ weight.T + bias`
    - max absolute error:
      - `0.0`
    - mean absolute error:
      - `0.0`
    - verdict:
      - `pass`
- `L2` task-graph artifact:
  - `artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_fc-task-graph.json`
  - measured build:
    - wall-clock:
      - `0.03 s`
    - peak RSS:
      - `14,268 KB`
- Supporting fix:
  - generalized `scripts/task6/build_task_graph.py`
    - it now derives expected weight and bias tensor shapes from the selected
      candidate contract instead of assuming the `L1` `4 -> 16` case
- Interpretation:
  - `L2` is now active rather than planned only
  - the first reduced-vocab `h64` rung preserves the same `c_fc` boundary and
    external-pack replay contract as `L1`
  - the next decision is no longer whether `L2` exists; it is whether to widen
    to `L3` (`v4k-h64-l1`) or spend the next slice on kernel-level synthesis /
    simulation evidence

### L0 Verilator harness later on 2026-04-22

- Added:
  - `sim/gen_task6_l0_gemv64_tb_data.py`
  - `sim/task6_l0_gemv64_tb_main.sv`
  - `sim/sim_utils.py`
  - flake outputs:
    - `task6-l0-gemv64-sim-main`
    - `task6-l0-gemv64-sv-sim`
    - `task6-l0-gemv64-sv-wave`
- First pass:
  - `nix build .#task6-l0-gemv64-sv-sim --no-link -L`
  - result:
    - `PASS: stores 64 outputs 64`
- Harness contract:
  - activation source:
    - `64` deterministic `f32` words
  - weight source:
    - `4096` deterministic `f32` words
  - completion rule:
    - observe `64` stores and compare them bit-exactly against generated
      expected outputs
  - memory-side behavior:
    - one outstanding read per source plus explicit `stDone` acknowledgement
      handling so the testbench matches the kernel's external-memory handshake
- Measured direct execution:
  - command target:
    - `/nix/store/cfcang44fpaifcchz6xrny925pgzx984-task6-l0-gemv64-sim-main/obj_dir/sim_main`
  - wall-clock:
    - `0.55 s`
  - peak RSS:
    - `4,852 KB`
- Build caveat:
  - Nix did not see the new simulation files until they were tracked by git,
    because the flake source snapshot omits untracked files
- Interpretation:
  - the `L0` Verilator scorecard item now passes
  - the Verilator runtime budget is comfortably satisfied
  - the next useful slice is mapped kernel synthesis, because DSP / LUT / FF
    evidence is still the main unanswered first-proof question

### L0 mapped utilization later on 2026-04-22

- Added:
  - flake outputs:
    - `task6-l0-gemv64-json`
    - `task6-l0-gemv64-utilization`
- Supporting fix:
  - `scripts/pipeline/write_utilization_report.py`
    - it now treats mapped blackbox modules such as `LUT*`, `FDRE`, and
      `DSP48E1` as leaf cells instead of recursing into their internal
      `$specify*` scaffolding
- First mapped report:
  - `nix build .#task6-l0-gemv64-utilization --no-link --print-out-paths`
  - output:
    - `/nix/store/57r5sdcry3nmh04x5hqz8shz9w65z0a1-task6-l0-gemv64-utilization`
- Mapped resource summary:
  - DSP:
    - `4`
  - BRAM36:
    - `0`
  - CLB LUTs:
    - `32,449`
  - CLB FFs:
    - `46,736`
  - slice lower bound:
    - `5,842`
- Synth runtime from the mapped `task6-l0-gemv64.json` build log:
  - wall-clock:
    - `57.95 s`
  - peak RSS:
    - `851,592 KB`
- Interpretation:
  - the first-proof DSP requirement now passes on `L0`
  - the FF ceiling also passes on `L0`
  - the LUT ceiling still fails by `2,589` LUT, so the synthetic kernel is not
    yet small enough to count as a clean first-proof win
  - the next useful choice is to cut LUT cost before promoting the lane, not to
    spend more time on basic simulation plumbing

### L0 int16 alternate datatype probe later on 2026-04-22

- Added:
  - `src/gemv64_int16.py`
  - `src/gemv64_int16_adapter.py`
  - flake outputs:
    - `task6-l0-gemv64-int16-json`
    - `task6-l0-gemv64-int16-utilization`
- First mapped report:
  - `nix build .#task6-l0-gemv64-int16-utilization --no-link --print-out-paths`
  - output:
    - `/nix/store/li6g5avkfdfjnfffp7924m1ndrxkik6b-task6-l0-gemv64-int16-utilization`
- Timed direct synth check:
  - wall-clock:
    - `54.57 s`
  - peak RSS:
    - `873,180 KB`
- Mapped resource summary:
  - DSP:
    - `1`
  - BRAM36:
    - `0`
  - CLB LUTs:
    - `35,737`
  - CLB FFs:
    - `59,276`
  - slice lower bound:
    - `7,410`
- Interpretation:
  - the int16 variant stays buildable, but it is not an improvement over the
    float `L0` proof
  - LUT cost gets worse by `3,288` relative to the float `L0` mapped result
  - the DSP signal weakens from `4 DSP48E1` to `1 DSP48E1`
  - this is a rejection of a datatype-only int16 substitution, not a promotion
    candidate for the lane

### L0 int8 alternate datatype probe later on 2026-04-22

- Probe setup:
  - verified locally that `torch.export` plus `torch_mlir.fx.export_and_import`
    can represent `torch.aten.mm` on `si8`
  - briefly wired an `int8` `L0` adapter to test the real lane pipeline
- Failure point:
  - `task6-l0-gemv64-int8-linalg`
  - error:
    - `unimplemented: for conversion to byte or char type dstOriginalDtype has to be passed to convertScalarToDtype`
  - observed behavior:
    - `torch-mlir-opt` crashes during `torch` to `linalg` lowering on the
      `si8` `torch.aten.mm` path
- Interpretation:
  - `int8` is currently a tooling blocker rather than a usable LUT-reduction
    path in this repo state
  - do not keep an `int8` `L0` package surface active until the byte/char
    lowering bug is fixed upstream or patched locally

### L1 redirected-kernel proof later on 2026-04-22

- Added:
  - `src/task6_rect_gemv.py`
  - `src/task6_rect_gemv_adapter.py`
  - `sim/gen_task6_contract_gemv_tb_data.py`
  - `sim/task6_contract_gemv_tb_main.sv`
  - model key:
    - `task6-l1-c-fc-redirect`
- Logged run bundle:
  - `artifacts/task6-streamtensor-lite/runs/2026-04-22T23-22-07+0200/`

#### Folded-bias attempt

- Goal:
  - keep the redirect surface at two inputs by appending bias as an extra
    external weight row and a constant `1` activation lane
- Outcome:
  - structural compilation succeeded, but exact replay failed at simulation on
    all `16` outputs
  - representative log lines:
    - `FAIL: addr 0 expected 0x3d085992 got 0x3d082000`
    - `FAIL: addr 1 expected 0x3d2a1d92 got 0x3d29e000`
  - maximum observed absolute error:
    - `0.000075929`
- Interpretation:
  - do not treat algebraic bias folding as an exact replay proof under the
    current float primitive lowering path

#### Explicit external bias attempt

- Goal:
  - keep bias explicit as a third input and prove that it survives as a top
    level external memory interface
- Early IR evidence:
  - `linalg` showed:
    - `func.func @main(%arg0: tensor<1x5xf32>, %arg1: tensor<5x16xf32>, %arg2: tensor<16xf32>)`
  - the body still separated `linalg.matmul` from the later bias add
- Failure point:
  - handshake and `hw-clean` no longer surfaced bias as a top-level load
    interface
  - the lowered top instead materialized an internal `handshake_memory_out_f32`
    block for that path
- Interpretation:
  - this is the one explicit externalization failure for the L1 bias path, so
    stop spending more slices there and use the kernel-only fallback

#### Accepted kernel-only fallback

- Accepted boundary:
  - the selected pre-bias `batch_matmul` site for
    `transformer.h.0.mlp.c_fc`
- Timed `yosys-stat`:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-yosys-stat --no-link -L`
  - result:
    - `ELAPSED=4.07`
    - `RSS_KB=564032`
  - design summary:
    - `num_cells = 12611`
    - `num_memory_bits = 512`
    - `$mul = 1`
    - `arith_mulf_in_f32_f32_out_f32 = 1`
    - `arith_addf_in_f32_f32_out_f32 = 1`
- Timed mapped utilization:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-utilization --no-link --print-out-paths`
  - output:
    - `/nix/store/cgk31f78g5c0rd8bwyw98v1p38m0vz4f-task6-l1-c-fc-redirect-utilization`
  - result:
    - `ELAPSED=64.82`
    - `RSS_KB=562944`
  - mapped summary:
    - DSP:
      - `4`
    - BRAM36:
      - `0`
    - CLB LUTs:
      - `33,116`
    - CLB FFs:
      - `51,296`
- Timed Verilator proof:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-sv-sim --no-link -L`
  - result:
    - `PASS: stores 16 outputs 16`
    - `ELAPSED=61.91`
    - `RSS_KB=437820`
  - testbench rule:
    - `ABS_TOL = 1.0e-4`
  - reason for tolerance:
    - the observed mismatch scale matched the visible `q16.16` float primitive
      path, so the accepted proof checks the redirected kernel against an
      explicit absolute error bound instead of bit-exact float equality
- Weight placement evidence:
  - `hw-clean` and `main.sv` still expose top-level `in1_ld0_*` weight load
    ports, so the large `16 x 4` weight tensor is not emitted as a giant RTL
    constant bundle
- Interpretation:
  - `L1` now has a valid redirected-kernel structural proof:
    - external weights: pass
    - `yosys-stat` runtime: pass
    - mapped DSP use: pass
    - Verilator proof: pass
  - the mapped LUT count still fails the lane ceiling at `33,116 > 29,860`
  - the next useful slice is `L2`, not further L1 bias surgery

### L2 redirected-kernel proof later on 2026-04-22

- Added:
  - model key:
    - `task6-l2-c-fc-redirect`
  - flake outputs:
    - `task6-l2-c-fc-redirect-tb-data-sv`
    - `task6-l2-c-fc-redirect-sim-main`
    - `task6-l2-c-fc-redirect-json`
    - `task6-l2-c-fc-redirect-utilization`
    - `task6-l2-c-fc-redirect-sv-sim`
- Logged run bundle:
  - `artifacts/task6-streamtensor-lite/runs/2026-04-22T23-22-07+0200/`

#### Accepted reduced-vocab proof

- Accepted boundary:
  - the selected pre-bias `batch_matmul` site for
    `tiny-stories-v1k-h64-l1`
    `transformer.h.0.mlp.c_fc`
- Manifest alignment:
  - `task6-l2-c-fc-redirect-tb-data-sv`
  - output:
    - `/nix/store/kv3li6fbzgj3w1sp5zzypvrh23a7c62g-task6-l2-c-fc-redirect-tb-data-sv`
- Timed `yosys-stat`:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l2-c-fc-redirect-yosys-stat --no-link -L`
  - result:
    - `ELAPSED=9.13`
    - `RSS_KB=563512`
  - design summary:
    - `num_cells = 13703`
    - `num_memory_bits = 8192`
    - `$mul = 1`
    - `arith_mulf_in_f32_f32_out_f32 = 1`
    - `arith_addf_in_f32_f32_out_f32 = 1`
- Timed mapped utilization:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l2-c-fc-redirect-utilization --no-link --print-out-paths -L`
  - output:
    - `/nix/store/2sfssv27f1ijhwlwzaxsny76ixvjrzmn-task6-l2-c-fc-redirect-utilization`
  - result:
    - `ELAPSED=88.93`
    - `RSS_KB=562776`
  - mapped summary:
    - DSP:
      - `4`
    - BRAM36:
      - `0`
    - CLB LUTs:
      - `50,235`
    - CLB FFs:
      - `65,523`
- Timed Verilator proof:
  - first run failure:
    - `Timeout waiting for redirected GEMV completion`
  - harness fix:
    - `sim/task6_contract_gemv_tb_main.sv`
    - `TIMEOUT_CYCLES` now scales with
      `ACTIVATION_WORDS + WEIGHT_WORDS + EXPECTED_STORE_COUNT`
  - rerun command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l2-c-fc-redirect-sv-sim --no-link -L`
  - rerun result:
    - `PASS: stores 256 outputs 256`
    - `ELAPSED=47.06`
    - `RSS_KB=437352`
- Weight placement evidence:
  - `hw-clean` and `main.sv` still expose top-level `in1_ld0_*` weight load
    ports, so the reduced-vocab `256 x 64` weight tensor is still external
- Interpretation:
  - `L2` is a valid reduced-vocab redirected-kernel proof:
    - external weights: pass
    - `yosys-stat` runtime: pass
    - mapped DSP use: pass
    - Verilator proof: pass
  - `L2` is not a promotion candidate for fit-first work:
    - LUT grows from `33,116` on `L1` to `50,235`
    - FF grows from `51,296` on `L1` to `65,523`
  - the next useful slice is fit reduction on the cheaper `L1` proof, not
    larger-lane bring-up

### L1 mapper-only fit check later on 2026-04-23

- Added:
  - direct `abc9` flake outputs:
    - `task6-l0-gemv64-abc9-json`
    - `task6-l0-gemv64-abc9-utilization`
    - `task6-l1-c-fc-redirect-abc9-json`
    - `task6-l1-c-fc-redirect-abc9-utilization`
  - staged `abc9` flake outputs:
    - `task6-l1-c-fc-redirect-staged-abc9-json`
    - `task6-l1-c-fc-redirect-staged-abc9-utilization`
- Logged run bundle:
  - `artifacts/task6-streamtensor-lite/runs/2026-04-23T09-23-28+0200/`

#### Direct `abc9` control on `L0`

- Timed mapped utilization:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l0-gemv64-abc9-utilization --no-link --print-out-paths`
  - output:
    - `/nix/store/mp68ywi5hy4zr5ldvjmm0zib5a5anddh-task6-l0-gemv64-abc9-utilization`
  - result:
    - `ELAPSED=94.83`
    - `RSS_KB=561388`
  - mapped summary:
    - DSP:
      - `4`
    - BRAM36:
      - `0`
    - CLB LUTs:
      - `32,478`
    - CLB FFs:
      - `46,736`
- Interpretation:
  - direct `abc9` is not a useful `L0` fit tactic:
    - LUT rises from `32,449` to `32,478`
    - FF and DSP stay effectively unchanged

#### Direct `abc9` on the accepted `L1` kernel

- Timed mapped utilization:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-abc9-utilization --no-link --print-out-paths`
  - output:
    - `/nix/store/iamh08ddr6pahr3py2ach61abzpxbrqs-task6-l1-c-fc-redirect-abc9-utilization`
  - result:
    - `ELAPSED=94.27`
    - `RSS_KB=561892`
  - mapped summary:
    - DSP:
      - `4`
    - BRAM36:
      - `0`
    - CLB LUTs:
      - `32,236`
    - CLB FFs:
      - `51,296`
- Weight placement and replay status:
  - unchanged from the accepted kernel-only `L1` proof:
    - large weights still enter through top-level `in1_ld0_*`
    - Verilator still passes on `task6-l1-c-fc-redirect-sv-sim`
    - `yosys-stat` still fits the micro-proof budget at `4.07 s`
- Interpretation:
  - direct `abc9` is a real but insufficient improvement on the active lane:
    - LUT falls from `33,116` to `32,236`
    - the ceiling still fails by `2,376`
  - mapper choice matters, but it is not enough on its own to clear the lane

#### Staged `abc9` check on the accepted `L1` kernel

- Timed staged build:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-staged-abc9-utilization --no-link --print-out-paths`
  - result:
    - `ELAPSED=15.14`
    - `RSS_KB=564392`
  - failure:
    - `ERROR: Module \`FDRE' is used with parameters but is not parametric!`
    - failure point:
      - `task6-l1-c-fc-redirect-staged-abc9-stage8.il`
- Interpretation:
  - stop the staged micro-flow after one failure:
    - it does not currently produce a mapped JSON on the accepted `L1` kernel
    - fixing the staged Xilinx primitive handling would be plumbing work, not a
      fit-first micro-proof
  - the next useful slice is no longer mapper-only:
    - keep direct `abc9` as the current best mapped `L1` result
    - move the next effort to RTL-structural LUT reduction on the shared float
      kernel path

### L1 `ui64` buffer-lite diagnostic later on 2026-04-23

- Added:
  - override file:
    - `rtl/task6/handshake_buffer_in_ui64_out_ui64_2slots_seq.sv`
  - flake outputs:
    - `task6-l1-c-fc-redirect-ui64-buffer-lite-sim-main`
    - `task6-l1-c-fc-redirect-ui64-buffer-lite-json`
    - `task6-l1-c-fc-redirect-ui64-buffer-lite-utilization`
    - `task6-l1-c-fc-redirect-ui64-buffer-lite-sv-sim`
- Logged run bundle:
  - `artifacts/task6-streamtensor-lite/runs/2026-04-23T09-23-28+0200/`

#### Why this slice

- Structural inspection of the accepted `L1` RTL showed:
  - `204` instances of `handshake_buffer_in_ui64_out_ui64_2slots_seq`
  - `48` instances of `handshake_buffer_in_none_out_none_2slots_seq_1ins_1outs_ctrl`
  - only one `arith_mulf_in_f32_f32_out_f32` and one
    `arith_addf_in_f32_f32_out_f32`
- that made the `ui64` two-slot buffer the cheapest first target for a fit
  probe without broad compiler surgery

#### Functional check

- Timed Verilator proof:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-ui64-buffer-lite-sv-sim --no-link -L`
  - tracked-file reminder:
    - the first rerun failed until `rtl/task6/handshake_buffer_in_ui64_out_ui64_2slots_seq.sv`
      was git-tracked, because the flake source snapshot omits untracked files
  - tested variants:
    - strict one-slot FIFO
    - fall-through skid-style one-slot FIFO
  - final result:
    - `ELAPSED=22.69`
    - `RSS_KB=437508`
    - `Timeout waiting for redirected GEMV completion`
- Interpretation:
  - the current `ui64` one-slot replacements are not valid drop-ins for the
    accepted `L1` handshake schedule
  - this counts as two failures of the same replacement class, so do not spend
    another slice on a third ad hoc `ui64` one-slot variant without a stronger
    semantic argument

#### Fit-only diagnostic

- Timed mapped utilization:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-ui64-buffer-lite-utilization --no-link --print-out-paths`
  - output:
    - `/nix/store/aw5y4ri37p3zp0dksym0y2f2agm5p5ax-task6-l1-c-fc-redirect-ui64-buffer-lite-utilization`
  - result:
    - `ELAPSED=53.61`
    - `RSS_KB=562884`
  - mapped summary:
    - DSP:
      - `4`
    - BRAM36:
      - `0`
    - CLB LUTs:
      - `20,725`
    - CLB FFs:
      - `15,731`
- Primitive signature:
  - `FDRE` drops from `51,293` on the accepted `L1` proof to `15,728`
  - `LUT6` drops from `19,276` to `3,750`
- Interpretation:
  - this is the strongest fit signal in the lane so far:
    - replacing only the `ui64` two-slot buffer class pushes the mapped design
      comfortably under the LUT ceiling while keeping `4 DSP48E1`
  - but it is diagnostic only:
    - the current replacement breaks the kernel contract, so it is not a valid
      promotion candidate
  - the next useful slice is now clear:
    - preserve the accepted `L1` functionality
    - find a semantically correct way to cut `ui64` buffer state, likely by
      targeting only a subset of buffers or by matching the existing ready/valid
      scheduling more faithfully than a generic one-slot drop-in

### L1 selective `buffer165` FIFO2 proof later on 2026-04-23

- Added:
  - helper module:
    - `rtl/task6/task6_ui64_fifo2_buffer.sv`
  - flake outputs:
    - `task6-l1-c-fc-redirect-buffer165-fifo2-sim-main`
    - `task6-l1-c-fc-redirect-buffer165-fifo2-sv-sim`
    - `task6-l1-c-fc-redirect-buffer165-fifo2-json`
    - `task6-l1-c-fc-redirect-buffer165-fifo2-utilization`
- Logged run bundle:
  - `artifacts/task6-streamtensor-lite/runs/2026-04-23T10-59-21+0200/`

#### Why this slice

- The class-wide `ui64` buffer replacements failed three times:
  - strict one-slot FIFO
  - fall-through one-slot FIFO
  - class-wide lean two-entry FIFO
- the next smallest non-redundant test was a single central loop-index site:
  - `handshake_buffer165`
  - this is the buffer that feeds `handshake_fork34`, which fans the loop index
    into the `handshake_mux30..37` selection tree

#### Functional proof

- Timed Verilator proof:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-buffer165-fifo2-sv-sim --no-link -L`
  - result:
    - `PASS: stores 16 outputs 16`
    - `ELAPSED=56.13`
    - `RSS_KB=437056`
- Interpretation:
  - targeted replacement is viable:
    - at least one central `ui64` loop-index buffer can move to the lean FIFO2
      implementation without breaking the accepted `L1` contract

#### Mapped utilization

- Timed mapped utilization:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-buffer165-fifo2-utilization --no-link --print-out-paths`
  - output:
    - `/nix/store/ay0550kjz47qmv3ig0wrr212sflz78fd-task6-l1-c-fc-redirect-buffer165-fifo2-utilization`
  - result:
    - `ELAPSED=66.21`
    - `RSS_KB=562608`
  - mapped summary:
    - DSP:
      - `4`
    - BRAM36:
      - `0`
    - CLB LUTs:
      - `33,020`
    - CLB FFs:
      - `51,292`
- Delta against accepted base `L1`:
  - LUT:
    - `33,116 -> 33,020` (`-96`)
  - FF:
    - `51,296 -> 51,292` (`-4`)
- Interpretation:
  - a single safe replacement is not enough to matter on its own
  - but it proves the right next shape:
    - do not replace the full `ui64` buffer class again
    - widen only within the same local index-distribution spine and keep
      Verilator as the immediate gate

### L1 class-wide `ui64` FIFO2 rejection later on 2026-04-23

- Added:
  - helper module:
    - `rtl/task6/handshake_buffer_in_ui64_out_ui64_2slots_seq_fifo2.sv`
  - flake outputs:
    - `task6-l1-c-fc-redirect-ui64-buffer-fifo2-sim-main`
    - `task6-l1-c-fc-redirect-ui64-buffer-fifo2-sv-sim`
    - `task6-l1-c-fc-redirect-ui64-buffer-fifo2-json`
    - `task6-l1-c-fc-redirect-ui64-buffer-fifo2-utilization`
- Logged run bundle:
  - `artifacts/task6-streamtensor-lite/runs/2026-04-23T11-05-39+0200/l1-ui64-buffer-fifo2-reject/summary.md`

#### Why this slice

- The one-slot class-wide replacements had already failed twice:
  - strict FIFO
  - fall-through FIFO
- the smallest remaining same-class check was a class-wide lean two-entry FIFO:
  - keep the `ui64` buffer interface and depth at `2`
  - cut the internal state and control logic compared with the generated
    baseline implementation

#### Functional proof

- Timed Verilator proof:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-ui64-buffer-fifo2-sv-sim --no-link -L`
  - result:
    - `Timeout waiting for redirected GEMV completion`
    - `ELAPSED=42.50`
    - `RSS_KB=437644`
- Interpretation:
  - this is the third failure of the same whole-class path:
    - one-slot strict
    - one-slot fall-through
    - two-slot FIFO2
  - per lane rules, whole-class `ui64` buffer replacement should stop here

### L1 selective index-spine FIFO2 proof later on 2026-04-23

- Added:
  - flake outputs:
    - `task6-l1-c-fc-redirect-index-spine-fifo2-sim-main`
    - `task6-l1-c-fc-redirect-index-spine-fifo2-sv-sim`
    - `task6-l1-c-fc-redirect-index-spine-fifo2-json`
    - `task6-l1-c-fc-redirect-index-spine-fifo2-utilization`
- Logged run bundle:
  - `artifacts/task6-streamtensor-lite/runs/2026-04-23T11-05-39+0200/l1-index-spine-fifo2-proof/summary.md`

#### Why this slice

- After the class-wide path was exhausted, the next bounded test was a local
  cluster around the already-safe `handshake_buffer165` site:
  - `handshake_buffer160`
  - `handshake_buffer161`
  - `handshake_buffer162`
  - `handshake_buffer163`
  - `handshake_buffer164`
  - `handshake_buffer165`
- these six sites sit on the same loop-index distribution spine feeding the
  local `handshake_mux30..37` / `handshake_cond_br32..39` region

#### Functional proof

- Timed Verilator proof:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-spine-fifo2-sv-sim --no-link -L`
  - result:
    - `PASS: stores 16 outputs 16`
    - `ELAPSED=58.30`
    - `RSS_KB=437376`
- Interpretation:
  - the safe selective replacement can widen at least across this local spine
    without breaking the accepted `L1` contract

#### Mapped utilization

- Timed mapped utilization:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-spine-fifo2-utilization --no-link --print-out-paths`
  - output:
    - `/nix/store/dkwlcml8ckf8gg5kx2c3v4w8d5yq43i6-task6-l1-c-fc-redirect-index-spine-fifo2-utilization`
  - result:
    - `ELAPSED=64.88`
    - `RSS_KB=563044`
  - mapped summary:
    - DSP:
      - `4`
    - BRAM36:
      - `0`
    - CLB LUTs:
      - `32,808`
    - CLB FFs:
      - `50,642`
- Primitive signature:
  - `FDRE`:
    - `50,639`
  - `LUT6`:
    - `18,981`
  - `LUT3`:
    - `6,595`
  - `LUT2`:
    - `3,591`
- Weight placement and runtime checks:
  - large weights emitted as RTL constants:
    - `no`
    - this slice only swaps selected buffer instances in copied `sv/main.sv`,
      so it inherits the accepted `L1` externalized-weight path unchanged
  - Yosys stat finished within budget:
    - `yes`
    - unchanged from the accepted `L1` kernel at `4.07 s`
- Delta against accepted base `L1`:
  - LUT:
    - `33,116 -> 32,808` (`-308`)
  - FF:
    - `51,296 -> 50,642` (`-654`)
- Interpretation:
  - the widened local spine is a real safe improvement, not measurement noise
  - but it still misses the LUT ceiling and still trails the direct `abc9`
    result of `32,236` LUT
  - the next cheapest valid slice is to test whether this safe structural
    reduction stacks with `abc9` before widening to more buffer sites

### L1 selective index-spine FIFO2 `abc9` proof later on 2026-04-23

- Added:
  - flake outputs:
    - `task6-l1-c-fc-redirect-index-spine-fifo2-abc9-json`
    - `task6-l1-c-fc-redirect-index-spine-fifo2-abc9-utilization`
- Logged run bundle:
  - `artifacts/task6-streamtensor-lite/runs/2026-04-23T11-09-44+0200/l1-index-spine-fifo2-abc9-proof/summary.md`

#### Why this slice

- The two strongest valid `L1` signals before this point were:
  - direct `abc9`:
    - `32,236` LUT
  - safe local `160..165` FIFO2 spine:
    - `32,808` LUT
- the cheapest remaining learning step was to test whether those two valid
  reductions compose without widening the structural patch

#### Mapped utilization

- Timed mapped utilization:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-spine-fifo2-abc9-utilization --no-link --print-out-paths`
  - output:
    - `/nix/store/0hxm9fclxr0sgg5wl6nq2w0r7f568p60-task6-l1-c-fc-redirect-index-spine-fifo2-abc9-utilization`
  - result:
    - `ELAPSED=92.79`
    - `RSS_KB=562772`
  - mapped summary:
    - DSP:
      - `4`
    - BRAM36:
      - `0`
    - CLB LUTs:
      - `32,036`
    - CLB FFs:
      - `50,642`
- Primitive signature:
  - `FDRE`:
    - `50,639`
  - `LUT6`:
    - `17,374`
  - `LUT3`:
    - `6,570`
  - `LUT2`:
    - `3,474`
  - `LUT5`:
    - `3,086`
- Weight placement and runtime checks:
  - large weights emitted as RTL constants:
    - `no`
    - this slice still reuses the accepted external-weight `L1` kernel and only
      changes selected buffer modules plus mapper selection
  - Verilator passed:
    - `yes`
    - inherited from the identical `task6-l1-c-fc-redirect-index-spine-fifo2`
      structural variant
  - Yosys stat finished within budget:
    - `yes`
    - unchanged from the accepted `L1` kernel at `4.07 s`
- Delta against prior `L1` points:
  - accepted base `L1`:
    - `33,116 -> 32,036` LUT (`-1,080`)
    - `51,296 -> 50,642` FF (`-654`)
  - direct `abc9`:
    - `32,236 -> 32,036` LUT (`-200`)
  - non-`abc9` local spine:
    - `32,808 -> 32,036` LUT (`-772`)
- Interpretation:
  - the safe local FIFO2 reduction and `abc9` do compose
  - this is the best `L1` mapped result in the lane so far, but it still misses
    the LUT ceiling by `2,176`
  - the next bounded local test is one more adjacent buffer cluster under the
    same `abc9` recipe, because the structural path is now validated and still
    has measurable headroom

### L1 selective index-fanout FIFO2 `abc9` proof later on 2026-04-23

- Added:
  - flake outputs:
    - `task6-l1-c-fc-redirect-index-fanout-fifo2-sim-main`
    - `task6-l1-c-fc-redirect-index-fanout-fifo2-sv-sim`
    - `task6-l1-c-fc-redirect-index-fanout-fifo2-abc9-json`
    - `task6-l1-c-fc-redirect-index-fanout-fifo2-abc9-utilization`
- Logged run bundle:
  - `artifacts/task6-streamtensor-lite/runs/2026-04-23T11-14-57+0200/l1-index-fanout-fifo2-abc9-proof/summary.md`

#### Why this slice

- The current safe local recipe had already improved twice:
  - `160..165` index spine:
    - `32,036` LUT under `abc9`
- the next directly adjacent ring is the `ui64` branch-output fanout driven by
  that spine:
  - `handshake_buffer173`
  - `handshake_buffer174`
  - `handshake_buffer175`
  - `handshake_buffer176`
  - `handshake_buffer177`
  - `handshake_buffer178`
  - `handshake_buffer179`
  - `handshake_buffer180`
  - `handshake_buffer181`
  - `handshake_buffer182`
- the exact hypothesis was:
  - if this immediate fanout ring still passes the kernel contract, the local
    FIFO2 replacement has not yet reached its safe boundary

#### Functional proof

- Timed Verilator proof:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-fanout-fifo2-sv-sim --no-link -L`
  - result:
    - `PASS: stores 16 outputs 16`
    - `ELAPSED=65.50`
    - `RSS_KB=436664`
- Interpretation:
  - the safe selective region extends through this immediate downstream fanout
    ring; the next gate remains mapped utilization, not more functional debug

#### Mapped utilization

- Timed mapped utilization:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-fanout-fifo2-abc9-utilization --no-link --print-out-paths`
  - output:
    - `/nix/store/adf0la4c5xkqdmvc6n5i37db5zaz929x-task6-l1-c-fc-redirect-index-fanout-fifo2-abc9-utilization`
  - result:
    - `ELAPSED=93.49`
    - `RSS_KB=563372`
  - mapped summary:
    - DSP:
      - `4`
    - BRAM36:
      - `0`
    - CLB LUTs:
      - `31,309`
    - CLB FFs:
      - `49,342`
- Primitive signature:
  - `FDRE`:
    - `49,339`
  - `LUT6`:
    - `16,067`
  - `LUT3`:
    - `7,213`
  - `LUT2`:
    - `3,392`
  - `LUT5`:
    - `3,101`
- Weight placement and runtime checks:
  - large weights emitted as RTL constants:
    - `no`
    - this variant still only swaps selected local buffer instances and keeps
      the accepted externalized-weight `L1` kernel intact
  - Verilator passed:
    - `yes`
  - Yosys stat finished within budget:
    - `yes`
    - unchanged from the accepted `L1` kernel at `4.07 s`
- Delta against prior `L1` points:
  - previous best `index-spine-fifo2-abc9`:
    - `32,036 -> 31,309` LUT (`-727`)
    - `50,642 -> 49,342` FF (`-1,300`)
  - accepted base `L1`:
    - `33,116 -> 31,309` LUT (`-1,807`)
    - `51,296 -> 49,342` FF (`-1,954`)
- Interpretation:
  - the local selective FIFO2 path is still productive and not yet at noise
  - this is the best `L1` mapped result in the lane so far, now within `1,449`
    LUT of the ceiling while preserving `4 DSP48E1`
  - the next bounded question is whether one further adjacent hop keeps paying
    or whether the local fit curve is flattening

### L1 selective index ring-2 FIFO2 `abc9` proof later on 2026-04-23

- Added:
  - flake outputs:
    - `task6-l1-c-fc-redirect-index-ring2-fifo2-sim-main`
    - `task6-l1-c-fc-redirect-index-ring2-fifo2-sv-sim`
    - `task6-l1-c-fc-redirect-index-ring2-fifo2-abc9-json`
    - `task6-l1-c-fc-redirect-index-ring2-fifo2-abc9-utilization`
- Logged run bundle:
  - `artifacts/task6-streamtensor-lite/runs/2026-04-23T11-20-09+0200/l1-index-ring2-fifo2-abc9-proof/summary.md`

#### Why this slice

- After the `173..182` fanout ring still improved fit materially, the next
  directly connected `ui64` ring was:
  - `handshake_buffer185`
  - `handshake_buffer186`
  - `handshake_buffer187`
  - `handshake_buffer188`
  - `handshake_buffer189`
  - `handshake_buffer190`
  - `handshake_buffer191`
  - `handshake_buffer192`
- these buffers are the next immediate downstream stage fed by the already-safe
  local ring, so they were the smallest remaining adjacent expansion

#### Functional proof

- Timed Verilator proof:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-ring2-fifo2-sv-sim --no-link -L`
  - result:
    - `PASS: stores 16 outputs 16`
    - `ELAPSED=69.90`
    - `RSS_KB=436804`
- Interpretation:
  - the safe local replacement region extends through this second downstream
    ring as well

#### Mapped utilization

- Timed mapped utilization:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-ring2-fifo2-abc9-utilization --no-link --print-out-paths`
  - output:
    - `/nix/store/saahgj5jaiv7bvhxjds1qypv62q57wbg-task6-l1-c-fc-redirect-index-ring2-fifo2-abc9-utilization`
  - result:
    - `ELAPSED=93.67`
    - `RSS_KB=563284`
  - mapped summary:
    - DSP:
      - `4`
    - BRAM36:
      - `0`
    - CLB LUTs:
      - `30,762`
    - CLB FFs:
      - `48,302`
- Primitive signature:
  - `FDRE`:
    - `48,299`
  - `LUT6`:
    - `15,147`
  - `LUT3`:
    - `7,614`
  - `LUT2`:
    - `3,299`
  - `LUT5`:
    - `3,135`
- Weight placement and runtime checks:
  - large weights emitted as RTL constants:
    - `no`
  - Verilator passed:
    - `yes`
  - Yosys stat finished within budget:
    - `yes`
    - unchanged from the accepted `L1` kernel at `4.07 s`
- Delta against prior `L1` points:
  - previous best `index-fanout-fifo2-abc9`:
    - `31,309 -> 30,762` LUT (`-547`)
    - `49,342 -> 48,302` FF (`-1,040`)
  - accepted base `L1`:
    - `33,116 -> 30,762` LUT (`-2,354`)
    - `51,296 -> 48,302` FF (`-2,994`)
- Interpretation:
  - the widening curve is still improving and has not flattened yet
  - this is the best `L1` mapped result in the lane so far, now only `902` LUT
    above the ceiling while preserving `4 DSP48E1`
  - the next bounded question is whether the connected `213..219` mux-return
    buffers provide one last meaningful drop or whether this is where the local
    buffer path tops out

### L1 selective index ring-3 FIFO2 `abc9` proof later on 2026-04-23

- Added:
  - flake outputs:
    - `task6-l1-c-fc-redirect-index-ring3-fifo2-sim-main`
    - `task6-l1-c-fc-redirect-index-ring3-fifo2-sv-sim`
    - `task6-l1-c-fc-redirect-index-ring3-fifo2-abc9-json`
    - `task6-l1-c-fc-redirect-index-ring3-fifo2-abc9-utilization`
- Logged run bundle:
  - `artifacts/task6-streamtensor-lite/runs/2026-04-23T11-24-52+0200/l1-index-ring3-fifo2-abc9-proof/summary.md`

#### Why this slice

- The next still-local connected `ui64` stage after ring-2 was the mux-return
  ring:
  - `handshake_buffer213`
  - `handshake_buffer214`
  - `handshake_buffer215`
  - `handshake_buffer216`
  - `handshake_buffer217`
  - `handshake_buffer218`
  - `handshake_buffer219`
- this was treated as the last blind local hop worth checking before the region
  became too diffuse for fast-learning work

#### Functional proof

- Timed Verilator proof:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-ring3-fifo2-sv-sim --no-link -L`
  - result:
    - `PASS: stores 16 outputs 16`
    - `ELAPSED=82.55`
    - `RSS_KB=437104`
- Interpretation:
  - the connected mux-return ring is still structurally safe under the kernel
    contract

#### Mapped utilization

- Timed mapped utilization:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-ring3-fifo2-abc9-utilization --no-link --print-out-paths`
  - output:
    - `/nix/store/y57gd36j5fbplkw51iv6if0cflppn052-task6-l1-c-fc-redirect-index-ring3-fifo2-abc9-utilization`
  - result:
    - `ELAPSED=93.19`
    - `RSS_KB=563112`
  - mapped summary:
    - DSP:
      - `4`
    - BRAM36:
      - `0`
    - CLB LUTs:
      - `30,320`
    - CLB FFs:
      - `47,392`
- Primitive signature:
  - `FDRE`:
    - `47,389`
  - `LUT6`:
    - `14,728`
  - `LUT3`:
    - `7,749`
  - `LUT2`:
    - `3,242`
  - `LUT5`:
    - `3,132`
- Weight placement and runtime checks:
  - large weights emitted as RTL constants:
    - `no`
  - Verilator passed:
    - `yes`
  - Yosys stat finished within budget:
    - `yes`
    - unchanged from the accepted `L1` kernel at `4.07 s`
- Delta against prior `L1` points:
  - previous best `index-ring2-fifo2-abc9`:
    - `30,762 -> 30,320` LUT (`-442`)
    - `48,302 -> 47,392` FF (`-910`)
  - accepted base `L1`:
    - `33,116 -> 30,320` LUT (`-2,796`)
    - `51,296 -> 47,392` FF (`-3,904`)
- Interpretation:
  - the local selective path still improves, but the gains are tapering
  - this is the best `L1` mapped result in the lane so far, now only `460` LUT
    above the ceiling while preserving `4 DSP48E1`
  - this is a good place to stop blind widening:
    - the next move should be a deliberate choice among the remaining adjacent
      control/merge sites rather than another generic ring expansion

### L1 deliberate control-merge FIFO2 `abc9` proof later on 2026-04-23

- Added:
  - `rtl/task6/task6_ctrl_fifo2_buffer.sv`
  - flake outputs:
    - `task6-l1-c-fc-redirect-index-ring3-ctrlmerge-fifo2-sim-main`
    - `task6-l1-c-fc-redirect-index-ring3-ctrlmerge-fifo2-sv-sim`
    - `task6-l1-c-fc-redirect-index-ring3-ctrlmerge-fifo2-json`
    - `task6-l1-c-fc-redirect-index-ring3-ctrlmerge-fifo2-abc9-json`
    - `task6-l1-c-fc-redirect-index-ring3-ctrlmerge-fifo2-abc9-utilization`
- Logged run bundle:
  - `artifacts/task6-streamtensor-lite/runs/2026-04-23T12-36-17+0200/l1-index-ring3-ctrlmerge-fifo2-proof/summary.md`

#### Why this slice

- The shared follow-up instruction was to:
  - freeze `task6-l1-c-fc-redirect-index-ring3-fifo2-abc9` as the reference
  - avoid more blind ring expansion
  - do one deliberate hotspot pass on the remaining nearby control or merge
    state
- The nearest still-local control-heavy sites around the frozen ring-3 region
  were:
  - `handshake_buffer194`
  - `handshake_buffer220`
  - `handshake_buffer229`
  - `handshake_buffer237`
- These buffers feed the nearby control-merge chain:
  - `handshake_buffer194 -> handshake_buffer220 -> handshake_control_merge2`
  - `handshake_buffer229 -> handshake_buffer237 -> handshake_control_merge1`
- The specific hypothesis was:
  - if these zero-width control buffers were still overprovisioned in the same
    way as the already-profitable `ui64` ring, a lean FIFO2 replacement might
    close the remaining `460` LUT gap without broadening the patch radius

#### Functional proof

- Because the derivation was already cached, the timed rerun first deleted the
  previous simulation outputs:
  - `nix-store --delete /nix/store/1xphnja7abzdswcfxqmhcfz3lj0y1wja-task6-l1-c-fc-redirect-index-ring3-ctrlmerge-fifo2-sim-main /nix/store/llngvrfdwz6a78hwml7ia2k6pam9i56c-task6-l1-c-fc-redirect-index-ring3-ctrlmerge-fifo2-sv-sim.json >/dev/null`
- Timed Verilator proof:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-ring3-ctrlmerge-fifo2-sv-sim --no-link -L`
  - result:
    - `PASS: stores 16 outputs 16`
    - `ELAPSED=149.22`
    - `RSS_KB=436284`
- Interpretation:
  - the deliberate control/merge hotspot is contract-safe, so the result is a
    real fit comparison rather than another functional dead end

#### Mapped utilization

- Timed mapped utilization:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-ring3-ctrlmerge-fifo2-abc9-utilization --no-link --print-out-paths`
  - output:
    - `/nix/store/h6mh3s3skf8spnczfabhl71khhb6asgv-task6-l1-c-fc-redirect-index-ring3-ctrlmerge-fifo2-abc9-utilization`
  - result:
    - `ELAPSED=156.72`
    - `RSS_KB=562952`
  - mapped summary:
    - DSP:
      - `4`
    - BRAM36:
      - `0`
    - CLB LUTs:
      - `30,360`
    - CLB FFs:
      - `47,384`
- Primitive signature:
  - `FDRE`:
    - `47,381`
  - `LUT6`:
    - `14,718`
  - `LUT3`:
    - `7,740`
  - `LUT2`:
    - `3,297`
  - `LUT5`:
    - `3,140`
- Weight placement and runtime checks:
  - large weights emitted as RTL constants:
    - `no`
    - this slice still reuses the accepted external-weight `L1` kernel and only
      changes four local control buffers plus the helper module they instantiate
  - Verilator passed:
    - `yes`
  - Yosys stat finished within budget:
    - `yes`
    - unchanged from the accepted `L1` kernel at `4.07 s`
- Delta against the frozen ring-3 reference:
  - LUT:
    - `30,320 -> 30,360` (`+40`)
  - FF:
    - `47,392 -> 47,384` (`-8`)
- Interpretation:
  - this hotspot is real and safe, but it is not a fit win
  - the result is close enough to rule out measurement noise as the likely
    explanation, but it still points the wrong way on the metric that matters
  - the right conclusion is to keep
    `task6-l1-c-fc-redirect-index-ring3-fifo2-abc9` frozen as the current `L1`
    reference and stop spending more slices on this local control/merge branch

### Reduced-vocab one-block-top Yosys gate later on 2026-04-23

- Logged run bundle:
  - `artifacts/task6-streamtensor-lite/runs/2026-04-23T12-36-17+0200/l1-one-block-top-yosys-gate/summary.md`

#### Why this gate

- The shared follow-up instruction also required:
  - after one deliberate hotspot pass, run the pending one-block-top Yosys gate
    before any `L3` or `L4` promotion
- The repo surface available for that check is:
  - `tiny-stories-v1k-h64-l1-selftest-top4-memory-yosys-json`
- This is a `yosys-json` gate rather than a dedicated `yosys-stat` package, but
  it exercises the one-block-top build path and is the existing reproducible
  budget gate in-tree

#### Timed gate

- Timed one-block-top Yosys build:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#tiny-stories-v1k-h64-l1-selftest-top4-memory-yosys-json --no-link --print-out-paths`
  - output:
    - `/nix/store/hh7fkqlis1kdgi07qgmxxjl1nl6lxrq9-tiny-stories-v1k-h64-l1-selftest-top4-memory-yosys.json`
  - result:
    - `ELAPSED=99.26`
    - `RSS_KB=564340`

#### Interpretation

- Relative to the lane budget:
  - one-block-top Yosys gate:
    - `99.26 s`
    - this passes the `< 2 min` budget
- Structural implications:
  - the promotion gate is no longer missing
  - but it does not rescue the fit-first decision:
    - the frozen `L1` reference still sits at `30,320` LUT, which is `460` over
      the ceiling
    - the best reduced-vocab `L2` mapped replay is still materially worse than
      that reference
- Conclusion:
  - do not widen to `L3` or `L4` from this result alone
  - the next slice, if any, should be a different fit lever than the rejected
    control/merge hotspot

### L1 local `ui1` selector-buffer FIFO2 proof later on 2026-04-23

- Added:
  - `rtl/task6/task6_ui1_fifo2_buffer.sv`
  - flake outputs:
    - `task6-l1-c-fc-redirect-index-ring3-ui1buf263-fifo2-sim-main`
    - `task6-l1-c-fc-redirect-index-ring3-ui1buf263-fifo2-sv-sim`
    - `task6-l1-c-fc-redirect-index-ring3-ui1buf263-fifo2-abc9-json`
    - `task6-l1-c-fc-redirect-index-ring3-ui1buf263-fifo2-abc9-utilization`
- Logged run bundle:
  - `artifacts/task6-streamtensor-lite/runs/2026-04-23T12-49-10+0200/l1-index-ring3-ui1buf263-fifo2-proof/summary.md`

#### Why this slice

- After the control/merge hotspot missed, the next smallest visibly different
  fit lever near the frozen ring-3 region was not another `ui64` branch
  widening, but the selector-side `ui1` state feeding the local fanout:
  - `arith_cmpi5 -> handshake_buffer263 -> handshake_fork49`
- Only six `handshake_buffer_in_ui1_out_ui1_2slots_seq` instances exist in the
  whole kernel, and `handshake_buffer263` is the one sitting directly inside
  the ring-3 neighborhood.
- The specific hypothesis was:
  - if the local compare result buffer is overbuilt in the same way as the
    profitable `ui64` buffers, replacing just this one selector buffer with a
    lean FIFO2 helper might recover LUT without another broad patch

#### Implementation note

- The first mapped build attempt exposed a packaging bug, not a design failure:
  - the copied source bundle still referenced the parent `sources.f` paths, so
    `mkSynthJson` saw both the old and new `main.sv` and failed with a duplicate
    `main` definition
- That was fixed by rewriting `sources.f` and `sv/filelist.f` to the new output
  directory before rerunning the probe.

#### Functional proof

- Timed Verilator proof:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-ring3-ui1buf263-fifo2-sv-sim --no-link -L`
  - result:
    - `PASS: stores 16 outputs 16`
    - `ELAPSED=150.24`
    - `RSS_KB=436780`
- Interpretation:
  - trimming this one selector-side `ui1` buffer is contract-safe

#### Mapped utilization

- Timed mapped utilization:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-ring3-ui1buf263-fifo2-abc9-utilization --no-link --print-out-paths`
  - output:
    - `/nix/store/ga92apld656zs2h1w0515iw76yr9ppmm-task6-l1-c-fc-redirect-index-ring3-ui1buf263-fifo2-abc9-utilization`
  - result:
    - `ELAPSED=150.20`
    - `RSS_KB=561796`
  - mapped summary:
    - DSP:
      - `4`
    - BRAM36:
      - `0`
    - CLB LUTs:
      - `30,370`
    - CLB FFs:
      - `47,388`
- Primitive signature:
  - `FDRE`:
    - `47,385`
  - `LUT6`:
    - `14,711`
  - `LUT3`:
    - `7,746`
  - `LUT2`:
    - `3,271`
  - `LUT5`:
    - `3,114`
- Weight placement and runtime checks:
  - large weights emitted as RTL constants:
    - `no`
  - Verilator passed:
    - `yes`
  - Yosys stat finished within budget:
    - `yes`
    - unchanged from the accepted `L1` kernel at `4.07 s`
- Delta against the frozen ring-3 reference:
  - LUT:
    - `30,320 -> 30,370` (`+50`)
  - FF:
    - `47,392 -> 47,388` (`-4`)
- Interpretation:
  - the local `ui1` selector-buffer trim is real and safe, but it is not a fit
    win
  - this is the second deliberate post-ring-3 hotspot that points the wrong
    way on LUT, so it should not become the next default lane direction

### L1 local `fork49` statevec proof later on 2026-04-23

- Added:
  - `rtl/task6/task6_ui1_fork5.sv`
  - flake outputs:
    - `task6-l1-c-fc-redirect-index-ring3-fork49-statevec-sim-main`
    - `task6-l1-c-fc-redirect-index-ring3-fork49-statevec-sv-sim`
    - `task6-l1-c-fc-redirect-index-ring3-fork49-statevec-abc9-json`
    - `task6-l1-c-fc-redirect-index-ring3-fork49-statevec-abc9-utilization`
- Logged run bundle:
  - `artifacts/task6-streamtensor-lite/runs/2026-04-23T13-02-39+0200/l1-index-ring3-fork49-statevec-proof/summary.md`

#### Why this slice

- After the selector-buffer trim missed, the next smallest visibly different
  fit lever in the same frozen ring-3 neighborhood was the five-way local
  selector fork itself:
  - `handshake_buffer263 -> handshake_fork49`
- The generated `handshake_fork49` implementation keeps one scalar `emitted`
  register per output leg.
- The specific hypothesis was:
  - a semantically equivalent local helper that keeps the same staggered
    handshake contract but packs completion state into one vector might let
    `abc9` share the control terms more effectively than the generated fork

#### Functional proof

- Timed Verilator proof:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-ring3-fork49-statevec-sv-sim --no-link -L`
  - result:
    - `PASS: stores 16 outputs 16`
    - `ELAPSED=147.32`
    - `RSS_KB=437320`
- Interpretation:
  - trimming only the local `fork49` state encoding is contract-safe

#### Mapped utilization

- Timed mapped utilization:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-ring3-fork49-statevec-abc9-utilization --no-link --print-out-paths`
  - output:
    - `/nix/store/gii6p7aprr0szvjfr8vg6m1sylywa081-task6-l1-c-fc-redirect-index-ring3-fork49-statevec-abc9-utilization`
  - result:
    - `ELAPSED=144.56`
    - `RSS_KB=562532`
  - mapped summary:
    - DSP:
      - `4`
    - BRAM36:
      - `0`
    - CLB LUTs:
      - `30,358`
    - CLB FFs:
      - `47,392`
- Primitive signature:
  - `FDRE`:
    - `47,389`
  - `LUT6`:
    - `14,734`
  - `LUT3`:
    - `7,754`
  - `LUT2`:
    - `3,276`
  - `LUT5`:
    - `3,130`
- Weight placement and runtime checks:
  - large weights emitted as RTL constants:
    - `no`
  - Verilator passed:
    - `yes`
  - Yosys stat finished within budget:
    - `yes`
    - unchanged from the accepted `L1` kernel at `4.07 s`
- Delta against the frozen ring-3 reference:
  - LUT:
    - `30,320 -> 30,358` (`+38`)
  - FF:
    - `47,392 -> 47,392` (`+0`)
- Interpretation:
  - the local `fork49` statevec helper is safe and the least-bad post-ring-3
    hotspot miss so far, but it is still not a fit win
  - this is the third deliberate post-ring-3 hotspot miss, so the lane should
    move on from local hotspot surgery rather than stacking more nearby buffer
    or fork micro-swaps

### L1 selector-cluster FIFO2 proof later on 2026-04-23

- Added:
  - `rtl/task6/task6_ui1_init0_fifo2_fork4.sv`
  - flake outputs:
    - `task6-l1-c-fc-redirect-index-ring3-selectcluster-fifo2-sim-main`
    - `task6-l1-c-fc-redirect-index-ring3-selectcluster-fifo2-sv-sim`
    - `task6-l1-c-fc-redirect-index-ring3-selectcluster-fifo2-abc9-json`
    - `task6-l1-c-fc-redirect-index-ring3-selectcluster-fifo2-abc9-utilization`
- Logged run bundle:
  - `artifacts/task6-streamtensor-lite/runs/2026-04-23T13-13-00+0200/l1-index-ring3-selectcluster-fifo2-proof/summary.md`

#### Why this slice

- After the one-site selector and fork hotspots missed, the next smallest
  structural cut inside the same local control tree was the selector leg:
  - `handshake_fork49_out4 -> handshake_buffer255 -> handshake_fork46`
- The specific hypothesis was:
  - if the cost is in the interaction between the init-0 selector buffer and
    the four-way fork, then replacing that whole local leg with one helper
    should be more informative than yet another one-instance swap

#### Functional proof

- Timed Verilator proof:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-ring3-selectcluster-fifo2-sv-sim --no-link -L`
  - result:
    - `PASS: stores 16 outputs 16`
    - `ELAPSED=149.01`
    - `RSS_KB=437064`
- Interpretation:
  - collapsing the local selector cluster is contract-safe

#### Mapped utilization

- Timed mapped utilization:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-ring3-selectcluster-fifo2-abc9-utilization --no-link --print-out-paths`
  - output:
    - `/nix/store/9d5q0szcjv49jmnwjnr5v2hz8jliffqd-task6-l1-c-fc-redirect-index-ring3-selectcluster-fifo2-abc9-utilization`
  - result:
    - `ELAPSED=147.09`
    - `RSS_KB=562120`
  - mapped summary:
    - DSP:
      - `4`
    - BRAM36:
      - `0`
    - CLB LUTs:
      - `30,358`
    - CLB FFs:
      - `47,392`
- Primitive signature:
  - `FDRE`:
    - `47,389`
  - `LUT6`:
    - `14,715`
  - `LUT3`:
    - `7,727`
  - `LUT2`:
    - `3,285`
  - `LUT5`:
    - `3,145`
- Weight placement and runtime checks:
  - large weights emitted as RTL constants:
    - `no`
  - Verilator passed:
    - `yes`
  - Yosys stat finished within budget:
    - `yes`
    - unchanged from the accepted `L1` kernel at `4.07 s`
- Delta against the frozen ring-3 reference:
  - LUT:
    - `30,320 -> 30,358` (`+38`)
  - FF:
    - `47,392 -> 47,392` (`+0`)
- Interpretation:
  - the first real selector-cluster cut ties the earlier `fork49` statevec
    helper exactly on top-line fit metrics
  - that is enough to close the selector-control tree as the next fit lever:
    it stays safe, but it does not beat the frozen ring-3 reference

### L1 downstream post-branch FIFO2 proof later on 2026-04-23

- Added flake outputs:
  - `task6-l1-c-fc-redirect-index-ring3-postbranch-fifo2-sim-main`
  - `task6-l1-c-fc-redirect-index-ring3-postbranch-fifo2-sv-sim`
  - `task6-l1-c-fc-redirect-index-ring3-postbranch-fifo2-abc9-json`
  - `task6-l1-c-fc-redirect-index-ring3-postbranch-fifo2-abc9-utilization`
- Logged run bundle:
  - `artifacts/task6-streamtensor-lite/runs/2026-04-23T13-55-32+0200/l1-index-ring3-postbranch-fifo2-proof/summary.md`

#### Why this slice

- After the selector-control tree closed, the next bounded non-selector area in
  the same `L1` kernel was the downstream post-branch `ui64` cluster:
  - `handshake_buffer264`, `265`, `266`, `269`, `270`, and `271`
- The specific hypothesis was:
  - the next real fit lever is still local FIFO state, but not in the selector
    neighborhood; replacing the branch-success data path and its immediate
    address/data staging should trim both LUTs and FFs without reopening the
    stalled selector-side search

#### Functional proof

- Timed Verilator proof:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-ring3-postbranch-fifo2-sv-sim --no-link -L`
  - result:
    - `PASS: stores 16 outputs 16`
    - `ELAPSED=149.45`
    - `RSS_KB=437752`
- Interpretation:
  - the downstream post-branch data cluster is contract-safe

#### Mapped utilization

- Timed mapped utilization:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-ring3-postbranch-fifo2-abc9-utilization --no-link --print-out-paths`
  - output:
    - `/nix/store/vgfr4q1q35jnlpdy8j5k0gdi3f6b7rhz-task6-l1-c-fc-redirect-index-ring3-postbranch-fifo2-abc9-utilization`
  - result:
    - `ELAPSED=149.96`
    - `RSS_KB=562980`
  - mapped summary:
    - DSP:
      - `4`
    - BRAM36:
      - `0`
    - CLB LUTs:
      - `29,967`
    - CLB FFs:
      - `46,612`
- Primitive signature:
  - `FDRE`:
    - `46,609`
  - `LUT6`:
    - `13,989`
  - `LUT3`:
    - `8,076`
  - `LUT2`:
    - `3,241`
  - `LUT5`:
    - `3,194`
- Weight placement and runtime checks:
  - large weights emitted as RTL constants:
    - `no`
  - Verilator passed:
    - `yes`
  - Yosys stat finished within budget:
    - `yes`
    - unchanged from the accepted `L1` kernel at `4.07 s`
- Delta against the frozen ring-3 reference:
  - LUT:
    - `30,320 -> 29,967` (`-353`)
  - FF:
    - `47,392 -> 46,612` (`-780`)
- Interpretation:
  - this is the first productive non-selector follow-up after the selector
    branch closed
  - the cluster is still just short of the ceiling, so exactly one bounded
    follow-up on the same downstream data path is justified

### L1 downstream post-branch out-buffer FIFO2 proof later on 2026-04-23

- Added flake outputs:
  - `task6-l1-c-fc-redirect-index-ring3-postbranch-outbuf-fifo2-sim-main`
  - `task6-l1-c-fc-redirect-index-ring3-postbranch-outbuf-fifo2-sv-sim`
  - `task6-l1-c-fc-redirect-index-ring3-postbranch-outbuf-fifo2-abc9-json`
  - `task6-l1-c-fc-redirect-index-ring3-postbranch-outbuf-fifo2-abc9-utilization`
- Logged run bundle:
  - `artifacts/task6-streamtensor-lite/runs/2026-04-23T13-55-32+0200/l1-index-ring3-postbranch-outbuf-fifo2-proof/summary.md`

#### Why this slice

- The first post-branch cut left the lane only `107` LUT over the ceiling.
- The cheapest same-direction extension was the pair of immediate `ui64`
  out-buffers from that cluster:
  - `handshake_buffer279` and `280`
- The specific hypothesis was:
  - if the downstream post-branch path is the right lever, replacing the two
    first post-fork out-buffers should be enough to clear `L1` without
    touching control state or reopening the selector-side search

#### Functional proof

- Timed Verilator proof:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-ring3-postbranch-outbuf-fifo2-sv-sim --no-link -L`
  - result:
    - `PASS: stores 16 outputs 16`
    - `ELAPSED=133.51`
    - `RSS_KB=437680`
- Interpretation:
  - extending the same downstream data-path lever through the immediate
    out-buffers remains contract-safe

#### Mapped utilization

- Timed mapped utilization:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-ring3-postbranch-outbuf-fifo2-abc9-utilization --no-link --print-out-paths`
  - output:
    - `/nix/store/7z3fdnp57z3b5bs1ziv1bjlrhbnlid3h-task6-l1-c-fc-redirect-index-ring3-postbranch-outbuf-fifo2-abc9-utilization`
  - result:
    - `ELAPSED=149.06`
    - `RSS_KB=562936`
  - mapped summary:
    - DSP:
      - `4`
    - BRAM36:
      - `0`
    - CLB LUTs:
      - `29,778`
    - CLB FFs:
      - `46,352`
- Primitive signature:
  - `FDRE`:
    - `46,349`
  - `LUT6`:
    - `13,887`
  - `LUT3`:
    - `8,050`
  - `LUT5`:
    - `3,189`
  - `LUT2`:
    - `3,188`
- Weight placement and runtime checks:
  - large weights emitted as RTL constants:
    - `no`
  - Verilator passed:
    - `yes`
  - Yosys stat finished within budget:
    - `yes`
    - unchanged from the accepted `L1` kernel at `4.07 s`
- Delta against the first post-branch cut:
  - LUT:
    - `29,967 -> 29,778` (`-189`)
  - FF:
    - `46,612 -> 46,352` (`-260`)
- Delta against the frozen ring-3 reference:
  - LUT:
    - `30,320 -> 29,778` (`-542`)
  - FF:
    - `47,392 -> 46,352` (`-1,040`)
- Interpretation:
  - this is the first validated `L1` point that clears both the LUT and FF
    ceilings while preserving external weights, `4 DSP48E1`, and the kernel
    contract
  - stop widening `L1` again here; the next replay should move to `L2` before
    any promotion toward `L3`

### L2 aligned post-branch FIFO2 replay later on 2026-04-23

- Added flake outputs:
  - `task6-l2-c-fc-redirect-postbranch-fifo2-sim-main`
  - `task6-l2-c-fc-redirect-postbranch-fifo2-sv-sim`
  - `task6-l2-c-fc-redirect-postbranch-fifo2-abc9-json`
  - `task6-l2-c-fc-redirect-postbranch-fifo2-abc9-utilization`
- Logged run bundle:
  - `artifacts/task6-streamtensor-lite/runs/2026-04-23T14-23-08+0200/l2-postbranch-fifo2-proof/summary.md`

#### Why this slice

- The lane rule after the new `L1` reference was:
  - replay that exact fit lever on `L2` before considering any `L3` promotion
- The generated `L2` SV does not match the `L1` post-branch neighborhood one
  for one:
  - `handshake_buffer264`, `265`, `266`, `270`, and `271` are still
    `ui64 -> ui64` buffers
  - `handshake_buffer269`, `279`, and `280` have changed type, so the full
    `L1` out-buffer replay is not a legal direct copy
- The smallest aligned hypothesis was therefore:
  - replace only the still-matching post-branch `ui64` buffers
    `264/265/266/270/271` with `task6_ui64_fifo2_buffer`
  - then re-run Verilator plus mapped `abc9` and stop if LUT moves the wrong
    way

#### Functional proof

- Timed Verilator proof:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l2-c-fc-redirect-postbranch-fifo2-sv-sim --no-link -L`
  - result:
    - `PASS: stores 256 outputs 256`
    - `ELAPSED=77.00`
    - `RSS_KB=437400`
- Interpretation:
  - the aligned subset replay is functionally valid on `L2`
  - no broad compiler or kernel surgery was needed to carry the `L1` lever
    over

#### Mapped utilization

- Timed mapped utilization:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l2-c-fc-redirect-postbranch-fifo2-abc9-utilization --no-link --print-out-paths`
  - output:
    - `/nix/store/85z4gz624dqdmqf9hszcxn65gqrv5drc-task6-l2-c-fc-redirect-postbranch-fifo2-abc9-utilization`
  - result:
    - `ELAPSED=255.15`
    - `RSS_KB=563416`
  - mapped summary:
    - DSP:
      - `4`
    - BRAM36:
      - `0`
    - CLB LUTs:
      - `51,622`
    - CLB FFs:
      - `64,873`
- Primitive signature:
  - `FDRE`:
    - `64,870`
  - `LUT6`:
    - `29,438`
  - `LUT5`:
    - `8,333`
  - `LUT3`:
    - `7,749`
  - `LUT2`:
    - `4,005`
- Weight placement and runtime checks:
  - large weights emitted as RTL constants:
    - `no`
    - unchanged from the accepted `L2` redirect; this replay only swaps local
      buffer modules and does not touch the external load interface
  - Verilator passed:
    - `yes`
  - Yosys stat finished within budget:
    - `not rerun`
    - the accepted `L2` kernel still has a separate `yosys-stat` proof at
      `9.13 s`, but this replay was judged directly on Verilator plus mapped
      `abc9`
- Delta against the existing `L2` kernel:
  - LUT:
    - `50,235 -> 51,622` (`+1,387`)
  - FF:
    - `65,523 -> 64,873` (`-650`)
- Delta against the current `L1` reference:
  - LUT:
    - `29,778 -> 51,622` (`+21,844`)
  - FF:
    - `46,352 -> 64,873` (`+18,521`)
- Interpretation:
  - the bounded `L1` fit lever does not survive as a useful fit lever on `L2`
    even when replayed only on the structurally matching `ui64` sites
  - this is a clean negative datapoint, not a broken build:
    - external weights still hold
    - `4 DSP48E1` still hold
    - the kernel contract still passes
  - close this exact replay path rather than widening it blindly, because LUT
    moved in the wrong direction on the first aligned test

### L2 downstream out-buffer FIFO2 probe later on 2026-04-23

- Added flake outputs:
  - `task6-l2-c-fc-redirect-downstream-outbuf-fifo2-sim-main`
  - `task6-l2-c-fc-redirect-downstream-outbuf-fifo2-sv-sim`
  - `task6-l2-c-fc-redirect-downstream-outbuf-fifo2-abc9-json`
  - `task6-l2-c-fc-redirect-downstream-outbuf-fifo2-abc9-utilization`
- Logged run bundle:
  - `artifacts/task6-streamtensor-lite/runs/2026-04-23T14-36-13+0200/l2-downstream-outbuf-fifo2-proof/summary.md`

#### Why this slice

- The next bounded `L2` rule after the aligned replay miss was:
  - try exactly one `L2`-native local probe in the changed downstream
    `272..280` neighborhood before abandoning `L2 c_fc` micro-surgery
- The generated `L2` SV in that neighborhood contains:
  - `handshake_buffer272`, `273`, `274`, `275`, `276`, and `278` as
    `ui64 -> ui64` buffers on the downstream data fanout
  - `handshake_buffer277` and `279` as ctrl-only buffers
  - `handshake_buffer280` as a `ui1` buffer
- The smallest legal hypothesis was therefore:
  - replace only `272/273/274/275/276/278` with
    `task6_ui64_fifo2_buffer`
  - keep the ctrl and `ui1` sites untouched
  - stop the `L2 c_fc` path if official CLB LUTs still moved the wrong way

#### Functional proof

- Timed Verilator proof:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l2-c-fc-redirect-downstream-outbuf-fifo2-sv-sim --no-link -L`
  - result:
    - `PASS: stores 256 outputs 256`
    - `ELAPSED=80.01`
    - `RSS_KB=437188`
- Interpretation:
  - the first `L2`-native downstream out-buffer cluster is functionally valid
  - the changed `272..280` neighborhood is not blocked by contract breakage

#### Mapped utilization

- Timed mapped utilization:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l2-c-fc-redirect-downstream-outbuf-fifo2-abc9-utilization --no-link --print-out-paths -L`
  - output:
    - `/nix/store/6rvwfbgznp2jad70hxmm69j8kqwgab0w-task6-l2-c-fc-redirect-downstream-outbuf-fifo2-abc9-utilization`
  - result:
    - `ELAPSED=261.04`
    - `RSS_KB=563320`
  - mapped summary:
    - DSP:
      - `4`
    - BRAM36:
      - `0`
    - CLB LUTs:
      - `51,832`
    - CLB FFs:
      - `64,743`
    - Estimated number of LCs:
      - `47,802`
- Primitive signature:
  - `FDRE`:
    - `64,740`
  - `LUT6`:
    - `29,301`
  - `LUT5`:
    - `8,416`
  - `LUT3`:
    - `8,112`
  - `LUT2`:
    - `4,027`
- Weight placement and runtime checks:
  - large weights emitted as RTL constants:
    - `no`
    - unchanged from the accepted `L2` redirect; this probe only swaps local
      buffer modules and does not touch the external load interface
  - Verilator passed:
    - `yes`
  - Yosys stat finished within budget:
    - `not rerun`
    - the accepted `L2` kernel still has a separate `yosys-stat` proof at
      `9.13 s`, but this probe was judged directly on Verilator plus mapped
      `abc9`
- Delta against the existing `L2` kernel:
  - LUT:
    - `50,235 -> 51,832` (`+1,597`)
  - FF:
    - `65,523 -> 64,743` (`-780`)
- Delta against the aligned `L2` replay:
  - LUT:
    - `51,622 -> 51,832` (`+210`)
  - FF:
    - `64,873 -> 64,743` (`-130`)
- Delta against the current `L1` reference:
  - LUT:
    - `29,778 -> 51,832` (`+22,054`)
  - FF:
    - `46,352 -> 64,743` (`+18,391`)
- Interpretation:
  - this first `L2`-native local probe does improve one diagnostic number:
    - mapped `Estimated number of LCs` drops to `47,802`
  - but the lane scorecard does not use that diagnostic number:
    - the official metric is CLB LUTs, and those worsen again to `51,832`
  - treat this as the second clean move-on signal for `L2 c_fc`:
    - external weights still hold
    - `4 DSP48E1` still hold
    - the kernel contract still passes
    - the official fit metric still moves the wrong way
  - stop `L2 c_fc` micro-surgery here and pivot within StreamTensor-lite to
    the reserve fallback boundary `mlp.c_proj`

### `c_proj` fallback boundary scout later on 2026-04-23

- Supporting script change:
  - generalized `scripts/task6/build_task_graph.py`
    - it now derives graph and tensor node names from the module leaf instead
      of hard-coding `c_fc`, so the same lightweight artifact path stays honest
      on `c_proj`
- Logged run bundle:
  - `artifacts/task6-streamtensor-lite/runs/2026-04-23T14-46-31+0200/cproj-fallback-scout/summary.md`

#### Why this slice

- The lane move-on rule after the second clean `L2 c_fc` miss was:
  - stop local `L2 c_fc` micro-surgery
  - pivot within StreamTensor-lite to the reserve fallback boundary
    `transformer.h.0.mlp.c_proj`
- The smallest honest question before building a new redirected kernel was:
  - does `c_proj` preserve the same lightweight artifact path at both `L1` and
    `L2`:
    - `linalg` candidate
    - external weight pack
    - module-level activation contract
    - exact packed replay
    - minimal task graph

#### L1 fallback boundary

- First `L1` candidate artifact:
  - `artifacts/task6/streamtensor-lite/l1/representative-core-v64-h4-c_proj-candidate.json`
  - measured finder runtime:
    - wall-clock:
      - `0.07 s`
    - peak RSS:
      - `13,272 KB`
  - selected site:
    - line `418`
    - value `%88`
  - shape contract:
    - `tensor<1x1x16xf32>`
    - `tensor<1x16x4xf32>`
    - `tensor<1x1x4xf32>`
  - candidate count:
    - `2`
- First `L1` `c_proj` pack:
  - `artifacts/task6/weights_pack/tiny-stories-1m-representative-core-v64-h4/transformer.h.0.mlp.c_proj/`
  - measured export:
    - wall-clock:
      - `4.69 s`
    - peak RSS:
      - `334,732 KB`
  - tensor shapes:
    - weight:
      - `(4, 16)`
    - bias:
      - `(4,)`
- First `L1` `c_proj` contract:
  - `artifacts/task6/streamtensor-lite/l1/representative-core-v64-h4-c_proj-contract/`
  - measured capture:
    - wall-clock:
      - `4.51 s`
    - peak RSS:
      - `342,492 KB`
  - sample contract:
    - input ids:
      - `[[0]]`
    - activation in:
      - `(1, 1, 16)`
    - activation out:
      - `(1, 1, 4)`
- First `L1` `c_proj` replay check:
  - artifact:
    - `artifacts/task6/streamtensor-lite/l1/representative-core-v64-h4-c_proj-contract-check.json`
  - measured replay:
    - wall-clock:
      - `1.83 s`
    - peak RSS:
      - `226,384 KB`
  - replay result:
    - formula:
      - `activation_in @ weight.T + bias`
    - max absolute error:
      - `0.0`
    - mean absolute error:
      - `0.0`
    - verdict:
      - `pass`
- First `L1` `c_proj` task graph:
  - `artifacts/task6/streamtensor-lite/l1/representative-core-v64-h4-c_proj-task-graph.json`
  - measured build:
    - wall-clock:
      - `0.07 s`
    - peak RSS:
      - `14,020 KB`
  - graph name:
    - `task6-c_proj-minimal-task-graph`

#### L2 fallback boundary

- First `L2` candidate artifact:
  - `artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_proj-candidate.json`
  - measured finder runtime:
    - wall-clock:
      - `0.08 s`
    - peak RSS:
      - `14,888 KB`
  - selected site:
    - line `412`
    - value `%94`
  - shape contract:
    - `tensor<1x1x256xf32>`
    - `tensor<1x256x64xf32>`
    - `tensor<1x1x64xf32>`
  - candidate count:
    - `1`
- First `L2` `c_proj` pack:
  - `artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_proj/`
  - measured export:
    - wall-clock:
      - `4.71 s`
    - peak RSS:
      - `335,104 KB`
  - tensor shapes:
    - weight:
      - `(64, 256)`
    - bias:
      - `(64,)`
- First `L2` `c_proj` contract:
  - `artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_proj-contract/`
  - measured capture:
    - wall-clock:
      - `4.54 s`
    - peak RSS:
      - `342,668 KB`
  - sample contract:
    - input ids:
      - `[[0]]`
    - activation in:
      - `(1, 1, 256)`
    - activation out:
      - `(1, 1, 64)`
- First `L2` `c_proj` replay check:
  - artifact:
    - `artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_proj-contract-check.json`
  - measured replay:
    - wall-clock:
      - `1.83 s`
    - peak RSS:
      - `226,016 KB`
  - replay result:
    - formula:
      - `activation_in @ weight.T + bias`
    - max absolute error:
      - `0.0`
    - mean absolute error:
      - `0.0`
    - verdict:
      - `pass`
- First `L2` `c_proj` task graph:
  - `artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_proj-task-graph.json`
  - measured build:
    - wall-clock:
      - `0.08 s`
    - peak RSS:
      - `13,760 KB`
  - graph name:
    - `task6-c_proj-minimal-task-graph`

#### Interpretation

- The reserve `mlp.c_proj` fallback boundary is now validated on the same
  lightweight gates that previously brought up `c_fc`:
  - clean `linalg.batch_matmul` sites exist on both `L1` and `L2`
  - external weight packs exist on both `L1` and `L2`
  - module-level activation contracts exist on both `L1` and `L2`
  - packed replay is exact on both `L1` and `L2`
- This does not yet claim any mapped fit result:
  - no redirected `c_proj` kernel has been built
  - no Verilator kernel harness has been run
  - no mapped utilization has been collected
- The next useful slice is therefore:
  - build the first redirected `c_proj` kernel at `L1`
  - judge it with the same fast loop before replaying onto `L2`

### `L1 c_proj` redirected kernel start later on 2026-04-23

- Added model:
  - `task6-l1-c-proj-redirect`
  - location:
    - `nix/models.nix`
  - implementation:
    - reuse the existing `task6_rect_gemv.py` kernel with
      `TASK6_RECT_GEMV_IN_DIM=16` and `TASK6_RECT_GEMV_OUT_DIM=4`
- Logged run bundle:
  - `artifacts/task6-streamtensor-lite/runs/2026-04-23T14-51-00+0200/l1-cproj-redirect-yosys-stat-proof/summary.md`

#### Why this slice

- After the fallback scout, the cheapest honest next claim was:
  - the first redirected `c_proj` kernel should compile through the inherited
    flow at `L1`
  - stop there if even `yosys-stat` breaks or exceeds the budget
- Reusing the existing rectangular GEMV kernel keeps this narrow:
  - no new arithmetic module
  - no new compiler path
  - only the boundary shape changes from `4 -> 16` to `16 -> 4`

#### First `yosys-stat` result

- Timed build:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-proj-redirect-yosys-stat --no-link -L`
  - result:
    - `ELAPSED=17.52`
    - `RSS_KB=563732`
- Pre-map structural signature:
  - `$mul`:
    - `1`
  - `arith_mulf_in_f32_f32_out_f32`:
    - `1`
  - `arith_addf_in_f32_f32_out_f32`:
    - `1`
  - `handshake_buffer_in_ui64_out_ui64_2slots_seq`:
    - `204`
  - `handshake_load_in_ui64_f32_none_out_f32_ui64`:
    - `4`
  - `handshake_store_in_ui64_f32_none_out_f32_ui64`:
    - `3`
- Interpretation:
  - the first redirected `c_proj` kernel is structurally live
  - it stays inside the `< 30 s` micro-proof budget on the first inherited gate
  - the expected float arithmetic extern signature is still present, so this is
    not blocked by a boundary mismatch
  - no fit claim should be made yet:
    - Verilator is still pending
    - mapped utilization is still pending

#### Next action

- Add the minimal `L1 c_proj` Verilator and mapped-utilization surfaces using
  the newly generated `c_proj` contract and weight-pack artifacts.

### `L1 c_proj` executable proof and mapper follow-up later on 2026-04-23

- Added flake outputs:
  - `task6-l1-c-proj-redirect-tb-data-sv`
  - `task6-l1-c-proj-redirect-sim-main`
  - `task6-l1-c-proj-redirect-json`
  - `task6-l1-c-proj-redirect-utilization`
  - `task6-l1-c-proj-redirect-sv-sim`
  - `task6-l1-c-proj-redirect-abc9-json`
  - `task6-l1-c-proj-redirect-abc9-utilization`
- Logged run bundles:
  - `artifacts/task6-streamtensor-lite/runs/2026-04-23T15-01-29+0200/l1-cproj-redirect-proof/summary.md`
  - `artifacts/task6-streamtensor-lite/runs/2026-04-23T15-04-46+0200/l1-cproj-redirect-abc9-proof/summary.md`

#### Why this slice

- After `yosys-stat`, the next smallest honest question was:
  - does the untouched `L1 c_proj` redirected kernel pass the captured contract
    under Verilator
  - and if so, is the first mapped result competitive enough to justify more
    real fit work
- The follow-up stop rule was:
  - if the first mapped result still trails the frozen `L1 c_fc` reference,
    allow at most one cheap mapper-only discriminator before leaving `c_proj`
    reserve-only

#### Base executable proof

- Timed Verilator proof:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-proj-redirect-sv-sim --no-link -L`
  - result:
    - `PASS: stores 4 outputs 4`
    - `ELAPSED=106.74`
    - `RSS_KB=437244`
- Timed mapped utilization:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-proj-redirect-utilization --no-link --print-out-paths -L`
  - output:
    - `/nix/store/hlq0lqfxrbglnc8dxzp0jgandqjw2i4m-task6-l1-c-proj-redirect-utilization`
  - result:
    - `ELAPSED=97.85`
    - `RSS_KB=562712`
  - mapped summary:
    - DSP:
      - `4`
    - BRAM36:
      - `0`
    - CLB LUTs:
      - `32,393`
    - CLB FFs:
      - `50,864`
- Weight placement and runtime checks:
  - large weights emitted as RTL constants:
    - `no`
    - inherited redirected-kernel structure still uses external loads plus the
      generated task6 contract/pack flow
  - Verilator passed:
    - `yes`
  - Yosys stat finished within budget:
    - `yes`
    - `17.52 s`
- Delta against raw `L1 c_fc` redirect:
  - LUT:
    - `33,116 -> 32,393` (`-723`)
  - FF:
    - `51,296 -> 50,864` (`-432`)
- Delta against frozen `L1 c_fc` reference:
  - LUT:
    - `29,778 -> 32,393` (`+2,615`)
  - FF:
    - `46,352 -> 50,864` (`+4,512`)
- Interpretation:
  - the untouched `L1 c_proj` redirect is a real executable fallback proof:
    - external weights hold
    - `4 DSP48E1` hold
    - Verilator passes
  - but it is not a mainline fit win:
    - it still misses the LUT ceiling by `2,533`
    - it clearly trails the frozen `L1 c_fc` reference
  - that justified only one cheap mapper-only discriminator, not a new blind
    optimization branch

#### Direct `abc9` follow-up

- Timed mapped utilization:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-proj-redirect-abc9-utilization --no-link --print-out-paths -L`
  - output:
    - `/nix/store/lffxb0w5ac1hwhfyyd12vxfnmsj9sd64-task6-l1-c-proj-redirect-abc9-utilization`
  - result:
    - `ELAPSED=143.08`
    - `RSS_KB=563156`
  - mapped summary:
    - DSP:
      - `4`
    - BRAM36:
      - `0`
    - CLB LUTs:
      - `31,611`
    - CLB FFs:
      - `50,864`
- Delta against base `L1 c_proj` redirect:
  - LUT:
    - `32,393 -> 31,611` (`-782`)
  - FF:
    - `50,864 -> 50,864` (`+0`)
- Delta against frozen `L1 c_fc` reference:
  - LUT:
    - `29,778 -> 31,611` (`+1,833`)
  - FF:
    - `46,352 -> 50,864` (`+4,512`)
- Interpretation:
  - direct `abc9` does buy a real reduction on the untouched `c_proj` kernel
  - but it still does not change lane order:
    - the kernel remains `1,751` LUT above the ceiling
    - and still worse than the frozen `L1 c_fc` reference by `1,833` LUT
  - treat this as enough evidence to keep `c_proj` reserve-only:
    - structurally valid
    - reproducible
    - useful fallback
    - not the main fit-first lane on mapper-only evidence

#### Next action

- Keep `task6-l1-c-fc-redirect-index-ring3-postbranch-outbuf-fifo2-abc9` as
  the main `L1` reference.
- Keep `c_proj` as a validated reserve fallback, and do not start another blind
  `c_proj` optimization loop unless there is a new bounded structural
  hypothesis stronger than mapper-only improvement.

### Bounded `L2` structural hypothesis on 2026-04-23

#### Hypothesis

- The remaining `L2 c_fc` fit failure is now more likely to be dominated by the
  monolithic `64 -> 256` downstream wrapper shape than by the GEMV arithmetic
  kernel itself:
  - `L1` only crossed the ceiling after trimming the downstream post-branch
    `ui64` cluster
  - the aligned `L2` replay of that same lever and the first `L2`-native
    downstream out-buffer probe both worsened official CLB LUTs
- The next bounded structural test is therefore:
  - replace the monolithic `64 -> 256` redirected kernel with one sequential
    `4 x 64` output-tiled wrapper that reuses a single `64 -> 64` redirected
    kernel instance across four phases
  - keep the same external activation/weight/store contract at the top level
  - remap only:
    - weight addresses:
      - `phase[1:0] ++ local_tile_addr[11:0]`
    - store addresses:
      - `phase[1:0] ++ local_store_addr[5:0]`
  - pass the same full `L2` contract and weight-pack artifacts through the
    existing Verilator harness

#### Bounds and stop rule

- Stay strictly inside `task6-streamtensor-lite` and only touch the `L2 c_fc`
  redirect path.
- Reuse the existing rectangular GEMV kernel and current proof harness.
- Do not broaden into compiler redesign, alternate dialects, or whole-model
  RTL.
- Reject the hypothesis immediately if any of these happen:
  - mapped `abc9` does not beat the current `L2` base at `50,235` LUT by a
    clear margin
  - DSP falls back to `0`
  - large weights reappear as RTL constants
  - the wrapper requires broad RTL surgery instead of a local top-level
    sequencer

### `L2 c_fc` tiled `4 x 64` wrapper proof later on 2026-04-23

- New bounded proof surfaces:
  - `task6-l2-c-fc-redirect-tile64-yosys-stat`
  - `task6-l2-c-fc-redirect-tile4x64-sim-main`
  - `task6-l2-c-fc-redirect-tile4x64-sv-sim`
  - `task6-l2-c-fc-redirect-tile4x64-abc9-json`
  - `task6-l2-c-fc-redirect-tile4x64-abc9-utilization`
- New local wrapper:
  - `rtl/task6/task6_l2_c_fc_tile4x64_main.sv`
- Artifact bundle:
  - `artifacts/task6-streamtensor-lite/runs/2026-04-23T16-03-42+0200/l2-cfc-tile4x64-proof/summary.md`

#### What was implemented

- The hypothesis was executed exactly as bounded:
  - one reused `64 -> 64` redirected kernel generated as
    `task6-l2-c-fc-redirect-tile64`
  - one local top-level sequencer that runs the tile kernel across four output
    phases while preserving the same external activation, weight, and store
    contract as the original `L2` kernel
- The wrapper only remaps:
  - weight addresses:
    - `{phase[1:0], local_tile_addr[11:0]}`
  - store addresses:
    - `{phase[1:0], local_store_addr[5:0]}`
- No compiler redesign or alternate lowering path was introduced; this stays
  strictly inside the existing StreamTensor-lite lane.

#### Commands

- Cheap kernel gate:
  - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l2-c-fc-redirect-tile64-yosys-stat --no-link -L`
- Full-contract Verilator proof:
  - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l2-c-fc-redirect-tile4x64-sv-sim --no-link -L`
- Mapped `abc9` utilization:
  - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l2-c-fc-redirect-tile4x64-abc9-utilization --no-link --print-out-paths -L`
  - output:
    - `/nix/store/cj8356nv9izcs60znfqfdysydrxdy8vc-task6-l2-c-fc-redirect-tile4x64-abc9-utilization`

#### Results

- `task6-l2-c-fc-redirect-tile64-yosys-stat`:
  - `ELAPSED=16.09`
  - `RSS_KB=561720`
  - stays inside the `< 30 s` micro-proof budget
- `task6-l2-c-fc-redirect-tile4x64-sv-sim`:
  - `PASS: stores 256 outputs 256`
  - `ELAPSED=161.55`
  - `RSS_KB=437564`
- `task6-l2-c-fc-redirect-tile4x64-abc9-utilization`:
  - `ELAPSED=153.09`
  - `RSS_KB=563056`
  - mapped resources:
    - `DSP48E1`
      - `4`
    - `BRAM36`
      - `0`
    - `CLB LUTs`
      - `32,460`
    - `CLB FFs`
      - `46,740`
    - `Estimated mapped LCs`
      - `29,089`
- Large weights emitted as RTL constants:
  - `no`
  - the top-level interface is still external-memory based, and the new
    wrapper only sequences one reused tile kernel around that contract

#### Deltas

- Against the existing untiled `L2` reference:
  - LUT:
    - `50,235 -> 32,460` (`-17,775`)
  - FF:
    - `65,523 -> 46,740` (`-18,783`)
- Against the best validated `L1` reference:
  - LUT:
    - `29,778 -> 32,460` (`+2,682`)
  - FF:
    - `46,352 -> 46,740` (`+388`)

#### Verdict

- The bounded structural hypothesis is supported.
- The monolithic `64 -> 256` wrapper shape was a major `L2` cost center:
  - reusing one external-weight `64 -> 64` kernel across four phases keeps
    `4 DSP48E1`, preserves the full `L2` contract, and collapses the mapped
    `L2` footprint to near-`L0`/`L1` scale
- This is the first fit-positive `L2` structural result in the lane and the new
  `L2 c_fc` reference.
- It is not yet enough to unblock `L3`:
  - `32,460` LUT is still `2,600` over the `29,860` ceiling

#### Next action

- Freeze `task6-l2-c-fc-redirect-tile4x64-abc9-utilization` as the new `L2`
  reference.
- If `L2 c_fc` continues, use at most one more bounded fit hypothesis on the
  reusable `64 -> 64` tile kernel or tile/wrapper seam.
- Do not reopen the abandoned monolithic `64 -> 256` local micro-surgery loop,
  and do not promote to `L3` until the tiled `L2` path clears the LUT ceiling.

### 2026-04-23 - Amend the active `L2` plan around the tiled wrapper

The branch had moved beyond the original Apr 22 ladder, so
`docs/task6-lane.md` was amended to match the recorded frontier in
`docs/task6-lane-results.md`.

The live contract is now:

- freeze `L1 c_fc` as solved for the first-proof bar
- keep `mlp.c_proj` reserve-only
- treat tiled `L2 c_fc` as the sole active mainline
- spend the already-authorized single follow-up probe on the tiled `L2`
  structure, not on the abandoned monolithic `64 -> 256` path

### 2026-04-23 - Instrument the tiled `L2` seam before touching RTL again

The first amended follow-up was a seam split: measure the untouched reusable
`64 -> 64` tile kernel directly, then compare it against the existing `4 x 64`
wrapper result.

#### Command

- `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l2-c-fc-redirect-tile64-abc9-utilization --no-link --print-out-paths -L`

#### Output

- `/nix/store/1jsmab9fgsjdv0n4czy9pqcgmy9l6rns-task6-l2-c-fc-redirect-tile64-abc9-utilization`

#### Result

- `CLB LUTs = 32,478`
- `CLB FFs = 46,736`
- `DSP48E1 = 4`
- `BRAM36 = 0`
- `Estimated number of LCs = 29,116`
- `ELAPSED = 92.53 s`
- `RSS_KB = 563,708`

#### Verdict

- The seam is not the dominant cost center.
- The existing tiled wrapper lands at `32,460 LUT / 46,740 FF`, so the seam
  delta is only:
  - `32,478 -> 32,460` (`-18 LUT`)
  - `46,736 -> 46,740` (`+4 FF`)
- That is too small to justify another seam-only iteration. The single
  remaining bounded probe had to target the reusable tile kernel itself.

### 2026-04-23 - One bounded tile-kernel follow-up on the tiled `L2` mainline

With the seam effectively flat, the single allowed follow-up probe moved into
the tile kernel's local post-branch/output `ui64` cluster.

Bounded edit:

- reuse the existing `task6_ui64_fifo2_buffer` helper
- replace only:
  - `handshake_buffer244`
  - `handshake_buffer245`
  - `handshake_buffer248`
  - `handshake_buffer250`
  - `handshake_buffer252`
  - `handshake_buffer253`
  - `handshake_buffer254`
  - `handshake_buffer256`
- do not change arithmetic, weight loading, or the tiled wrapper protocol

This stays inside the existing StreamTensor-lite lane and is intentionally
smaller than reopening monolithic `L2` surgery.

#### Cheap kernel gate

- `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l2-c-fc-redirect-tile64-postbranch-outbuf-fifo2-abc9-utilization --no-link --print-out-paths -L`

Output:

- `/nix/store/jxgi6fqjd9hivzhkgmjqpnm1m4ghkwx9-task6-l2-c-fc-redirect-tile64-postbranch-outbuf-fifo2-abc9-utilization`

Kernel-gate result:

- `CLB LUTs = 31,968`
- `CLB FFs = 45,928`
- `DSP48E1 = 4`
- `BRAM36 = 0`
- `Estimated number of LCs = 28,689`
- `ELAPSED = 93.06 s`
- `RSS_KB = 563,328`

Kernel-gate delta versus the untouched tile kernel:

- LUT:
  - `32,478 -> 31,968` (`-510`)
- FF:
  - `46,736 -> 45,928` (`-808`)

Verdict:

- This is a real kernel-local win, so the same bounded hypothesis was worth one
  replay into the full `4 x 64` wrapper.

#### Full wrapper replay

- Verilator proof:
  - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2-sv-sim --no-link -L`
- Direct rerun for a clean run-bundle sim log:
  - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' /nix/store/363slmdlg8mv44sqxczkd0vbp9sji7ig-task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2-sim-main/obj_dir/sim_main`
- Mapped `abc9` utilization:
  - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2-abc9-utilization --no-link --print-out-paths -L`

Output:

- `/nix/store/cj1s942zmpcwg0xz73g86k58idwavari-task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2-abc9-utilization`

Wrapper replay result:

- Verilator:
  - `PASS: stores 256 outputs 256`
  - build-time `ELAPSED = 85.86 s`
  - build-time `RSS_KB = 437,444`
  - direct rerun `ELAPSED = 2.25 s`
  - direct rerun `RSS_KB = 5,224`
- mapped `abc9` utilization:
  - `CLB LUTs = 31,907`
  - `CLB FFs = 45,932`
  - `DSP48E1 = 4`
  - `BRAM36 = 0`
  - `Estimated number of LCs = 28,653`
  - `ELAPSED = 94.03 s`
  - `RSS_KB = 562,812`

Wrapper delta versus the prior tiled `L2` reference:

- LUT:
  - `32,460 -> 31,907` (`-553`)
- FF:
  - `46,740 -> 45,932` (`-808`)

Wrapper delta versus the current `L1` reference:

- LUT:
  - `29,778 -> 31,907` (`+2,129`)
- FF:
  - `46,352 -> 45,932` (`-420`)

#### Verdict

- The amended tiled-`L2` follow-up succeeded in the narrow sense:
  - the seam hypothesis is now falsified
  - the bounded tile-kernel post-branch/output probe is real
  - replaying it into the full tiled wrapper preserves external weights,
    `4 DSP48E1`, and the `L2` contract
- The new `L2` reference is now:
  - `task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2-abc9-utilization`
  - `31,907 LUT / 45,932 FF / 4 DSP / 0 BRAM`
- This is still not enough to unblock `L3`:
  - `31,907` LUT is still `2,047` above the `29,860` ceiling

#### Next action

- Do not reopen monolithic `L2 c_fc` micro-surgery.
- Do not reopen the already-closed seam-only line.
- Treat the amended one-probe plan as spent.
- Any further `L2 c_fc` work now needs a new structural hypothesis that is
  stronger than "another nearby buffer cluster may help."

### 2026-04-23 - Amend the live plan after the selective-buffer phase

The branch evidence now fixes the continuation rule more tightly than the older
`72a502f` selective-buffer checkpoint alone.

Interpretation:

- Treat the selective-buffer widening that led into `72a502f` as the end of the
  blind ring-expansion loop, not the start of more generic widening.
- Freeze `task6-l1-c-fc-redirect-index-ring3-postbranch-outbuf-fifo2-abc9` as
  the `L1` gold reference.
- Keep `mlp.c_proj` reserve-only.
- Keep monolithic `L2 c_fc` micro-surgery closed.
- Treat tiled `L2 c_fc` as the sole active mainline until a stronger structural
  hypothesis appears.

One code-structure cleanup is now part of the plan before another local probe
wave:

- `rtl/task6/task6_ui64_fifo2_buffer.sv`
- `rtl/task6/handshake_buffer_in_ui64_out_ui64_2slots_seq_fifo2.sv`

These currently carry the same FIFO body under two names. That duplication was
acceptable for fast proof work, but it is now a drift risk. Future local
rewrites should be driven by:

- one canonical FIFO2 helper implementation
- thin wrappers or aliases only where an old module name must be preserved
- one small patch map naming the rewritten sites, instead of scattering more
  near-duplicate helper modules and ad hoc site lists across `flake.nix`

This is a plan amendment only. It does not reopen the spent `L2` probe budget,
and it does not authorize another local `L2 c_fc` edit without a new bounded
structural hypothesis.

### 2026-04-23 - Consolidate the `ui64` FIFO2 probe plumbing and validate no regression

This closes the code-structure cleanup that the amended plan required before
another local probe wave.

Changes:

- Added `nix/task6-ui64-fifo2-site-map.nix` as the single source of truth for
  the Task 6 `ui64` FIFO2 rewrite site lists.
- Added shared flake helpers:
  - `mkTask6PatchedSv`
  - `mkTask6Ui64Fifo2SitePatchSv`
  - `mkTask6Ui64Fifo2WholeClassSv`
- Replaced the repeated inline `runCommand` site-rewrite blocks for the
  existing `L1` and `L2` FIFO2 probes with those helpers.
- Reduced duplicate RTL:
  - `rtl/task6/task6_ui64_fifo2_buffer.sv` is now the canonical FIFO2 body.
  - `rtl/task6/handshake_buffer_in_ui64_out_ui64_2slots_seq_fifo2.sv` is now
    only a thin wrapper that instantiates the canonical helper under the legacy
    module name expected by the old whole-class path.
- Needed operational step:
  - `nix/task6-ui64-fifo2-site-map.nix` had to be staged before Nix could see
    it because the flake source snapshot excludes untracked files.

Validation bundle:

- `artifacts/task6-streamtensor-lite/runs/2026-04-23T18-08-31+0200/`

Commands rerun:

- `nix build .#task6-l1-c-fc-redirect-ui64-buffer-fifo2-utilization --no-link --print-out-paths -L`
- `nix build .#task6-l1-c-fc-redirect-index-ring3-postbranch-outbuf-fifo2-abc9-utilization --no-link --print-out-paths -L`
- `nix build .#task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2-abc9-utilization --no-link --print-out-paths -L`
- `nix build .#task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2-sv-sim --no-link -L`
- direct rerun:
  - `/nix/store/4hdp3s5lqqwqkpwqwy6mxwc634fk5ixd-task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2-sim-main/obj_dir/sim_main`

Results:

- legacy whole-class wrapper still builds through the alias wrapper:
  - `23,161 LUT / 27,591 FF / 4 DSP / 0 BRAM`
- frozen `L1` reference is unchanged:
  - `29,778 LUT / 46,352 FF / 4 DSP / 0 BRAM`
- active tiled `L2` reference is unchanged:
  - `31,907 LUT / 45,932 FF / 4 DSP / 0 BRAM`
- direct rerun still passes:
  - `PASS: stores 256 outputs 256`

Verdict:

- The cleanup is accepted.
- The probe plumbing is now safe to reuse for future local rewrites.
- No accepted Task 6 reference moved, and no old evidence path was stranded.

Next action:

- Use the cleaned plumbing for one new bounded `L2 tile64` structural
  hypothesis on the remaining mixed data/control store path, not for another
  generic `ui64` buffer-only sweep.

### 2026-04-23 - First mixed `tile64` fork/control seam probe fails functionally

The first post-cleanup seam probe targeted the remaining local store-path
fanout state in the tiled `64 -> 64` kernel:

- `handshake_fork50`
- `handshake_fork51`
- `handshake_fork52`
- `handshake_buffer246`
- `handshake_buffer247`
- `handshake_buffer255`

Implementation:

- Added lean fork helpers:
  - `rtl/task6/task6_ui64_fork2.sv`
  - `rtl/task6/task6_ui64_fork3.sv`
  - `rtl/task6/task6_ctrl_fork3.sv`
- Reused `rtl/task6/task6_ctrl_fifo2_buffer.sv` for the zero-width control
  buffers in the same seam.
- Added the local surface:
  - `task6-l2-c-fc-redirect-tile64-storepath-forkctrl-*`

Run bundle:

- `artifacts/task6-streamtensor-lite/runs/2026-04-23T18-14-40+0200/`

Command run:

- `nix build .#task6-l2-c-fc-redirect-tile64-storepath-forkctrl-sv-sim --no-link -L`

Result:

- Verilator build completed, but the contract failed:
  - `FAIL: expected 256 stores but observed 64`
- runtime:
  - `80.97 s`
- peak RSS:
  - `438,164 KB`

Verdict:

- Reject this combined helper cluster as a valid drop-in.
- The failure happens before mapped scoring, so there is no reason to run
  `abc9` on this exact surface.

Next action:

- Narrow the same seam.
- Keep the zero-width control buffers untouched on the next attempt.
- If the seam work continues, isolate the fork-state helpers only:
  - `fork50`
  - `fork51`
  - `fork52`

### 2026-04-23 - Fork-only follow-up reproduces the same `64`-store failure

The narrowed follow-up kept the original zero-width control buffers and changed
only the local fanout helpers:

- `fork50`
- `fork51`
- `fork52`

Surface:

- `task6-l2-c-fc-redirect-tile64-storepath-forks-*`

Run bundle:

- `artifacts/task6-streamtensor-lite/runs/2026-04-23T18-18-28+0200/`

Command run:

- `nix build .#task6-l2-c-fc-redirect-tile64-storepath-forks-sv-sim --no-link -L`

Result:

- same contract failure as the wider cluster:
  - `FAIL: expected 256 stores but observed 64`
- runtime:
  - `83.16 s`
- peak RSS:
  - `438,492 KB`

Verdict:

- The remaining local store-path helper substitution line is closed.
- The failure survives after removing the ctrl-buffer substitutions, so the
  problem is not just the zero-width FIFO replacements.
- Do not spend another `L2 tile64` slice on helper replacement in this same
  neighborhood.

Blocking state:

- The current amended `L2` plan is now exhausted.
- More local `L2 c_fc` RTL edits would violate the lane rule unless a new
  structural hypothesis is stated first.

### 2026-04-23 - Implement the stage-local runner surface

The only remaining concrete operational item in the current lane plan was the
missing stage-local runner surface. I closed that gap without reopening the RTL
search:

- added:
  - `justfile`
  - `scripts/task6/run_stage_local.py`
- exported the missing package surfaces needed by the runner:
  - `task6-l0-gemv64-yosys-stat`
  - `task6-l1-c-fc-redirect-index-ring3-postbranch-outbuf-fifo2-yosys-stat`
  - `task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2-yosys-stat`

The runner now covers the active and gated ladder surfaces:

- `just task6-l0`
- `just task6-l1`
- `just task6-l2`
- `just task6-l3`
- `just task6-l4`
- `just task6-x1`
- `just task6-x2`
- `just task6-x3`

Design rule:

- active rungs execute the existing frozen/reference proof surfaces and write a
  fresh run bundle under `artifacts/task6-streamtensor-lite/runs/<timestamp>/`
- blocked rungs do not pretend to run; they emit a summary bundle that records
  the current promotion gate and next action explicitly
- the runner is a frozen status surface:
  - its timings are replay timings, not frontier experiment timings
  - do not keep spending frontier bandwidth on blocked-rung sweeps or runner
    feature growth unless the frontier itself changes

### 2026-04-24 - Clean the stage-local runner and freeze it as status-only

The runner needed execution cleanup, not more feature growth.

Problems fixed:

- `L1` and `L2` were previously mixing different surfaces inside one rung:
  - `yosys-stat` came from the base kernel path
  - sim and mapped utilization came from the frozen/reference patched surface
- `README.md` used absolute workstation paths, which are not useful in GitHub
- run-directory allocation used an `exists()` check before `mkdir()`, which was
  collision-resistant in practice but not race-safe in principle
- the branch was recording blocked-run sweeps as if they were frontier
  experiments

Fixes applied:

- added exact `yosys-stat` derivations for the frozen `L1` and active tiled `L2`
  references
- changed the runner summaries to label timings explicitly as cache-hit status
  replay timings
- changed runner `README.md` links to relative paths
- changed run-directory allocation to retry on `FileExistsError`
- pruned the blocked-run sweep artifacts from the current tree and stopped
  treating them as experiment rows

Execution gate:

- before any new `L2 c_fc` frontier experiment, record one short hypothesis
  note here with:
  - expected dominant cost center
  - expected LUT delta
  - explicit falsifier
- without that note, only `just task6-l0`, `task6-l1`, and `task6-l2` status
  replays are allowed

### 2026-04-24 - Revalidate the frozen status surface on the active rungs only

Run bundles:

- `artifacts/task6-streamtensor-lite/runs/2026-04-24T00-10-19+0200/`
- `artifacts/task6-streamtensor-lite/runs/2026-04-24T00-10-27+0200/`
- `artifacts/task6-streamtensor-lite/runs/2026-04-24T00-10-36+0200/`

Commands run:

- `nix shell nixpkgs#just -c just task6-l0`
- `nix shell nixpkgs#just -c just task6-l1`
- `nix shell nixpkgs#just -c just task6-l2`

Results:

- `just task6-l0` remains a replay of the kernel-only miss:
  - Verilator: `PASS: stores 64 outputs 64`
  - mapped utilization: `32,449 LUT / 46,736 FF / 4 DSP / 0 BRAM`
- `just task6-l1` is now stage-pure across Yosys, sim, and utilization:
  - Verilator: `PASS: stores 16 outputs 16`
  - mapped utilization: `29,778 LUT / 46,352 FF / 4 DSP / 0 BRAM`
- `just task6-l2` is now stage-pure across Yosys, sim, and utilization:
  - Verilator: `PASS: stores 256 outputs 256`
  - mapped utilization: `31,907 LUT / 45,932 FF / 4 DSP / 0 BRAM`

Operational conclusion:

- The runner is now a cleaner status surface for the active ladder.
- It is no longer the frontier.
- The branch remains blocked on a new structural hypothesis, not on tooling.

### 2026-04-24 - New bounded structural hypothesis: the tile-local output scratch memory is the remaining `L2` cost center

This is a research note only. No new RTL experiment was run here.

Evidence reviewed from the exact stage-pure frozen/reference surfaces:

- `L1` exact frozen reference:
  - `29,778 LUT / 46,352 FF / 4 DSP / 0 BRAM`
  - `11,519` pre-map design cells
- `L2` exact active tiled reference:
  - `31,907 LUT / 45,932 FF / 4 DSP / 0 BRAM`
  - `11,265` pre-map design cells
- The tiled `L2` wrapper shell itself is tiny:
  - `main.sv` is only `128` lines in the exact `yosys-stat` bundle
- The mapped leaf mix shifts materially from `L1` to `L2` even though the
  pre-map cell count does not grow:
  - `LUT6`: `13,887 -> 15,280` (`+1,393`)
  - `LUT5`: `3,189 -> 5,526` (`+2,337`)
  - `LUT3`: `8,050 -> 6,295` (`-1,755`)
  - `FF` stays roughly flat
- The exact memory inventory shows only one memory module in each bundle:
  - `L1`: `handshake_memory_out_f32_id3 = 512 bits`
  - `L2`: `handshake_memory_out_f32_id3 = 2,048 bits`
- The generated SV confirms that this module is the same control shape in both
  cases, but the tiled `L2` kernel grows it from:
  - `reg [31:0] _handshake_memory_3[0:15]`
  - to `reg [31:0] _handshake_memory_3[0:63]`
- That `L2` memory remains a local multi-ported register array with:
  - two write ports
  - two combinational read ports
  - `6-bit` local addresses
- That shape is consistent with LUT-mux expansion rather than BRAM use, which
  matches the current resource signature:
  - `4 DSP / 0 BRAM`
  - higher `LUT5/LUT6`, not a large FF increase

Hypothesis:

- The remaining `L2` gap is dominated by the tile-local output scratch memory
  and its widened address/mux logic inside `task6_l2_c_fc_tile64_kernel`, not
  by the `tile4x64` phase wrapper seam.
- The next bounded structural move should therefore be a storage-class /
  access-pattern rewrite on that local scratchpad, not another nearby FIFO/site
  sweep.
- Concretely: replace the current `2R/2W` async register-array behavior behind
  `handshake_memory_out_f32_id3` with a bounded alternative that exploits the
  already-serial tiled wrapper, so the tile kernel no longer pays for the same
  wide multi-port mux structure.

Expected dominant cost center:

- `handshake_memory_out_f32_id3` plus its immediate `ldAddr*` / `stAddr*`
  decode and valid/ready cone inside the `64 -> 64` tile kernel

Expected LUT delta:

- `-1,000` to `-2,500` LUT on the active tiled `L2` reference if this memory
  shape is actually dominant
- That is large enough to close most or all of the remaining `2,047` LUT gap
  without needing another architecture pivot

Explicit falsifier:

- A bounded rewrite of this tile-local scratch storage does not improve the
  active tiled `L2` mapped result by at least `800` LUT
- Or the mapped leaf mix stays dominated by the same `LUT5/LUT6` pattern
  without a clear storage-shape change
- Or the rewrite requires broad compiler/backend surgery instead of a local
  tile-kernel substitution
- Or the result breaks any of the current retained wins:
  - external weights
  - `DSP > 0`
  - passing tile-kernel / tiled-wrapper Verilator proof

Smallest validating artifact:

- Do not start at the full `tile4x64` wrapper
- First build the cheapest possible probe around the tile-local scratch memory:
  - either a standalone mapped comparison of the current `64 x 32` multi-port
    scratchpad against one bounded alternative
  - or a `tile64`-kernel-only substitution of that memory behavior
- Only replay into the full `tile4x64` wrapper if the `tile64`-local probe
  shows a clear mapped win while keeping the current contract intact

### 2026-04-24 - Amend the live execution order after the deep research audit

The external audit does not change the branch thesis, but it does change what
counts as the next mainline execution step.

Decision:

- keep StreamTensor-lite, but narrow its role:
  - it remains the fast extraction / contract / kernel-comparison harness
  - it is no longer assumed to be the whole board-fit solution by itself
- freeze the current validated StreamTensor-lite references:
  - `L1` gold reference:
    - `task6-l1-c-fc-redirect-index-ring3-postbranch-outbuf-fifo2-abc9`
    - `29,778 LUT / 46,352 FF / 4 DSP / 0 BRAM`
  - active tiled `L2` reference:
    - `task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2-abc9-utilization`
    - `31,907 LUT / 45,932 FF / 4 DSP / 0 BRAM`
- keep `mlp.c_proj` reserve-only
- keep monolithic `L2 c_fc` surgery closed
- keep `L3` blocked

New mainline execution order:

1. Finish the `top4-memory` / DDR3 shell evidence.
   - use the existing narrowed external-memory packages
   - record a final utilization result plus a short bandwidth note
2. Promote quantization from deferred follow-up to a bounded core track.
   - start from `task3-experiments`
   - import only the smallest donor set needed to test one surviving route on
     the same extracted-op proof surfaces
3. Run one bounded alternate-lowering comparison.
   - compare the current handshake-heavy path against one alternative on the
     same extracted contract
4. Only if one quantized route survives do we design a new low-bit tile
   kernel.

Operational rule change:

- the default next action is no longer "another local StreamTensor-lite RTL
  tweak"
- architecture-level tracks now take priority over further float32 helper
  surgery
- each new architecture-level track gets one bounded pass before we decide
  whether it deserves another slice

### 2026-04-24 - Execute the first bounded DDR3 / `top4-memory` pass

Run bundle:

- `artifacts/task6/runs/2026-04-24T11-26-50+0200/`

Commands run:

- `nix build .#tiny-stories-1m-baseline-float-selftest-top4-memory-external-memory-plan --no-link --print-out-paths`
- `nix build .#tiny-stories-1m-baseline-float-selftest-top4-memory-utilization --no-link --print-out-paths`
  - interrupted after the narrowed shell re-entered staged Yosys and no new
    mapped result had landed inside the bounded pass window

Direct outputs:

- external-memory-plan output:
  - `/nix/store/92wwyy3d90z6kiclnqncig9365ikd64n-tiny-stories-1m-baseline-float-selftest-top4-memory-external-memory-plan`
- live narrowed-shell utilization observations before interruption:
  - `stage1.il` and `stage2.il` began building
  - active staged Yosys worker reached at least:
    - `8,935,948 KB` RSS
    - later sampled at `6,215,864 KB` RSS while still active

What this bounded pass confirms:

- the narrowed `top4-memory` plan is still reproducible in the current branch
- the selected DDR3 candidates are unchanged:
  - `\handshake_memory_out_f32_id342`
  - `\handshake_memory_out_f32_id341`
  - `\handshake_memory_out_f32_id340`
  - `\handshake_memory_out_f32_id18`
- each selected module remains `3216448 x 32` bits:
  - `102,926,336` bits each
- selected total:
  - `411,705,344` bits
  - `49.08 MiB`
  - `95.1%` of the `433,040,010` eligible bits
- the narrowed shell still re-enters staged Yosys cleanly on the real baseline
  after the external-memory plan is applied

Bounded bandwidth worksheet:

- full cold sweep of the selected top-four footprint:
  - `1.6 GB/s` -> `32.16 ms`
  - `2.0 GB/s` -> `25.73 ms`
  - `3.2 GB/s` -> `16.08 ms`
  - `4.0 GB/s` -> `12.87 ms`
  - `6.4 GB/s` -> `8.04 ms`
- pessimistic upper bound if all four tables were reread every token:
  - `1 tok/s` -> `0.051 GB/s`
  - `10 tok/s` -> `0.515 GB/s`
  - `50 tok/s` -> `2.573 GB/s`
  - `100 tok/s` -> `5.146 GB/s`
- interpretation:
  - the selected memory footprint is small enough to be board-credible only if
    the runtime access pattern is far below the full-cold-sweep upper bound
  - this worksheet is a sizing note, not a measured DDR3 traffic trace

Verdict:

- This bounded pass is `partial`, not `closed`.
- The exact top-four DDR3 target set is reconfirmed and the narrowed shell
  still reaches staged Yosys on the real baseline.
- It did not produce a new mapped shell utilization result within the bounded
  pass.

Next action:

- if the DDR3 track gets another slice, rerun
  `tiny-stories-1m-baseline-float-selftest-top4-memory-utilization` under
  `scripts/pipeline/monitor_build.sh` so the late-stage shell frontier is
  captured as a real artifact
- otherwise move on to the bounded PT2E-static quantized replay rather than
  waiting blindly on another uninstrumented narrowed-shell build

### 2026-04-24 - Execute the bounded PT2E-static quantized replay

Run bundle:

- `artifacts/task6/runs/2026-04-24T11-32-46+0200/`

Commands run:

- `nix build .#tiny-stories-1m-cf-stats --no-link --print-out-paths`
- `nix build .#tiny-stories-1m-cf --no-link --print-out-paths`
- `nix build .#tiny-stories-1m-handshake --no-link --print-out-paths`
- cache-hot timing replays:
  - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#tiny-stories-1m-cf-stats --no-link --print-out-paths`
  - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#tiny-stories-1m-handshake --no-link --print-out-paths`

Direct outputs:

- `cf-stats`:
  - `/nix/store/zz6f4lb25aiajxwg3qipcwvky2q2fzcr-tiny-stories-1m-cf.stats`
- `cf`:
  - `/nix/store/m6a5fb7i1bxn2dyb6bidj3f7fkjvbkq7-tiny-stories-1m-cf.mlir`
- `handshake`:
  - `/nix/store/00bda3b97cnrgfi002d0hwjckkak25xg-tiny-stories-1m-handshake.mlir`

What this bounded pass confirms:

- the surviving quantized route in this branch is still `tiny-stories-1m`
  PT2E-static
- it still clears `cf-stats`
- it also now demonstrably clears:
  - full `cf`
  - full `handshake`
- important structural fact:
  - the quantized `handshake` path is currently built through
    `scripts/pipeline/cf_to_handshake_lsq.sh`
  - the live process invocation confirmed:
    - `circt-opt ... --lower-cf-to-handshake=lsq -handshake-insert-buffers`
- this means the surviving quantized route is already riding the LSQ handshake
  lowering path rather than the exact stock handshake script used by the float
  StreamTensor-lite mainline

Measured / observed details:

- `cf` artifact size:
  - `28,826,105` bytes
- `handshake` artifact size:
  - `500,285,892` bytes
- cache-hot replay timings:
  - `cf-stats`:
    - `ELAPSED=1.60`
    - `RSS_KB=294,732`
  - `handshake`:
    - `ELAPSED=0.26`
    - `RSS_KB=37,024`
- live frontier sample during the first `handshake` build:
  - `circt-opt` RSS around `3,195,504 KB`

Verdict:

- This bounded pass is `helpful`.
- The quantized route is stronger than the older note that stopped at
  `cf-stats`; it now reaches real `handshake`.
- `dynamic-int8` and `torchao` still stay frozen.

Next action:

- use this result to frame the alternate-lowering slice carefully:
  - do not compare "float stock handshake" versus "quantized LSQ handshake" as
    if only one variable changed
  - instead, pick one bounded A/B where the contract and representation are
    aligned well enough to isolate the lowering question
- keep the quantized route active, but do not widen it blindly into heavier
  downstream stages before that comparison is explicit

### 2026-04-24 - Execute the bounded LSQ alternate-lowering `L1` A/B

Run bundle:

- `artifacts/task6/runs/2026-04-24T11-40-03+0200/`

Commands run:

- `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-lsq-index-ring3-postbranch-outbuf-fifo2-yosys-stat --no-link --print-out-paths -L`
- `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-lsq-index-ring3-postbranch-outbuf-fifo2-abc9-utilization --no-link --print-out-paths -L`
- `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-lsq-index-ring3-postbranch-outbuf-fifo2-sv-sim --no-link --print-out-paths -L`

Why this A/B was chosen:

- The amended plan called for exactly one bounded alternate-lowering comparison
  on the same extracted `L1 c_fc` contract before any more kernel work.
- The surviving quantized full-model route already reaches `handshake` through
  `cf_to_handshake_lsq.sh`, so LSQ is the one concrete non-default lowering
  family already alive in this repo.
- The right first slice was therefore not "quantized LSQ versus float stock",
  but "same float extracted contract, LSQ lowering versus stock lowering",
  followed by the same validated selective `ui64` FIFO2 override pattern.

First issue found:

- Tightening the selective `ui64` patch helper to require exact replacement
  exposed that the historical `L1` hotspot site lists were not stage-pure on
  the LSQ path.
- The helper now fails fast if a listed `handshake_buffer*` site is not
  actually a `task6_ui64_fifo2_buffer` replacement target in the generated
  `sv/main.sv`.
- On the LSQ bundle, several old hotspot IDs are not `ui64` buffers:
  - ctrl buffers: `163,164,174,175,192,270`
  - `ui1` buffers: `176,271,280`
  - `f32` buffer: `216`
- The effective LSQ patchable subsets were:
  - index ring 3:
    - `160,161,162,165,173,177,178,179,180,181,182,185,186,187,188,189,190,191,213,214,215,217,218,219`
  - post-branch:
    - `264,265,266,269`
  - post-branch out-buffer:
    - `279`

Direct outputs:

- raw LSQ `sv` bundle:
  - `/nix/store/vv4bdibfff16bqg6vbv16dn7amxy2nmq-task6-l1-c-fc-redirect-lsq-sv`
- `yosys-stat`:
  - `/nix/store/zpimvrnbsi6yzg8iwzdi9f2lhqajn83f-task6-l1-c-fc-redirect-lsq-index-ring3-postbranch-outbuf-fifo2-yosys.stat`
- mapped utilization:
  - `/nix/store/3agxx5vklnklbz91mw1rgkj6sijsmcyh-task6-l1-c-fc-redirect-lsq-index-ring3-postbranch-outbuf-fifo2-abc9-utilization`
- built `sim_main`:
  - `/nix/store/zrvkisdq6476jccidssq8mr4y421wl7i-task6-l1-c-fc-redirect-lsq-index-ring3-postbranch-outbuf-fifo2-sim-main/obj_dir/sim_main`

Structural comparison against the frozen float `L1` reference:

- frozen float `sv` bundle:
  - `main.sv`: `7,664` lines, `809,614` bytes
  - total `sv`: `54` files, `1,109,724` bytes
- LSQ `sv` bundle:
  - `main.sv`: `8,241` lines, `896,749` bytes
  - total `sv`: `54` files, `1,185,425` bytes
- frozen float `yosys-stat`:
  - `num_cells=11,519`
- LSQ `yosys-stat`:
  - `ELAPSED=4.69`
  - `RSS_KB=564,140`
  - `num_cells=12,222`
  - `num_memory_bits=512`
  - top cell types:
    - `$mux=3,440`
    - `$and=2,845`
    - `$not=2,459`
    - `$dff=2,181`
    - `$or=722`

Mapped comparison against the frozen float `L1` reference:

- frozen float mapped reference:
  - `DSP=4`
  - `BRAM36=0`
  - `CLB LUTs=29,778`
  - `CLB FFs=46,352`
- LSQ mapped result:
  - `ELAPSED=89.23`
  - `RSS_KB=563,056`
  - `DSP=4`
  - `BRAM36=0`
  - `CLB LUTs=29,329`
  - `CLB FFs=46,570`
  - dominant mapped leaf types:
    - `LUT6=14,399`
    - `LUT3=7,653`
    - `LUT2=3,329`
    - `LUT5=2,568`
    - `LUT4=1,380`
    - `FDRE=46,567`
    - `RAM32M=6`

Functional result:

- `sv-sim` does not pass the same redirected `L1` contract.
- Verilator built successfully, but the run aborted with:
  - `Timeout waiting for redirected GEMV completion`
  - `task6_contract_gemv_tb_main.sv:259`
- measured sim timing:
  - `ELAPSED=82.09`
  - `RSS_KB=437,484`

Verdict:

- This bounded LSQ A/B is `structurally interesting but operationally negative`.
- Positive signal:
  - it beats the frozen float `L1` reference on mapped LUT
    - `29,778 -> 29,329`
  - it preserves `4 DSP48E1`
  - it stays under the `29,860` LUT ceiling on mapped area alone
- Negative signal:
  - it is not a drop-in-safe replacement for the same proof harness because the
    redirected `L1` contract still times out under Verilator
- The one-pass alternate-lowering slice is therefore spent and closed without
  becoming the new mainline.

Next action:

- Do not widen alternate-lowering work on this branch without a stronger
  hypothesis than "LSQ might lower LUT".
- Keep the result recorded as a negative A/B reference.
- Continue with quantized extracted-op parity on the Task 6 proof harness,
  using the surviving PT2E-static route as the active architecture track.

### 2026-04-24 - Execute the bounded PT2E-static extracted-op parity pass

Run bundle:

- `artifacts/task6/runs/2026-04-24T13-02-11+0200/`

Why this slice was next:

- After the bounded full-model PT2E-static replay and the bounded LSQ A/B, the
  smallest remaining architecture question was:
  - can the surviving PT2E-static route actually survive on the direct Task 6
    extracted-op harness once the weight matrix is externalized?
- The right first slice was the smallest `L1` surface:
  - `tiny-stories-1m-representative-core-v64-h4`
  - `task6-l1-c-fc-redirect`
  - shape `[1, 4] x [4, 16]`

Implementation added:

- `src/task6_rect_gemv_pt2e_static_quant_adapter.py`
- model key:
  - `task6-l1-c-fc-redirect-pt2e-static`

Commands run:

- `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-pt2e-static-torch --no-link --print-out-paths -L`
- `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-torch --no-link --print-out-paths -L`
- local PT2E graph inspection under the pinned `python-with-tiny-stories` env
  with:
  - `TASK6_RECT_GEMV_IN_DIM=4`
  - `TASK6_RECT_GEMV_OUT_DIM=16`

Direct outputs:

- quantized extracted-op `torch`:
  - `/nix/store/qfamvz0l8b6axi8pr7snnxm61y5yfp31-task6-l1-c-fc-redirect-pt2e-static-torch.mlir`
- frozen float `L1` `torch` reference:
  - `/nix/store/zbg1drcqw0a1w77pww3nv8xq3whvqg5p-task6-l1-c-fc-redirect-torch.mlir`

Measured details:

- quantized extracted-op `torch` build:
  - `ELAPSED=4.61`
  - `RSS_KB=276,128`
- frozen float `L1` `torch` build:
  - `ELAPSED=4.24`
  - `RSS_KB=276,464`
- local PT2E inspection:
  - `ELAPSED=2.26`
  - `RSS_KB=341,772`

Key result:

- the exported `torch` MLIR is byte-identical between the PT2E-static route and
  the frozen float route:
  - quantized size:
    - `299` bytes
  - float size:
    - `299` bytes
  - shared SHA-256:
    - `f72bdc8d20105e9b8ee048aec691ee16839eee7d9020ce7e18330b1590810d9b`
  - `cmp` result:
    - `TORCH_EXPORT_IDENTICAL=1`

Local graph inspection explains why:

- prepared graph:
  - still only `aten.matmul.default`
- converted graph:
  - still only `aten.matmul.default`
- re-exported graph:
  - still only `aten.matmul.default`
- there are no inserted quant/dequant nodes on this direct external-weight
  GEMV surface

Interpretation:

- This is not "quantized, then optimized away later in MLIR".
- PT2E-static is already a no-op at the PyTorch export surface for this
  external-weight kernel.
- So the direct extracted-op parity path fails before any later IR or RTL
  question becomes relevant.

Verdict:

- This bounded quantization slice is `reject-quant-noop`.
- The broader `tiny-stories-1m` PT2E-static route remains useful as a
  full-model reference because it reaches real `handshake`.
- But the direct external-weight Task 6 kernel does not currently survive as a
  quantized extracted-op route.

Next action:

- Do not widen `task6-l1-c-fc-redirect-pt2e-static` onto `L2` or any heavier
  parity surface.
- Do not start a low-bit kernel from this route.
- Any further quantization work now needs a new extracted-op hypothesis that
  actually quantizes with external weights instead of collapsing back to the
  frozen float graph.

### 2026-04-24 - Amend execution after the second deep-research audit

The latest audit changes the execution posture, not the Task 6 thesis.

Keep:

- StreamTensor-lite as the rapid extraction / contract / kernel-comparison
  harness
- `mlp.c_fc` as the mainline boundary
- `mlp.c_proj` as reserve-only
- monolithic `L2 c_fc` surgery closed
- `L3` blocked until an architecture-level result changes the story

Change:

- stop treating more float32 helper tuning as the default frontier
- make the `top4-memory` / DDR3 shell pass the first architecture-level track
- keep quantization active only if it starts from minimized TinyStories
  surfaces first:
  - `tiny-stories-1m-representative-core`
  - then the frozen `L1` cutout
  - only then wider replay
- keep alternate-lowering closed unless a new bounded hypothesis appears
- do not start a new low-bit kernel family until one quantized route survives
  the extracted-op parity gates as a genuinely quantized artifact

Operational consequence:

- `just task6-l0`, `just task6-l1`, and `just task6-l2` remain status-only
  replay surfaces
- the next live execution slice is the monitored baseline
  `tiny-stories-1m-baseline-float-selftest-top4-memory-utilization` rerun,
  not another local kernel edit

### 2026-04-24 - First `top4-memory` rerun after switching to upstream CIRCT

Run bundle:

- `artifacts/task6/runs/2026-04-24T13-34-06+0200/`

Command run:

- `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#tiny-stories-1m-baseline-float-selftest-top4-memory-external-memory-plan --no-link --print-out-paths -L`

Observed result:

- The command did not reach the `top4-memory` model derivations.
- It first re-entered the one-time upstream toolchain bootstrap:
  - `llvm-tblgen`
  - `llvm`
  - `mlir`
  - `circt`
- measured wall-clock before manual stop:
  - `77.96 s`
- deepest direct progress seen in the build log:
  - `llvm-tblgen` configure complete
  - `llvm-tblgen` build at `[221/388]`
- no external-memory-plan store path was emitted

Interpretation:

- This is not a new DDR3 shell result.
- It is the first concrete cost of the earlier branch decision to switch from
  the local CIRCT fork to upstream `llvm/circt`.
- Until that toolchain bootstrap lands once on this machine, architecture-level
  reruns will spend their bounded pass budget on toolchain re-entry instead of
  on the actual `top4-memory` shell question.

Verdict:

- Record this as `blocked-upstream-toolchain-bootstrap`.
- Do not treat it as evidence for or against the `top4-memory` shell itself.

Next action:

- Warm the upstream LLVM/MLIR/CIRCT stack once, then rerun the monitored
  baseline `top4-memory` pass.

### 2026-04-24 - Cheapest `L0` warm-up probe after the upstream rerun block

Run bundle:

- `artifacts/task6/runs/2026-04-24T13-37-32+0200/`

Command run:

- `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l0-gemv64-yosys-stat --no-link --print-out-paths -L`

Observed result:

- measured wall-clock before manual stop:
  - `32.17 s`
- no store path was emitted
- the log again re-entered the upstream toolchain bootstrap before any Task 6
  IR stage:
  - `llvm-tblgen`
  - `llvm`
  - `mlir`
  - `circt`
- deepest direct progress seen before stop:
  - `llvm-tblgen` configure complete

Interpretation:

- This confirms the blocker is not specific to the baseline `top4-memory`
  shell.
- The branch is currently blocked on completing one full upstream
  LLVM/MLIR/CIRCT bootstrap on this machine after the `llvm/circt` switch.
- Restarted Task 6 targets do not meaningfully advance the plan until that
  bootstrap lands once.

Verdict:

- Record this as the second `blocked-upstream-toolchain-bootstrap` signal.

Next action:

- Stop spending experiment slices on restarted Task 6 targets.
- Let one full upstream bootstrap finish, then resume with the monitored
  baseline `top4-memory` pass.

### 2026-04-24 - Resume execution with external memory mainline and one bounded quant spike

Execution change:

- keep the thesis unchanged:
  - external memory and quantization stay the two active architecture tracks
  - StreamTensor-lite stays the comparison harness, not the whole solution
- change the emphasis:
  - make external memory the mainline lane
  - keep quantization as a single bounded spike on minimized TinyStories
    surfaces rather than a survey

Mainline external-memory hypothesis:

- The correct next architecture-level run is still the monitored baseline
  `tiny-stories-1m-baseline-float-selftest-top4-memory-utilization` pass.
- With the repo-local CIRCT overlay removed and the `circt-nix` upstream pair
  restored, this rerun should finally produce a real narrowed-shell utilization
  result instead of spending the entire bounded pass in toolchain bootstrap.
- Expected result:
  - either a mapped `top4-memory` shell bundle with real `DSP / BRAM / LUT / FF`
    numbers and a usable monitor summary
  - or a new concrete blocker later than toolchain bootstrap
- Falsifier:
  - the run again fails to reach the actual `top4-memory` model stages
  - or produces no narrowed-shell utilization artifact

Bounded quantization-spike hypothesis:

- The surviving PT2E-static route should be replayed first on minimized
  TinyStories full-model surfaces, not on the already-rejected direct
  external-weight extracted-op surface.
- The missing fast-loop surface in this repo is a representative-core
  PT2E-static model key that uses the same reduced-config construction as
  `tiny-stories-1m-representative-core`, then runs through the existing LSQ
  quantized pipeline.
- Expected result:
  - a minimized representative-core PT2E-static route that reaches at least
    `cf-stats`, and ideally `handshake`, faster than the full
    `tiny-stories-1m` quantized path
- Falsifier:
  - the minimized representative-core PT2E-static route fails before `cf`
  - or it clearly collapses back to the same unquantized surface without
    surviving as a meaningful quantized full-model artifact

Operational split:

- Start the monitored baseline `top4-memory` rerun first and let it consume the
  larger experiment budget.
- Use the wait time to add the representative-core PT2E-static quant surface
  and run exactly one bounded minimized-surface quant replay.

### 2026-04-24 - Mainline `top4-memory` rerun after restoring `circt-nix` as shipped

Run bundle:

- `artifacts/task6/runs/2026-04-24T18-05-18+0200-baseline-top4-memory-utilization/`

Command run:

- `MONITOR_GLOBAL_PGREP_PATTERN="default-builder.sh|yosys -q -s run.ys|yosys-abc" scripts/pipeline/monitor_build.sh artifacts/task6/runs/2026-04-24T18-05-18+0200-baseline-top4-memory-utilization 5 -- nix build .#tiny-stories-1m-baseline-float-selftest-top4-memory-utilization --no-link --print-out-paths -L`

Observed result:

- This is no longer blocked on upstream LLVM/MLIR/CIRCT bootstrap.
- The run reaches the real baseline TinyStories lowering stack and fails at:
  - `tiny-stories-1m-baseline-float-handshake.mlir.drv`
  - `circt-opt ... -flatten-memref -flatten-memref-calls -canonicalize -cse -handshake-legalize-memrefs -canonicalize -cse`
- failure mode:
  - upstream CIRCT segfault
  - `pipeline/common.sh: line 28: Segmentation fault (core dumped)`
- monitor summary:
  - `exit_status=1`
  - `wall_seconds=16`
  - `peak_vmrss_kb=565,464`
- no narrowed-shell utilization artifact was emitted

Interpretation:

- Restoring `circt-nix` as shipped fixed the earlier source-pair compile
  mismatch, but it exposes a new downstream blocker on this branch:
  - upstream CIRCT now crashes during the baseline float `cf -> handshake`
    lowering before the `top4-memory` shell flow can answer the real shell-fit
    question
- So the external-memory lane is still the mainline, but it is currently
  blocked by a concrete upstream CIRCT runtime failure rather than by bootstrap
  warm-up

Verdict:

- Record this as `block-upstream-circt-handshake-crash`.
- Do not treat it as evidence for or against `top4-memory` itself.

Next action:

- Keep external memory as the mainline lane.
- Before another baseline `top4-memory` shell pass, either:
  - pin back to a CIRCT pair that survives `tiny-stories-1m-baseline-float-handshake`
  - or isolate the minimal crashing `cf.mlir` reproducer for the upstream
    `-handshake-legalize-memrefs` failure
- Use the bounded quantization spike meanwhile, since it does not require
  reopening the closed StreamTensor-lite float32 tuning loop

### 2026-04-24 - First minimized representative-core PT2E-static quant spike attempt

Run bundle:

- `artifacts/task6/runs/2026-04-24T18-06-57+0200-representative-core-pt2e-static-cf-stats-attempt/`

Why this slice was chosen:

- The plan calls for quantization to stay a bounded spike on minimized
  TinyStories surfaces first, not another full `tiny-stories-1m` replay and
  not another extracted-op PT2E-static retry.
- The missing fast-loop surface was a representative-core full-model
  PT2E-static key, so this slice adds exactly that and tries the smallest
  meaningful gate:
  - `tiny-stories-1m-representative-core-pt2e-static-cf-stats`

Implementation added:

- `TinyStories/model_adapter_representative_core_pt2e_static_quant.py`
- model key:
  - `tiny-stories-1m-representative-core-pt2e-static`

Command run:

- `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#tiny-stories-1m-representative-core-pt2e-static-cf-stats --no-link --print-out-paths -L`

Observed result:

- The first attempt does not reach PyTorch export or MLIR stages.
- Nix evaluation fails immediately because the new adapter file is untracked and
  therefore omitted from the flake source snapshot:
  - `Path 'TinyStories/model_adapter_representative_core_pt2e_static_quant.py' ... is not tracked by Git`
- measured front-end cost:
  - `ELAPSED=1.24`
  - `RSS_KB=184,688`

Interpretation:

- This is not a quantization verdict yet.
- It is only the flake tracked-file rule firing on the newly added minimized
  quant adapter.

Verdict:

- Record this as `block-untracked-quant-surface`.

Next action:

- Track the new representative-core PT2E-static adapter in Git, commit the
  current lane state, then rerun the same `cf-stats` gate unchanged.

### 2026-04-24 - Standalone repro for the baseline float `cf -> handshake` crash

Run bundle:

- `artifacts/task6/runs/2026-04-24T18-11-02+0200-baseline-handshake-repro/`

Command run:

- `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' /nix/store/9am975q7rmbvpzxzgg1j260da3qhkqzq-circt-1.144.0g20260331_5dc62fe/bin/circt-opt /nix/store/k34gyy0qqnsd0f7yi595kxs2mx3nfjr1-tiny-stories-1m-baseline-float-cf.mlir -flatten-memref -flatten-memref-calls -canonicalize -cse -handshake-legalize-memrefs -canonicalize -cse`

Observed result:

- The upstream CIRCT crash reproduces directly outside the Nix pipeline.
- key crash signature:
  - `mlir::DenseElementsAttr::getNumElements() const`
- measured direct reproducer cost:
  - `ELAPSED=1.42`
  - `RSS_KB=94,720`
- output file stays empty:
  - `0` bytes in `/tmp/task6-baseline-float-handshake-repro.mlir`

Interpretation:

- The active external-memory blocker is a clean standalone CIRCT runtime crash,
  not a wrapper bug in the Task 6 shell machinery.
- That makes the next external-memory choice much narrower:
  - either pin back to a non-crashing CIRCT pair for shell work
  - or isolate and report the crashing `cf.mlir` reproducer upstream

Verdict:

- Record this as `pass-reproducer`.

Next action:

- Use this reproducer as the concrete blocker reference for the external-memory
  mainline while the bounded quant spike continues.

### 2026-04-24 - Representative-core PT2E-static quant spike rerun on a tracked tree

Run bundle:

- `artifacts/task6/runs/2026-04-24T18-11-27+0200-representative-core-pt2e-static-cf-stats/`

Command run:

- `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#tiny-stories-1m-representative-core-pt2e-static-cf-stats --no-link --print-out-paths -L`

Direct outputs:

- `cf-stats`:
  - `/nix/store/lggrgacn2ymq9b579sgca94wbpvawwz0-tiny-stories-1m-representative-core-pt2e-static-cf.stats`
- quantized `torch` MLIR:
  - `/nix/store/gx4kwvs2sajyd55vzyggc8r4ag1wajl2-tiny-stories-1m-representative-core-pt2e-static-torch.mlir`

Observed result:

- The minimized representative-core PT2E-static route is a real surviving full
  model surface, not a no-op like the rejected direct external-weight
  extracted-op route.
- Measured build cost:
  - `ELAPSED=49.58`
  - `RSS_KB=293,732`
- The exported `torch` MLIR contains explicit quantized structure:
  - `66` `torch.aten.quantize_per_tensor` ops
  - `17` `torch.aten.matmul` ops
- Torch-MLIR warns that several quantized operands are only partially traced and
  therefore remain in QDQ form around `torch.aten.matmul`.
- The route reaches real `cf-stats` on the minimized model, with a nontrivial
  lowered control/memory shape:
  - `arith.cmpi=1,724`
  - `cf.cond_br=1,419`
  - `memref.alloc=104`
  - `memref.global=18`

Interpretation:

- This is the first bounded quant spike on minimized TinyStories that actually
  survives as a quantized full-model artifact in this branch.
- It is therefore materially stronger than the earlier direct extracted-op
  PT2E-static no-op result.

Verdict:

- Record this as `pass-quant-minimized-cf`.

Next action:

- Spend exactly one more gate on the same minimized surface:
  - `tiny-stories-1m-representative-core-pt2e-static-handshake`

### 2026-04-24 - Representative-core PT2E-static `handshake` gate

Run bundle:

- `artifacts/task6/runs/2026-04-24T18-12-19+0200-representative-core-pt2e-static-handshake/`

Command run:

- `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#tiny-stories-1m-representative-core-pt2e-static-handshake --no-link --print-out-paths -L`

Observed result:

- The minimized representative-core quantized route fails in the same upstream
  CIRCT shell pipeline as the baseline float shell:
  - `circt-opt ... -flatten-memref -flatten-memref-calls -canonicalize -cse -handshake-legalize-memrefs -canonicalize -cse`
- crash signature matches the baseline reproducer:
  - `mlir::DenseElementsAttr::getNumElements() const`
- measured cost:
  - `ELAPSED=5.45`
  - `RSS_KB=421,944`

Interpretation:

- The external-memory mainline and the bounded quant spike now share the same
  concrete blocker:
  - upstream CIRCT crashes in `-handshake-legalize-memrefs`
- This means the next architecture-level choice is no longer "which lane first"
  so much as "which CIRCT pair is allowed to answer either lane at all"

Verdict:

- Record this as `block-shared-upstream-circt-handshake-crash`.

Next action:

- Do not widen quantization further on this branch until the handshake crash is
  removed or worked around.
- Keep the minimized representative-core PT2E-static `cf-stats` result as the
  live quant reference surface below that blocker.

### 2026-04-24 - Direct pass isolation for the shared upstream CIRCT crash

Run bundle:

- `artifacts/task6/runs/2026-04-24T18-28-54+0200-flatten-memref-isolation/`

Command set:

- `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' /nix/store/9am975q7rmbvpzxzgg1j260da3qhkqzq-circt-1.144.0g20260331_5dc62fe/bin/circt-opt /nix/store/k34gyy0qqnsd0f7yi595kxs2mx3nfjr1-tiny-stories-1m-baseline-float-cf.mlir -flatten-memref`
- `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' /nix/store/9am975q7rmbvpzxzgg1j260da3qhkqzq-circt-1.144.0g20260331_5dc62fe/bin/circt-opt /nix/store/a0jsiyfh8py537xidmx38hkkdkz773j3-tiny-stories-1m-representative-core-pt2e-static-cf.mlir -flatten-memref`

Supporting control checks:

- baseline `-canonicalize -cse`:
  - passes
- baseline `-flatten-memref-calls`:
  - passes

Observed result:

- The shared upstream blocker is narrower than the earlier shell logs implied:
  both the baseline float shell and the minimized representative-core PT2E-static
  quant spike crash on `-flatten-memref` alone.
- crash signature matches in both cases:
  - `mlir::DenseElementsAttr::getNumElements() const`
- measured direct reproducer costs:
  - baseline float:
    - `ELAPSED=2.35`
    - `RSS_KB=93,940`
  - representative-core PT2E-static:
    - `ELAPSED=1.29`
    - `RSS_KB=43,764`

Manual bounded probes:

- These do **not** reproduce the crash:
  - trivial `memref.global` plus `memref.get_global`
  - trivial `memref.global` plus `memref.load`
  - trivial strided-arg `memref.load` / `memref.store`
- These fail as legalization leftovers, not as crashes:
  - trivial `memref.expand_shape`
  - trivial `memref.subview`

Reducer attempts:

- `circt-reduce` from the upstream CIRCT package is not usable for this input in
  current packaging:
  - it cannot parse the `memref`-dialect file as invoked here
- `mlir-reduce` from the paired MLIR package exposes reducer/test options only
  through reduction-pass configuration and did not emit a reduced test case for
  this crash in one bounded attempt

Interpretation:

- The mainline external-memory blocker and the bounded quant blocker are the
  same single-pass CIRCT failure:
  - `flatten-memref`
- That is a better blocker statement than the earlier broader label
  `handshake-legalize-memrefs`.
- The current state is sufficient to justify one of only two next moves:
  - pin back to a known non-crashing CIRCT pair for branch progress
  - or extract/report the crashing full-model `cf.mlir` inputs upstream

Verdict:

- Record this as `pass-shared-flatten-memref-reproducer`.

Next action:

- Do not spend more lane time on downstream shell or quant widening until the
  `flatten-memref` blocker is either worked around or swapped out by a different
  CIRCT pair.

### 2026-04-24 - First replay of the local CIRCT fork fixes on top of `circt-nix`

Run bundle:

- `artifacts/task6/runs/2026-04-24T19-05-18+0200-representative-core-pt2e-static-handshake-fork-patches/`

Local source used:

- `/home/roland/circt`

Patch set added to this repo:

- `patches/circt-upstream-task3-recovery/0001-flatten-memref-shape-ops-after-memref-flattening.patch`
- `patches/circt-upstream-task3-recovery/0002-handle-cfg-threaded-memrefs-in-handshake-lowering.patch`
- `patches/circt-upstream-task3-recovery/0003-support-extra-frontend-ops-in-handshaketohw.patch`
- `patches/circt-upstream-task3-recovery/0004-mark-assert-and-math-illegal-in-handshaketohw.patch`
- `patches/circt-upstream-task3-recovery/0005-handle-dense-resource-globals-in-flattenmemrefs.patch`
- `patches/circt-upstream-task3-recovery/0006-lower-func-conversion-priority-in-handshaketohw.patch`
- `patches/circt-upstream-task3-recovery/0007-legalize-unrealized-conversion-casts-in-handshaketohw.patch`
- `patches/circt-upstream-task3-recovery/0008-defer-func-lowering-until-body-is-legal.patch`
- `patches/circt-upstream-task3-recovery/0009-handle-memref-model-io-and-cache-submodule-lookups.patch`
- `patches/circt-upstream-task3-recovery/0010-lower-float-ops-as-externs-in-handshaketohw.patch`

Command run:

- `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#tiny-stories-1m-representative-core-pt2e-static-handshake --no-link --print-out-paths -L`

Observed result:

- The replay gets past Nix evaluation and starts rebuilding CIRCT with the new
  patch stack.
- It fails in `patchPhase`, before compile or MLIR lowering, because the first
  `FlattenMemRefs` patch no longer applies cleanly to the newer upstream CIRCT
  revision packaged by `circt-nix`.
- Direct patch failure from the build log:
  - `Hunk #5 FAILED at 515`
  - reject file:
    - `lib/Transforms/FlattenMemRefs.cpp.rej`
- measured cost:
  - `ELAPSED=6.15`
  - `RSS_KB=421,892`

Interpretation:

- The April 20 fork fixes are directionally relevant, but they are not
  drop-in-applicable to the current upstream CIRCT package as-is.
- The active blocker has therefore shifted one step earlier:
  - from runtime `flatten-memref` crash
  - to source drift in `FlattenMemRefs.cpp` during patch application

Verdict:

- Record this as `block-circt-patch-drift`.

Next action:

- Rebase or hand-adapt the `FlattenMemRefs` fixes onto the current upstream
  source, then rerun the same minimized representative-core `handshake` gate
  unchanged before spending another slice on the heavier external-memory shell.

### 2026-04-24 - Rebased fork patch stack clears CIRCT compile but trips one buffer regression test

Run bundle:

- `artifacts/task6/runs/2026-04-24T19-18-44+0200-representative-core-pt2e-static-handshake-rebased-fork-patches/`

Rebased patch set now applied in this repo:

- `patches/circt-upstream-task3-recovery/0001-flatten-memref-shape-ops-after-memref-flattening.patch`
- `patches/circt-upstream-task3-recovery/0002-handle-cfg-threaded-memrefs-in-handshake-lowering.patch`
- `patches/circt-upstream-task3-recovery/0005-handle-dense-resource-globals-in-flattenmemrefs.patch`
- `patches/circt-upstream-task3-recovery/0011-rebased-handshaketohw-stack.patch`

Command run:

- `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#tiny-stories-1m-representative-core-pt2e-static-handshake --no-link --print-out-paths -L`

Observed result:

- The rebased patch stack now applies cleanly to the `circt-nix` packaged
  CIRCT source.
- CIRCT completes `buildPhase` successfully.
- The critical patched files compile and link:
  - `lib/Transforms/FlattenMemRefs.cpp`
  - `lib/Dialect/Handshake/Transforms/LegalizeMemrefs.cpp`
  - `lib/Conversion/HandshakeToHW/HandshakeToHW.cpp`
- `check-circt` then runs and reports exactly one failure:
  - `CIRCT :: Conversion/HandshakeToHW/test_buffer.mlir`
- The failing FileCheck expects:
  - `hw.constant false`
- The patched lowering emits:
  - `hw.constant 0 : i0`
- measured build cost:
  - `ELAPSED=803.01`
  - `RSS_KB=421,760`
- test summary:
  - `Passed: 1163`
  - `Failed: 1`
  - `Expectedly Failed: 6`
  - `Unsupported: 39`

Interpretation:

- This is a real step forward from the original upstream blocker.
- The local fork fixes are no longer blocked by patch drift, and the old
  `flatten-memref` infrastructure path is cleared far enough to rebuild the
  whole packaged CIRCT toolchain.
- The active blocker has shifted again:
  - away from runtime `flatten-memref` crash
  - away from patch drift
  - to one CIRCT regression expectation in Handshake-to-HW buffer lowering
- That is the right scale of blocker to address next because it keeps checks
  enabled and should let the same representative-core `handshake` gate answer
  the actual Task 6 question once aligned.

Verdict:

- Record this as `block-circt-check-buffer-test`.

Next action:

- Recover the matching buffer-test update from the local fork history and rerun
  the same representative-core `handshake` gate unchanged before moving on to a
  heavier external-memory rerun.

### 2026-04-24 - Rebased fork stack plus buffer-test fix clears CIRCT and exposes the next quant blocker

Run bundle:

- `artifacts/task6/runs/2026-04-24T19-41-24+0200-representative-core-pt2e-static-handshake-rebased-fork-patches-plus-testfix/`

Additional patch added from local fork history:

- `patches/circt-upstream-task3-recovery/0012-update-buffer-lowering-test-for-constant-order.patch`

Command run:

- `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#tiny-stories-1m-representative-core-pt2e-static-handshake --no-link --print-out-paths -L`

Observed result:

- CIRCT now builds completely under Nix with the rebased patch stack plus the
  matching test update.
- The build reaches `fixupPhase`, so:
  - the old upstream `flatten-memref` crash is cleared
  - the earlier `check-circt` blocker on
    `Conversion/HandshakeToHW/test_buffer.mlir` is also cleared
- The representative-core quantized `handshake` derivation then fails later in
  its own lowering pipeline with:
  - `<Pass-Options-Parser>: no such option lsq`
  - `failed to add lower-cf-to-handshake with options lsq`
- measured cost:
  - `ELAPSED=829.21`
  - `RSS_KB=421,940`

Interpretation:

- This is the first clean proof that the local fork fixes are functionally
  relevant on current upstream packaging:
  - we are no longer blocked by patch drift
  - we are no longer blocked by the upstream CIRCT `flatten-memref` crash
  - we are no longer blocked by the one failing Handshake-to-HW regression test
- The quantized representative-core route is still blocked, but now on a more
  specific contract mismatch:
  - the route expects an LSQ-specific `lower-cf-to-handshake=lsq` option
  - the current patched upstream stack does not expose that option
- This means the external-memory float mainline can be resumed on the repaired
  CIRCT base, while the quant spike now needs either:
  - restoration of the older LSQ memory-lowering extension, or
  - a non-LSQ handshake path

Verdict:

- Record this as `block-missing-lsq-option`.

Next action:

- Rerun the external-memory mainline on the repaired CIRCT stack first.
- Keep the quant spike bounded and decide separately whether to restore the LSQ
  option support or switch that route onto a non-LSQ path.

### 2026-04-28 - Fixed `top34-memory` utilization completes after GC-rooted JSON rerun

Run bundles:

- Full monitored staged rerun:
  - `artifacts/task6/runs/2026-04-27T23-43-30+0200-baseline-top34-memory-utilization-filterfix-rerun`
- JSON/utilization rerun after freeing disk:
  - `artifacts/task6/runs/2026-04-28T03-11-30+0200-baseline-top34-memory-utilization-filterfix-json-rerun`

Commands:

- full staged run:
  - `nix build .#tiny-stories-1m-baseline-float-selftest-top34-memory-utilization --no-link --print-out-paths -L`
  - wrapped with `scripts/pipeline/monitor_build.sh`
- after ENOSPC:
  - temporarily preserved the successful `stage8h` output with a Nix GC root
  - ran `nix-store --gc --max-freed 64424509440`, which freed `60.8 GiB`
  - reran the same utilization target under the monitor

Full staged rerun result:

- exit status: `1`
- wall time: `12340` seconds
- peak sampled `VmRSS`: `20,578,672 KiB`
- peak sampled `VmHWM`: `20,816,540 KiB`
- completed:
  - `stage6a targeted techmap cells_map` through all `221/221` restart
    batches
  - `stage8b abc -luts 2:2,3,6:5,10,20`
  - `stage8h opt_lut_ins -tech xilinx`
- failure:
  - JSON derivation preparation hit `OSError: [Errno 28] No space left on
    device` in `filter_rtlil_modules.py`
- interpretation:
  - this crossed both prior external-memory frontiers
  - the failure was disk exhaustion, not a synthesis-path failure

JSON/utilization rerun result:

- exit status: `0`
- wall time: `294` seconds
- peak sampled `VmRSS`: `22,539,800 KiB`
- peak sampled `VmHWM`: `23,849,916 KiB`
- final monitor stage line:
  - `stage9 write_json`
- output:
  - `/nix/store/lnzv5y9vj69s8hhg3zp0x35hrmzmrrzz-tiny-stories-1m-baseline-float-selftest-top34-memory-utilization`
  - durable copy:
    `artifacts/task6/runs/2026-04-28T03-11-30+0200-baseline-top34-memory-utilization-filterfix-json-rerun/utilization`

Mapped utilization:

- `clb_luts`: `56,899,009 / 298,600` (`19055.26%`)
- `clb_ffs`: `58,496,710 / 597,200` (`9795.16%`)
- `slices_lower_bound`: `7,312,089 / 74,650` (`9795.16%`)
- `dsp`: `0 / 1920` (`0.00%`)
- `bram36`: `0 / 955` (`0.00%`)

Delta versus copied all-memory baseline:

- copied baseline:
  - `clb_luts`: `40,416,086`
  - `clb_ffs`: `58,072,527`
  - `dsp`: `0`
  - `bram36_equivalent`: `0.0`
- `top34-memory` delta:
  - `clb_luts`: `+16,482,923` (`+40.78%`)
  - `clb_ffs`: `+424,183` (`+0.73%`)
  - `dsp`: unchanged at `0`
  - `bram36`: unchanged at `0`

Largest remaining non-top mapped owners by LUT count:

- `handshake_memory_out_f32_id77`: `631,072` LUTs, `8,360` FFs
- `math_fpowi_in_f32_ui64_out_f32`: `370,334` LUTs, `0` FFs
- `handshake_memory_out_f32_id25`: `340,924` LUTs, `2,437` FFs
- `handshake_memory_out_f32_id72`: `47,456` LUTs, `8,212` FFs
- `handshake_memory_out_f32_id37`: `34,955` LUTs, `2,132` FFs

Interpretation:

- The production filter fix is verified.
- `top34-memory` is a real toolchain-frontier improvement:
  - it clears the prior `top4-memory` `stage6a` residual-memory frontier
  - it clears the prior `top32-memory` `stage8b` ABC frontier
  - it produces a final utilization bundle after the disk-space issue is fixed
- `top34-memory` is not a mapped-resource improvement:
  - LUT usage is materially worse than the copied all-memory baseline
  - FF usage is slightly worse
  - DSP and BRAM remain unused

Decision:

- Close this `top34-memory` execution slice as `positive` for compiler
  frontier movement and `negative` for mapped resource reduction.
- Do not move directly to DDR3 controller integration for this exact shell.
- Keep external memory alive only as a contract/interface-shaping lane:
  - explain why the current blackbox shell inflates LUTs before widening it
    again
  - use the largest residual owners above as the next inspection targets if
    this lane gets another slice
  - compare any follow-up against the copied all-memory baseline, not only
    against OOM progress

### 2026-04-28 - Redirection baseline owner extraction corrected

Decision record:

- `docs/task6-redirection-decision.md`

Machine-readable baseline:

- `artifacts/task6/parallel-hypotheses/baseline-top34.csv`

Command:

- `python3 scripts/task6/extract_metrics.py artifacts/task6/runs/2026-04-28T03-11-30+0200-baseline-top34-memory-utilization-filterfix-json-rerun artifacts/task6-streamtensor-lite/runs/2026-04-24T00-10-27+0200/stage-local-l1 artifacts/task6-streamtensor-lite/runs/2026-04-24T00-10-36+0200/stage-local-l2 --artifact top34-memory --artifact l1-c-fc-frozen --artifact l2-c-fc-tile4x64 --out artifacts/task6/parallel-hypotheses/baseline-top34.csv`

Script update:

- `scripts/task6/extract_metrics.py` now weights `top_owners` by direct owner
  instance count under the real synthesized `main` module when the design is
  wrapped by `tiny_stories_selftest_top`.
- The old extraction ranked one instance of each module definition, which made
  single large owners like `handshake_memory_out_f32_id77` look dominant while
  hiding heavily repeated buffer types.

Corrected `top34-memory` owner signal:

- `handshake_buffer_in_ui64_out_ui64_2slots_seq`:
  `168,260` instances, `34,156,780` LUT, `43,747,600` FF.
- `handshake_buffer_in_f64_out_f64_2slots_seq`:
  `28,455` instances, `5,776,365` LUT, `7,398,300` FF.
- `handshake_buffer_in_f32_out_f32_2slots_seq`:
  `50,929` instances, `5,449,403` LUT, `6,722,628` FF.
- The copied all-memory baseline delta is still unchanged:
  `+16,482,923` LUT and `+424,183` FF for `top34-memory`.

Interpretation:

- The negative baseline is stronger than the earlier owner list suggested:
  the external-memory shell is dominated by repeated two-slot handshake buffers
  and mux/index fabric, not only by a few large residual memory modules.
- This supports the redirection decision:
  external memory remains useful only when paired with streaming/tiled engines
  that avoid reconstructing the full lowered handshake shell.

Immediate execution queue:

1. `H1`: score a streaming/tiled GEMV memory contract before any DDR3 work.
   Required first artifact: cycles/token, bytes/token, external weight bytes,
   and `DSP > 0` on the existing `L2` tiled surface or a smaller synthetic
   derivative.
2. `H2`: add int8/int4 packed-weight GEMV candidates only on bounded kernels.
   Required first artifact: Verilator pass, bounded numeric error, and either
   `<15k` LUT on `L2` scale or at least `2x` LUT reduction versus the current
   `31,907` LUT `L2` reference.
3. `H3`: replace the `L2` tiled wrapper's handshake-heavy sequencing with a
   static counter/FSM proof. Required first artifact: Verilator pass and mapped
   LUT below the current `31,907` LUT reference.
4. `H5`: compute model/rung byte budgets before larger replays. Required first
   artifact: weight bytes, activation bytes, and minimum bandwidth for the
   reduced-vocab, representative-core, and any proposed staged TinyStories
   rungs.

Stop rule:

- Do not spend another full-model `topN-memory` mapped run unless one of the
  bounded lanes above first predicts an order-of-magnitude fabric reduction or
  eliminates the repeated two-slot buffer class from the top-owner list.

### 2026-04-28 - H5 first byte-budget artifact from existing weight packs

Artifact:

- `artifacts/task6/parallel-hypotheses/h5-rung-byte-budgets.csv`

Inputs:

- `artifacts/task6/weights_pack/tiny-stories-1m-representative-core-v64-h4/transformer.h.0.mlp.c_fc/manifest.json`
- `artifacts/task6/weights_pack/tiny-stories-1m-representative-core-v64-h4/transformer.h.0.mlp.c_proj/manifest.json`
- `artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_fc/manifest.json`
- `artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_proj/manifest.json`

Assumption:

- This is a minimum sequential traffic estimate for the MLP weights if weights
  are streamed once per token and activations/bias remain `f32`.
- It does not include tokenizer, embeddings, attention, layernorm, activation
  approximation, DDR burst overhead, or cache reuse.

Observed budgets:

- `tiny-stories-1m-representative-core-v64-h4` full MLP stack:
  - f32 weights: `1,504` bytes/token
  - int8 weights with f32 activations/bias: `736` bytes/token
  - int4 weights with f32 activations/bias: `608` bytes/token
- `tiny-stories-v1k-h64-l1` full MLP stack:
  - f32 weights: `134,912` bytes/token
  - int8 weights with f32 activations/bias: `36,608` bytes/token
  - int4 weights with f32 activations/bias: `20,224` bytes/token

Interpretation:

- The `v1k-h64-l1` MLP is the first useful H1/H2 bandwidth surface:
  it is small enough to reason about by inspection but large enough that f32
  weight streaming is already about `132 KiB` per token for the MLP alone.
- The immediate H2 value is concrete:
  int8 packed weights cut the `v1k-h64-l1` MLP traffic estimate by about `3.7x`,
  and int4 packed weights cut it by about `6.7x`, before any activation or
  sequencer savings.

### 2026-04-28 - H1/H2 streaming-contract score artifact

Artifact:

- `artifacts/task6/parallel-hypotheses/h1-h2-streaming-contract-score.csv`
- `artifacts/task6/parallel-hypotheses/h1-h2-streaming-contract-score.json`

Script:

- `scripts/task6/score_streaming_contract.py`

Command:

- `python3 scripts/task6/score_streaming_contract.py --manifest artifacts/task6/weights_pack/tiny-stories-1m-representative-core-v64-h4/transformer.h.0.mlp.c_fc/manifest.json --manifest artifacts/task6/weights_pack/tiny-stories-1m-representative-core-v64-h4/transformer.h.0.mlp.c_proj/manifest.json --manifest artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_fc/manifest.json --manifest artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_proj/manifest.json --dsp-lanes 4 --out-csv artifacts/task6/parallel-hypotheses/h1-h2-streaming-contract-score.csv --out-json artifacts/task6/parallel-hypotheses/h1-h2-streaming-contract-score.json`

Assumption:

- `dsp_lanes = 4`, matching the current mapped `L1`/`L2` references.
- Cycle estimates are hard lower bounds: `ceil(MACs / dsp_lanes)`.
- Byte estimates count streamed weights once per token plus f32 bias,
  activation input, and activation output. They exclude burst overhead,
  attention, layernorm, activation approximation, and any cache reuse.

Key rows:

- `tiny-stories-v1k-h64-l1` full MLP stack:
  - `32,768` MACs/token
  - `8,192` minimum compute cycles/token at `4` DSP lanes
  - `134,912` f32 bytes/token
  - `36,608` bytes/token with int8 weights and f32 activations/bias
  - `20,224` bytes/token with int4 weights and f32 activations/bias
  - `16.47` f32 bytes/cycle, `4.47` int8-weight bytes/cycle,
    `2.47` int4-weight bytes/cycle
- `tiny-stories-1m-representative-core-v64-h4` full MLP stack:
  - `256` MACs/token
  - `64` minimum compute cycles/token at `4` DSP lanes
  - `1,504` f32 bytes/token
  - `736` bytes/token with int8 weights and f32 activations/bias
  - `608` bytes/token with int4 weights and f32 activations/bias

Interpretation:

- H1 is viable as a memory-contract lane only if the implementation avoids the
  full lowered handshake shell. The corrected `top34-memory` owner list shows
  the shell cost is repeated two-slot buffers, while this score shows the
  sequential MLP traffic itself is small enough to model cheaply on `v1k-h64-l1`.
- H2 has a measurable bandwidth payoff before RTL work:
  int8 weights reduce the `v1k-h64-l1` MLP traffic from about `132 KiB/token`
  to about `36 KiB/token`, and int4 reduces it to about `20 KiB/token`.
- This does not yet prove a mapped LUT reduction. The next H2 implementation
  should be a bounded packed-weight GEMV kernel, not another full-model
  quantized lowering route.

Next action:

- Use the generated H1/H2 score as the acceptance target for the next bounded
  implementation:
  - H1 static/streaming GEMV should preserve `4 DSP` and keep memory traffic
    close to the `v1k-h64-l1` score rows.
  - H2 packed int8/int4 GEMV should prove functional error bounds and mapped
    resource reduction on a small kernel before any `L3` or whole-model replay.

### 2026-04-28 - H3 wrapper inspection narrows the static-sequencer target

Artifact:

- `artifacts/task6/parallel-hypotheses/h3-static-wrapper-inspection.json`

Inspected source:

- `rtl/task6/task6_l2_c_fc_tile4x64_main.sv`

Observation:

- The `L2` tiled wrapper is already a static phase sequencer:
  - `active_q`
  - `phase_q`
  - `launch_pending_q`
- It reuses one `task6_l2_c_fc_tile64_kernel` over four output phases.
- It forms the upper weight address and output store address bits from
  `phase_q`.
- It auto-acks tile output for phases `0..2` and only exposes `out0_valid` on
  phase `3`.

Prior mapped evidence:

- untouched tile64 kernel: `32,478` LUT
- untouched tile4x64 wrapper: `32,460` LUT
- postbranch tile64 kernel: `31,968` LUT
- postbranch tile4x64 wrapper: `31,907` LUT

Decision:

- H3 should not spend its next slice replacing the outer tiled wrapper.
- The wrapper is already static and has negligible mapped cost relative to the
  tile kernel.
- The real H3 target is now narrower:
  build or sketch a bounded static `64x64` tile-kernel proof that removes the
  generated handshake buffers/forks/muxes inside the kernel while preserving
  the existing activation/weight/store contract.

### 2026-04-28 - H2 quantized-weight contract replay

Artifact:

- `artifacts/task6/parallel-hypotheses/h2-quantized-weight-replay.csv`
- `artifacts/task6/parallel-hypotheses/h2-quantized-weight-replay.json`

Script:

- `scripts/task6/score_quantized_weight_replay.py`

Command:

- `python3 scripts/task6/score_quantized_weight_replay.py --case l1-c_fc=artifacts/task6/streamtensor-lite/l1/representative-core-v64-h4-c_fc-contract/manifest.json=artifacts/task6/weights_pack/tiny-stories-1m-representative-core-v64-h4/transformer.h.0.mlp.c_fc/manifest.json --case l1-c_proj=artifacts/task6/streamtensor-lite/l1/representative-core-v64-h4-c_proj-contract/manifest.json=artifacts/task6/weights_pack/tiny-stories-1m-representative-core-v64-h4/transformer.h.0.mlp.c_proj/manifest.json --case l2-c_fc=artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_fc-contract/manifest.json=artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_fc/manifest.json --case l2-c_proj=artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_proj-contract/manifest.json=artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_proj/manifest.json --normalized-rmse-threshold 0.02 --out-csv artifacts/task6/parallel-hypotheses/h2-quantized-weight-replay.csv --out-json artifacts/task6/parallel-hypotheses/h2-quantized-weight-replay.json`

Method:

- Replay captured `activation_in @ dequantized(weight).T + bias` contracts.
- Test symmetric int8 and int4 weights with:
  - one per-tensor scale
  - per-output-channel scales
- Keep activations and bias in `f32`.
- Use `normalized_rmse <= 0.02` as the first bounded pass/fail threshold.

Result:

- int8 passes all four captured contracts:
  - `L1 c_fc`: per-tensor `0.00674`, per-output `0.00278`
  - `L1 c_proj`: per-tensor `0.00608`, per-output `0.00658`
  - `L2 c_fc`: per-tensor `0.00991`, per-output `0.00656`
  - `L2 c_proj`: per-tensor `0.00881`, per-output `0.00663`
- int4 fails all four captured contracts even with per-output scales:
  - `L1 c_fc`: best `0.05647`
  - `L1 c_proj`: best `0.12575`
  - `L2 c_fc`: best `0.12264`
  - `L2 c_proj`: best `0.11153`

Decision:

- Keep int8 as the active H2 packed-weight RTL candidate.
- Do not spend RTL implementation time on this simple int4 scheme.
- Reopen int4 only if a different bounded quantization scheme is proposed,
  such as group-wise scaling, mixed precision, or activation-aware calibration.

Next action:

- Build the smallest int8 packed-weight GEMV proof that can be compared against
  the current `4 DSP` L0/L1/L2 references.
- The first RTL gate should prove:
  - functional replay against the captured contract
  - `DSP > 0`
  - mapped LUT below the current float L0/L2 kernel class, or a clear reason
    why dequantization must move outside the kernel.

### 2026-04-28 - H2 bounded int8 GEMV RTL proof surface prepared

Artifact:

- `artifacts/task6/parallel-hypotheses/h2-int8-gemv64-rtl-proof.json`

Sources:

- `flake.nix`
- `rtl/task6/task6_int8_gemv64_kernel.sv`
- `sim/task6_int8_gemv64_tb_main.sv`
- `sim/gen_task6_int8_gemv64_tb_data.py`

Command:

- `python3 sim/gen_task6_int8_gemv64_tb_data.py --out-json artifacts/task6/parallel-hypotheses/h2-int8-gemv64-rtl-proof.json`
- `nix build .#task6-int8-gemv64-sv-sim --no-link --print-out-paths -L`
- `python3 sim/gen_task6_int8_gemv64_tb_data.py --sim-result-json /nix/store/alwiq620fdhryhhz9kxhdfg5f3p955wr-task6-int8-gemv64-sv-sim.json --out-json artifacts/task6/parallel-hypotheses/h2-int8-gemv64-rtl-proof.json`
- `nix build .#task6-int8-gemv64-yosys-stat --no-link --print-out-paths -L`
- `python3 sim/gen_task6_int8_gemv64_tb_data.py --sim-result-json /nix/store/alwiq620fdhryhhz9kxhdfg5f3p955wr-task6-int8-gemv64-sv-sim.json --yosys-stat-json /nix/store/2p1gl2hpfw0q1shbnpbyv4avrwjs87gh-task6-int8-gemv64-yosys-stat.json --out-json artifacts/task6/parallel-hypotheses/h2-int8-gemv64-rtl-proof.json`
- `nix build .#task6-int8-gemv64-utilization --no-link --print-out-paths -L`
- `python3 sim/gen_task6_int8_gemv64_tb_data.py --sim-result-json /nix/store/alwiq620fdhryhhz9kxhdfg5f3p955wr-task6-int8-gemv64-sv-sim.json --yosys-stat-json /nix/store/2p1gl2hpfw0q1shbnpbyv4avrwjs87gh-task6-int8-gemv64-yosys-stat.json --mapped-utilization-summary-json /nix/store/lwizcdpbhh36ah4fafa0zgvbv8n3zs4a-task6-int8-gemv64-utilization/summary.json --out-json artifacts/task6/parallel-hypotheses/h2-int8-gemv64-rtl-proof.json`

Prepared contract:

- `64 x 64` GEMV
- signed int8 activations
- signed int8 weights
- signed int32 accumulation
- `4,096` MACs
- combinational address/data activation and weight memories
- ready/valid output stream

Deterministic vector summary:

- activation SHA256: `9d8e95167716149b582c1e8f772e5b312655bc79adf990872b9ecc46ce150174`
- weight SHA256: `498ae3ff71f98690cd4ec3aafa2d70f6adc5600f869cac426dad14e091ff7fa9`
- expected-output SHA256: `7bd0a431ea01f3cd043896562031b5792ecce0f35f3850f0dc0ff271f77abed8`
- expected output range: `-1164..1688`

Execution status:

- RTL source and self-checking testbench are prepared.
- Flake target `.#task6-int8-gemv64-sv-sim` is wired.
- `python3 -m py_compile sim/gen_task6_int8_gemv64_tb_data.py` passes.
- The JSON artifact validates with `python3 -m json.tool`.
- The RTL simulation passes through Nix-provided Verilator:
  - output: `/nix/store/alwiq620fdhryhhz9kxhdfg5f3p955wr-task6-int8-gemv64-sv-sim.json`
  - pass line: `PASS: task6 int8 GEMV stores 64 outputs 64 cycles 4162`
- The light Yosys gate passes through Nix-provided `pkgs.yosys`:
  - output: `/nix/store/2p1gl2hpfw0q1shbnpbyv4avrwjs87gh-task6-int8-gemv64-yosys-stat.json`
  - `DSP48E1`: `1`
  - LUT primitive cells: `68` (`LUT2=42`, `LUT3=1`, `LUT4=1`,
    `LUT5=2`, `LUT6=22`)
  - `FDRE`: `66`
  - `CARRY4`: `7`
  - Yosys log estimated LCs: `46`
- The mapped JSON utilization gate passes through the existing utilization
  reporter:
  - output: `/nix/store/lwizcdpbhh36ah4fafa0zgvbv8n3zs4a-task6-int8-gemv64-utilization`
  - `clb_luts`: `68`
  - `clb_ffs`: `66`
  - `dsp`: `1`
  - `bram36_equiv`: `0`
  - `slices_lower_bound`: `9`

Interpretation:

- This answers the immediate "do we have an int8 RTL surface?" question with
  "yes, a bounded fixed-point int8 kernel now passes Verilator and maps one
  DSP48E1 under light `synth_xilinx`, with a durable mapped utilization row."
- It is deliberately narrower than the earlier H2 numeric replay:
  the replay kept activations and bias in `f32`, while this bounded RTL proof is
  a fixed-point int8-activation/int8-weight kernel with int32 accumulation.
- It avoids the older torch-mlir byte/char int8 route that blocked the prior
  local `task6-l0-gemv64-int8` probe.
- H2 stays active. The next required evidence is a scaled bounded variant:
  either multiple DSP lanes sharing the same controller, or a small tiled
  `L2`-shape wrapper that proves the low standalone LUT count survives the
  interface and sequencing needed by a real MLP slice.

### 2026-04-28 - H2 bounded int8 GEMV four-lane RTL proof

Artifact:

- `artifacts/task6/parallel-hypotheses/h2-int8-gemv64-lanes4-rtl-proof.json`

Sources:

- `flake.nix`
- `rtl/task6/task6_int8_gemv64_lanes4_kernel.sv`
- `sim/task6_int8_gemv64_lanes4_tb_main.sv`
- `sim/gen_task6_int8_gemv64_tb_data.py`

Command:

- `nix build .#task6-int8-gemv64-lanes4-sv-sim --no-link --print-out-paths -L`
- `nix build .#task6-int8-gemv64-lanes4-yosys-stat --no-link --print-out-paths -L`
- `nix build .#task6-int8-gemv64-lanes4-utilization --no-link --print-out-paths -L`
- `python3 sim/gen_task6_int8_gemv64_tb_data.py --artifact-name h2-int8-gemv64-lanes4-rtl-proof --kernel-source rtl/task6/task6_int8_gemv64_lanes4_kernel.sv --testbench-source sim/task6_int8_gemv64_lanes4_tb_main.sv --top-name task6_int8_gemv64_lanes4_kernel --lane-count 4 --nix-target-prefix task6-int8-gemv64-lanes4 --sim-result-json /nix/store/z1fdggakr9xbd5wb5l3iyxknbvkc902a-task6-int8-gemv64-lanes4-sv-sim.json --yosys-stat-json /nix/store/pcj9qnir5n61zvfnqd9j1pw9yis8fh01-task6-int8-gemv64-lanes4-yosys-stat.json --mapped-utilization-summary-json /nix/store/1020khq23md4gdl7kscx7b9p3kxiy0qm-task6-int8-gemv64-lanes4-utilization/summary.json --out-json artifacts/task6/parallel-hypotheses/h2-int8-gemv64-lanes4-rtl-proof.json`

Prepared contract:

- `64 x 64` GEMV
- signed int8 activations
- signed int8 weights
- signed int32 accumulation
- `4,096` MACs
- `4` parallel output/MAC lanes sharing one controller
- `16` output tiles
- combinational address/data activation and packed-lane weight memories
- ready/valid output stream

Execution status:

- The RTL simulation passes through Nix-provided Verilator:
  - output: `/nix/store/z1fdggakr9xbd5wb5l3iyxknbvkc902a-task6-int8-gemv64-lanes4-sv-sim.json`
  - pass line: `PASS: task6 int8 GEMV4 stores 64 outputs 64 cycles 1090`
- The light Yosys gate passes through Nix-provided `pkgs.yosys`:
  - output: `/nix/store/pcj9qnir5n61zvfnqd9j1pw9yis8fh01-task6-int8-gemv64-lanes4-yosys-stat.json`
  - `DSP48E1`: `4`
  - LUT primitive cells: `242` (`LUT2=149`, `LUT3=39`, `LUT4=1`,
    `LUT5=11`, `LUT6=42`)
  - `FDRE`: `187`
  - `CARRY4`: `18`
  - Yosys log estimated LCs: `148`
- The mapped JSON utilization gate passes through the existing utilization
  reporter:
  - output: `/nix/store/1020khq23md4gdl7kscx7b9p3kxiy0qm-task6-int8-gemv64-lanes4-utilization`
  - `clb_luts`: `242`
  - `clb_ffs`: `187`
  - `dsp`: `4`
  - `bram36_equiv`: `0`
  - `slices_lower_bound`: `31`

Interpretation:

- The four-lane proof keeps the same fixed-point int8/int8/int32 contract as
  the single-lane proof, but proves the controller can feed and retire four
  parallel DSP MAC lanes.
- Compared with the single-lane proof, simulation cycles improve from `4162`
  to `1090`, while mapped DSP usage scales linearly from `1` to `4`.
- Mapped LUTs rise from `68` to `242` and FFs rise from `66` to `187`, so the
  widened datapath does not create the kind of control/interface explosion
  seen in the float baseline lanes.
- H2 remains the strongest local resource-reduction lane. The next evidence
  should attach this four-lane fixed-point datapath to a small explicit
  packed-weight memory or an `L2`-shape tile wrapper before extrapolating to
  the full MLP shell.

### 2026-04-28 - H2 four-lane int8 packed-weight interface proof

Artifact:

- `artifacts/task6/parallel-hypotheses/h2-int8-gemv64-lanes4-packed-rtl-proof.json`

Sources:

- `flake.nix`
- `rtl/task6/task6_int8_gemv64_lanes4_packed_kernel.sv`
- `sim/task6_int8_gemv64_lanes4_packed_tb_main.sv`
- `sim/gen_task6_int8_gemv64_tb_data.py`

Command:

- `nix build .#task6-int8-gemv64-lanes4-packed-sv-sim --no-link --print-out-paths -L`
- `nix build .#task6-int8-gemv64-lanes4-packed-yosys-stat --no-link --print-out-paths -L`
- `nix build .#task6-int8-gemv64-lanes4-packed-utilization --no-link --print-out-paths -L`
- `python3 sim/gen_task6_int8_gemv64_tb_data.py --artifact-name h2-int8-gemv64-lanes4-packed-rtl-proof --kernel-source rtl/task6/task6_int8_gemv64_lanes4_packed_kernel.sv --testbench-source sim/task6_int8_gemv64_lanes4_packed_tb_main.sv --top-name task6_int8_gemv64_lanes4_packed_kernel --lane-count 4 --packed-weight-words 1024 --nix-target-prefix task6-int8-gemv64-lanes4-packed --sim-result-json /nix/store/0q6r90sdfd4jgksdwf5sfixnrj3dap59-task6-int8-gemv64-lanes4-packed-sv-sim.json --yosys-stat-json /nix/store/f8500lrc4gn6k8wnswlv2n6k5lizsaia-task6-int8-gemv64-lanes4-packed-yosys-stat.json --mapped-utilization-summary-json /nix/store/sh60mam9pc36p3mh5w2wsiznbd56434b-task6-int8-gemv64-lanes4-packed-utilization/summary.json --out-json artifacts/task6/parallel-hypotheses/h2-int8-gemv64-lanes4-packed-rtl-proof.json`

Prepared contract:

- `64 x 64` GEMV
- signed int8 activations
- signed int8 weights
- signed int32 accumulation
- `4,096` MACs
- `4` parallel output/MAC lanes sharing one controller
- `1,024` packed weight words, each carrying one `4`-lane int8 weight vector
- one packed weight address/data port per activation step
- ready/valid output stream

Execution status:

- The RTL simulation passes through Nix-provided Verilator:
  - output: `/nix/store/0q6r90sdfd4jgksdwf5sfixnrj3dap59-task6-int8-gemv64-lanes4-packed-sv-sim.json`
  - pass line: `PASS: task6 int8 GEMV4 packed stores 64 outputs 64 cycles 1090`
- The light Yosys gate passes through Nix-provided `pkgs.yosys`:
  - output: `/nix/store/f8500lrc4gn6k8wnswlv2n6k5lizsaia-task6-int8-gemv64-lanes4-packed-yosys-stat.json`
  - `DSP48E1`: `4`
  - LUT primitive cells: `242` (`LUT2=149`, `LUT3=39`, `LUT4=1`,
    `LUT5=11`, `LUT6=42`)
  - `FDRE`: `187`
  - `CARRY4`: `9`
  - Yosys log estimated LCs: `148`
- The mapped JSON utilization gate passes through the existing utilization
  reporter:
  - output: `/nix/store/sh60mam9pc36p3mh5w2wsiznbd56434b-task6-int8-gemv64-lanes4-packed-utilization`
  - `clb_luts`: `242`
  - `clb_ffs`: `187`
  - `dsp`: `4`
  - `bram36_equiv`: `0`
  - `slices_lower_bound`: `31`

Interpretation:

- The packed interface proof preserves the four-lane fixed-point datapath and
  throughput from the previous H2 proof while replacing four independent
  weight addresses with one packed-word address.
- Compared with the unpacked four-lane proof, mapped LUTs, FFs, DSPs, and
  lower-bound slices remain unchanged (`242`, `187`, `4`, and `31`), while
  `CARRY4` cells drop from `18` to `9` and public wire bits drop from `629` to
  `587`.
- This is still a kernel/interface proof, not a full local-memory proof: the
  weights are supplied through a combinational packed data port rather than an
  inferred or explicit BRAM.
- The next H2 gate should add an explicit small packed-weight memory boundary
  or an `L2`-shape tile wrapper around this packed interface, so the memory
  read latency and storage mapping are represented before scaling further.

### 2026-04-28 - H2 four-lane int8 packed-weight sync-memory proof

Artifact:

- `artifacts/task6/parallel-hypotheses/h2-int8-gemv64-lanes4-packed-sync-mem-rtl-proof.json`

Sources:

- `flake.nix`
- `rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv`
- `rtl/task6/task6_int8_gemv64_lanes4_packed_sync_mem_kernel.sv`
- `sim/task6_int8_gemv64_lanes4_packed_sync_mem_tb_main.sv`
- `sim/gen_task6_int8_gemv64_tb_data.py`

Command:

- `nix build .#task6-int8-gemv64-lanes4-packed-sync-mem-sv-sim --no-link --print-out-paths -L`
- `nix build .#task6-int8-gemv64-lanes4-packed-sync-mem-yosys-stat --no-link --print-out-paths -L`
- `nix build .#task6-int8-gemv64-lanes4-packed-sync-mem-utilization --no-link --print-out-paths -L`
- `python3 sim/gen_task6_int8_gemv64_tb_data.py --artifact-name h2-int8-gemv64-lanes4-packed-sync-mem-rtl-proof --extra-kernel-source rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv --kernel-source rtl/task6/task6_int8_gemv64_lanes4_packed_sync_mem_kernel.sv --testbench-source sim/task6_int8_gemv64_lanes4_packed_sync_mem_tb_main.sv --top-name task6_int8_gemv64_lanes4_packed_sync_mem_kernel --lane-count 4 --packed-weight-words 1024 --local-packed-weight-memory --packed-weight-read-latency-cycles 1 --nix-target-prefix task6-int8-gemv64-lanes4-packed-sync-mem --sim-result-json /nix/store/54q4wq3182nhmvkf6sfrk6rvabz779a6-task6-int8-gemv64-lanes4-packed-sync-mem-sv-sim.json --yosys-stat-json /nix/store/lx8jdyxh3ckph7p6qn0y7zn4pxxrlx2y-task6-int8-gemv64-lanes4-packed-sync-mem-yosys-stat.json --mapped-utilization-summary-json /nix/store/y62fmdqmhj5ls485qanksvrqn6fhq7gn-task6-int8-gemv64-lanes4-packed-sync-mem-utilization/summary.json --out-json artifacts/task6/parallel-hypotheses/h2-int8-gemv64-lanes4-packed-sync-mem-rtl-proof.json`

Prepared contract:

- `64 x 64` GEMV
- signed int8 activations
- signed int8 weights
- signed int32 accumulation
- `4,096` MACs
- `4` parallel output/MAC lanes sharing one controller
- `1,024` packed weight words, each carrying one `4`-lane int8 weight vector
- loadable synchronous local packed-weight memory
- one-cycle packed-weight read latency
- ready/valid output stream

Execution status:

- The RTL simulation passes through Nix-provided Verilator:
  - output: `/nix/store/54q4wq3182nhmvkf6sfrk6rvabz779a6-task6-int8-gemv64-lanes4-packed-sync-mem-sv-sim.json`
  - pass line: `PASS: task6 int8 GEMV4 syncmem stores 64 outputs 64 cycles 1106`
- The light Yosys gate passes through Nix-provided `pkgs.yosys`:
  - output: `/nix/store/lx8jdyxh3ckph7p6qn0y7zn4pxxrlx2y-task6-int8-gemv64-lanes4-packed-sync-mem-yosys-stat.json`
  - `DSP48E1`: `4`
  - `RAMB36E1`: `1`
  - LUT primitive cells: `250` (`LUT2=160`, `LUT3=41`, `LUT4=2`,
    `LUT5=6`, `LUT6=41`)
  - `FDRE`: `193`
  - `CARRY4`: `11`
  - Yosys log estimated LCs: `149`
- The mapped JSON utilization gate passes through the existing utilization
  reporter:
  - output: `/nix/store/y62fmdqmhj5ls485qanksvrqn6fhq7gn-task6-int8-gemv64-lanes4-packed-sync-mem-utilization`
  - `clb_luts`: `250`
  - `clb_ffs`: `193`
  - `dsp`: `4`
  - `bram36`: `1`
  - `bram36_equiv`: `1.0`
  - `bram_kb`: `36`
  - `slices_lower_bound`: `32`

Interpretation:

- This is the first H2 proof that crosses from a combinational packed-weight
  interface into an explicit loadable local memory boundary.
- Yosys infers one `RAMB36E1` for the `1024 x 32` packed-weight store, so the
  proof now exercises BRAM as well as the four DSP MAC lanes.
- Compared with the prior packed combinational proof, the memory boundary costs
  only `+8` LUT, `+6` FF, and `+1` slice lower bound while adding one BRAM36
  and increasing simulation from `1090` to `1106` cycles.
- H2 remains active. The next useful gate is either an `L2`-shape tile wrapper
  around this sync-memory interface or a direct resource comparison for the
  activation/output memory boundary on the same int8 datapath.

### 2026-04-28 - H2 L2-shaped int8 64x256 sync-memory wrapper proof

Artifact:

- `artifacts/task6/parallel-hypotheses/h2-int8-gemv64x256-lanes4-packed-sync-mem-rtl-proof.json`

Sources:

- `flake.nix`
- `rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv`
- `rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel.sv`
- `sim/task6_int8_gemv64x256_lanes4_packed_sync_mem_tb_main.sv`
- `sim/gen_task6_int8_gemv64_tb_data.py`

Command:

- `nix build .#task6-int8-gemv64x256-lanes4-packed-sync-mem-sv-sim --no-link --print-out-paths -L`
- `nix build .#task6-int8-gemv64x256-lanes4-packed-sync-mem-yosys-stat --no-link --print-out-paths -L`
- `nix build .#task6-int8-gemv64x256-lanes4-packed-sync-mem-utilization --no-link --print-out-paths -L`
- `python3 sim/gen_task6_int8_gemv64_tb_data.py --artifact-name h2-int8-gemv64x256-lanes4-packed-sync-mem-rtl-proof --extra-kernel-source rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv --kernel-source rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel.sv --testbench-source sim/task6_int8_gemv64x256_lanes4_packed_sync_mem_tb_main.sv --top-name task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel --in-dim 64 --out-dim 256 --lane-count 4 --packed-weight-words 4096 --local-packed-weight-memory --packed-weight-read-latency-cycles 1 --nix-target-prefix task6-int8-gemv64x256-lanes4-packed-sync-mem --sim-result-json /nix/store/3c3hfxjp9hrg7ljkmkvbb44l4dg7x4sj-task6-int8-gemv64x256-lanes4-packed-sync-mem-sv-sim.json --yosys-stat-json /nix/store/xhl71pr1kxxx2x4a045686l6p002yciv-task6-int8-gemv64x256-lanes4-packed-sync-mem-yosys-stat.json --mapped-utilization-summary-json /nix/store/nk7x17kryxq1wkrh06kb5dqnw6pdr5y6-task6-int8-gemv64x256-lanes4-packed-sync-mem-utilization/summary.json --out-json artifacts/task6/parallel-hypotheses/h2-int8-gemv64x256-lanes4-packed-sync-mem-rtl-proof.json`

Prepared contract:

- `64 x 256` GEMV as four sequential `64 x 64` output phases
- signed int8 activations
- signed int8 weights
- signed int32 accumulation
- `16,384` MACs
- `4` parallel output/MAC lanes in the reused tile core
- `4,096` packed weight words, each carrying one `4`-lane int8 weight vector
- loadable synchronous local packed-weight memory
- one-cycle packed-weight read latency
- ready/valid output stream

Execution status:

- The RTL simulation passes through Nix-provided Verilator:
  - output: `/nix/store/3c3hfxjp9hrg7ljkmkvbb44l4dg7x4sj-task6-int8-gemv64x256-lanes4-packed-sync-mem-sv-sim.json`
  - pass line: `PASS: task6 int8 GEMV4x256 syncmem stores 256 outputs 256 cycles 4426`
- The light Yosys gate passes through Nix-provided `pkgs.yosys`:
  - output: `/nix/store/xhl71pr1kxxx2x4a045686l6p002yciv-task6-int8-gemv64x256-lanes4-packed-sync-mem-yosys-stat.json`
  - `DSP48E1`: `4`
  - `RAMB36E1`: `4`
  - LUT primitive cells: `257` (`LUT2=165`, `LUT3=40`, `LUT4=5`,
    `LUT5=8`, `LUT6=39`)
  - `FDRE`: `198`
  - `CARRY4`: `11`
  - Yosys log estimated LCs: `152`
- The mapped JSON utilization gate passes through the existing utilization
  reporter:
  - output: `/nix/store/nk7x17kryxq1wkrh06kb5dqnw6pdr5y6-task6-int8-gemv64x256-lanes4-packed-sync-mem-utilization`
  - `clb_luts`: `257`
  - `clb_ffs`: `198`
  - `dsp`: `4`
  - `bram36`: `4`
  - `bram36_equiv`: `4.0`
  - `bram_kb`: `144`
  - `slices_lower_bound`: `33`

Regression checks:

- `python3 -m py_compile sim/gen_task6_int8_gemv64_tb_data.py`
- `nix-instantiate --parse flake.nix`
- Existing int8 proof artifacts regenerated byte-for-byte after adding
  `--in-dim` and `--out-dim` generator parameters:
  - `h2-int8-gemv64-rtl-proof.json`
  - `h2-int8-gemv64-lanes4-rtl-proof.json`
  - `h2-int8-gemv64-lanes4-packed-rtl-proof.json`
  - `h2-int8-gemv64-lanes4-packed-sync-mem-rtl-proof.json`

Interpretation:

- This answers the previous H2 gate directly: the explicit sync-memory int8
  datapath survives the first `L2`-shaped `64 -> 256` output wrapper.
- Compared with the prior `64 x 64` sync-memory proof, the wrapper keeps the
  same `4` DSP MAC lane footprint and scales packed weight storage from one to
  four `RAMB36E1` blocks.
- The control/output wrapper adds only `+7` mapped LUT, `+5` FF, and `+1`
  slice lower bound versus the `64 x 64` sync-memory proof; `CARRY4` is
  unchanged.
- Runtime is near-linear: `4426` cycles versus `4 * 1106 = 4424` for four
  independent tile runs.
- H2 remains the strongest concrete resource-reduction lane. The next useful
  gate is to add the activation/output memory boundary for this int8 datapath
  or replay the same shape against a captured `c_fc` numeric contract.

### 2026-04-28 - H2 L2-shaped int8 local activation/output memory proof

Artifact:

- `artifacts/task6/parallel-hypotheses/h2-int8-gemv64x256-lanes4-packed-sync-mem-local-io-rtl-proof.json`

Sources:

- `flake.nix`
- `rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv`
- `rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel.sv`
- `rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_local_io_kernel.sv`
- `sim/task6_int8_gemv64x256_lanes4_packed_sync_mem_local_io_tb_main.sv`
- `sim/gen_task6_int8_gemv64_tb_data.py`

Prepared contract:

- `64 x 256` GEMV as four sequential `64 x 64` output phases
- signed int8 activations and weights
- signed int32 accumulation and output storage
- `4` parallel output/MAC lanes in the reused tile core
- `4,096` loadable packed weight words
- `64` loadable activation bytes
- `256` captured int32 outputs behind a synchronous read port
- one-cycle packed-weight read latency
- one-cycle output-memory read latency

Execution status:

- The RTL simulation passes through Nix-provided Verilator:
  - output:
    `/nix/store/zhrnqzbjijr10y4xdv590g31wv0ifqnn-task6-int8-gemv64x256-lanes4-packed-sync-mem-local-io-sv-sim.json`
  - pass line:
    `PASS: task6 int8 GEMV4x256 localio reads 256 outputs 256 compute_cycles 4426 total_cycles 4682`
- The light Yosys gate passes through Nix-provided `pkgs.yosys`:
  - output:
    `/nix/store/s45pmvyb84j6ch8kynp2q0bkzz68yg0p-task6-int8-gemv64x256-lanes4-packed-sync-mem-local-io-yosys-stat.json`
  - `DSP48E1`: `4`
  - `RAMB36E1`: `4`
  - `RAMB18E1`: `1`
  - `RAM64M`: `3`
  - LUT primitive cells: `257` (`LUT2=165`, `LUT3=40`, `LUT4=5`,
    `LUT5=8`, `LUT6=39`)
  - `FDRE`: `198`
  - `CARRY4`: `11`
  - Yosys log estimated LCs: `152`
- The mapped JSON utilization gate passes through the existing utilization
  reporter:
  - output:
    `/nix/store/jkii8nbpgsd9jkxi3qzf253v99f8lxb9-task6-int8-gemv64x256-lanes4-packed-sync-mem-local-io-utilization`
  - `clb_luts`: `257`
  - `clb_ffs`: `198`
  - `dsp`: `4`
  - `bram36`: `4`
  - `bram36_equiv`: `4.5`
  - `bram_kb`: `162`
  - `slices_lower_bound`: `33`

Regression checks:

- `python3 -m py_compile sim/gen_task6_int8_gemv64_tb_data.py`
- `nix-instantiate --parse flake.nix`
- Existing int8 proof artifacts regenerated byte-for-byte after adding
  generator metadata for local activation/output memory:
  - `h2-int8-gemv64-rtl-proof.json`
  - `h2-int8-gemv64-lanes4-rtl-proof.json`
  - `h2-int8-gemv64-lanes4-packed-rtl-proof.json`
  - `h2-int8-gemv64-lanes4-packed-sync-mem-rtl-proof.json`
  - `h2-int8-gemv64x256-lanes4-packed-sync-mem-rtl-proof.json`

Interpretation:

- This crosses the activation/output memory boundary without increasing mapped
  LUTs, FFs, DSPs, or slice lower bound versus the prior `64 x 256`
  sync-memory wrapper.
- The added local output capture costs one `RAMB18E1`, raising memory from
  `4.0` to `4.5` BRAM36-equivalent blocks; the local activation memory maps to
  three `RAM64M` cells.
- Compute latency is unchanged at `4426` cycles; the `4682` total cycle count
  includes the synchronous readback of all `256` captured outputs.
- H2 remains the strongest concrete resource-reduction lane. The next useful
  gate is either to replay this shape against the captured `c_fc` numeric
  contract or to begin replacing the float `L2` wrapper boundary with this
  local-memory int8 contract.

### 2026-04-28 - H2 captured `L2 c_fc` int8 local-I/O contract replay

Artifact:

- `artifacts/task6/parallel-hypotheses/h2-int8-l2-c-fc-local-io-contract-replay.json`

Sources:

- `flake.nix`
- `sim/gen_task6_int8_l2_c_fc_contract_tb_data.py`
- `sim/task6_int8_l2_c_fc_contract_local_io_tb_main.sv`
- `rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv`
- `rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel.sv`
- `rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_local_io_kernel.sv`

Input artifacts:

- contract:
  `artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_fc-contract/manifest.json`
- weight pack:
  `artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_fc/manifest.json`
- generated testbench data:
  `/nix/store/n35ch4f4g660c4jajc6f6a3m07lbqp4d-task6-int8-l2-c-fc-contract-local-io-tb-data-sv`

Command:

- `nix build .#task6-int8-l2-c-fc-contract-local-io-sv-sim --no-link --print-out-paths -L`
- `python3 sim/gen_task6_int8_l2_c_fc_contract_tb_data.py --artifact-name h2-int8-l2-c-fc-local-io-contract-replay --contract-manifest artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_fc-contract/manifest.json --weight-pack-manifest artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_fc/manifest.json --sim-result-json /nix/store/p6swbg96jynrh9gzj300n86871dhyfvi-task6-int8-l2-c-fc-contract-local-io-sv-sim.json --yosys-stat-json /nix/store/s45pmvyb84j6ch8kynp2q0bkzz68yg0p-task6-int8-gemv64x256-lanes4-packed-sync-mem-local-io-yosys-stat.json --mapped-utilization-summary-json /nix/store/jkii8nbpgsd9jkxi3qzf253v99f8lxb9-task6-int8-gemv64x256-lanes4-packed-sync-mem-local-io-utilization/summary.json --out-json artifacts/task6/parallel-hypotheses/h2-int8-l2-c-fc-local-io-contract-replay.json`

Quantization contract:

- activation:
  - int8 per-tensor symmetric
  - scale: `0.01876247210765448`
  - quantized range: `-105..127`
- weight:
  - int8 per-output symmetric
  - scale range: `0.00026671916950406053..0.0005978438563234224`
  - quantized range: `-127..127`
- accumulator:
  - int32 raw RTL output
  - expected accumulator range: `-51239..54338`
- bias:
  - f32 bias is not inside the RTL
  - it is added during dequantized contract scoring

Execution status:

- Verilator contract replay passes:
  - output:
    `/nix/store/p6swbg96jynrh9gzj300n86871dhyfvi-task6-int8-l2-c-fc-contract-local-io-sv-sim.json`
  - pass line:
    `PASS: task6 int8 L2 c_fc localio reads 256 outputs 256 compute_cycles 4426 total_cycles 4682`
- Dequantized replay against captured `activation_out` passes the current
  threshold:
  - normalized RMSE: `0.008803690780475175`
  - threshold: `0.02`
  - max absolute error: `0.003402371872713701`
  - mean absolute error: `0.0009829674033341599`
  - RMSE: `0.0012404946345053037`
- Mapped resources reuse the proven local-I/O RTL shape:
  - `clb_luts`: `257`
  - `clb_ffs`: `198`
  - `dsp`: `4`
  - `bram36`: `4`
  - `bram18`: `1`
  - `bram36_equiv`: `4.5`
  - `bram_kb`: `162`
  - `slices_lower_bound`: `33`

Interpretation:

- This closes the previous H2 numeric gap: the local-memory int8 RTL is no
  longer only a synthetic-vector proof; it now replays the captured
  `tiny-stories-v1k-h64-l1` `transformer.h.0.mlp.c_fc` contract.
- The Verilator test checks the raw int32 accumulators exactly. The JSON
  artifact separately scores the dequantized output against the captured f32
  module output with f32 bias applied outside the RTL.
- The resource story does not change from the prior local-I/O proof because the
  same RTL shape is used; only the loaded activation and weight contents now
  come from the captured `L2 c_fc` contract.
- H2 remains the strongest concrete path. The next useful gate is to make the
  scale/bias/output boundary explicit around this int8 contract, then use that
  as the replacement candidate for the float `L2` wrapper boundary.

### 2026-04-28 - H2 explicit scale/bias/output boundary for `L2 c_fc`

Artifact:

- `artifacts/task6/parallel-hypotheses/h2-int8-l2-c-fc-scale-bias-output-boundary.json`

Script:

- `scripts/task6/score_int8_output_boundary.py`

Nix target:

- `task6-int8-l2-c-fc-scale-bias-output-boundary`
- output:
  `/nix/store/jv6845gszc5qgb601r6x43i4ih4lgzj2-task6-int8-l2-c-fc-scale-bias-output-boundary`

Command:

- `python3 scripts/task6/score_int8_output_boundary.py --contract-manifest artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_fc-contract/manifest.json --weight-pack-manifest artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_fc/manifest.json --contract-replay-json artifacts/task6/parallel-hypotheses/h2-int8-l2-c-fc-local-io-contract-replay.json --out-json artifacts/task6/parallel-hypotheses/h2-int8-l2-c-fc-scale-bias-output-boundary.json`
- `nix build .#task6-int8-l2-c-fc-scale-bias-output-boundary --no-link --print-out-paths -L`

Boundary contract:

- RTL output:
  - int32 accumulators in local output memory
- output formula:
  - `f32_out[i] = int32_acc[i] * effective_scale[i] + bias[i]`
- effective scale:
  - `activation_scale * per-output weight_scale`
- sidecar dtypes:
  - scale: `float32`
  - bias: `float32`
- output dtype:
  - `float32`
- postprocess operations:
  - `256` f32 multiplies
  - `256` f32 adds

Result:

- status: `PASS`
- normalized RMSE: `0.008803690780475175`
- threshold: `0.02`
- effective scale range:
  - `5.004310978396703e-06..1.1217028679000805e-05`
- accumulator range:
  - `-51239..54338`
- sidecar hashes:
  - effective scale SHA256:
    `7e70d09bd94b0a9fa02d6e8069efa2f96e0d96a7f12b4c3e2cd3d3b682a78b50`
  - bias SHA256:
    `5f70bf18a086007016e948b04aed3b82103a36bea41755b6cddfaf10ace3c6ef`

Byte budget:

- activation int8 bytes: `64`
- packed-weight local memory bytes: `16,384`
- accumulator output int32 bytes: `1,024`
- effective-scale f32 bytes: `1,024`
- bias f32 bytes: `1,024`
- dequantized output f32 bytes: `1,024`
- scale plus bias sidecar bytes: `2,048`
- postprocess read/write bytes:
  - `4,096`
  - accumulator read + scale read + bias read + f32 output write
- minimum external payload if sidecars are loaded once:
  - `18,496` bytes

Decision:

- The replacement candidate boundary is now explicit:
  - replace the float `L2 c_fc` GEMV body with the int8 local-memory
    accumulator contract plus a scale/bias f32 output boundary.
- This does not prove that f32 postprocess should be implemented in the same
  RTL kernel:
  - the f32 scale/bias stage needs a separate mapped-cost gate
  - an alternate int8-to-int8 downstream boundary may be cheaper if the next
    layer can accept a quantized activation contract.
- Next gate:
  - measure the scale/bias postprocess option or define an int8-to-int8
    downstream boundary before replacing the full float `L2` wrapper.

### 2026-04-28 - H2 int8-to-int8 downstream boundary plan for `L2 c_fc`

Plan amendment:

- Default next direction:
  - do not implement the f32 scale/bias postprocess in RTL first
  - first score whether the existing int8 `c_fc` proof can hand a quantized
    activation to the downstream path
- First gate:
  - score `c_fc int32 accumulator -> int8 activation` candidates against the
    captured `L2 c_fc` contract
  - include the immediate GELU implication, because the next consumer is not
    just raw `c_fc` output
- Candidate boundaries:
  - `pre_gelu_int8_activation`
  - `post_gelu_int8_activation`
- Continue rule:
  - if either candidate stays under normalized RMSE `0.02`, implement a
    bounded fixed-point requant/output-memory RTL proof
  - if both candidates fail, fall back to the explicit f32 scale/bias boundary
    recorded above

Artifact:

- `artifacts/task6/parallel-hypotheses/h2-int8-l2-c-fc-downstream-int8-boundary.json`

Script:

- `scripts/task6/score_int8_downstream_boundary.py`

Nix target:

- `task6-int8-l2-c-fc-downstream-int8-boundary`
- output:
  `/nix/store/vh5jr6pngp2x6xgmrpfid6gbimbvmqnx-task6-int8-l2-c-fc-downstream-int8-boundary`

Command:

- `python3 scripts/task6/score_int8_downstream_boundary.py --contract-manifest artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_fc-contract/manifest.json --weight-pack-manifest artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_fc/manifest.json --contract-replay-json artifacts/task6/parallel-hypotheses/h2-int8-l2-c-fc-local-io-contract-replay.json --out-json artifacts/task6/parallel-hypotheses/h2-int8-l2-c-fc-downstream-int8-boundary.json`
- `nix build .#task6-int8-l2-c-fc-downstream-int8-boundary --no-link --print-out-paths -L`

Execution result:

- status: `PASS`
- threshold: `0.02`
- output scale source:
  - single captured contract sample used as calibration reference
- calibration caveat:
  - a production activation scale still needs a calibration set before
    board-level claims

Candidate results:

- `pre_gelu_int8_activation`:
  - verdict: `pass`
  - output scale: `0.0030651141808727593`
  - output q range: `-127..126`
  - raw `c_fc` normalized RMSE: `0.010439723621125493`
  - downstream GELU normalized RMSE: `0.010411107180230455`
  - output payload: `256` int8 bytes plus one `4` byte scale
- `post_gelu_int8_activation`:
  - verdict: `pass`
  - output scale: `0.0019919775901474546`
  - output q range: `-68..127`
  - raw `c_fc` normalized RMSE before post-GELU requant:
    `0.008803690780475175`
  - downstream GELU normalized RMSE after post-GELU requant:
    `0.011913045139803343`
  - output payload: `256` int8 bytes plus one `4` byte scale

Byte-budget implication:

- f32 output bytes replaced: `1,024`
- int8 output write savings versus f32: `768` bytes per captured `c_fc` output
- this is smaller than the prior explicit f32 boundary, which required:
  - `1,024` int32 output bytes
  - `1,024` scale bytes
  - `1,024` bias bytes
  - `1,024` f32 output bytes
  - `4,096` bytes of postprocess read/write traffic

Decision:

- The recommended next boundary is `post_gelu_int8_activation`.
- H2 remains active.
- Next gate:
  - implement a bounded fixed-point requant/output-memory RTL proof for the
    recommended post-GELU int8 activation boundary
  - keep the f32 scale/bias boundary as the fallback if the fixed-point
    requant proof fails or if wider calibration invalidates the single-sample
    activation scale

### 2026-04-28 - H2 post-GELU int8 requant/output-memory RTL proof

Artifact:

- `artifacts/task6/parallel-hypotheses/h2-int8-l2-c-fc-post-gelu-requant-rtl-proof.json`

Sources:

- `flake.nix`
- `rtl/task6/task6_int8_l2_c_fc_post_gelu_requant_kernel.sv`
- `sim/task6_int8_l2_c_fc_post_gelu_requant_tb_main.sv`
- `sim/gen_task6_int8_l2_c_fc_post_gelu_requant_tb_data.py`

Nix targets:

- `task6-int8-l2-c-fc-post-gelu-requant-tb-data-sv`
- `task6-int8-l2-c-fc-post-gelu-requant-sv-sim`
- `task6-int8-l2-c-fc-post-gelu-requant-yosys-stat`
- `task6-int8-l2-c-fc-post-gelu-requant-utilization`
- `task6-int8-l2-c-fc-post-gelu-requant-rtl-proof`
- proof output:
  `/nix/store/r49371dw4wpxfg8n9kgljvqdjjs764p3-task6-int8-l2-c-fc-post-gelu-requant-rtl-proof`

Commands:

- `nix build .#task6-int8-l2-c-fc-post-gelu-requant-sv-sim --no-link --print-out-paths -L`
- `nix build .#task6-int8-l2-c-fc-post-gelu-requant-rtl-proof --no-link --print-out-paths -L`
- `python3 sim/gen_task6_int8_l2_c_fc_post_gelu_requant_tb_data.py --contract-manifest artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_fc-contract/manifest.json --weight-pack-manifest artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_fc/manifest.json --downstream-boundary-json artifacts/task6/parallel-hypotheses/h2-int8-l2-c-fc-downstream-int8-boundary.json --sim-result-json /nix/store/j724i985rk0ghnr7ignyiaawa2wahx5k-task6-int8-l2-c-fc-post-gelu-requant-sv-sim.json --yosys-stat-json /nix/store/yz0g979bl9ghfg5c82gk6k5vdlxclbyk-task6-int8-l2-c-fc-post-gelu-requant-yosys-stat.json --mapped-utilization-summary-json /nix/store/7z38qbssw76fyljf3zkisgn5p8vk878l-task6-int8-l2-c-fc-post-gelu-requant-utilization/summary.json --out-json artifacts/task6/parallel-hypotheses/h2-int8-l2-c-fc-post-gelu-requant-rtl-proof.json`

RTL contract:

- input:
  - the existing captured `L2 c_fc` int8 local-I/O contract
  - `64` int8 activation bytes
  - `4,096` packed int8 weight words
  - per-output fixed-point scale multiplier sidecar
  - per-output fixed-point bias sidecar
- postprocess:
  - `x_q = round_shift(acc * scale_mul, scale_shift) + bias_q`
  - `y_q = (x_q >> 1) + round_shift(gelu_quad_q * x_q * x_q, 2*x_frac)`
  - `q = saturate_i8(round_shift(y_q * output_requant_mult, output_requant_shift))`
- fixed-point constants:
  - `x_frac = 12`
  - `scale_shift = 24`
  - `gelu_quad_q = 1634`
  - `output_requant_shift = 16`
  - `output_requant_mult = 8032`
- GELU approximation:
  - bounded small-range quadratic: `0.5*x + 0.39894228*x*x`
  - valid for this proof's captured pre-GELU range:
    `-0.3890774397806243..0.38768501500220276`

Execution status:

- status: `PASS`
- Verilator:
  - output:
    `/nix/store/j724i985rk0ghnr7ignyiaawa2wahx5k-task6-int8-l2-c-fc-post-gelu-requant-sv-sim.json`
  - pass line:
    `PASS: task6 int8 L2 c_fc postgelu requant reads 256 outputs 256 compute_cycles 4939 total_cycles 5195`
- fixed-point post-GELU score:
  - normalized RMSE: `0.011991351771288544`
  - threshold: `0.02`
  - max absolute error: `0.0025458221821932497`
  - output q range: `-67..127`
  - output scale: `0.0019919775901474546`

Mapped resources:

- output:
  `/nix/store/7z38qbssw76fyljf3zkisgn5p8vk878l-task6-int8-l2-c-fc-post-gelu-requant-utilization`
- `clb_luts`: `653`
- `clb_ffs`: `217`
- `dsp`: `26`
- `bram36`: `4`
- `bram18`: `3`
- `bram36_equiv`: `5.5`
- `bram_kb`: `198`
- `slices_lower_bound`: `82`

Delta against the prior captured `L2 c_fc` int8 local-I/O proof:

- LUT: `257 -> 653` (`+396`)
- FF: `198 -> 217` (`+19`)
- DSP: `4 -> 26` (`+22`)
- BRAM36-equivalent: `4.5 -> 5.5` (`+1.0`)
- lower-bound slices: `33 -> 82` (`+49`)
- compute cycles: `4426 -> 4939` (`+513`)
- total cycles: `4682 -> 5195` (`+513`)

Byte-budget implication:

- output activation stays at `256` int8 bytes
- f32 output bytes replaced: `1,024`
- int8 output write savings versus f32: `768` bytes
- fixed-point sidecars are:
  - scale multiplier: `1,024` bytes
  - bias q: `1,024` bytes
- in this captured `c_fc` contract, `bias_q` is all zero, but the proof keeps
  the sidecar memory present so the boundary is not specialized to this one
  zero-bias checkpoint

Decision:

- The recommended post-GELU int8 activation boundary now has a bounded RTL
  proof, not just an offline scorer.
- The proof is functionally and numerically valid, but the local in-kernel GELU
  approximation costs `+22` DSP over the accumulator-only local-I/O proof.
- H2 remains active.
- Next gate:
  - either accept the extra DSP as a fit-positive tradeoff and integrate this
    post-GELU int8 boundary into the `L2 c_fc` replacement path
  - or run one bounded DSP-reduction follow-up for the postprocess stage before
    integration, such as a multi-cycle square/output-multiply schedule

### 2026-04-28 - H2 `c_proj` handoff from the post-GELU int8 boundary

Plan update:

- Treat the post-GELU proof's `26 DSP` result as fit-positive:
  - this is only `1.35%` of the XC7A200T `1,920` DSP budget
  - the active float `L2 c_fc` reference still costs
    `31,907 LUT / 45,932 FF / 4 DSP / 0 BRAM`
  - the post-GELU int8 proof costs only
    `653 LUT / 217 FF / 26 DSP / 5.5 BRAM36-equivalent`
- Do not spend the next slice trying to reduce DSP use.
- Instead, prove that the accepted `c_fc -> GELU -> int8 activation` boundary
  remains useful when consumed by the next MLP operator, `c_proj`.

Artifact:

- `artifacts/task6/parallel-hypotheses/h2-int8-l2-c-proj-from-post-gelu-boundary.json`

Script:

- `scripts/task6/score_int8_c_proj_from_post_gelu.py`

Nix target:

- `task6-int8-l2-c-proj-from-post-gelu-boundary`
- output:
  `/nix/store/w7jfi6han1f8fhwhdryy9aci9x1qgk7d-task6-int8-l2-c-proj-from-post-gelu-boundary`

Command:

- `python3 scripts/task6/score_int8_c_proj_from_post_gelu.py --c-fc-contract-manifest artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_fc-contract/manifest.json --c-fc-weight-pack-manifest artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_fc/manifest.json --c-proj-contract-manifest artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_proj-contract/manifest.json --c-proj-weight-pack-manifest artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_proj/manifest.json --post-gelu-requant-json artifacts/task6/parallel-hypotheses/h2-int8-l2-c-fc-post-gelu-requant-rtl-proof.json --out-json artifacts/task6/parallel-hypotheses/h2-int8-l2-c-proj-from-post-gelu-boundary.json`
- `nix build .#task6-int8-l2-c-proj-from-post-gelu-boundary --no-link --print-out-paths -L`

Execution result:

- status: `PASS`
- threshold: `0.02`
- `c_proj` input versus `GELU(c_fc expected)`:
  - normalized RMSE: `3.939776752351999e-08`
  - max absolute error: `1.600132085166628e-08`
- post-GELU int8 dequantized activation versus captured `c_proj` input:
  - normalized RMSE: `0.01199135641153676`
  - max absolute error: `0.0025458211614692583`
- `c_proj` output from post-GELU int8 activation and per-output int8 weights:
  - normalized RMSE: `0.014010386505018001`
  - max absolute error: `0.0009424232727163438`
  - mean absolute error: `0.0002511875694791357`

`c_proj` quantization contract:

- input features: `256`
- output features: `64`
- MACs: `16,384`
- activation quantization:
  - post-GELU int8 per-tensor symmetric
- weight quantization:
  - int8 per-output symmetric
- weight scale range:
  - `0.0004040582442846824..0.0006334623248558345`
- accumulator range:
  - `-53371..78617`

Byte-budget implication:

- post-GELU activation:
  - `256` int8 bytes replaces `1,024` f32 bytes
  - activation transfer savings: `768` bytes
- `c_proj` weights:
  - `16,384` int8 bytes replaces `65,536` f32 bytes
  - weight transfer savings: `49,152` bytes
  - per-output scale sidecar: `256` bytes

Decision:

- Promote H2 from a `c_fc`-only proof to a `c_fc -> GELU -> c_proj` chain
  candidate.
- Next gate:
  - implement a bounded `256x64` int8 `c_proj` RTL proof fed by the
    post-GELU int8 activation
- Falsifier:
  - if the bounded `c_proj` RTL proof does not stay under normalized RMSE
    `0.02`, or if its mapped LUT/FF cost erases the post-GELU `c_fc` win, fall
    back to the narrower `c_fc` boundary before claiming an MLP-chain
    replacement.

### 2026-04-28 - H2 `c_proj` RTL proof from the post-GELU int8 boundary

Artifact:

- `artifacts/task6/parallel-hypotheses/h2-int8-l2-c-proj-from-post-gelu-rtl-proof.json`

Sources:

- `flake.nix`
- `rtl/task6/task6_int8_l2_c_proj_from_post_gelu_kernel.sv`
- `sim/task6_int8_l2_c_proj_from_post_gelu_tb_main.sv`
- `sim/gen_task6_int8_l2_c_proj_from_post_gelu_tb_data.py`

Nix targets:

- `task6-int8-l2-c-proj-from-post-gelu-tb-data-sv`
- `task6-int8-l2-c-proj-from-post-gelu-sv-sim`
- `task6-int8-l2-c-proj-from-post-gelu-yosys-stat`
- `task6-int8-l2-c-proj-from-post-gelu-json`
- `task6-int8-l2-c-proj-from-post-gelu-utilization`
- `task6-int8-l2-c-proj-from-post-gelu-rtl-proof`
- proof output:
  `/nix/store/95l187w8i0h49a4dgbaj9p7xc1camf0h-task6-int8-l2-c-proj-from-post-gelu-rtl-proof`

Commands:

- `nix build .#task6-int8-l2-c-proj-from-post-gelu-sv-sim --no-link --print-out-paths -L`
- `nix build .#task6-int8-l2-c-proj-from-post-gelu-rtl-proof --no-link --print-out-paths -L`
- `python3 sim/gen_task6_int8_l2_c_proj_from_post_gelu_tb_data.py --c-fc-contract-manifest artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_fc-contract/manifest.json --c-fc-weight-pack-manifest artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_fc/manifest.json --c-proj-contract-manifest artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_proj-contract/manifest.json --c-proj-weight-pack-manifest artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_proj/manifest.json --post-gelu-requant-json artifacts/task6/parallel-hypotheses/h2-int8-l2-c-fc-post-gelu-requant-rtl-proof.json --sim-result-json /nix/store/9r187q4gm5n3z6glzkk9g9lwlrfkiix2-task6-int8-l2-c-proj-from-post-gelu-sv-sim.json --yosys-stat-json /nix/store/0yfw1qq2hpq8s87gayihaq84hykymbwx-task6-int8-l2-c-proj-from-post-gelu-yosys-stat.json --mapped-utilization-summary-json /nix/store/qjpmpgaf3gy1yq156ir855cxn20k0gwa-task6-int8-l2-c-proj-from-post-gelu-utilization/summary.json --out-json artifacts/task6/parallel-hypotheses/h2-int8-l2-c-proj-from-post-gelu-rtl-proof.json`

RTL contract:

- input:
  - post-GELU int8 activation from the proven `L2 c_fc` boundary
  - `256` int8 activation bytes
  - `4,096` packed int8 weight words for `64 x 256` `c_proj`
- compute:
  - same lanes4 int8 MAC core, instantiated directly as `IN_DIM=256`,
    `OUT_DIM=64`
- output:
  - `64` int32 accumulators
  - dequantization remains outside this bounded proof and is scored by the
    generator with per-output weight scales

Execution status:

- status: `PASS`
- Verilator:
  - output:
    `/nix/store/9r187q4gm5n3z6glzkk9g9lwlrfkiix2-task6-int8-l2-c-proj-from-post-gelu-sv-sim.json`
  - pass line:
    `PASS: task6 int8 L2 c_proj from postgelu reads 64 outputs 64 compute_cycles 4178 total_cycles 4242`
- numerical score from RTL accumulators:
  - normalized RMSE: `0.014010386505018001`
  - threshold: `0.02`
  - max absolute error: `0.0009424232727163438`
  - accumulator range: `-53371..78617`

Mapped resources:

- output:
  `/nix/store/qjpmpgaf3gy1yq156ir855cxn20k0gwa-task6-int8-l2-c-proj-from-post-gelu-utilization`
- `clb_luts`: `271`
- `clb_ffs`: `197`
- `dsp`: `4`
- `bram36`: `4`
- `bram18`: `1`
- `bram36_equiv`: `4.5`
- `bram_kb`: `162`
- `slices_lower_bound`: `34`

Byte-budget implication:

- post-GELU activation:
  - `256` int8 bytes replaces `1,024` f32 bytes
  - activation transfer savings: `768` bytes
- `c_proj` weights:
  - `16,384` int8 bytes replaces `65,536` f32 bytes
  - weight transfer savings: `49,152` bytes
  - per-output scale sidecar: `256` bytes
- `c_proj` accumulator output:
  - `256` bytes

Bounded chain resource picture:

- `c_fc -> GELU -> int8 activation` RTL proof:
  - `653 LUT / 217 FF / 26 DSP / 5.5 BRAM36-equivalent`
- `c_proj` RTL proof from that activation:
  - `271 LUT / 197 FF / 4 DSP / 4.5 BRAM36-equivalent`
- bounded sum before composing one shared top:
  - `924 LUT / 414 FF / 30 DSP / 10.0 BRAM36-equivalent`

Decision:

- H2 now has bounded RTL evidence on both sides of the MLP handoff:
  - the producer proof creates the post-GELU int8 activation
  - the consumer proof accepts that activation and computes exact int32
    `c_proj` accumulators
- H2 remains active and should be treated as the leading replacement path.
- Next gate:
  - compose the proven `c_fc` post-GELU producer and this `c_proj` consumer in
    one bounded chain top, with an explicit activation handoff memory or stream
  - keep the current two-proof bounded sum as the resource expectation until
    the composed top exists

### 2026-04-28 - H2 composed `c_fc -> GELU -> c_proj` int8 RTL proof

Artifact:

- `artifacts/task6/parallel-hypotheses/h2-int8-l2-mlp-chain-post-gelu-c-proj-rtl-proof.json`

Sources:

- `flake.nix`
- `rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_kernel.sv`
- `sim/task6_int8_l2_mlp_chain_post_gelu_c_proj_tb_main.sv`
- `sim/gen_task6_int8_l2_mlp_chain_post_gelu_c_proj_tb_data.py`

Nix targets:

- `task6-int8-l2-mlp-chain-post-gelu-c-proj-tb-data-sv`
- `task6-int8-l2-mlp-chain-post-gelu-c-proj-sv-sim`
- `task6-int8-l2-mlp-chain-post-gelu-c-proj-yosys-stat`
- `task6-int8-l2-mlp-chain-post-gelu-c-proj-json`
- `task6-int8-l2-mlp-chain-post-gelu-c-proj-utilization`
- `task6-int8-l2-mlp-chain-post-gelu-c-proj-rtl-proof`
- proof output:
  `/nix/store/8a7k3d05k09vwvgssyxi0zm4k8pldydk-task6-int8-l2-mlp-chain-post-gelu-c-proj-rtl-proof`

Commands:

- `nix build .#task6-int8-l2-mlp-chain-post-gelu-c-proj-sv-sim --no-link --print-out-paths -L`
- `nix build .#task6-int8-l2-mlp-chain-post-gelu-c-proj-rtl-proof --no-link --print-out-paths -L`

RTL contract:

- composed top:
  - `task6_int8_l2_mlp_chain_post_gelu_c_proj_kernel`
- sequence:
  - load captured `c_fc` activation, packed weights, requant scale sidecars,
    and fixed-point bias sidecars
  - run the proven `c_fc -> fixed-point GELU -> post-GELU int8` producer
  - sequentially transfer the `256` post-GELU int8 activations through an
    explicit local-memory handoff
  - run the proven `c_proj` int8 consumer from that handoff activation
  - expose `64` int32 `c_proj` accumulators through the output read port

Execution status:

- status: `PASS`
- Verilator:
  - output:
    `/nix/store/0bmdr5j5lr43zvmdavs6174rzqp397s6-task6-int8-l2-mlp-chain-post-gelu-c-proj-sv-sim.json`
  - pass line:
    `PASS: task6 int8 L2 mlp chain postgelu c_proj reads 64 outputs 64 compute_cycles 9631 total_cycles 9695`
- numerical score from the composed-chain `c_proj` accumulators:
  - normalized RMSE: `0.014010386505018005`
  - threshold: `0.02`
  - max absolute error: `0.0009424232727163438`
- post-GELU int8 activation handoff score:
  - normalized RMSE versus captured `c_proj` input:
    `0.011991356411536758`
  - post-GELU q range:
    `-67..127`

Mapped resources:

- `clb_luts`: `944`
- `clb_ffs`: `426`
- `dsp`: `30`
- `bram36`: `8`
- `bram18`: `4`
- `bram36_equiv`: `10.0`
- `bram_kb`: `360`
- `slices_lower_bound`: `118`

Delta against the prior two-proof bounded sum:

- prior separate proofs:
  - `924 LUT / 414 FF / 30 DSP / 10.0 BRAM36-equivalent`
- composed top:
  - `944 LUT / 426 FF / 30 DSP / 10.0 BRAM36-equivalent`
- overhead:
  - `+20` LUT
  - `+12` FF
  - `+0` DSP
  - `+0.0` BRAM36-equivalent

Byte-budget implication:

- `c_fc` activation:
  - `64` int8 bytes
- `c_fc` packed weights:
  - `16,384` bytes
- `c_fc` fixed-point sidecars:
  - `1,024` scale-multiplier bytes
  - `1,024` bias-q bytes
- post-GELU handoff:
  - `256` int8 bytes replaces `1,024` f32 bytes
  - handoff savings: `768` bytes
- `c_proj` packed weights:
  - `16,384` int8 bytes replaces `65,536` f32 bytes
  - weight transfer savings: `49,152` bytes
- `c_proj` accumulator output:
  - `256` bytes

Decision:

- Promote H2 from two bounded RTL proofs to a composed bounded MLP-chain proof.
- The DSP use is a positive signal, not a problem:
  - the composed proof uses `30` DSPs, about `1.56%` of the target board's
    `1,920` DSP budget
  - the key win is that the MLP chain now maps to DSP and BRAM instead of the
    repeated LUT/FF-heavy float handshake shell
- The composed chain keeps the prior numeric result and adds only a tiny
  handoff/control overhead over the two-proof sum.
- Next gate:
  - define the output boundary after `c_proj`, including dequantization,
    residual/add, or the next quantized handoff target
  - keep this composed RTL proof as the current H2 promotion reference until a
    larger calibrated sample set or downstream boundary invalidates it

### 2026-04-28 - H2 `c_proj` output boundary score

Artifact:

- `artifacts/task6/parallel-hypotheses/h2-int8-l2-c-proj-output-boundary.json`

Script:

- `scripts/task6/score_int8_c_proj_output_boundary.py`

Nix target:

- `task6-int8-l2-c-proj-output-boundary`
- output:
  `/nix/store/cjvhkpgmk6hk673jp67l7pwqpp1xqm65-task6-int8-l2-c-proj-output-boundary`

Command:

- `nix build .#task6-int8-l2-c-proj-output-boundary --no-link --print-out-paths -L`

Purpose:

- define the output side of the composed int8 MLP proof before adding more RTL
- score both:
  - int32 accumulator to f32 `c_proj` output
  - int32 accumulator to int8 `c_proj` output
- carry forward the nearby Linalg context showing the next operation after
  `c_proj`:
  - bias add
  - then a same-shape add with another `1x1x64` tensor, which is the residual
    path that still needs explicit capture before a residual/add RTL proof

Execution result:

- status: `PASS`
- accumulator hash matches the composed-chain proof:
  - `8ef8c2a85f1cc1369dd6cad3d716215c8311ec8a407497a003947a5e222025e2`
- f32 output candidate:
  - formula:
    `f32_out[i] = int32_acc[i] * post_gelu_scale * weight_scale[i] + bias[i]`
  - normalized RMSE: `0.014010386505018001`
  - verdict: `pass`
- int8 output candidate:
  - calibration:
    single captured `c_proj` `activation_out` max-abs scale
  - output scale:
    `0.0006137476192684625`
  - output q range:
    `-91..127`
  - normalized RMSE: `0.015465772661379424`
  - verdict: `pass`

Byte-budget implication:

- `c_proj` accumulator output:
  - `256` int32 bytes
- f32 output boundary sidecars:
  - `256` effective-scale bytes
  - `256` bias bytes
- f32 output bytes:
  - `256`
- int8 output bytes:
  - `64`
- int8 output write savings versus f32:
  - `192` bytes for this `64`-wide `c_proj` output

Decision:

- Promote the post-`c_proj` int8 output boundary as the next H2 implementation
  target.
- Do not implement residual/add yet:
  - the Linalg context confirms the add is next, but the residual tensor itself
    is not in the current `c_proj` module contract
  - capture that residual tensor before claiming a fused residual path
- Next gate:
  - implement a bounded fixed-point `c_proj` requant/output-memory RTL proof
  - then decide whether to capture the residual tensor for an int8 residual-add
    score or fall back to a f32 dequantized residual boundary

### 2026-04-28 - H2 composed MLP chain with `c_proj` int8 output requant

Artifact:

- `artifacts/task6/parallel-hypotheses/h2-int8-l2-mlp-chain-c-proj-requant-rtl-proof.json`

RTL and test files:

- `rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_requant_kernel.sv`
- `sim/task6_int8_l2_mlp_chain_c_proj_requant_tb_main.sv`
- `sim/gen_task6_int8_l2_mlp_chain_c_proj_requant_tb_data.py`

Nix targets:

- `task6-int8-l2-mlp-chain-c-proj-requant-sv-sim`
- `task6-int8-l2-mlp-chain-c-proj-requant-rtl-proof`
- output:
  `/nix/store/n5z8yq3dxkqq52pjk0zshpyhyadkimih-task6-int8-l2-mlp-chain-c-proj-requant-rtl-proof`

Commands:

- `nix build .#task6-int8-l2-mlp-chain-c-proj-requant-sv-sim --no-link --print-out-paths -L`
- `nix build .#task6-int8-l2-mlp-chain-c-proj-requant-rtl-proof --no-link --print-out-paths -L`

Purpose:

- extend the promoted composed chain:
  `c_fc -> fixed-point GELU -> int8 handoff -> c_proj`
- add a bounded fixed-point post-`c_proj` output stage:
  `q[i] = saturate_i8(round_shift(acc[i] * scale_mul[i], 24) + bias_q[i])`
- store the 64-wide `c_proj` result as int8 in local output memory instead of
  leaving the chain at the int32 accumulator boundary

Execution result:

- status: `PASS`
- Verilator:
  - reads: `64`
  - outputs: `64`
  - compute cycles: `9760`
  - total cycles: `9824`
- fixed-point output:
  - output scale: `0.0006137476192684625`
  - output q range: `-91..127`
  - normalized RMSE: `0.015465772661379428`
  - output-q hash matches the prior `c_proj` int8 output-boundary quantizer
  - accumulator hash matches the prior composed-chain and output-boundary
    artifacts
- Yosys mapped check:
  - `0` reported problems

Mapped utilization:

- LUTs: `1123 / 298600 = 0.38%`
- FFs: `443 / 597200 = 0.07%`
- DSPs: `34 / 1920 = 1.77%`
- BRAM36: `8 / 955 = 0.84%`
- BRAM18: `6`
- BRAM36-equivalent: `11.0 / 955 = 1.15%`

Delta versus the previous composed-chain accumulator-boundary proof:

- LUTs: `+179`
- FFs: `+17`
- DSPs: `+4`
- BRAM36-equivalent: `+1.0`
- Interpretation:
  - the int8 output stage costs a small amount of logic and one additional
    BRAM36-equivalent for the `c_proj` requant sidecars/output storage
  - the overall resource picture remains very small relative to the board

Decision:

- Promote this as the current H2 RTL reference for the bounded MLP-chain output
  boundary.
- Next gate:
  - capture the residual/add tensor after `c_proj`
  - score whether an int8 residual-add boundary is viable
  - only then implement or reject a fused residual-add RTL proof

### 2026-04-28 - H2 residual-add boundary scout after `c_proj`

Artifact:

- `artifacts/task6/parallel-hypotheses/h2-int8-l2-residual-add-boundary-scout.json`

Script and Nix target:

- `scripts/task6/trace_int8_residual_add_boundary.py`
- `task6-int8-l2-residual-add-boundary-scout`
- output:
  `/nix/store/5g8z9m1gmf2w453kw61v7pg5qniyxiyl-task6-int8-l2-residual-add-boundary-scout`

Commands:

- `python3 scripts/task6/trace_int8_residual_add_boundary.py --c-fc-contract-manifest artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_fc-contract/manifest.json --c-proj-contract-manifest artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_proj-contract/manifest.json --c-proj-candidate-json artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_proj-candidate.json --c-proj-requant-rtl-proof-json artifacts/task6/parallel-hypotheses/h2-int8-l2-mlp-chain-c-proj-requant-rtl-proof.json --out-json artifacts/task6/parallel-hypotheses/h2-int8-l2-residual-add-boundary-scout.json`
- `nix build .#task6-int8-l2-residual-add-boundary-scout --no-link --print-out-paths -L`

Result:

- status: `NEEDS_CAPTURE`
- upstream `c_proj` int8 output proof remains usable:
  - status: `PASS`
  - output scale: `0.0006137476192684625`
  - output q range: `-91..127`
  - normalized RMSE: `0.015465772661379428`
  - output-q hash: `93020d792e1a60480198b96b4daf79beca0cb1507253c14b2a4494eaed8b5f8d`
- next Linalg add site:
  - line: `418`
  - result: `%96`
  - operands: `%62`, `%95`
  - interpretation:
    - `%95` is the post-`c_proj` bias-add value
    - `%62` is the separate residual tensor that is not present in the current
      `c_proj` module contract

Capture route for the next numeric gate:

- capture residual operand from `transformer.h.0.ln_2` `activation_in`
- cross-check `transformer.h.0.ln_2` `activation_out` against the existing
  `transformer.h.0.mlp.c_fc` `activation_in` contract
- cross-check `transformer.h.0.mlp.c_proj` `activation_out` against the
  existing `c_proj` contract
- cross-check block output with:
  `block_out = ln_2.activation_in + mlp.c_proj.activation_out`
- then score:
  - `residual_f32 + c_proj_output_q * c_proj_output_scale`
  - `residual_q * residual_scale + c_proj_output_q * c_proj_output_scale`
  - quantized residual-add output for the next boundary

Execution notes:

- the old L2 Linalg store path recorded in the candidate JSON could not be
  restored with `nix-store -r`
- a direct rebuild of `tiny-stories-v1k-h64-l1-linalg` started compiling the
  full Torch/Triton closure, so it was stopped and replaced with this
  lower-cost scout artifact
- the prior Python environment used for the original contract capture had been
  garbage-collected, so the actual residual tensor capture still needs either a
  restored lightweight Python environment or an intentional rebuild of that
  capture environment

Decision:

- Do not claim residual-add numeric viability yet.
- Promote the exact capture route above as the next executable gate.

### 2026-04-28 - H2 residual-add boundary capture and score

Artifacts:

- `artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-residual-add-contract/`
- `artifacts/task6/parallel-hypotheses/h2-int8-l2-residual-add-boundary.json`

Scripts and Nix targets:

- `scripts/task6/export_residual_add_contract.py`
- `scripts/task6/score_int8_residual_add_boundary.py`
- `task6-int8-l2-residual-add-contract`
- `task6-int8-l2-residual-add-boundary`

Environment note:

- The first attempt through `python.pkgs.torch-bin` still pulled CUDA/NCCL
  source builds through the CUDA wheel closure.
- The capture target now uses a local CPU-only PyTorch wheel override:
  `torch-2.9.1+cpu-cp311-cp311-manylinux_2_28_x86_64.whl`
  with hash `sha256-PeKtubREPckhDvHxsW2jZHrOU1UxZtY2C7vX7dbxbk0=`.
- `transformers` and `safetensors` are overridden to use that CPU wheel for
  this capture path.

Contract capture result:

- status: `PASS`
- residual source: `transformer.h.0.ln_2` `activation_in`
- block output check:
  - `residual_activation_in + c_proj_activation_out` vs block output
  - normalized RMSE: `0.0`
- cross-checks against existing module contracts:
  - `ln2_activation_out` vs `c_fc.activation_in`: normalized RMSE
    `1.8294183695719108e-07`
  - `c_proj.activation_in` vs contract: normalized RMSE
    `2.8896815448809813e-07`
  - `c_proj.activation_out` vs contract: normalized RMSE
    `3.9373162995150223e-07`

Residual-add boundary score:

- status: `PASS`
- threshold: normalized RMSE `<= 0.02`
- `c_proj` output q hash:
  `93020d792e1a60480198b96b4daf79beca0cb1507253c14b2a4494eaed8b5f8d`
  - matches both the output-boundary scorer and RTL proof
- residual quantization:
  - scale: `0.0007355256578115028`
  - q range: `-114..127`
  - q hash:
    `a455841a965b5073c01ded9aa310f6d496376139cb9ccb3f3fc0c62a8e84d3f7`
- final residual-add output quantization:
  - scale: `0.0007500236330698129`
  - q range: `-125..127`
  - q hash:
    `28654845bf312e6298524e3444dd045cf7fb7fb30a0c693f211214ddc7970418`

Boundary metrics:

- `f32_residual_plus_int8_c_proj_vs_block_output`:
  - normalized RMSE: `0.007978545180826635`
  - verdict: pass
- `int8_residual_plus_int8_c_proj_vs_block_output`:
  - normalized RMSE: `0.009136092226376756`
  - verdict: pass
- `int8_final_residual_add_output_vs_block_output`:
  - normalized RMSE: `0.01095521307528224`
  - verdict: pass

Byte budget for this single-token L2 gate:

- residual f32: `256` bytes
- residual int8: `64` bytes
- `c_proj` int8 output: `64` bytes
- final residual-add int8 output: `64` bytes
- residual int8 savings vs f32: `192` bytes
- final output int8 savings vs f32: `192` bytes

Decision:

- Promote the residual-add boundary to the next implementation gate.
- Next gate: implement a bounded residual-add RTL proof that consumes:
  - residual int8 vector plus residual scale
  - `c_proj` int8 output vector plus `c_proj` output scale
  - final output scale
  - expected final q hash above

### 2026-04-29 - H2 composed MLP chain with int8 residual-add RTL proof

Artifact:

- `artifacts/task6/parallel-hypotheses/h2-int8-l2-mlp-chain-residual-add-rtl-proof.json`

RTL, testbench, and generator:

- `rtl/task6/task6_int8_l2_mlp_chain_residual_add_kernel.sv`
- `sim/task6_int8_l2_mlp_chain_residual_add_tb_main.sv`
- `sim/gen_task6_int8_l2_mlp_chain_residual_add_tb_data.py`

Nix targets:

- `task6-int8-l2-mlp-chain-residual-add-tb-data-sv`
- `task6-int8-l2-mlp-chain-residual-add-sv-sim`
- `task6-int8-l2-mlp-chain-residual-add-yosys-stat`
- `task6-int8-l2-mlp-chain-residual-add-json`
- `task6-int8-l2-mlp-chain-residual-add-utilization`
- `task6-int8-l2-mlp-chain-residual-add-rtl-proof`
- proof output:
  `/nix/store/a6ysyfr2xmh1a7k94di5clf4qzmnci0j-task6-int8-l2-mlp-chain-residual-add-rtl-proof`

Commands:

- `nix build .#task6-int8-l2-mlp-chain-residual-add-sv-sim --no-link --print-out-paths -L`
- `nix build .#task6-int8-l2-mlp-chain-residual-add-rtl-proof --no-link --print-out-paths -L`

Purpose:

- close the residual-add implementation gate after the captured boundary score
- extend the composed H2 RTL chain to:
  `c_fc -> fixed-point GELU -> post-GELU int8 -> c_proj -> c_proj int8 output -> residual-add int8 output`
- consume the captured residual vector as int8 and store the final block output
  as int8 in local output memory

Execution result:

- status: `PASS`
- Verilator:
  - reads: `64`
  - outputs: `64`
  - compute cycles: `9889`
  - total cycles: `9953`
- Yosys mapped check:
  - `0` reported problems
- final residual-add output:
  - output scale: `0.0007500236330698129`
  - output q range: `-125..127`
  - output q hash:
    `28654845bf312e6298524e3444dd045cf7fb7fb30a0c693f211214ddc7970418`
  - hash matches the captured residual-add boundary quantizer
  - fixed RTL residual-add output vs block output normalized RMSE:
    `0.01095521307528224`
  - fixed RTL residual-add output vs boundary quantizer normalized RMSE: `0.0`

Mapped utilization:

- LUTs: `1226 / 298600 = 0.41%`
- FFs: `468 / 597200 = 0.08%`
- DSPs: `36 / 1920 = 1.88%`
- BRAM36: `8 / 955 = 0.84%`
- BRAM18: `6`
- BRAM36-equivalent: `11.0 / 955 = 1.15%`
- slices lower bound: `154 / 74650 = 0.21%`

Delta versus the previous composed-chain `c_proj` int8-output proof:

- LUTs: `1123 -> 1226` (`+103`)
- FFs: `443 -> 468` (`+25`)
- DSPs: `34 -> 36` (`+2`)
- BRAM36-equivalent: `11.0 -> 11.0` (`+0.0`)

Interpretation:

- The residual-add postprocess is a small incremental cost over the prior
  `c_proj` int8-output proof.
- The DSP use remains fit-positive: the full bounded MLP plus residual-add
  proof uses only `36` DSPs, about `1.88%` of the board budget.
- This completes the current int8 residual-add question for the bounded L2
  gate: it works in RTL, passes simulation, matches the captured boundary
  quantizer, and stays very small in mapped utilization.

Decision:

- Promote this as the current H2 RTL reference for a block-output int8 boundary.
- Next gate:
  - integrate the residual-add proof into a board-programmable selftest lane
  - keep the lane bounded first, then scale only after the programmed-board
    selftest path proves the I/O contract and pass/fail reporting

### 2026-04-29 - H2 residual-add board selftest bitstream

Artifacts:

- `fpga/rtl/task6_int8_l2_mlp_chain_residual_add_selftest_top.sv`
- `sim/task6_int8_l2_mlp_chain_residual_add_selftest_tb_main.sv`

Nix targets:

- `task6-int8-l2-mlp-chain-residual-add-selftest-top`
- `task6-int8-l2-mlp-chain-residual-add-selftest-sim-main`
- `task6-int8-l2-mlp-chain-residual-add-selftest-sv-sim`
- `task6-int8-l2-mlp-chain-residual-add-selftest-json`
- `task6-int8-l2-mlp-chain-residual-add-selftest-utilization`
- `task6-int8-l2-mlp-chain-residual-add-selftest-xdc`
- `task6-int8-l2-mlp-chain-residual-add-selftest-fasm`
- `task6-int8-l2-mlp-chain-residual-add-selftest-bitstream`

Purpose:

- move the bounded int8 residual-add RTL proof from simulator-only evidence to
  a board-programmable pass/fail selftest
- reuse the existing `matmul_selftest.xdc` board pins:
  `SYS_CLK`, `SYS_RSTN`, and `led_3bits_tri_o[2:0]`
- load the fixed proof vectors into the DUT, pulse `start`, wait for `done`,
  read all `64` output bytes, and assert:
  - `led_3bits_tri_o[0]`: heartbeat
  - `led_3bits_tri_o[1]`: pass
  - `led_3bits_tri_o[2]`: fail

Commands:

- `nix build .#task6-int8-l2-mlp-chain-residual-add-selftest-sv-sim --no-link --print-out-paths -L`
- `nix build .#task6-int8-l2-mlp-chain-residual-add-selftest-utilization --no-link --print-out-paths -L`
- `nix build .#task6-int8-l2-mlp-chain-residual-add-selftest-fasm --no-link --print-out-paths -L`
- `nix build .#task6-int8-l2-mlp-chain-residual-add-selftest-bitstream --no-link --print-out-paths -L`

Execution result:

- Verilator wrapper selftest: `PASS`
  - pass LED asserted after `18676` simulated cycles
  - output path:
    `/nix/store/7vbz64gnv359myip0j8j26xf5rwn73ds-task6-int8-l2-mlp-chain-residual-add-selftest-sv-sim.json`
- Yosys mapped check:
  - `0` reported problems
  - JSON path:
    `/nix/store/md3y3hzgpi5gm0cw94wkyx9iz52lzwqd-task6-int8-l2-mlp-chain-residual-add-selftest.json`
  - utilization report:
    `/nix/store/ahlxmh9hgw711l3wywld1b1fwp22b047-task6-int8-l2-mlp-chain-residual-add-selftest-utilization`
- nextpnr/FASM:
  - legal route: router reached `overused=0`, `overuse=0`, `archfail=0`
  - post-route max frequency: `141.02 MHz`
  - requested target: `12.00 MHz`
  - FASM path:
    `/nix/store/9m7pxa76vkna92jdfln0l2hp74wggw3g-task6-int8-l2-mlp-chain-residual-add-selftest.fasm`
- bitstream:
  - status: `PASS`
  - bit path:
    `/nix/store/rdg9hr176qqln2lg0a2dqxscddqamy30-task6-int8-l2-mlp-chain-residual-add-selftest.bit`

Mapped utilization:

- LUTs: `6944 / 298600 = 2.33%`
- FFs: `566 / 597200 = 0.09%`
- DSPs: `36 / 1920 = 1.88%`
- BRAM36: `8 / 955 = 0.84%`
- BRAM18: `6`
- BRAM36-equivalent: `11.0 / 955 = 1.15%`
- BRAM KiB: `396 / 34380 = 1.15%`
- slices lower bound: `868 / 74650 = 1.16%`

Delta versus the bare residual-add RTL proof:

- LUTs: `1226 -> 6944` (`+5718`)
- FFs: `468 -> 566` (`+98`)
- DSPs: `36 -> 36` (`+0`)
- BRAM36-equivalent: `11.0 -> 11.0` (`+0.0`)

Interpretation:

- The selftest wrapper adds LUT-heavy fixed-vector load and compare logic, but
  it does not increase DSP or BRAM use over the bare residual-add kernel.
- This is the intended board bring-up tradeoff: spend a small amount of LUT
  budget to prove the real I/O contract and visible pass/fail reporting.
- The bitstream artifact is ready for physical programming and LED observation.

Tooling note:

- The first selftest JSON attempt used the generic `mkSynthJson` path, which
  pulled the `yosys-slang`/`yosys-0.64` bootstrap path and failed before design
  synthesis with `genericBuild: command not found`.
- The accepted selftest JSON target uses explicit `read_verilog -sv` commands
  with `pkgs.yosys`, matching the other Task 6 RTL proof targets.

Decision:

- Board-programmable evidence is now available for the bounded int8 residual
  add lane.
- Next gate:
  - physically program
    `/nix/store/rdg9hr176qqln2lg0a2dqxscddqamy30-task6-int8-l2-mlp-chain-residual-add-selftest.bit`
  - observe heartbeat/pass/fail LEDs under real board clock/reset
  - if pass LED asserts and fail LED stays low, promote the lane from
    bitstream-ready to on-board validated

### 2026-04-29 - H2 residual-add board selftest programmed

Programming command:

- `sudo openFPGALoader -c digilent_hs3 --ftdi-serial 210299BF3824 -m /nix/store/rdg9hr176qqln2lg0a2dqxscddqamy30-task6-int8-l2-mlp-chain-residual-add-selftest.bit`

Observed LEDs:

- board-visible LED 1: fixed on, believed to be the board power/status LED
- board-visible LED 2: blinking
- board-visible LED 3: fixed on
- board-visible LED 4: off

Design LED mapping:

- `led_3bits_tri_o[0]`: heartbeat, pin `P30`
- `led_3bits_tri_o[1]`: pass, pin `M30`
- `led_3bits_tri_o[2]`: fail, pin `N30`

Interpretation:

- The three design-driven LEDs match the expected pass pattern:
  heartbeat blinking, pass asserted, fail deasserted.
- This promotes the bounded int8 residual-add lane from bitstream-ready to
  on-board validated, subject to the board-visible first LED indeed being the
  always-on board status LED rather than one of the three constrained design
  pins.

Tooling note:

- Programming through the literal `result` symlink was reported to fail with:
  `Can't program SPI flash: missing device-package information`.
- The explicit Nix store `.bit` path works. For future runs, use
  `$(readlink -f result)` or the direct `.bit` store path so
  `openFPGALoader` sees the `.bit` file name instead of the extensionless
  `result` symlink name.

Decision:

- Record this as the first successful on-board validation of the bounded H2
  int8 residual-add selftest.
- Next gate:
  - decide whether to build a DDR3 bring-up selftest or scale the bounded
    on-board lane to a larger streaming-memory surface

### 2026-04-29 - LED map diagnostic bitstream

Artifacts:

- `fpga/rtl/task6_led_map_top.sv`

Nix targets:

- `task6-led-map-json`
- `task6-led-map-xdc`
- `task6-led-map-fasm`
- `task6-led-map-bitstream`

Purpose:

- disambiguate the physical board LED order before interpreting the residual-add
  pass/fail selftest LEDs
- use the same `SYS_CLK`, `SYS_RSTN`, and `led_3bits_tri_o[2:0]` pin
  constraints as the Task 6 residual-add board selftest

Expected repeating pattern:

- `led_3bits_tri_o = 3'b001`
- `led_3bits_tri_o = 3'b010`
- `led_3bits_tri_o = 3'b100`
- `led_3bits_tri_o = 3'b111`

Bitstream:

- `/nix/store/1d7wfvkzaf7bdsigsm5g6hlq8xn7yzw4-task6-led-map.bit`

Programming command:

- `sudo openFPGALoader -c digilent_hs3 --ftdi-serial 210299BF3824 -m /nix/store/1d7wfvkzaf7bdsigsm5g6hlq8xn7yzw4-task6-led-map.bit`

Use:

- Watch which physical LEDs participate in the one-hot sequence.
- The LED that turns on during `3'b001` is design LED `[0]`, heartbeat in the
  residual-add selftest.
- The LED that turns on during `3'b010` is design LED `[1]`, pass in the
  residual-add selftest.
- The LED that turns on during `3'b100` is design LED `[2]`, fail in the
  residual-add selftest.
- During `3'b111`, all three design-driven user LEDs should be on.

Observed physical mapping:

- top green LED: always on, not one of the three design-driven LEDs
- design LED `[0]`, pin `P30`: red
- design LED `[1]`, pin `M30`: green
- design LED `[2]`, pin `N30`: orange

Residual-add selftest interpretation:

- expected pass pattern:
  - top green: always on, ignored
  - red: blinking heartbeat
  - green: solid on pass
  - orange: off fail
- orange off after programming is a good sign: it means the fail LED is not
  asserted.

### 2026-04-29 - Residual-add selftest JTAG reset hardening

Observed board behavior:

- After a board power cycle, the residual-add selftest asserts the green pass
  LED in less than a second.
- After JTAG reprogramming the same bitstream without power cycling, the pass
  LED does not reliably assert.

Interpretation:

- The compute path is still likely good: a power cycle gives the design a clean
  reset and the selftest passes quickly.
- The issue is likely reset sequencing after configuration. JTAG programming
  can leave the external `SYS_RSTN` input high, so the selftest FSM may not see
  the same reset edge it sees after a board power cycle.

RTL change:

- `task6_int8_l2_mlp_chain_residual_add_selftest_top` now includes an internal
  post-configuration reset counter.
- `config_reset_count_q` is initialized to zero and holds `selftest_reset`
  asserted until bit `7` becomes high, giving the design `128` clocks of local
  reset after configuration even if `SYS_RSTN` never toggles.
- The DUT reset and selftest FSM reset path now use `selftest_reset`.

Verification:

- `nix-instantiate --parse flake.nix`
- `git diff --check`
- `nix build .#task6-int8-l2-mlp-chain-residual-add-selftest-sv-sim --no-link --print-out-paths -L`
  - result: `PASS`
  - pass LED asserted after `18804` simulated cycles
  - output path:
    `/nix/store/bgf2lpchpil22kaq0bfw1l9mcdgmv3af-task6-int8-l2-mlp-chain-residual-add-selftest-sv-sim.json`
- `nix build .#task6-int8-l2-mlp-chain-residual-add-selftest-bitstream --no-link --print-out-paths -L`
  - result: `PASS`
  - post-route max frequency: `161.24 MHz`
  - requested target: `12.00 MHz`
  - bit path:
    `/nix/store/vp6gcd52scyys0m694ka0zgnk39di6ym-task6-int8-l2-mlp-chain-residual-add-selftest.bit`
- `nix build .#task6-int8-l2-mlp-chain-residual-add-selftest-utilization --no-link --print-out-paths -L`
  - output path:
    `/nix/store/kihvlwn139wzxmvl2kgl320i5fm44777-task6-int8-l2-mlp-chain-residual-add-selftest-utilization`
  - LUTs: `7039 / 298600 = 2.36%`
  - FFs: `574 / 597200 = 0.10%`
  - DSPs: `36 / 1920 = 1.88%`
  - BRAM36-equivalent: `11 / 955 = 1.15%`

Expected physical test:

- Program the new bitstream without power cycling:
  `sudo openFPGALoader -c digilent_hs3 --ftdi-serial 210299BF3824 -m /nix/store/vp6gcd52scyys0m694ka0zgnk39di6ym-task6-int8-l2-mlp-chain-residual-add-selftest.bit`
- Expected LED pattern after less than a second:
  - top green: always on, ignored
  - red: blinking heartbeat
  - green: solid on pass
  - orange: off fail
- If this passes after a JTAG-only reprogram, the reset-sequencing hypothesis
  is confirmed.

Follow-up observation:

- The reset-hardened bitstream asserted the orange fail LED after JTAG
  programming.
- Interpretation:
  - the selftest is now starting after JTAG configuration
  - the remaining problem is inside the selftest result path, most likely a
    timeout or output-compare mismatch

Diagnostic bitstream:

- Added `DEBUG_LEDS` mode to
  `task6_int8_l2_mlp_chain_residual_add_selftest_top`.
- Added flake targets:
  - `task6-int8-l2-mlp-chain-residual-add-selftest-debug-json`
  - `task6-int8-l2-mlp-chain-residual-add-selftest-debug-fasm`
  - `task6-int8-l2-mlp-chain-residual-add-selftest-debug-bitstream`
- Built debug bitstream:
  `/nix/store/xz6ddhxm9l5ijg4ndkd8cv3sq8ki66i1-task6-int8-l2-mlp-chain-residual-add-selftest-debug.bit`
- Post-route max frequency: `135.91 MHz`
- Requested target: `12.00 MHz`

Debug LED decoding after a failure:

- The pattern cycles through four slow phases:
  1. fail reason
  2. failing output index bits `[2:0]`
  3. failing output index bits `[5:3]`
  4. all three design LEDs on as a separator
- Fail reason phase:
  - orange + red: timeout
  - orange + green: output mismatch
  - red + green + orange: default / unexpected state
- Index phases use binary on the design LEDs:
  - red is bit `0`
  - green is bit `1`
  - orange is bit `2`
- The always-on top green board LED is not part of this code.

Next physical test:

- Program the diagnostic bitstream:
  `sudo openFPGALoader -c digilent_hs3 --ftdi-serial 210299BF3824 -m /nix/store/xz6ddhxm9l5ijg4ndkd8cv3sq8ki66i1-task6-int8-l2-mlp-chain-residual-add-selftest-debug.bit`
- Watch the three design-driven LEDs for one full repeating cycle and record:
  fail-reason phase, low-index phase, high-index phase, separator phase.

Follow-up physical observation:

- Observed sequence:
  - red + green + orange
  - green + orange
  - nothing
- Interpretation:
  - red + green + orange is the separator phase
  - green + orange is `FAIL_REASON_MISMATCH`
  - the following `nothing` phase is failing-index bits `[2:0] = 0`
  - the board is failing on output index `0`
- Generated expected value for output index `0`:
  - `expected_residual_add_output_q_values[0] = 8'sh0a`

Value diagnostic bitstream:

- Added `DEBUG_LEDS=2` mode to
  `task6_int8_l2_mlp_chain_residual_add_selftest_top`.
- Added flake targets:
  - `task6-int8-l2-mlp-chain-residual-add-selftest-value-debug-json`
  - `task6-int8-l2-mlp-chain-residual-add-selftest-value-debug-fasm`
  - `task6-int8-l2-mlp-chain-residual-add-selftest-value-debug-bitstream`
- Verification:
  - `nix-instantiate --parse flake.nix`: pass
  - `git diff --check`: pass
  - `nix build .#task6-int8-l2-mlp-chain-residual-add-selftest-sv-sim --no-link --print-out-paths -L`:
    pass at `18804` cycles
    - `/nix/store/63cl9maj4galk7izanpzc6jmnnic803r-task6-int8-l2-mlp-chain-residual-add-selftest-sv-sim.json`
  - `nix build .#task6-int8-l2-mlp-chain-residual-add-selftest-value-debug-json --no-link --print-out-paths -L`:
    pass
    - `/nix/store/7465vpi28yc4cjy56b7rq73x78i2bmb8-task6-int8-l2-mlp-chain-residual-add-selftest-value-debug.json`
  - `nix build .#task6-int8-l2-mlp-chain-residual-add-selftest-value-debug-bitstream --no-link --print-out-paths -L`:
    pass
    - `/nix/store/11jndspp1b4j7gs46h26nx2mjji8gmrz-task6-int8-l2-mlp-chain-residual-add-selftest-value-debug.bit`
- Post-route timing:
  - max frequency: `146.31 MHz`
  - requested target: `12.00 MHz`

Value debug LED decoding:

- Ignore the always-on top board green LED.
- On the three design-driven LEDs, red is bit `0`, green is bit `1`, and
  orange is bit `2`.
- The cycle has 16 phases:
  1. all LEDs: start marker
  2. fail reason
  3. failing index bits `[2:0]`
  4. failing index bits `[5:3]`
  5. red + orange: expected-byte marker
  6. expected byte bits `[2:0]`
  7. expected byte bits `[5:3]`
  8. expected byte bits `[7:6]`, using red for bit `6` and green for bit `7`
  9. red + green: observed-byte marker
  10. observed byte bits `[2:0]`
  11. observed byte bits `[5:3]`
  12. observed byte bits `[7:6]`, using red for bit `6` and green for bit `7`
  13. nothing: gap
  14. nothing: gap
  15. nothing: gap
  16. all LEDs: end marker
- Expected index-0 byte `0x0a` should display after the red + orange marker as:
  - green
  - red
  - nothing

Follow-up value-debug physical observation:

- Observed sequence:
  - red + green + orange
  - green + orange
  - nothing
  - red + orange
  - green
  - red
  - nothing
  - red + green
  - green
  - red + orange
  - red
  - nothing
  - red + green + orange
- Interpretation:
  - fail reason is `FAIL_REASON_MISMATCH`
  - failing index is still `0`
  - expected final output byte is `0x0a`
  - observed final output byte is `0x6a`
- The residual-add formula produces `0x6a` for index `0` if the add stage
  consumes `c_proj = 0x7f` with residual `0x02`, so the next diagnostic
  checks the actual c_proj byte presented to the residual-add write.

C-proj diagnostic bitstream:

- Added `DEBUG_LEDS=3` mode to display the expected c_proj byte and the
  first c_proj byte observed by the residual-add write path.
- Added flake targets:
  - `task6-int8-l2-mlp-chain-residual-add-selftest-c-proj-debug-json`
  - `task6-int8-l2-mlp-chain-residual-add-selftest-c-proj-debug-fasm`
  - `task6-int8-l2-mlp-chain-residual-add-selftest-c-proj-debug-bitstream`
- Verification:
  - `nix build .#task6-int8-l2-mlp-chain-residual-add-selftest-c-proj-debug-json --no-link --print-out-paths -L`:
    pass
    - `/nix/store/hczhy2bwgh3p744sis9fy34anhpk876i-task6-int8-l2-mlp-chain-residual-add-selftest-c-proj-debug.json`
  - `nix build .#task6-int8-l2-mlp-chain-residual-add-selftest-c-proj-debug-bitstream --no-link --print-out-paths -L`:
    pass
    - `/nix/store/j10fhmdb4w9mvk5gdijjx21762ia5qqf-task6-int8-l2-mlp-chain-residual-add-selftest-c-proj-debug.bit`
- Post-route timing:
  - max frequency: `156.67 MHz`
  - requested target: `12.00 MHz`

C-proj debug LED decoding:

- Ignore the always-on top board green LED.
- The cycle layout is the same as value debug, except the byte after
  red + orange is expected c_proj and the byte after red + green is the
  first c_proj observed by the residual-add write path.
- Expected c_proj for index `0` is `0x0a`, displayed as:
  - green
  - red
  - nothing
- If the observed c_proj is `0x7f`, it should display after the red + green
  marker as:
  - red + green + orange
  - red + green + orange
  - red

Follow-up c-proj debug physical observation:

- Observed sequence after the red + orange marker:
  - green
  - red
  - nothing
- Observed sequence after the red + green marker:
  - red + green + orange for two phases
  - red
  - nothing
- Interpretation:
  - expected c_proj byte for output index `0` is `0x0a`
  - residual-add consumed c_proj byte `0x7f`
  - this confirms the value-debug inference that output `0x6a` was produced
    by adding residual `0x02` to saturated c_proj `0x7f`

C-proj requant split diagnostic bitstream:

- Added c_proj requant debug outputs for the first output write:
  accumulator, scale multiplier, bias, and requantized output byte.
- Added `DEBUG_LEDS=4` mode to display three match bits for index `0`:
  accumulator matches expected, scale matches expected, and bias matches
  expected, followed by the observed c_proj output byte.
- Added flake targets:
  - `task6-int8-l2-mlp-chain-residual-add-selftest-c-proj-requant-debug-json`
  - `task6-int8-l2-mlp-chain-residual-add-selftest-c-proj-requant-debug-fasm`
  - `task6-int8-l2-mlp-chain-residual-add-selftest-c-proj-requant-debug-bitstream`
- Verification:
  - `nix build .#task6-int8-l2-mlp-chain-residual-add-selftest-sv-sim --no-link --print-out-paths -L`:
    pass at `18804` cycles
    - `/nix/store/4q44akfqr9gl2gkc6bzy9vbj0fx2dm40-task6-int8-l2-mlp-chain-residual-add-selftest-sv-sim.json`
  - `nix build .#task6-int8-l2-mlp-chain-residual-add-selftest-c-proj-requant-debug-json --no-link --print-out-paths -L`:
    pass
    - `/nix/store/49p4im0ckwmia98vyyvfbpnrk484jrcq-task6-int8-l2-mlp-chain-residual-add-selftest-c-proj-requant-debug.json`
  - `nix build .#task6-int8-l2-mlp-chain-residual-add-selftest-c-proj-requant-debug-bitstream --no-link --print-out-paths -L`:
    pass
    - `/nix/store/qg4wbb17a00v9212c3nny3ybgk7cpjhp-task6-int8-l2-mlp-chain-residual-add-selftest-c-proj-requant-debug.bit`
- Post-route timing:
  - max frequency: `137.99 MHz`
  - requested target: `12.00 MHz`

C-proj requant split debug LED decoding:

- Ignore the always-on top board green LED.
- After the red + orange marker, three phases show match bits:
  1. c_proj accumulator match
  2. c_proj scale multiplier match
  3. c_proj bias match
- For those match phases:
  - green means match
  - red + orange means mismatch or not captured
- After the red + green marker, the observed c_proj output byte is displayed
  with the same three-phase byte encoding as before.
- If the accumulator/scale/bias are all correct but the output is still
  `0x7f`, the likely fault is in synthesized requant arithmetic.
- If the accumulator is mismatched while scale and bias match, the likely
  fault is upstream in the c_fc/post-GELU/c_proj accumulator chain.

Follow-up c-proj requant split debug physical observation:

- Normal self-test bitstream after the first sign-extension patch still failed
  on hardware: orange stayed on and red blinked.
- `DEBUG_LEDS=4` physical sequence:
  - red + green + orange
  - green + orange
  - nothing
  - red + orange
  - green
  - red + green
  - red + green + orange
  - red
  - nothing
- Interpretation:
  - failing output index is still `0`
  - c_proj accumulator matches the generated expected value
  - c_proj requant scale multiplier matches the generated expected value
  - c_proj requant bias matches the generated expected value
  - observed c_proj output byte is still `0x7f`
  - expected c_proj output byte is `0x0a`
- This keeps the suspected fault inside the synthesized c_proj requant
  arithmetic rather than the reset/load path, constant ROM contents, or
  upstream accumulator path.

C-proj requant shift-add trial:

- Replaced the c_proj requant `acc * scale_mul` expression with an explicit
  signed 32x32 shift-add multiply helper.
- Rationale:
  - simulation already passes with the original `*`
  - hardware diagnostics show correct operands but a saturated-looking c_proj
    output
  - replacing the inferred DSP-backed multiply tests whether the synthesis/P&R
    implementation of that signed multiply is the hardware-only mismatch
- Verification:
  - `nix build .#task6-int8-l2-mlp-chain-residual-add-selftest-sv-sim --no-link --print-out-paths -L`:
    pass at `18804` cycles
    - `/nix/store/jky2iv3zjl0d0x4lgx44gb40qllrm23s-task6-int8-l2-mlp-chain-residual-add-selftest-sv-sim.json`
  - `nix build .#task6-int8-l2-mlp-chain-residual-add-selftest-json --no-link --print-out-paths -L`:
    pass
    - `/nix/store/kpx1jvxlgd3fa5fmh0wv2vh46kffcx31-task6-int8-l2-mlp-chain-residual-add-selftest.json`
  - `nix build .#task6-int8-l2-mlp-chain-residual-add-selftest-bitstream --no-link --print-out-paths -L`:
    pass
    - `/nix/store/2hi48w49al1yh8z52b8hf0pylrqnpgjg-task6-int8-l2-mlp-chain-residual-add-selftest.bit`
- Yosys synthesis resource note:
  - `DSP48E1`: `32`, down from `36` before removing this multiply from the DSP
    path
- Packed utilization from the routed build:
  - `SLICE_LUTX`: `15264 / 597200` (`2.56%`)
  - `SLICE_FFX`: `718 / 597200` (`0.12%`)
  - `DSP48E1`: `32 / 1920` (`1.67%`)
  - `RAMB36E1`: `8 / 955`
  - `RAMB18E1`: `6 / 1910`
  - BRAM36-equivalent: `11 / 955` (`1.15%`)
- Post-route timing:
  - max frequency: `163.48 MHz`
  - requested target: `12.00 MHz`

Next physical test:

- Program:
  `sudo openFPGALoader -c digilent_hs3 --ftdi-serial 210299BF3824 /nix/store/2hi48w49al1yh8z52b8hf0pylrqnpgjg-task6-int8-l2-mlp-chain-residual-add-selftest.bit`
- Expected pass indication:
  - ignore the always-on top board green LED
  - design red LED blinks as heartbeat
  - design green LED is solid on
  - design orange LED is off

Follow-up shift-add physical observation:

- Programmed:
  `/nix/store/2hi48w49al1yh8z52b8hf0pylrqnpgjg-task6-int8-l2-mlp-chain-residual-add-selftest.bit`
- Observed:
  - red blinking
  - orange fixed on
- Interpretation:
  - the normal self-test still fails after replacing the c_proj requant DSP
    multiply with explicit shift-add logic
  - this weakens the simple "bad inferred c_proj DSP multiply" hypothesis
  - remaining likely causes are the rounded shift/saturation arithmetic, a
    synthesis issue with the combinational requant function shape, or an
    unobserved mismatch inside the product/shift intermediate values

Shift-add c-proj requant diagnostic bitstream:

- Rebuilt the `DEBUG_LEDS=4` c_proj requant diagnostic against the shift-add
  RTL.
- Verification:
  - `nix build .#task6-int8-l2-mlp-chain-residual-add-selftest-c-proj-requant-debug-bitstream --no-link --print-out-paths -L`:
    pass
    - `/nix/store/bw89f87zf1pb9a9w7rqc8ayglzksi8b1-task6-int8-l2-mlp-chain-residual-add-selftest-c-proj-requant-debug.bit`
- Packed utilization:
  - `SLICE_LUTX`: `15619 / 597200` (`2.61%`)
  - `SLICE_FFX`: `832 / 597200` (`0.14%`)
  - `DSP48E1`: `32 / 1920` (`1.67%`)
  - `RAMB36E1`: `8 / 955`
  - `RAMB18E1`: `6 / 1910`
- Post-route timing:
  - max frequency: `182.05 MHz`
  - requested target: `12.00 MHz`

Next physical test:

- Program:
  `sudo openFPGALoader -c digilent_hs3 --ftdi-serial 210299BF3824 /nix/store/bw89f87zf1pb9a9w7rqc8ayglzksi8b1-task6-int8-l2-mlp-chain-residual-add-selftest-c-proj-requant-debug.bit`
- Record one full repeated sequence from the three design-driven LEDs.
- Ignore the always-on top board green LED.
