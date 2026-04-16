# Task 6 MoE Lane

This worktree owns Mixture of Experts exploration for Task 6.

## Scope

- treat MoE as a feasibility-first strategy, not an immediate implementation
  commitment
- determine whether TinyStories 1M can be adapted to an MoE-style inference
  path in a way that is meaningful for this repo
- if not, identify one existing small MoE model in PyTorch format that is a
  credible pipeline candidate

## Baseline

Use:

- `artifacts/task6/baselines/tiny-stories-1m-baseline-float-selftest-all-memory-utilization`

Always record:

- whether the comparison is against TinyStories 1M, another candidate model, or
  only a paper claim
- the expected resource-saving mechanism
- the likely cost in routing, control, memory traffic, or compiler complexity

## Immediate TODO

1. Answer the first gating question: can TinyStories 1M be meaningfully adapted
   to MoE for this task, or is that effectively a different model family?
2. If the answer is no or unclear, identify one small existing PyTorch MoE
   model that could plausibly be processed by this repo.
3. Map the expected FPGA benefit precisely:
   - smaller active expert footprint
   - reduced on-chip parameter residency
   - or some other mechanism
4. Reject vague MoE enthusiasm unless it connects to a concrete resource-saving
   story for this board and flow.

## Questions to answer

- Can TinyStories 1M itself be adapted to MoE in a way that still answers Task
  6, or would that be a separate model-selection experiment?
- Would MoE reduce the limiting FPGA resource here, or mostly shift cost into
  gating, routing, and memory movement?
- Is MoE likely more promising combined with DDR3 use than as a standalone
  strategy?

## Out of scope

- broad retraining or model research without a clear repo-facing experiment
- reviewer-facing plan edits
- treating MoE papers as applicable without checking the actual pipeline impact

## Exit condition

This lane is ready to merge back when it produces a clear recommendation:

- `reject TinyStories-to-MoE adaptation`
- `try existing small PyTorch MoE model`
- or `attempt narrow MoE adaptation path`

That recommendation must include the expected resource-saving mechanism and the
main implementation risk.
