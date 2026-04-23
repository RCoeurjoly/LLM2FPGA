# Task 6 StreamTensor-lite Run 2026-04-23T14-23-08+0200

## Scope

- Lane:
  - `task6-streamtensor-lite`
- Rung:
  - `L2`
- Starting reference:
  - `task6-l1-c-fc-redirect-index-ring3-postbranch-outbuf-fifo2-abc9`
  - `29,778 LUT / 46,352 FF / 4 DSP / 0 BRAM`
- Goal:
  - replay the new `L1` post-branch fit lever on `L2` using the smallest
    structurally aligned subset of the generated SV

## Steps

- `l2-postbranch-fifo2-proof`
  - summary:
    - [summary.md](/home/roland/LLM2FPGA_task6_streamtensor_lite/artifacts/task6-streamtensor-lite/runs/2026-04-23T14-23-08+0200/l2-postbranch-fifo2-proof/summary.md)
  - verdict:
    - clean negative replay
  - result:
    - `51,622 LUT / 64,873 FF / 4 DSP / 0 BRAM`

## Outcome

- Best result:
  - keep the existing `L2` reference, not this replay
- Verilator:
  - pass
- Large weights emitted as RTL constants:
  - `no`
- Yosys stat finished within budget:
  - `not rerun`
  - accepted `L2` kernel still has a separate `9.13 s` proof
- Next action:
  - do not widen this exact replay; if `L2` work continues, target the changed
    `272..280` neighborhood rather than reusing the `L1` patch literally
