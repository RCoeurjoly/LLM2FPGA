# Task 6 StreamTensor Lite UI1 Selector Buffer Probe

- Timestamp: `2026-04-23T12-49-10+0200`
- Scope: `task6-streamtensor-lite`
- Lane focus: `L1` fit reduction
- Hypothesis:
  - a single selector-side `ui1` buffer trim at `handshake_buffer263`, the
    local compare result feeding `handshake_fork49`, might recover LUT without
    another `ui64` branch expansion
- Verdict:
  - the probe is contract-safe and keeps external weights plus `4 DSP48E1`
  - mapped `abc9` lands at `30,370` LUT / `47,388` FF, which is `50` LUT worse
    than the frozen `task6-l1-c-fc-redirect-index-ring3-fifo2-abc9` reference
- Recorded steps:
  - `l1-index-ring3-ui1buf263-fifo2-proof/summary.md`

