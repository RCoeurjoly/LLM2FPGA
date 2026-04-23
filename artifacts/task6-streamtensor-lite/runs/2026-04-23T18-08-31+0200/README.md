# Task 6 StreamTensor-lite Run 2026-04-23T18-08-31+0200

## Scope

- Lane:
  - `task6-streamtensor-lite`
- Rung:
  - infrastructure validation for the active `L1` and tiled `L2` references
- Starting references:
  - `task6-l1-c-fc-redirect-index-ring3-postbranch-outbuf-fifo2-abc9`
  - `29,778 LUT / 46,352 FF / 4 DSP / 0 BRAM`
  - `task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2-abc9-utilization`
  - `31,907 LUT / 45,932 FF / 4 DSP / 0 BRAM`
- Goal:
  - consolidate the `ui64` FIFO2 probe plumbing to one canonical helper plus a
    small site map, then prove the accepted reference metrics and the legacy
    class-wide wrapper path stay unchanged

## Steps

- `plumbing-cleanup-validation`
  - summary:
    - [summary.md](/home/roland/LLM2FPGA_task6_streamtensor_lite/artifacts/task6-streamtensor-lite/runs/2026-04-23T18-08-31+0200/plumbing-cleanup-validation/summary.md)
  - verdict:
    - no-regression infrastructure checkpoint
  - result:
    - legacy class-wide wrapper still builds at `23,161 LUT / 27,591 FF / 4 DSP / 0 BRAM`
    - frozen `L1` reference remains `29,778 LUT / 46,352 FF / 4 DSP / 0 BRAM`
    - active tiled `L2` reference remains `31,907 LUT / 45,932 FF / 4 DSP / 0 BRAM`

## Outcome

- Best result:
  - keep the existing frozen `L1` and tiled `L2` references unchanged
- Verilator:
  - pass on the active tiled `L2` reference via direct rerun
- Large weights emitted as RTL constants:
  - `no`
- Yosys stat finished within budget:
  - `not rerun`
  - this checkpoint only validates the probe-plumbing refactor
- Next action:
  - spend the next bounded `L2` probe on the remaining mixed data/control
    store-path seam in the `tile64` kernel, not on another `ui64` buffer-only
    rewrite
