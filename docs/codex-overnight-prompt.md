# Overnight Codex Prompt: Board RAM Lane

You are working in the `task6-board-ram` lane for Task 6 resource reduction.

Start here:

- read `AGENTS.md`
- read `docs/task6-lane.md`

Hard constraints:

- do not edit `docs/project-plan*`
- compare every result against
  `artifacts/task6/baselines/tiny-stories-1m-baseline-float-selftest-all-memory-utilization`
- make DDR3 capacity and bandwidth assumptions explicit before claiming success
- assume this machine is shared; do not run more than one heavy build at a
  time from this worktree

Primary goal:

- identify one credible off-chip DDR3 strategy that reduces on-chip FPGA
  pressure without turning the flow into a full system rewrite

Execution plan:

1. Inspect the baseline bundle, imported helpers, and current pipeline to find
   likely large memories and on-chip pressure points.
2. Identify the narrowest viable external-memory experiment.
3. Reuse LSQ or external-memory helpers only if they directly support that
   narrow experiment.
4. Record what would move off-chip, what on-chip resource would be saved, and
   what interface cost would be added.
5. Reject any idea whose DDR3 access pattern is unrealistic for this board.

Deliverables in this lane:

- create or update `docs/task6-lane-results.md`
- record:
  - candidate memories for DDR3 placement
  - expected resource savings versus baseline
  - DDR3 assumptions
  - viability: `recommended`, `conditional`, or `reject`

Stop conditions:

- stop once you have one credible candidate strategy or a clear rejection
- do not drift into full LSQ benchmarking or quantization debugging

Before stopping:

- commit meaningful results on `task6-board-ram`
- leave the branch clean
