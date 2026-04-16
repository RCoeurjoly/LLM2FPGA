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

## Parallel strategy execution guidance

Use one lane per strategy, derived from `task6`.

Recommended lane names:

- `task6-quant`
- `task6-eqmap`
- `task6-board-ram`
- `task6-lsq`
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
