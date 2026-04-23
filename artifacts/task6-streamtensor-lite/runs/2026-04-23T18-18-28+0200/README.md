# Task 6 StreamTensor-lite Run 2026-04-23T18-18-28+0200

## Scope

- Lane:
  - `task6-streamtensor-lite`
- Rung:
  - `L2` tiled `64 -> 64` kernel seam follow-up
- Starting reference:
  - `task6-l2-c-fc-redirect-tile64-postbranch-outbuf-fifo2-abc9`
  - `31,968 LUT / 45,928 FF / 4 DSP / 0 BRAM`
- Goal:
  - retest the same local store-path seam with the control buffers left
    untouched, so only the fanout helpers `fork50`, `fork51`, and `fork52`
    change

## Steps

- `l2-tile64-storepath-forks-proof`
  - summary:
    - [summary.md](/home/roland/LLM2FPGA_task6_streamtensor_lite/artifacts/task6-streamtensor-lite/runs/2026-04-23T18-18-28+0200/l2-tile64-storepath-forks-proof/summary.md)
  - verdict:
    - functional rejection
  - result:
    - Verilator again aborts after `64` observed stores instead of `256`

## Outcome

- Best result:
  - keep the existing tiled `L2` reference; the fork-helper-only seam is also
    not a valid drop-in
- Verilator:
  - fail
- Large weights emitted as RTL constants:
  - `no`
- Yosys stat finished within budget:
  - `not rerun`
- Next action:
  - close the current store-path helper seam and require a new structural
    hypothesis before any more local `L2 c_fc` RTL edits
