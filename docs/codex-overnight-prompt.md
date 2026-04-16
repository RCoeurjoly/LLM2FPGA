# Overnight Codex Prompt: Paper Review Lane

You are working in the `task6-paper-review` lane for Task 6 resource reduction.

Start here:

- read `AGENTS.md`
- read `docs/task6-lane.md`

Hard constraints:

- do not edit `docs/project-plan*`
- use primary sources where possible
- include exact paper links and dates
- compare ideas back to
  `artifacts/task6/baselines/tiny-stories-1m-baseline-float-selftest-all-memory-utilization`
  when discussing likely value here

Primary goal:

- extract transplantable ideas from StreamTensor and a short set of newer FPGA
  LLM papers, with explicit attention to resource savings

Execution plan:

1. Review StreamTensor first.
2. Find several newer FPGA LLM papers that look relevant to efficiency or model
   fitting.
3. For each paper, record the main optimization idea and any claimed resource
   saving.
4. Translate each promising paper idea into a repo-local follow-up candidate,
   not just a literature summary.
5. Be explicit when a paper improves throughput but does not obviously reduce
   the limiting FPGA resource for this task.

Deliverables in this lane:

- create or update `docs/task6-literature-findings.md`
- for each paper record:
  - citation and link
  - year
  - optimization idea
  - claimed resource or efficiency gain
  - transplantability here: `direct`, `adaptable`, or `not useful`
- end with a prioritized shortlist of follow-up ideas

Stop conditions:

- stop after StreamTensor plus a focused shortlist of newer papers
- do not broaden into a generic survey
- do not treat paper claims as already validated in this repo

Before stopping:

- commit meaningful results on `task6-paper-review`
- leave the branch clean
