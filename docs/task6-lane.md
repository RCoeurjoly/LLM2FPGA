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
- keep StreamTensor-lite as the fast contract-extraction and kernel-comparison
  harness, not as the whole board-fit solution by itself
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

The lane has moved beyond the original monolithic `L2 c_fc` search, and the
execution order has changed accordingly.

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
- Keep tiled `L2 c_fc` as the active StreamTensor-lite reference surface:
  - `task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2-abc9-utilization`
  - `31,907 LUT / 45,932 FF / 4 DSP / 0 BRAM`
  - the seam split showed the wrapper only contributes about `18 LUT` beyond
    the base tile kernel, and one bounded tile-kernel post-branch/output probe
    then trimmed another `553 LUT` / `808 FF` from the tiled `L2` reference
  - this is still `2,047 LUT` over the ceiling, so `L3` remains blocked

Current continuation rule:

- the old helper-micro-surgery loop is closed:
  - the amended one-probe tiled-`L2` follow-up has been spent
  - seam instrumentation was effectively flat
  - one bounded tile-kernel post-branch/output probe improved `L2`, but did
    not clear the ceiling
- do not return to monolithic `64 -> 256` `L2` micro-surgery
- do not promote to `L3` until a new architecture-level result justifies it
- do not make another local `L2 c_fc` RTL edit without a new structural
  hypothesis that is stronger than "another nearby buffer cluster may help"
- the probe plumbing is now consolidated:
  - `rtl/task6/task6_ui64_fifo2_buffer.sv` is the canonical FIFO2 helper
  - `rtl/task6/handshake_buffer_in_ui64_out_ui64_2slots_seq_fifo2.sv` is only
    the legacy wrapper module name
  - local rewrite sites come from
    `nix/task6-ui64-fifo2-site-map.nix` through shared flake helpers instead
    of repeated inline site lists
- the first mixed store-path helper seam is now closed:
  - the combined `fork50`/`fork51`/`fork52` plus ctrl-buffer helper probe
    aborted after only `64` observed stores
  - the narrowed fork-only follow-up reproduced the same `64`-store failure
- do not spend another local `tile64` seam slice on helper substitution in
  this neighborhood
- further `L2 c_fc` RTL work now requires a new structural hypothesis
- execution gate for any future frontier edit:
  - before another `L2 c_fc` RTL experiment, record one short hypothesis note
    in `docs/task6-resource-usage-reduction-notes.md` with:
    - expected dominant cost center
    - expected LUT delta
    - explicit falsifier
  - without that note, only the frozen status-replay surface is allowed

## Mainline Execution Order

The mainline no longer assumes that the next best move is another local
StreamTensor-lite RTL tweak.

1. Finish the `top4-memory` / DDR3 shell evidence.
   - use the existing narrowed external-memory packages and comparison bundles
   - record a final utilization result plus a short bandwidth note
   - treat this as the first architecture-level question because the dominant
     eligible memory blocks are already known and reproducible in this repo
2. Promote quantization from deferred follow-up to a bounded core track.
   - start from `task3-experiments`
   - import only the smallest donor set needed to test one surviving route on
     the same extracted-op proof surfaces
   - require parity with the current StreamTensor-lite proof harness before
     widening scope
3. Run one alternate-lowering comparison on the same extracted contracts.
   - compare the current handshake-heavy path against one bounded alternative
   - do not let this become a broad compiler survey
4. Only if one quantized route survives do we design a new low-bit tile
   kernel.
   - do not keep extending the float32 tile family as the default path

Default kill rule:

- each architecture-level track gets one bounded pass before we decide whether
  it deserves another slice
- if DDR3, quantization import, or alternate lowering does not produce a
  materially better system story quickly, close that path explicitly before
  starting another

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

1. Frozen reference harness
   - keep `just task6-l0`, `just task6-l1`, and `just task6-l2` as the
     status-only replay surface
   - keep the existing packed-weight, contract, and task-graph artifacts as the
     comparison harness for future architecture tracks
   - do not spend more branch effort on runner growth or blocked-rung sweeps

2. DDR3 / `top4-memory` shell evidence
   - use the existing narrowed external-memory packages first
   - close the question with:
     - one reproducible external-memory-plan result
     - one shell utilization result if it completes within a bounded pass
     - one short bandwidth note with explicit assumptions
   - if the narrowed shell still fails late, record the blocker exactly and
     move on instead of widening this loop blindly

3. Quantization bounded replay
   - treat the PT2E-static `tiny-stories-1m` route as the first candidate
   - keep `dynamic-int8` and `torchao` frozen unless importer behavior changes
   - require parity with the existing proof harness before widening scope:
     - extracted-op contract replay first
     - then `yosys-stat`
     - then sim / mapped utilization only if the earlier stages survive

