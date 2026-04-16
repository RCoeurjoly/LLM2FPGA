# Task 6 Board RAM Lane

This worktree owns on-board DDR3 resource reduction experiments for Task 6.

## Scope

- use the board's 2 Gb DDR3 as a first-class resource
- identify weights, activations, or buffers that can move off-chip to reduce
  on-chip FPGA pressure
- record capacity and bandwidth assumptions explicitly before claiming success

## Baseline

Use:

- `artifacts/task6/baselines/tiny-stories-1m-baseline-float-selftest-all-memory-utilization`

Always record:

- what moved off-chip
- the on-chip resource delta versus baseline
- the assumed DDR3 capacity and bandwidth story
- any interface, latency, or controller cost added by the change

## Immediate TODO

1. Inspect the current baseline and imported pipeline helpers to find which
   memories are likely still consuming on-chip resources.
2. Identify the narrowest viable external-memory experiment, not a full system
   rewrite.
3. Reuse the LSQ / external-memory helpers only when they directly support the
   chosen off-chip memory path.
4. Reject any approach that saves BRAM but creates an unrealistic DDR3 access
   pattern for this board.

## Questions to answer

- Which memories are the best first candidates for off-chip placement?
- What is the expected on-chip resource saving?
- Is the DDR3 bandwidth story plausible for inference, not only for storage?

## Out of scope

- quantization route debugging
- eqmap or general RTL cleanup work
- reviewer-facing plan edits

## Exit condition

This lane is ready to merge back when it presents a credible off-chip memory
strategy with explicit resource savings and explicit DDR3 assumptions.
