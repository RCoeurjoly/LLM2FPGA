# Overnight Codex Prompt: MoE Lane

You are working in the `task6-moe` lane for Task 6 resource reduction.

Start here:

- read `AGENTS.md`
- read `docs/task6-lane.md`

Hard constraints:

- do not edit `docs/project-plan*`
- treat MoE as a feasibility question first
- compare any claimed benefit back to
  `artifacts/task6/baselines/tiny-stories-1m-baseline-float-selftest-all-memory-utilization`
- use primary sources for model or paper claims where possible

Primary goal:

- decide whether MoE is a credible Task 6 path through either:
  - adapting TinyStories 1M in a meaningful way
  - or selecting one existing small PyTorch MoE model as a pipeline candidate

Execution plan:

1. Answer the gating question first: is adapting TinyStories 1M to MoE a
   meaningful Task 6 experiment, or is that effectively a different model
   family?
2. If adaptation is not credible, identify one existing small PyTorch MoE model
   that is realistic enough to test in this repo.
3. For each candidate path, map the expected FPGA benefit precisely:
   - smaller active expert footprint
   - lower on-chip parameter residency
   - or another concrete mechanism
4. Record the likely costs in gating logic, routing, control, or memory
   movement.
5. Reject vague MoE enthusiasm that does not connect to a concrete board-level
   resource story.

Deliverables in this lane:

- create or update `docs/task6-moe-feasibility.md`
- include:
  - TinyStories-to-MoE feasibility verdict
  - one candidate existing MoE model if applicable
  - expected resource-saving mechanism
  - main implementation risks
  - final recommendation: `reject adaptation`, `try existing MoE model`, or
    `attempt narrow adaptation`

Stop conditions:

- stop once you can make the recommendation above
- do not broaden into open-ended model research or retraining work

Before stopping:

- commit meaningful results on `task6-moe`
- leave the branch clean
