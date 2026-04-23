# Task 6 StreamTensor-lite Run 2026-04-23T14-36-13+0200

## Scope

- Lane:
  - `task6-streamtensor-lite`
- Rung:
  - `L2`
- Starting reference:
  - `task6-l2-c-fc-redirect`
  - `50,235 LUT / 65,523 FF / 4 DSP / 0 BRAM`
- Goal:
  - test exactly one bounded `L2`-native downstream `272..280` fit lever after
    the aligned `L1` replay miss before deciding whether `L2 c_fc` should
    continue or pivot to the fallback boundary

## Steps

- `l2-downstream-outbuf-fifo2-proof`
  - summary:
    - [summary.md](/home/roland/LLM2FPGA_task6_streamtensor_lite/artifacts/task6-streamtensor-lite/runs/2026-04-23T14-36-13+0200/l2-downstream-outbuf-fifo2-proof/summary.md)
  - verdict:
    - clean negative local probe
  - result:
    - `51,832 LUT / 64,743 FF / 4 DSP / 0 BRAM`

## Outcome

- Best result:
  - keep the existing `L2` reference, not this local probe
- Verilator:
  - pass
- Large weights emitted as RTL constants:
  - `no`
- Yosys stat finished within budget:
  - `not rerun`
  - accepted `L2` kernel still has a separate `9.13 s` proof
- Next action:
  - stop `L2 c_fc` micro-surgery and pivot within StreamTensor-lite to the
    reserve fallback boundary `mlp.c_proj`
