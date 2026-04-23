# Task 6 StreamTensor Lite Deliberate Hotspot And One-Block Gate

- Timestamp: `2026-04-23T12-36-17+0200`
- Scope: `task6-streamtensor-lite`
- Lane focus: `L1` fit reduction, then `L2` promotion gate
- Hypothesis:
  - after freezing `task6-l1-c-fc-redirect-index-ring3-fifo2-abc9`, one
    deliberate nearby control/merge hotspot might beat the remaining `460` LUT
    gap without another blind ring expansion
  - after that single hotspot pass, the pending one-block-top Yosys gate should
    run before any `L3` or `L4` promotion decision
- Verdict:
  - the `194/220` and `229/237` control/merge hotspot is contract-safe but
    regresses LUT from `30,320` to `30,360`, so the frozen ring-3 point remains
    the `L1` reference
  - the reduced-vocab one-block-top Yosys gate completes in `99.26 s`, which
    clears the `< 2 min` budget, but it does not justify promotion because the
    best frozen `L1` fit point still misses the LUT ceiling
- Recorded steps:
  - `l1-index-ring3-ctrlmerge-fifo2-proof/summary.md`
  - `l1-one-block-top-yosys-gate/summary.md`

