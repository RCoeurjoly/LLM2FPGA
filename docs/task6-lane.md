# Task 6 LSQ Lane

This worktree owns handshake, LSQ, and nearby external-memory lowering
experiments for Task 6.

## Scope

- compare the standard handshake path against LSQ-based alternatives
- reuse the imported LSQ-oriented pipeline pieces only where they directly help
  reduce resource pressure
- evaluate whether LSQ changes real FPGA usage or only moves complexity around

## Baseline

Use:

- `artifacts/task6/baselines/tiny-stories-1m-baseline-float-selftest-all-memory-utilization`

Always record:

- first failing stage
- resource deltas versus baseline
- any added compiler patch or script burden
- whether the change also depends on external memory assumptions

## Immediate TODO

1. Identify the narrowest comparison between the standard handshake path and an
   LSQ-enabled path in the current imported pipeline.
2. Confirm which scripts and patches are already present and which still need a
   targeted Stage C import.
3. Measure whether LSQ lowers the limiting on-chip resource or merely shifts
   the cost to interfaces and control logic.
4. Keep the first experiment small enough that a negative result is still
   informative.

## Questions to answer

- Is handshake really one of the dominant resource drivers in this flow?
- Does LSQ improve the resource story enough to justify the added complexity?
- Does LSQ become more compelling only when combined with on-board DDR3 use?

## Out of scope

- quantization route debugging
- pure paper survey work
- reviewer-facing plan edits

## Exit condition

This lane is ready to merge back when it shows a clear side-by-side result for
standard handshake versus LSQ, with explicit baseline comparison and patch
burden.
