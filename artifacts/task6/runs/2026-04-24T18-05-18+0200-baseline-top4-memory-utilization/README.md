# 2026-04-24 baseline `top4-memory` utilization rerun

Command:

```bash
MONITOR_GLOBAL_PGREP_PATTERN="default-builder.sh|yosys -q -s run.ys|yosys-abc" \
scripts/pipeline/monitor_build.sh \
  artifacts/task6/runs/2026-04-24T18-05-18+0200-baseline-top4-memory-utilization \
  5 -- \
  nix build .#tiny-stories-1m-baseline-float-selftest-top4-memory-utilization \
    --no-link --print-out-paths -L
```

Verdict:

- `block-upstream-circt-handshake-crash`

What happened:

- The run is no longer blocked on upstream LLVM/MLIR/CIRCT bootstrap.
- It reaches real TinyStories lowering and then crashes in upstream CIRCT while
  building `tiny-stories-1m-baseline-float-handshake.mlir`.
- Failing command inside the pipeline:

```text
circt-opt ... -flatten-memref -flatten-memref-calls -canonicalize -cse -handshake-legalize-memrefs -canonicalize -cse
```

Key metrics:

- `exit_status=1`
- `wall_seconds=16`
- `peak_vmrss_kb=565464`

Files:

- [build.log](build.log)
- [summary.txt](summary.txt)
- [processes.tsv](processes.tsv)
- [process-samples.tsv](process-samples.tsv)
