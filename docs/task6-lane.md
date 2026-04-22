# Task 6 StreamTensor Lite Lane

This worktree owns the StreamTensor-lite Task 6 lane.

The goal is not to port StreamTensor wholesale. The goal is to test the
smallest architecture change that attacks the actual current bottleneck:
replace full-model RTL expansion with a reusable block-engine direction built
around a narrow GEMV/matvec proof.

## Scope

- keep Torch-MLIR / Linalg as the frontend
- stop treating full-model RTL lowering as the default success path
- target a reusable block-engine direction, not a monolithic whole-model RTL
- use external weights explicitly in the first real experiment
- force a resource signature that moves away from `0 DSP / 0 BRAM`
- prefer the cheapest artifact that answers the current question
- keep this separate from:
  - board-RAM / `top4-memory` shell work
  - quantization follow-up
  - alternate-dialect or LSQ lane work
- reject any version of this lane that turns into a full compiler rewrite

## Source idea

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

## Baseline

Use:

- `artifacts/task6/baselines/tiny-stories-1m-baseline-float-selftest-all-memory-utilization`

Measurement rule for this lane:

- for early experiments, compare the same model and the same stage first
- use representative-core artifacts for the first constrained proof
- prefer pre-RTL structural checkpoints where possible
- replay on the real TinyStories baseline only after the constrained proof
  changes the resource signature or structural shape in the intended direction

Always record:

- exact stage reached or first failing stage
- exact linear / GEMV / block-engine boundary being changed
- stage-stat delta at the same stage
- mapped utilization delta when available
- host wall-clock time and peak memory
- DSP / BRAM / LUT / FF mix before and after the change
- whether the result still looks useful once downstream stages are included

## Immediate Mission

Produce one narrow proof that a single Linalg linear / GEMV op can be
redirected into a small reused kernel that:

- uses externalized weights,
- consumes DSPs,
- avoids full-model RTL expansion as the core story,
- and gives a measurable move away from the current `0 DSP / 0 BRAM` pattern.

Required first output:

- one shortlist memo with:
  - candidate linear / GEMV insertion point
  - cheapest artifact where that region is still identifiable
  - why it can become a reused kernel boundary
  - how weights are externalized in the proof
  - what resource-signature change should appear if the idea is working
  - cheapest validation artifact
  - replay target if the result is helpful

## Execution Plan

1. Freeze the lane thesis.
   - keep Torch-MLIR / Linalg
   - do not pursue a full-model RTL lowering victory condition here
   - treat external weights plus a reused kernel as the primary architectural
     hypothesis

2. Isolate one candidate linear / GEMV region.
   - begin with `tiny-stories-1m-representative-core-v64-h4`
   - move to a larger representative-core sweep point only if the region is not
     structurally meaningful there
   - prefer a point where the boundary is still obvious in Linalg, or at worst
     in a nearby lower-level representation that is still mechanically
     transformable

3. Define the first reusable-kernel proof.
   - choose one linear / GEMV-shaped op or short subgraph
   - define a tiny task graph around it
   - keep activations on-chip and model weights as external inputs
   - require the implementation direction to be DSP-backed rather than
     all-fabric arithmetic

4. Implement the narrow redirection.
   - build the smallest possible proof that the chosen region can stop behaving
     like generic expanded RTL and start behaving like an invoked reusable
     kernel boundary
   - accept a synthetic or constrained first demo if it preserves the
     architectural point

5. Judge by resource signature first.
   - the first pass/fail question is not token throughput
   - it is whether the proof moves the design away from `0 DSP / 0 BRAM`
   - if that does not happen, the StreamTensor-lite thesis weakens immediately

6. Promote or prune.
   - replay on the real TinyStories baseline only if the constrained proof is
     structurally credible and changes the mix in the intended direction
   - prune if the lane requires whole-compiler surgery before one linear / GEMV
     proof works

## Candidate First Experiments

1. Single Linalg linear / GEMV redirection
   - prove that one representative linear op can be carved out of the current
     flow and redirected into a reused kernel boundary
   - weights become explicit external inputs
   - the success signal is visible DSP usage and a less fabric-heavy structure

2. Single-block task-graph proof
   - keep one transformer-style block boundary but only as a control/task graph
     sketch
   - do not lower the whole block into generic RTL
   - use this only if the single-linear proof needs one level of surrounding
     context to stay meaningful

3. Bounded activation buffering around the reused kernel
   - add FIFO or ping-pong buffering only as support for the GEMV proof
   - do not make generic buffering the primary experiment

## Questions To Answer

- Which exact TinyStories linear / GEMV region is the best first reused-kernel
  candidate?
- At what representation level can that region still be redirected cleanly?
- Can the first proof consume DSPs and externalized weights without collapsing
  back into generic RTL expansion?
- Which representative-core sweep point is the first one large enough to make
  that proof credible?

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
  - one local linear / GEMV redirection produces a credible reused-kernel proof
    with external weights and a better resource signature, and is worth replaying
    on the real baseline
- `mixed`
  - the idea only works in a constrained demo without a believable replay path
- `reject`
  - the idea cannot redirect one narrow linear / GEMV region without turning
    Task 6 into a compiler-rewrite project
