# 2026-04-26 baseline `top4-memory` utilization, `stage6a` batch size 4

Command:

```sh
env 'MONITOR_GLOBAL_PGREP_PATTERN=default-builder.sh|yosys -q -s run.ys|yosys-abc|.yosys-wrapped' \
  scripts/pipeline/monitor_build.sh \
  artifacts/task6/runs/2026-04-26T02-55-01+0200-baseline-top4-memory-utilization-stage6a-batch4 \
  5 -- \
  nix build .#tiny-stories-1m-baseline-float-selftest-top4-memory-utilization \
    --no-link --print-out-paths -L
```

Result:

- exit status: `1`
- wall time: `20566` seconds
- peak sampled `VmRSS`: `29,808,588 KiB`
- peak sampled `VmHWM`: `29,809,904 KiB`
- final logged stage: `stage6a targeted techmap cells_map batch 103/118`
- failure: Yosys worker killed with exit code `137`

Interpretation:

- Reducing `stage6a` restart batch size from `8` to `4` moved the build deeper,
  but did not clear the heaviest late `cells_map` batches.
- The next execution step is `stage6a` batch size `2`.
