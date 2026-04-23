# Task 6 StreamTensor-lite Run 2026-04-23T18-14-40+0200

## Scope

- Lane:
  - `task6-streamtensor-lite`
- Rung:
  - `L2` tiled `64 -> 64` kernel seam probe
- Starting reference:
  - `task6-l2-c-fc-redirect-tile64-postbranch-outbuf-fifo2-abc9`
  - `31,968 LUT / 45,928 FF / 4 DSP / 0 BRAM`
- Goal:
  - test whether the remaining tiled `L2` gap sits in the untouched mixed
    store-path fanout state around `fork50`, `fork51`, `fork52`, and the local
    zero-width control buffers

## Steps

- `l2-tile64-storepath-forkctrl-proof`
  - summary:
    - [summary.md](/home/roland/LLM2FPGA_task6_streamtensor_lite/artifacts/task6-streamtensor-lite/runs/2026-04-23T18-14-40+0200/l2-tile64-storepath-forkctrl-proof/summary.md)
  - verdict:
    - functional rejection
  - result:
    - Verilator aborts after `64` observed stores instead of `256`

## Outcome

- Best result:
  - keep the existing tiled `L2` reference; this seam-cluster helper is not a
    valid drop-in
- Verilator:
  - fail
- Large weights emitted as RTL constants:
  - `no`
- Yosys stat finished within budget:
  - `not rerun`
- Next action:
  - if the same seam is probed again, keep the zero-width control buffers
    untouched and isolate the fork-state helpers only
