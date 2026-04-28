# 2026-04-27 baseline `top34-memory` utilization filter-fix rerun

Command:

```sh
MONITOR_GLOBAL_PGREP_PATTERN='default-builder.sh|yosys -q -s run.ys|yosys-abc|.yosys-wrapped' \
  scripts/pipeline/monitor_build.sh \
  artifacts/task6/runs/2026-04-27T23-43-30+0200-baseline-top34-memory-utilization-filterfix-rerun \
  5 -- \
  nix build .#tiny-stories-1m-baseline-float-selftest-top34-memory-utilization \
    --no-link --print-out-paths -L
```

Result:

- exit status: `1`
- wall time: `12340` seconds
- peak sampled `VmRSS`: `20,578,672 KiB`
- peak sampled `VmHWM`: `20,816,540 KiB`
- final monitor stage line: `stage8h opt_lut_ins -tech xilinx`
- failure: `filter_rtlil_modules.py` hit `OSError: [Errno 28] No space left on device` while the JSON derivation prepared the filtered RTLIL input

Interpretation:

- The run cleared `stage6a targeted techmap cells_map` through all `221/221` restart batches.
- The run cleared `stage8b abc -luts 2:2,3,6:5,10,20`.
- The run cleared through `stage8h`, so it crossed both prior external-memory frontiers.
- The failure is an environment/disk-space blocker, not evidence against the `top34-memory` synthesis path.
- The successful `stage8h` output was temporarily preserved with a Nix GC root before cleanup and the final JSON rerun.
