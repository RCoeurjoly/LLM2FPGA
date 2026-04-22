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
     - `tiny-stories-1m-baseline-float-selftest-top4-memory-*`
   - current milestone:
     - finish the narrowed-shell utilization run and record whether the split
       `stage6a` / `stage8*` path completes or still hits an OOM-class
       bottleneck
   - continue only if:
     - the lane reaches a later stage than baseline or lowers peak memory / RSS
   - prune only if:
     - the narrowed shell still fails without improving the bottleneck shape

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
