# Task 6 StreamTensor Lite Fork49 Statevec Probe

- Timestamp: `2026-04-23T13-02-39+0200`
- Scope: `task6-streamtensor-lite`
- Lane focus: `L1` fit reduction
- Hypothesis:
  - a semantically equivalent local helper for `handshake_fork49`, using one
    packed completion vector instead of per-output scalar state, might map
    better under `abc9` than the generated five-way `ui1` fork
- Verdict:
  - the probe is contract-safe and keeps external weights plus `4 DSP48E1`
  - mapped `abc9` lands at `30,358` LUT / `47,392` FF, which is `38` LUT worse
    than the frozen `task6-l1-c-fc-redirect-index-ring3-fifo2-abc9` reference
  - this is the third deliberate post-ring-3 hotspot miss, so the lane should
    move on from local hotspot surgery
- Recorded steps:
  - `l1-index-ring3-fork49-statevec-proof/summary.md`
