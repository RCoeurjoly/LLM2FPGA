# Task 6 StreamTensor Lite Selector Cluster Probe

- Timestamp: `2026-04-23T13-13-00+0200`
- Scope: `task6-streamtensor-lite`
- Lane focus: `L1` fit reduction
- Hypothesis:
  - collapsing the local selector-side `buffer255 -> fork46` leg into one
    helper with an init-0 token and a tiny FIFO might reduce LUT more than the
    earlier one-site buffer or fork swaps
- Verdict:
  - the probe is contract-safe and keeps external weights plus `4 DSP48E1`
  - mapped `abc9` lands at `30,358` LUT / `47,392` FF, tying the earlier
    `fork49` statevec helper and still missing the frozen
    `task6-l1-c-fc-redirect-index-ring3-fifo2-abc9` reference by `38` LUT
  - this closes the selector-control tree as the next fit lever
- Recorded steps:
  - `l1-index-ring3-selectcluster-fifo2-proof/summary.md`
