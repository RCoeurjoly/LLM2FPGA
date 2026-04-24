# 2026-04-24 representative-core PT2E-static `cf-stats` rerun

Command:

```bash
/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' \
  nix build .#tiny-stories-1m-representative-core-pt2e-static-cf-stats \
    --no-link --print-out-paths -L \
    2>&1 | tee \
    /tmp/task6-representative-core-pt2e-static-cf-stats-rerun.log
```

Verdict:

- `pass-quant-minimized-cf`

What happened:

- Once the new representative-core PT2E-static adapter is tracked by Git, the
  minimized full-model quant route reaches real `cf-stats`.
- The exported `torch` MLIR remains genuinely quantized rather than collapsing
  to the old float-only extracted-op failure mode: it contains `66`
  `quantize_per_tensor` ops around `17` matmuls.
- The route therefore survives as a bounded minimized-surface quant spike, but
  only through the pre-handshake stages.

Key metrics:

- `ELAPSED=49.58`
- `RSS_KB=293732`
- output: `/nix/store/lggrgacn2ymq9b579sgca94wbpvawwz0-tiny-stories-1m-representative-core-pt2e-static-cf.stats`

Files:

- [build.log](build.log)
