# Task 6 StreamTensor Lite Ring-3 Extension

- Timestamp: `2026-04-23T11-24-52+0200`
- Scope: `task6-streamtensor-lite`
- Lane focus: `L1` fit reduction
- Hypothesis:
  - the last still-local hop, the connected `213..219` mux-return ring, may
    clear or nearly clear the remaining LUT gap
- Verdict:
  - the ring-3 cluster still passes the `L1` contract
  - under `abc9`, it reaches `30,320` LUT / `47,392` FF with `4 DSP48E1`,
    leaving only `460` LUT over the ceiling
- Recorded steps:
  - `l1-index-ring3-fifo2-abc9-proof/summary.md`
