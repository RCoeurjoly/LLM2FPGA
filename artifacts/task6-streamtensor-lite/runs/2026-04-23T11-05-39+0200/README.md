# Task 6 StreamTensor Lite Buffer Spine Follow-up

- Timestamp: `2026-04-23T11-05-39+0200`
- Scope: `task6-streamtensor-lite`
- Lane focus: `L1` fit reduction
- Hypothesis:
  - whole-class `ui64` buffer replacement should be stopped if a third variant
    still breaks the kernel contract
  - a wider but still local FIFO2 replacement on the loop-index distribution
    spine may preserve functionality and cut more mapped area than the single
    `buffer165` replacement
- Verdict:
  - the third whole-class FIFO2 attempt failed and closes that path
  - the safe local `160..165` spine replacement passes Verilator and trims
    mapped area to `32,808` LUT / `50,642` FF with `4 DSP48E1`
- Recorded steps:
  - `l1-ui64-buffer-fifo2-reject/summary.md`
  - `l1-index-spine-fifo2-proof/summary.md`
