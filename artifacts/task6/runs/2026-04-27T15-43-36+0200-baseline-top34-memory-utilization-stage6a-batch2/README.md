# 2026-04-27 baseline `top34-memory` utilization, `stage6a` batch size 2

Command:

```sh
env 'MONITOR_GLOBAL_PGREP_PATTERN=default-builder.sh|yosys -q -s run.ys|yosys-abc|.yosys-wrapped' \
  scripts/pipeline/monitor_build.sh \
  artifacts/task6/runs/2026-04-27T15-43-36+0200-baseline-top34-memory-utilization-stage6a-batch2 \
  5 -- \
  nix build .#tiny-stories-1m-baseline-float-selftest-top34-memory-utilization \
    --no-link --print-out-paths -L
```

Result:

- run status: interrupted or abandoned before monitor completion
- checked at: `2026-04-27T16:28:57+02:00`
- active `nix` / `yosys` process at check time: none
- final logged stage: `stage6a targeted techmap cells_map batch 16/221`
- completion summary from monitor: absent

Interpretation:

- This artifact is retained only to explain the partial `top34-memory` run
  directory.
- Do not use this run as positive or negative evidence for `top34-memory`.
- The next valid step is to rerun the same utilization target under the monitor.
