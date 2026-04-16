# Overnight Codex Prompt: Quantization Lane

You are working in the `task6-quant` lane for Task 6 resource reduction.

Start here:

- read `AGENTS.md`
- read `docs/task6-lane.md`

Hard constraints:

- do not edit `docs/project-plan*`
- compare every result against
  `artifacts/task6/baselines/tiny-stories-1m-baseline-float-selftest-all-memory-utilization`
- assume this machine is shared with other overnight lanes; do not start more
  than one heavy build at a time from this worktree

Primary goal:

- classify the three full-model quantization routes:
  - `tiny-stories-1m`
  - `tiny-stories-1m-dynamic-int8`
  - `tiny-stories-1m-torchao`

Execution plan:

1. Inspect the current flake/model wiring and confirm which packages and stages
   exist for each route.
2. Use the lightest checks first: `nix eval`, script inspection, and narrow
   builds before broader builds.
3. For each route, determine the first failing stage or farthest successful
   stage.
4. Record whether the route changes the resource story in a meaningful way or
   only changes model representation.
5. Only import additional debug reproducers if the full-model route fails and
   current artifacts are not enough to localize the issue.

Deliverables in this lane:

- create or update `docs/task6-lane-results.md`
- include one section per quantization route
- for each route record:
  - first failing stage
  - current viability: `recommended`, `conditional`, or `reject`
  - baseline comparison
  - extra patch burden

Stop conditions:

- stop after you can classify all three routes, even if some are negative
- if one route is clearly strongest, say so explicitly
- do not drift into DDR3, MoE, or broad RTL cleanup work

Before stopping:

- commit meaningful results on `task6-quant`
- leave the branch clean
