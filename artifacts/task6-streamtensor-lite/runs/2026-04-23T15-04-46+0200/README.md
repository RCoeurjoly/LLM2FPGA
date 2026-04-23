# Task 6 StreamTensor-lite Run 2026-04-23T15-04-46+0200

## Scope

- Lane:
  - `task6-streamtensor-lite`
- Rung:
  - `L1` reserve fallback mapper discriminator
- Starting reference:
  - `task6-l1-c-proj-redirect`
  - `32,393 LUT / 50,864 FF / 4 DSP / 0 BRAM`
- Goal:
  - run exactly one cheap mapper-only check on the untouched `L1 c_proj`
    redirected kernel before deciding whether it stays active or reserve-only

## Steps

- `l1-cproj-redirect-abc9-proof`
  - summary:
    - [summary.md](/home/roland/LLM2FPGA_task6_streamtensor_lite/artifacts/task6-streamtensor-lite/runs/2026-04-23T15-04-46+0200/l1-cproj-redirect-abc9-proof/summary.md)
  - verdict:
    - helpful mapper drop, still reserve-only
  - result:
    - `31,611 LUT / 50,864 FF / 4 DSP / 0 BRAM`

## Outcome

- Best result:
  - `abc9` improves `L1 c_proj`, but not enough to beat the frozen `L1 c_fc`
    reference
- Verilator:
  - inherited pass from the base `L1 c_proj` proof
- Large weights emitted as RTL constants:
  - `no`
- Yosys stat finished within budget:
  - inherited pass at `17.52 s`
- Next action:
  - keep `c_proj` reserve-only and continue to treat the frozen `L1 c_fc`
    reference as the main fit-first proof
