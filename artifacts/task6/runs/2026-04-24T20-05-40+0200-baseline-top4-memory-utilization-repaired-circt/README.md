# 2026-04-24 baseline `top4-memory` utilization with repaired CIRCT

Command:

```sh
nix build .#tiny-stories-1m-baseline-float-selftest-top4-memory-utilization --no-link --print-out-paths -L
```

Result:

- exit status: `1`
- wall time: `6572` seconds
- peak sampled `VmRSS`: `30,322,432 KiB`
- peak sampled `VmHWM`: `30,323,020 KiB`
- final logged stage: `stage6a targeted techmap cells_map batch 13/15`
- failure: Yosys worker killed with exit code `137`

Interpretation:

- The repaired CIRCT stack is no longer the blocker for this run.
- The external-memory shell reaches the split Yosys flow and restart-batched
  `stage6a`.
- `stage6a` still needs a smaller restart batch or another memory-shaping
  change before the full-baseline `top4-memory` utilization can land.
