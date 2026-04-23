# Task 6 StreamTensor Lite Lane

This worktree owns the StreamTensor-lite Task 6 lane.

The goal is not to port StreamTensor wholesale. The goal is to test the
smallest architecture change that attacks the actual current bottleneck:
replace full-model RTL expansion with a reusable block-engine direction built
around a narrow GEMV proof that can be rejected quickly if it fails.

## Thesis

- keep Torch-MLIR / Linalg as the frontend
- stop treating full-model RTL lowering as the default success path
- target a reusable block-engine direction, not monolithic whole-model RTL
- use external weights explicitly in the first real experiment
- force a resource signature that moves away from `0 DSP / 0 BRAM`
- prefer the cheapest artifact that answers the current question
- keep this separate from:
  - board-RAM / `top4-memory` shell work
  - quantization follow-up
  - alternate-dialect or LSQ lane work
- reject any version of this lane that turns into a full compiler rewrite

## Source Idea

This lane is grounded in the shared ChatGPT plan plus the existing Task 6
paper-review findings:

- `StreamTensor-lite / fit-first accelerator lane` is the top-ranked active
  direction
- the copied float baseline is about `135x` over LUT budget and about `97x`
  over FF budget while using `0` BRAM and `0` DSP
- that symptom says the current flow is structurally expanding the model into
  fabric instead of producing a reusable accelerator architecture
- StreamTensor is relevant because it keeps a higher-level frontend and moves
  into dataflow lowering, fusion, resource allocation, and bufferization rather
  than lowering the entire model into one monolithic RTL structure
- the architectural signal to copy first is not "stream everything"; it is
  "reuse a constrained accelerator block with off-chip parameters"

Practical interpretation for this lane:

- keep the experiment local and narrow
- start with one linear / GEMV-shaped region, not a full transformer-block port
- prove that the lane can consume DSPs and externalized weights before chasing
  broader compiler changes
- do not start with a whole-model scheduler, HLS port, or new compiler stack

## Baseline And Comparison Rule

Use:

- `artifacts/task6/baselines/tiny-stories-1m-baseline-float-selftest-all-memory-utilization`

Measurement rule for this lane:

- compare the same model and the same stage first
- use representative-core artifacts for the first constrained proof
- prefer pre-RTL structural checkpoints where possible
- replay on the real TinyStories baseline only after the constrained proof
  changes the resource signature or structural shape in the intended direction

Always record:

- exact stage reached or first failing stage
- exact kernel boundary being changed
- stage-stat delta at the same stage
- mapped utilization delta when available
- host wall-clock time and peak memory
- DSP / BRAM / LUT / FF mix before and after the change
- whether the result still looks useful once downstream stages are included

## First-Proof Scorecard

Artifact under test:

- one redirected GEMV proof around a single reused kernel boundary

Fixed ceilings for the first proof:

- use at most `10%` of the copied device budget from the baseline summary
- LUT ceiling: `29,860`
- FF ceiling: `59,720`

Must-have checks:

| Check | Requirement | Why |
| --- | --- | --- |
| DSP use | `DSP > 0` in the kernel or one-block-top Yosys stat | proves arithmetic is no longer all-fabric |
| Weight placement | large weights come from a pack file or mocked ROM-style interface | rejects constant-materialized RTL as the main story |
| LUT ceiling | `<= 29,860` LUT | keeps the first proof small enough to matter |
| FF ceiling | `<= 59,720` FF | same reason as LUT ceiling |
| Verilator | kernel test passes | preserves functional credibility |
| Micro-proof runtime | kernel Yosys stat completes in `< 30 s` | keeps rejection fast enough to drive daily iteration |
| Whole-model dependency | proof is meaningful without whole-model lowering | preserves fast rejection |

Fail-fast checks:

- still `0 DSP`
- weights are still emitted as giant RTL constants
- the proof only becomes meaningful after whole-model lowering
- the compile loop breaks the stage budgets below by more than `2x` on repeat

## Benchmark Pack And Time Budgets

These budgets are the default feedback-loop guardrails for the lane:

