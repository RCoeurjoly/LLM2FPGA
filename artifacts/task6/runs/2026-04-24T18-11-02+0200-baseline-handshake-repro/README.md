# 2026-04-24 baseline float `cf -> handshake` standalone reproducer

Command:

```bash
/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' \
  /nix/store/9am975q7rmbvpzxzgg1j260da3qhkqzq-circt-1.144.0g20260331_5dc62fe/bin/circt-opt \
    /nix/store/k34gyy0qqnsd0f7yi595kxs2mx3nfjr1-tiny-stories-1m-baseline-float-cf.mlir \
    -flatten-memref -flatten-memref-calls -canonicalize -cse \
    -handshake-legalize-memrefs -canonicalize -cse \
    >/tmp/task6-baseline-float-handshake-repro.mlir \
    2>artifacts/task6/runs/2026-04-24T18-11-02+0200-baseline-handshake-repro/build.log
```

Verdict:

- `pass-reproducer`

What happened:

- The upstream CIRCT crash reproduces directly outside the Nix pipeline wrapper.
- The standalone `circt-opt` invocation dies in `-handshake-legalize-memrefs`
  with the same `DenseElementsAttr::getNumElements()` stack signature seen in
  the blocked `top4-memory` shell run.

Key metrics:

- `ELAPSED=1.42`
- `RSS_KB=94720`
- `signal=11`

Files:

- [build.log](build.log)