4. Alternate-lowering comparison
   - compare the current handshake-heavy path against one bounded alternative
     on the same extracted contract
   - this is a structural A/B, not a broad compiler survey

5. Stop rule for the whole-model lane
   - once a reduced-vocab `h64` rung exists, the whole-model TinyStories lane
     stays only as a comparison artifact
   - it must not remain the default iteration route for StreamTensor-lite work

## Immediate Mission

Keep the existing narrow proof harness intact while shifting the next execution
steps to the first architecture-level questions:

- can the top four dominant memory tables be externalized into a believable
  DDR3-facing shell story?
- can one surviving quantized route reach the same extracted-op proof surfaces
  as the float StreamTensor-lite harness?
- does one alternate lowering materially reduce control/buffer amplification on
  the same extracted contract?

Required next outputs:

- one closed DDR3 / `top4-memory` evidence bundle
- one bounded quantization replay result on the surviving route
- one bounded alternate-lowering comparison result

## Execution Plan

1. Keep the frozen StreamTensor-lite references as the comparison baseline.
   - `L1`: `task6-l1-c-fc-redirect-index-ring3-postbranch-outbuf-fifo2-abc9`
   - `L2`: `task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2-abc9`
   - `c_proj` stays reserve-only
   - monolithic `L2 c_fc` surgery stays closed

2. Execute one bounded DDR3 / `top4-memory` pass.
   - rebuild the reproducible external-memory plan
   - attempt the narrowed shell utilization path once
   - record the exact stage reached if it does not close
   - include a bandwidth note grounded in the selected-module size

3. Execute one bounded quantization pass.
   - use `tiny-stories-1m` PT2E-static first
   - start from the cheapest comparable stage
   - only widen if it reaches parity with the existing extracted-op harness

4. Execute one bounded alternate-lowering pass.
   - compare one non-default lowering family against the handshake-heavy path
     on the same `L1 c_fc` contract
   - require direct structural comparability and preserved external weights

5. Gate any new kernel design on the quantization result.
   - do not design another float32 tile family as the default next step
   - only start a low-bit tile kernel after one quantized route survives the
     bounded pass above

6. Kill rule.
   - each architecture-level track gets one bounded pass before another slice
     is allowed
   - if a pass does not produce a materially better system story, close it
     explicitly and move on

## Candidate Architecture Experiments

1. `top4-memory` narrowed shell
   - primary architecture experiment
   - externalize the four dominant vocab-sized tables and judge whether the
     shell story is becoming board-credible

2. PT2E-static quantized TinyStories replay
   - primary quantization experiment
   - reuse the existing quantized model route already kept alive in this repo
   - the first extracted-op parity slice is now spent negative:
     - `task6-l1-c-fc-redirect-pt2e-static-torch` is byte-identical to the
       frozen float `torch` export
     - the direct external-weight GEMV stays plain `aten.matmul`
   - keep the broader `tiny-stories-1m` PT2E-static route only as a reference
     surface unless a new extracted-op quant hypothesis appears

3. Alternate-lowering `L1 c_fc` A/B
   - primary structural comparison
   - use exactly the same extracted contract to judge whether handshake/control
     amplification is the dominant residual cost
   - the first bounded LSQ same-contract pass is now spent:
     - mapped LUT improved to `29,329`
     - the identical redirected contract still timed out in Verilator
   - keep this comparison closed unless a stronger lowering hypothesis appears

4. Low-bit tile kernel
   - locked behind a surviving quantized format
   - only start once the arithmetic format question is no longer open

## Open Questions

- What is the minimum believable DDR3 bandwidth assumption for the current
  board-facing shell story?
- Is there any extracted-op boundary that PT2E-static actually quantizes once
  weights are externalized, or does the route collapse back to float on all
  direct StreamTensor-lite kernels?

## Out Of Scope

- full StreamTensor reimplementation
- reopening local FIFO/fork micro-surgery as the default loop
- reopening monolithic `L2 c_fc` surgery
- promoting `L3` before an architecture-level result changes the story
- designing a new low-bit kernel before one quantized route survives
- broad compiler/toolchain redesign instead of bounded A/B comparisons
- reviewer-facing project-plan edits

## Exit Condition

This lane is ready to hand off when it produces one measured architecture-level
conclusion with evidence:

- `helpful`
  - at least one bounded architecture track materially improves the board-fit
    story while preserving the existing proof harness
- `mixed`
  - StreamTensor-lite remains valuable as comparison infrastructure, but the
    winning system story comes from DDR3, quantization, or alternate lowering
- `reject`
  - the branch cannot produce a believable board-facing story without turning
    Task 6 into a broad compiler or hardware retargeting project
