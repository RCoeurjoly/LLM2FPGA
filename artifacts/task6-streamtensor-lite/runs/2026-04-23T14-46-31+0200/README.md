# Task 6 StreamTensor-lite Run 2026-04-23T14-46-31+0200

## Scope

- Lane:
  - `task6-streamtensor-lite`
- Rung:
  - fallback boundary scout after `L2 c_fc` closed
- Starting reference:
  - `task6-l2-c-fc-redirect`
  - `50,235 LUT / 65,523 FF / 4 DSP / 0 BRAM`
- Goal:
  - validate that the reserve fallback boundary `transformer.h.0.mlp.c_proj`
    can reuse the same lightweight pack-and-contract artifact path before
    spending on a new redirected kernel

## Steps

- `cproj-fallback-scout`
  - summary:
    - [summary.md](/home/roland/LLM2FPGA_task6_streamtensor_lite/artifacts/task6-streamtensor-lite/runs/2026-04-23T14-46-31+0200/cproj-fallback-scout/summary.md)
  - verdict:
    - fallback boundary validated
  - result:
    - exact packed replay on both `L1` and `L2`

## Outcome

- Best result:
  - `mlp.c_proj` is now a real reserve fallback boundary, not just a plan item
- Verilator:
  - not run yet for `c_proj`
- Large weights emitted as RTL constants:
  - not applicable yet; this step stopped at external pack plus contract replay
- Yosys stat finished within budget:
  - not run yet for `c_proj`
- Next action:
  - build the first redirected `c_proj` kernel at `L1`, then replay only if the
    same fast-loop gates stay honest
