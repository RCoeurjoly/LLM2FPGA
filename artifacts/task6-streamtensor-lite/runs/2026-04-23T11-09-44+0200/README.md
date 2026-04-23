# Task 6 StreamTensor Lite `abc9` Composition Check

- Timestamp: `2026-04-23T11-09-44+0200`
- Scope: `task6-streamtensor-lite`
- Lane focus: `L1` fit reduction
- Hypothesis:
  - the strongest safe local FIFO2 reduction may stack with the strongest valid
    mapper choice, `abc9`
- Verdict:
  - the selective `160..165` FIFO2 spine does stack with `abc9`
  - the combined result reaches `32,036` LUT / `50,642` FF with `4 DSP48E1`,
    the best `L1` mapped point in the lane so far
- Recorded steps:
  - `l1-index-spine-fifo2-abc9-proof/summary.md`
