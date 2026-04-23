# Task 6 StreamTensor-lite Run 2026-04-23T13-55-32+0200

## Scope

- Lane:
  - `task6-streamtensor-lite`
- Rung:
  - `L1`
- Starting reference:
  - `task6-l1-c-fc-redirect-index-ring3-fifo2-abc9`
  - `30,320 LUT / 47,392 FF / 4 DSP / 0 BRAM`
- Goal:
  - test exactly one or two bounded non-selector fit levers after the
    selector/control ring-3 branch was closed

## Steps

- `l1-index-ring3-postbranch-fifo2-proof`
  - summary:
    - [summary.md](/home/roland/LLM2FPGA_task6_streamtensor_lite/artifacts/task6-streamtensor-lite/runs/2026-04-23T13-55-32+0200/l1-index-ring3-postbranch-fifo2-proof/summary.md)
  - verdict:
    - productive non-selector hit
  - result:
    - `29,967 LUT / 46,612 FF / 4 DSP / 0 BRAM`
- `l1-index-ring3-postbranch-outbuf-fifo2-proof`
  - summary:
    - [summary.md](/home/roland/LLM2FPGA_task6_streamtensor_lite/artifacts/task6-streamtensor-lite/runs/2026-04-23T13-55-32+0200/l1-index-ring3-postbranch-outbuf-fifo2-proof/summary.md)
  - verdict:
    - ceiling-clearing `L1` reference
  - result:
    - `29,778 LUT / 46,352 FF / 4 DSP / 0 BRAM`

## Outcome

- Best result:
  - `task6-l1-c-fc-redirect-index-ring3-postbranch-outbuf-fifo2-abc9`
- Verilator:
  - pass on both probes
- Large weights emitted as RTL constants:
  - `no`
- Yosys stat finished within budget:
  - `yes`, unchanged at `4.07 s`
- Next action:
  - replay the new `L1` reference on `L2` before any `L3` promotion
