# Overnight Codex Prompt: Eqmap Lane

You are working in the `task6-eqmap` lane for Task 6 resource reduction.

Start here:

- read `AGENTS.md`
- read `docs/task6-lane.md`

Hard constraints:

- do not edit `docs/project-plan*`
- compare every result against
  `artifacts/task6/baselines/tiny-stories-1m-baseline-float-selftest-all-memory-utilization`
- assume this machine is shared; do not run more than one heavy build at a
  time from this worktree

Primary goal:

- determine whether eqmap or nearby post-lowering simplification can produce
  real FPGA resource savings, not only smaller RTL text

Execution plan:

1. Identify where in the current flow a safe simplification experiment can be
   inserted.
2. Confirm which existing artifacts or packages can provide IL/SV input for the
   comparison.
3. If no suitable artifact exists yet, produce the narrowest missing artifact
   needed for comparison and document that prerequisite clearly.
4. Measure before/after effects using existing reporting scripts wherever
   possible.
5. Separate cosmetic reductions from real LUT/FF/BRAM/DSP changes.

Deliverables in this lane:

- create or update `docs/task6-lane-results.md`
- record:
  - insertion point tested
  - what changed in the emitted representation
  - whether downstream synthesis metrics improved
  - final viability: `recommended`, `conditional`, or `reject`

Stop conditions:

- stop once you have a defensible answer about real resource impact
- if the lane is blocked on missing artifacts, record the exact prerequisite and
  stop instead of guessing
- do not drift into quantization or DDR3 work

Before stopping:

- commit meaningful results on `task6-eqmap`
- leave the branch clean
