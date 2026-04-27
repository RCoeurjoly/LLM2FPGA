# 2026-04-26 baseline `top4-memory` utilization, `stage6a` batch size 8

Command:

```sh
env 'MONITOR_GLOBAL_PGREP_PATTERN=default-builder.sh|yosys -q -s run.ys|yosys-abc|.yosys-wrapped' \
  scripts/pipeline/monitor_build.sh \
  artifacts/task6/runs/2026-04-26T00-34-00+0200-baseline-top4-memory-utilization-stage6a-batch8 \
  5 -- \
  nix build .#tiny-stories-1m-baseline-float-selftest-top4-memory-utilization \
    --no-link --print-out-paths -L
```

Result:

- exit status: `1`
- wall time: `8393` seconds
- peak sampled `VmRSS`: `30,171,296 KiB`
- peak sampled `VmHWM`: `30,171,664 KiB`
- final logged stage: `stage6a targeted techmap cells_map batch 52/59`
- failure: Yosys worker killed with exit code `137`

Interpretation:

- Reducing `stage6a` restart batch size from `32` to `8` moved the full
  baseline `top4-memory` shell much deeper into the heavy late module range.
- The heaviest late batch still reaches the host memory ceiling, so the next
  execution step is `stage6a` batch size `4`.