| Stage | Budget | Notes |
| --- | --- | --- |
| Python export + weight pack | `< 30 s` | export should stay cheap enough to rerun repeatedly |
| Task-graph generation | `< 10 s` | graph construction must be almost free |
| Verilator kernel test | `< 20 s` | fast functional rejection |
| Yosys stat for kernel | `< 30 s` | first structural check |
| Yosys stat for one-block top | `< 2 min` | highest allowed "slow" loop for promotion |

Operational rule:

- record wall-clock and peak RSS on every run
- once an experiment is recorded, commit and push before starting the next one
- reject stages that keep missing these budgets before widening the artifact

## Model Ladder

The primary execution ladder is now the minimum fast-feedback loop required for
this lane to drive day-to-day Task 6 decisions.

| Rung | Artifact class | Model target | Status | Promotion rule |
| --- | --- | --- | --- | --- |
| `L0` | synthetic `64x64` GEMV smoke | `task6-l0-gemv64` external-weight kernel | running | use only for kernel plumbing and DSP validation |
| `L1` | TinyStories single linear op | block-0 `mlp.c_fc` extracted from `tiny-stories-1m-representative-core-v64-h4` | frozen reference | first-proof bar cleared at `29,778 LUT / 46,352 FF / 4 DSP / 0 BRAM`; do not reopen local `L1` hotspot surgery unless `L2` forces a boundary rethink |
| `L2` | reduced-vocab replay | `tiny-stories-v1k-h64-l1` | running | monolithic `64 -> 256` micro-surgery is closed; the active mainline is the tiled `4 x 64` wrapper around one reused `64 -> 64` kernel |
| `L3` | reduced-vocab replay | planned `tiny-stories-v4k-h64-l1` | planned | promote only if `L2` clears the first-proof scorecard |
| `L4` | representative-core replay | existing `tiny-stories-1m-representative-core-v64-h4` | reserve | replay only after `L3` shows a structural win |

Deferred extension ladder:

| Rung | Model target | Status | Use |
| --- | --- | --- | --- |
| `X1` | planned `tiny-stories-v10k-h64-l1` | planned | later fidelity step, not part of the default fast loop |
| `X2` | planned `tiny-stories-v10k-h64-l2` | planned | later reuse step if `X1` is still too small |
| `X3` | existing `tiny-stories-1m-baseline-float` | reserve | final replay only after `L4` remains believable downstream |

Model-ladder rule:

- hold `hidden_size = 64` fixed in the reduced-vocab ladder
- vary vocabulary size and layer count before touching width
- keep single-token forward as the default path
- do not let the deferred extension ladder become the default loop until the
  primary ladder is exhausted

## Active Frontier

The lane has moved beyond the original monolithic `L2 c_fc` search.

- Keep `L1 c_fc` as the solved first-proof reference:
  - `task6-l1-c-fc-redirect-index-ring3-postbranch-outbuf-fifo2-abc9`
  - `29,778 LUT / 46,352 FF / 4 DSP / 0 BRAM`
  - treat the earlier selective-buffer widening through `72a502f` as a closed
    search phase:
    - it proved local FIFO2 replacement can compose safely with `abc9`
    - it did not justify more blind ring expansion once the curve tapered
- Keep `mlp.c_proj` reserve-only:
  - structurally validated and executable, but still worse than the frozen
    `L1 c_fc` point on the scorecard
- Treat tiled `L2 c_fc` as the sole active mainline:
  - `task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2-abc9-utilization`
  - `31,907 LUT / 45,932 FF / 4 DSP / 0 BRAM`
  - the seam split showed the wrapper only contributes about `18 LUT` beyond
    the base tile kernel, and one bounded tile-kernel post-branch/output probe
    then trimmed another `553 LUT` / `808 FF` from the tiled `L2` reference
  - this is still `2,047 LUT` over the ceiling, so `L3` remains blocked

Current continuation rule:

- the amended one-probe tiled-`L2` follow-up has been spent:
  - seam instrumentation was effectively flat
  - one bounded tile-kernel post-branch/output probe improved `L2`, but did
    not clear the ceiling
