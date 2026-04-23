# L1 `c_proj` Redirect `abc9`

## Commands

- `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-proj-redirect-abc9-utilization --no-link --print-out-paths -L`

## Logs

- [abc9-utilization.log](/home/roland/LLM2FPGA_task6_streamtensor_lite/artifacts/task6-streamtensor-lite/runs/2026-04-23T15-04-46+0200/l1-cproj-redirect-abc9-proof/abc9-utilization.log)

## Metrics

- DSP:
  - `4`
- BRAM36:
  - `0`
- LUT:
  - `31,611`
- FF:
  - `50,864`
- Large weights emitted as RTL constants:
  - `no`
- `abc9` wall-clock / RSS:
  - `143.08 s` / `563,156 KB`
- Delta vs base `L1 c_proj` redirect:
  - `LUT -782`
  - `FF +0`
- Delta vs frozen `L1 c_fc` reference:
  - `LUT +1,833`
  - `FF +4,512`

## Verdict

- Direct `abc9` does help the untouched `L1 c_proj` redirect, but not enough.
- The fallback remains structurally valid and reproducible, yet it still trails
  the frozen `L1 c_fc` reference on the official fit metric.

## Next Action

- Keep `c_proj` as a validated reserve fallback and do not switch the main lane
  away from the frozen `L1 c_fc` reference on mapper-only evidence.
