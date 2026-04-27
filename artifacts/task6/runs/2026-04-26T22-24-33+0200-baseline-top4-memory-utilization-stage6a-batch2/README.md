# 2026-04-26 baseline `top4-memory` utilization, `stage6a` batch size 2

Command:

```sh
env 'MONITOR_GLOBAL_PGREP_PATTERN=default-builder.sh|yosys -q -s run.ys|yosys-abc|.yosys-wrapped' \
  scripts/pipeline/monitor_build.sh \
  artifacts/task6/runs/2026-04-26T22-24-33+0200-baseline-top4-memory-utilization-stage6a-batch2 \
  5 -- \
  nix build .#tiny-stories-1m-baseline-float-selftest-top4-memory-utilization \
    --no-link --print-out-paths -L
```

Result:

- exit status: `1`
- wall time: `23229` seconds
- peak sampled `VmRSS`: `29,865,256 KiB`
- peak sampled `VmHWM`: `29,866,344 KiB`
- final logged stage: `stage6a targeted techmap cells_map batch 205/236`
- failure: Yosys worker killed with exit code `137`

Interpretation:

- Reducing `stage6a` restart batch size from `4` to `2` moved the build deeper,
  but did not clear the late `cells_map` frontier.
- Batch `205/236` maps residual `16384 x 32` memory modules
  `\handshake_memory_out_f32_id70` and `\handshake_memory_out_f32_id71`, so the
  next execution step is wider memory externalization rather than only smaller
  batches.
