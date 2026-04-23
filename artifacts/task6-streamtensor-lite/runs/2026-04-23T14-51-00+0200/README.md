# Task 6 StreamTensor-lite Run 2026-04-23T14-51-00+0200

## Scope

- Lane:
  - `task6-streamtensor-lite`
- Rung:
  - `L1` reserve fallback kernel start
- Starting reference:
  - `representative-core-v64-h4-c_proj-contract-check.json`
  - exact fallback-boundary replay at line `418` / `%88`
- Goal:
  - turn the validated `mlp.c_proj` fallback boundary into the first redirected
    kernel artifact and judge it on the cheapest inherited gate first

## Steps

- `l1-cproj-redirect-yosys-stat-proof`
  - summary:
    - [summary.md](/home/roland/LLM2FPGA_task6_streamtensor_lite/artifacts/task6-streamtensor-lite/runs/2026-04-23T14-51-00+0200/l1-cproj-redirect-yosys-stat-proof/summary.md)
  - verdict:
    - first redirected kernel compiles
  - result:
    - `17.52 s` `yosys-stat`

## Outcome

- Best result:
  - `task6-l1-c-proj-redirect` is now a live redirected-kernel model, not just
    a fallback-boundary plan item
- Verilator:
  - not run yet for `c_proj`
- Large weights emitted as RTL constants:
  - not checked yet for the redirected kernel
- Yosys stat finished within budget:
  - `yes`
- Next action:
  - add the minimal `L1 c_proj` Verilator and mapped-utilization surfaces and
    stop immediately if they do not preserve the same fast-loop discipline
