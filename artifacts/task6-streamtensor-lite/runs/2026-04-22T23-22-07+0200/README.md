# Task6 StreamTensor Lite Run 2026-04-22T23-22-07+0200

- Scope:
  - `L1` redirected-kernel follow-up for `tiny-stories-1m-representative-core-v64-h4`
    at `transformer.h.0.mlp.c_fc`
- Recorded steps:
  - `l1-folded-bias-replay-fail`
  - `l1-explicit-bias-externalization-fail`
  - `l1-kernel-only-proof`
  - `l2-kernel-only-proof`
- Accepted checkpoint:
  - the pre-bias `4 -> 16` redirected kernel keeps weights external, finishes
    `yosys-stat` within budget, maps to `4 DSP48E1`, and passes Verilator with
    `ABS_TOL = 1.0e-4` to account for the visible `q16.16` float primitive path
- Next action:
  - stop spending more time on `L2` kernel plumbing for now and move the next
    slice to the first fit-reduction idea, because `L2` already proves the
    redirect works functionally while also showing a worse fit trend than `L1`
