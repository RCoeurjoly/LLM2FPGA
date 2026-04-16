# Task 6 Eqmap Lane

This worktree owns post-lowering simplification experiments for Task 6.

## Scope

- explore eqmap or nearby simplification passes that reduce logic after lowering
- measure whether simplification changes real FPGA resource usage, not only RTL
  size
- keep comparisons anchored to the copied baseline bundle

## Baseline

Use:

- `artifacts/task6/baselines/tiny-stories-1m-baseline-float-selftest-all-memory-utilization`

Always record:

- which representation was simplified
- what changed in module/cell/resource counts
- whether the simplified result still reaches the same downstream stage

## Immediate TODO

1. Identify where eqmap or equivalent simplification can be inserted in the
   current flow without changing the model semantics.
2. Establish a before/after measurement path using the existing IL and Yosys
   reporting scripts.
3. Separate cosmetic RTL size changes from actual LUT/FF/BRAM/DSP savings.
4. Reject any simplification that improves text size but degrades downstream
   synthesis or timing proxies.

## Questions to answer

- Does eqmap reduce the actual limiting FPGA resource?
- Is the gain large enough to matter relative to quantization or DDR3 use?
- Can the simplification be kept as a local script step, or does it require
  invasive compiler patching?

## Out of scope

- quantization route debugging
- DDR3 / external-memory placement work
- reviewer-facing plan edits

## Exit condition

This lane is ready to merge back when it demonstrates a reproducible resource
delta versus baseline or shows clearly that eqmap is not worth carrying.
