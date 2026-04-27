# 2026-04-27 baseline `top34-memory` utilization rerun, `stage6a` batch size 2

Command:

```sh
env 'MONITOR_GLOBAL_PGREP_PATTERN=default-builder.sh|yosys -q -s run.ys|yosys-abc|.yosys-wrapped' \
  scripts/pipeline/monitor_build.sh \
  artifacts/task6/runs/2026-04-27T16-35-00+0200-baseline-top34-memory-utilization-stage6a-batch2-rerun \
  5 -- \
  nix build .#tiny-stories-1m-baseline-float-selftest-top34-memory-utilization \
    --no-link --print-out-paths -L
```

Result:

- exit status: `1`
- wall time: `11367` seconds
- peak sampled `VmRSS`: `19,928,932 KiB`
- peak sampled `VmHWM`: `20,280,128 KiB`
- final logged stage: `stage9 write_json`
- failure: `ERROR: Parser error in line 66916687: dangling attribute`

Interpretation:

- The run cleared `stage6a targeted techmap cells_map` through batch `221/221`.
- The run cleared `stage8b abc`, which was the previous `top32-memory`
  frontier.
- The new blocker is final JSON emission or parsing of the mapped design, not
  the previous residual-memory `cells_map` or ABC OOM frontier.
