# Task 6 StreamTensor Lite Selective Buffer Proof

- Timestamp: `2026-04-23T10-59-21+0200`
- Scope: `task6-streamtensor-lite`
- Lane focus: `L1` fit reduction
- Hypothesis:
  - class-wide `ui64` buffer replacement is too disruptive
  - a small selective replacement on the loop-index distribution spine may keep
    the kernel contract while still trimming mapped area
- Verdict:
  - replacing only `handshake_buffer165` with the lean FIFO2 buffer passes the
    `L1` contract and slightly reduces mapped area
- Recorded steps:
  - `l1-buffer165-fifo2-proof/summary.md`