- do not return to monolithic `64 -> 256` `L2` micro-surgery
- do not promote to `L3` until the tiled `L2` reference clears the ceiling
- do not make another local `L2 c_fc` RTL edit without a new structural
  hypothesis that is stronger than "another nearby buffer cluster may help"
- the probe plumbing is now consolidated:
  - `rtl/task6/task6_ui64_fifo2_buffer.sv` is the canonical FIFO2 helper
  - `rtl/task6/handshake_buffer_in_ui64_out_ui64_2slots_seq_fifo2.sv` is only
    the legacy wrapper module name
  - local rewrite sites come from
    `nix/task6-ui64-fifo2-site-map.nix` through shared flake helpers instead
    of repeated inline site lists
- the next bounded `L2` probe should target the mixed data/control store-path
  seam in the tiled `64 -> 64` kernel, not another `ui64` buffer-only rewrite

## Exact First Insertion Point

The first insertion point is fixed now:

- target the block-0 MLP expansion linear
- GPT-Neo module path:
  - `transformer.h.0.mlp.c_fc`
- representation level:
  - `linalg` on tensors immediately after the Torch-MLIR backend-to-Linalg
    lowering step
- exported-IR fallback:
  - the first post-norm MLP linear op in block `0` if importer naming changes
- shape contract:
  - single-token MLP expansion GEMV:
    - `[1, hidden_size] x [hidden_size, 4 * hidden_size]`
  - discovery rung target:
    - `[1, 4] x [4, 16]` on `tiny-stories-1m-representative-core-v64-h4`
  - reduced-vocab ladder target:
    - `[1, 64] x [64, 256]` on `tiny-stories-v*k*-h64-l*`

Why this is first:

- it is a plain linear / GEMV-shaped region with static shape
- it avoids attention-specific control and softmax concerns
- it repeats across transformer blocks, so success has a believable replay path
- it is a better first proof than `lm_head`, which is larger and more likely to
  dominate the experiment before the kernel boundary is stable

Artifact rule:

- discover the boundary first on `tiny-stories-1m-representative-core-v64-h4`
- replay the first real micro-fit proof on `tiny-stories-v1k-h64-l1`

## Immediate Tracks

1. Frozen micro-fit ladder
   - add the reduced-vocab, `hidden_size = 64` rung family in the order listed
     above
   - do not widen the ladder until each rung clears or fails the scorecard

2. First-class weight-packer path
   - add:
     - `scripts/task6/export_weights_pack.py`
     - `scripts/task6/export_l1_contract.py`
     - `scripts/task6/verify_l1_contract.py`
     - `scripts/task6/build_task_graph.py`
     - `artifacts/task6/weights_pack/<model-rung>/`
     - `artifacts/task6/streamtensor-lite/l1/<contract-dir>/`
   - the first proof must consume packed weights or a mocked ROM-style
     interface, not embedded constants

3. Stage-local runner surface
   - desired command surface:
     - `just task6-l0`
     - `just task6-l1`
     - `just task6-l2`
     - and upward through the ladder
   - each rung should emit:
     - structural summary
     - Yosys stat
     - wall-clock
     - peak memory
     - verdict
   - note:
     - the repo does not currently ship a `justfile`, so these are required
       follow-up work items, not a current claim

4. Stop rule for the whole-model lane
   - once a reduced-vocab `h64` rung exists, the whole-model TinyStories lane
     stays only as a comparison artifact
   - it must not remain the default iteration route for StreamTensor-lite work

## Immediate Mission

Produce one narrow proof that the block-0 MLP expansion linear can be
redirected into a small reused kernel that:

- uses externalized weights
- consumes DSPs
- avoids full-model RTL expansion as the core story
- gives a measurable move away from the current `0 DSP / 0 BRAM` pattern
- stays within the first-proof scorecard and stage budgets

Required first output:

- one shortlist memo with:
  - the chosen block-0 linear boundary
  - cheapest artifact where that region is still identifiable
  - why it can become a reused kernel boundary
  - how weights are externalized in the proof
  - what resource-signature change should appear if the idea is working
  - cheapest validation artifact
  - replay target if the result is helpful

