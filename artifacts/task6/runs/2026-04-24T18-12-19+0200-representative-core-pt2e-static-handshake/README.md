# 2026-04-24 representative-core PT2E-static `handshake` gate

Command:

```bash
/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' \
  nix build .#tiny-stories-1m-representative-core-pt2e-static-handshake \
    --no-link --print-out-paths -L \
    2>&1 | tee \
    /tmp/task6-representative-core-pt2e-static-handshake.log
```

Verdict:

- `block-shared-upstream-circt-handshake-crash`

What happened:

- The minimized representative-core PT2E-static quant spike reaches `cf.mlir`
  and then crashes in the same upstream CIRCT pass as the baseline float shell:

```text
circt-opt ... -flatten-memref -flatten-memref-calls -canonicalize -cse -handshake-legalize-memrefs -canonicalize -cse
```

- The crash signature again centers on
  `mlir::DenseElementsAttr::getNumElements() const`, which means the quant
  spike and the external-memory mainline now share one concrete toolchain
  blocker.

Key metrics:

- `ELAPSED=5.45`
- `RSS_KB=421944`
- `exit_status=1`

Files:

- [build.log](build.log)
