# Task 6 StreamTensor-lite Run 2026-04-23T15-01-29+0200

## Scope

- Lane:
  - `task6-streamtensor-lite`
- Rung:
  - `L1` reserve fallback executable proof
- Starting reference:
  - `task6-l1-c-proj-redirect-yosys-stat`
  - `17.52 s` micro-proof
- Goal:
  - add the minimal Verilator and mapped-utilization surfaces for the new
    `L1 c_proj` redirected kernel and decide whether it is lane-worthy

## Steps

- `l1-cproj-redirect-proof`
  - summary:
    - [summary.md](/home/roland/LLM2FPGA_task6_streamtensor_lite/artifacts/task6-streamtensor-lite/runs/2026-04-23T15-01-29+0200/l1-cproj-redirect-proof/summary.md)
  - verdict:
    - valid executable fallback proof, not a fit win
  - result:
    - `32,393 LUT / 50,864 FF / 4 DSP / 0 BRAM`

## Outcome

- Best result:
  - `L1 c_proj` is now a real executable reserve path
- Verilator:
  - pass
- Large weights emitted as RTL constants:
  - `no`
- Yosys stat finished within budget:
  - `yes`
- Next action:
  - run one cheap direct `abc9` check on the same untouched kernel before
    deciding whether `c_proj` deserves any real optimization work
