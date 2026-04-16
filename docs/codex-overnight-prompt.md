# Overnight Codex Prompt: LSQ Lane

You are working in the `task6-lsq` lane for Task 6 resource reduction.

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

- determine whether LSQ or related handshake changes produce a better resource
  story than the standard handshake path

Execution plan:

1. Inspect the currently imported scripts, patches, and flake wiring for the
   standard path and any available LSQ path.
2. Identify what is already present versus what would require a minimal Stage C
   import.
3. Design the narrowest possible side-by-side comparison between standard
   handshake and LSQ.
4. Measure whether LSQ reduces the limiting on-chip resource or only shifts
   cost into control logic or interfaces.
5. If the lane is blocked by a missing helper, document the exact missing file
   or patch rather than broadening the scope.

Deliverables in this lane:

- create or update `docs/task6-lane-results.md`
- record:
  - comparison setup
  - what was already available
  - any missing prerequisite
  - resource effect versus baseline
  - viability: `recommended`, `conditional`, or `reject`

Stop conditions:

- stop after a defensible side-by-side conclusion or a clearly documented block
- do not drift into full DDR3 planning or paper survey work

Before stopping:

- commit meaningful results on `task6-lsq`
- leave the branch clean
