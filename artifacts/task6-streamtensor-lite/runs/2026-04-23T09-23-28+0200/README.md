# Task 6 StreamTensor Lite Mapper Check

- Timestamp: `2026-04-23T09-23-28+0200`
- Scope: `task6-streamtensor-lite`
- Lane focus: `L1` fit reduction, with `L0` as the control
- Hypothesis:
  - direct `synth_xilinx -abc9` might reduce the accepted `L1` kernel enough to
    matter for the fit-first lane
  - if the staged IL `abc9` flow also works on the micro-kernel, it might beat
    the direct SV mapping path
- Verdict:
  - direct `abc9` is a real but insufficient `L1` improvement
  - staged `abc9` fails before mapped JSON generation
- Recorded steps:
  - `l1-abc9-mapper-check/summary.md`
  - `l1-staged-abc9-fail/summary.md`
  - `l1-ui64-buffer-lite-diagnostic/summary.md`