## Execution Plan

1. Freeze the scorecard, rung ladder, and first insertion point.
   - do not let experiments move forward without using them

2. Export and pack the first kernel weights.
   - isolate the block-0 `mlp.c_fc` weights
   - write them into a first-class weight pack artifact
   - reject any path that immediately materializes them back into constants

3. Build the smallest task graph around the kernel.
   - keep activations on-chip
   - make the packed weights external inputs
   - aim for DSP-backed arithmetic first

4. Validate on `L0` and `L1`.
   - use `task6-l0-gemv64` as the synthetic external-weight `64x64` GEMV
     harness for plumbing and kernel smoke validation
   - use `tiny-stories-1m-representative-core-v64-h4` for the first
     TinyStories-shaped boundary check
   - capture one deterministic `L1` sample contract at the selected
     `transformer.h.0.mlp.c_fc` site and replay it directly from the packed
     weight/bias tensors before widening into any heavier simulation path
   - do not promote if the scorecard or time budgets fail

5. Promote to the micro-fit ladder or reject.
   - first promotion target:
     - `tiny-stories-v1k-h64-l1`
   - stop widening once a rung fails the scorecard
   - if the monolithic reduced-vocab rung misses, pivot to one bounded tiled
     wrapper experiment before changing the boundary
   - after the selective-buffer `L1` phase clears the ceiling, do not keep
     widening that loop blindly:
     - freeze the winning `L1` reference
     - carry only reusable tile-kernel edits forward into `L2`
   - replay on representative-core only after the reduced-vocab ladder shows a
     believable structural win
   - keep `tiny-stories-v10k-h64-l1`, `tiny-stories-v10k-h64-l2`, and the real
     TinyStories baseline as deferred extension steps, not the default loop

6. Current active step.
   - freeze `L1`
   - keep `c_proj` reserve-only
   - keep tiled `L2 c_fc` as the only active mainline
   - keep monolithic `L2 c_fc` surgery closed
   - do not spend another local `L2 c_fc` probe until a new structural
     hypothesis exists
   - before the next probe wave, refactor the probe plumbing so local rewrites
     come from:
     - one canonical FIFO2 helper plus wrappers where old module names must stay
     - one small patch map that names the rewritten sites

## Candidate First Experiments

1. Block-0 `mlp.c_fc` kernel extraction
   - primary experiment
   - carve out the first MLP expansion linear as the reused kernel boundary

2. Block-0 `mlp.c_proj` kernel extraction
   - reserve fallback if the expansion linear imports badly
   - still keep the proof inside the MLP path, not attention

3. Tiled `lm_head` scorer
   - later rung only
   - use only after the internal MLP kernel path is structurally credible

## Open Questions

- Should the first packed-weight proof use a file-backed pack, a mocked ROM
  interface, or both?
- Is `tiny-stories-1m-representative-core-v64-h4` large enough to preserve the
  block-0 MLP boundary meaningfully, or should promotion to `tiny-stories-v1k-h64-l1`
  happen immediately after the boundary is identified?
- What is the smallest Verilator harness that still proves the kernel contract
  honestly?

## Out Of Scope

- full StreamTensor reimplementation
- porting the whole model into a new accelerator architecture before one narrow
  linear / GEMV proof works
- on-board DDR3 / external-memory work
- quantization route debugging
- alternate-dialect, LSQ, or eqmap work unless a specific dependency emerges
- reviewer-facing project-plan edits

## Exit Condition

This lane is ready to merge back when it produces one measured conclusion with
evidence:

- `helpful`
  - one local MLP linear redirection produces a credible reused-kernel proof
    with external weights, `DSP > 0`, and a better resource signature, and is
    worth replaying on the real baseline
- `mixed`
  - the idea only works in a constrained demo without a believable replay path
- `reject`
  - the idea cannot redirect one narrow linear / GEMV region without turning
    Task 6 into a compiler-rewrite project
