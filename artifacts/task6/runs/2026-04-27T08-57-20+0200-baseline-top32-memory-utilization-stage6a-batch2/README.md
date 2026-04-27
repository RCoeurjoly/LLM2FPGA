# 2026-04-27 baseline `top32-memory` utilization, `stage6a` batch size 2

Command:

```sh
env 'MONITOR_GLOBAL_PGREP_PATTERN=default-builder.sh|yosys -q -s run.ys|yosys-abc|.yosys-wrapped' \
  scripts/pipeline/monitor_build.sh \
  artifacts/task6/runs/2026-04-27T08-57-20+0200-baseline-top32-memory-utilization-stage6a-batch2 \
  5 -- \
  nix build .#tiny-stories-1m-baseline-float-selftest-top32-memory-utilization \
    --no-link --print-out-paths -L
```

Result:

- exit status: `1`
- wall time: `23890` seconds
- peak sampled `VmRSS`: `24,736,208 KiB`
- peak sampled `VmHWM`: `26,633,804 KiB`
- final logged stage: `stage8b abc -luts 2:2,3,6:5,10,20`
- failure: Yosys worker killed with exit code `137`

Interpretation:

- This run cleared `stage6a targeted techmap cells_map` through batch `222/222`.
- That crosses the previous `top4-memory` batch-size-2 OOM point at
  `stage6a` batch `205/236`, so wider memory externalization fixed the
  immediate residual-memory `cells_map` frontier.
- The new blocker is later ABC/LUT mapping in `stage8b`.
