# Task 6 Paper Review Lane

This worktree owns the literature review track for Task 6.

## Scope

- review StreamTensor first for transplantable FPGA-efficiency ideas
- review newer FPGA LLM papers with explicit attention to resource savings
- extract only ideas that can plausibly fit this repo's pipeline and board

## Baseline

Use:

- `artifacts/task6/baselines/tiny-stories-1m-baseline-float-selftest-all-memory-utilization`

Always record:

- the paper's main optimization idea
- the claimed resource or efficiency benefit
- whether the claim is on-chip savings, off-chip memory use, throughput, or a
  mixed metric
- whether the idea looks directly transplantable, adaptable, or not useful here

## Immediate TODO

1. Review StreamTensor for concrete implementation ideas relevant to this repo.
2. Gather a short list of newer FPGA LLM papers and summarize their efficiency
   techniques.
3. For each paper, extract the claimed resource saving, if any.
4. Translate promising ideas into repo-local follow-up candidates instead of
   leaving them as abstract literature notes.

## Questions to answer

- Which paper ideas are most compatible with this flow?
- Which ideas promise real LUT/FF/BRAM/DSP savings versus only throughput?
- Does MoE look practical here, or is it likely a separate model-selection
  path rather than an adaptation of TinyStories 1M?

## Out of scope

- implementing heavy code changes in the synthesis flow
- reviewer-facing plan edits
- treating paper claims as valid without mapping them to this board and repo

## Exit condition

This lane is ready to merge back when it produces a short, prioritized list of
transplantable ideas with explicit expected resource impact and a clear next
experiment for each.
