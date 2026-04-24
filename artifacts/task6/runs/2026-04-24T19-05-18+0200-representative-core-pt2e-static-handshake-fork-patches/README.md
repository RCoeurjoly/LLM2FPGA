# 2026-04-24 representative-core PT2E-static `handshake` with fork patch stack

Command:

```bash
/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' \
  nix build .#tiny-stories-1m-representative-core-pt2e-static-handshake \
    --no-link --print-out-paths -L
```

Verdict:

- `block-circt-patch-drift`

What happened:

- The first attempt to replay the local `/home/roland/circt` fixes on top of
  `circt-nix` as shipped gets past Nix evaluation and into CIRCT `patchPhase`.
- The patched build fails before compile because the first functional patch in
  the series does not apply cleanly to the newer upstream CIRCT source:

```text
applying patch .../0001-flatten-memref-shape-ops-after-memref-flattening.patch
patching file lib/Transforms/FlattenMemRefs.cpp
...
Hunk #5 FAILED at 515.
```

- So the immediate blocker is source drift between the April 20 fork commits and
  the newer `circt-nix` packaged CIRCT revision, not the old runtime
  `flatten-memref` crash.

Key metrics:

- `ELAPSED=6.15`
- `RSS_KB=421892`

Files:

- [build.log](build.log)
