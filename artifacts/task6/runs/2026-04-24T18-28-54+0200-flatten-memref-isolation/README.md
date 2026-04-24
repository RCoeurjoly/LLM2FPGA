# 2026-04-24 direct `flatten-memref` isolation

Command set:

```bash
/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' \
  /nix/store/9am975q7rmbvpzxzgg1j260da3qhkqzq-circt-1.144.0g20260331_5dc62fe/bin/circt-opt \
    /nix/store/k34gyy0qqnsd0f7yi595kxs2mx3nfjr1-tiny-stories-1m-baseline-float-cf.mlir \
    -flatten-memref

/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' \
  /nix/store/9am975q7rmbvpzxzgg1j260da3qhkqzq-circt-1.144.0g20260331_5dc62fe/bin/circt-opt \
    /nix/store/a0jsiyfh8py537xidmx38hkkdkz773j3-tiny-stories-1m-representative-core-pt2e-static-cf.mlir \
    -flatten-memref
```

Verdict:

- `pass-shared-flatten-memref-reproducer`

What happened:

- The shared upstream CIRCT blocker is narrower than the earlier pipeline logs
  suggested: both the baseline float shell and the minimized representative-core
  PT2E-static quant spike crash on `-flatten-memref` alone.
- The stack signature matches in both cases and centers on
  `mlir::DenseElementsAttr::getNumElements() const`.
- Baseline control checks:
  - `-canonicalize -cse`: passes
  - `-flatten-memref-calls`: passes
- Bounded manual probes did not yield a tiny reproducer:
  - trivial `memref.global`: passes
  - trivial strided-arg load/store: passes
  - trivial `expand_shape` / `subview` snippets fail with legalization leftovers,
    not crashes
- Reducer attempts are not usable enough in the current packaging:
  - `circt-reduce` cannot parse this `memref`-dialect input
  - `mlir-reduce` accepts `reduction-tree` style configuration but emitted no
    reduced file for this crash test

Key metrics:

- baseline float:
  - `ELAPSED=2.35`
  - `RSS_KB=93940`
  - `exit_status=139`
- representative-core PT2E-static:
  - `ELAPSED=1.29`
  - `RSS_KB=43764`
  - `exit_status=139`

Files:

- [scratch-notes.txt](scratch-notes.txt)
