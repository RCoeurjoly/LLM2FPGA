# Task 6 StreamTensor Lite Fanout-Ring Extension

- Timestamp: `2026-04-23T11-14-57+0200`
- Scope: `task6-streamtensor-lite`
- Lane focus: `L1` fit reduction
- Hypothesis:
  - the safe selective FIFO2 region may extend one hop beyond the `160..165`
    index spine into the immediate `173..182` branch-output fanout
- Verdict:
  - the adjacent fanout ring still passes the `L1` contract
  - under `abc9`, that wider local cluster reaches `31,309` LUT / `49,342` FF
    with `4 DSP48E1`, the best `L1` mapped point so far
- Recorded steps:
  - `l1-index-fanout-fifo2-abc9-proof/summary.md`
