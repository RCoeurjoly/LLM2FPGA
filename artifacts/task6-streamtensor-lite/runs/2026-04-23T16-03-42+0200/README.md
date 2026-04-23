# Task 6 StreamTensor-lite Run 2026-04-23T16-03-42+0200

## Scope

- Lane:
  - `task6-streamtensor-lite`
- Rung:
  - `L2`
- Starting reference:
  - `task6-l2-c-fc-redirect`
  - `50,235 LUT / 65,523 FF / 4 DSP / 0 BRAM`
- Goal:
  - test the bounded structural hypothesis that a sequential `4 x 64` wrapper
    around one reused external-weight `64 -> 64` kernel beats the monolithic
    `L2` `64 -> 256` wrapper while preserving the same top-level contract

## Steps

- `l2-cfc-tile4x64-proof`
  - summary:
    - [summary.md](/home/roland/LLM2FPGA_task6_streamtensor_lite/artifacts/task6-streamtensor-lite/runs/2026-04-23T16-03-42+0200/l2-cfc-tile4x64-proof/summary.md)
  - verdict:
    - positive structural hit, still above the final LUT ceiling
  - result:
    - `32,460 LUT / 46,740 FF / 4 DSP / 0 BRAM`

## Outcome

- Best result:
  - `task6-l2-c-fc-redirect-tile4x64-abc9-utilization` becomes the new `L2`
    reference
- Verilator:
  - pass
- Large weights emitted as RTL constants:
  - `no`
- Yosys stat finished within budget:
  - `yes`
  - `16.09 s` on `task6-l2-c-fc-redirect-tile64-yosys-stat`
- Next action:
  - keep the tiled wrapper as the official `L2` reference and, if continuing on
    `L2 c_fc`, spend at most one more bounded probe on the reusable `64 -> 64`
    tile kernel or the tile/wrapper seam
