# 2026-04-24 representative-core PT2E-static `handshake` with rebased fork patches

Command:

```bash
/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' \
  nix build .#tiny-stories-1m-representative-core-pt2e-static-handshake \
    --no-link --print-out-paths -L
```

Verdict:

- `block-circt-check-buffer-test`

What happened:

- The rebased local `/home/roland/circt` patch stack applies cleanly to the
  `circt-nix` packaged upstream source.
- CIRCT then compiles all the way through `buildPhase`, including the patched
  files that mattered for the original blocker:
  - `lib/Transforms/FlattenMemRefs.cpp`
  - `lib/Dialect/Handshake/Transforms/LegalizeMemrefs.cpp`
  - `lib/Conversion/HandshakeToHW/HandshakeToHW.cpp`
- So the old immediate failure mode is gone:
  - no `patchPhase` reject
  - no early `flatten-memref` build crash
- The derivation still fails before the representative-core `handshake` target
  can consume the packaged CIRCT because `check-circt` reports one regression
  mismatch:

```text
Failed Tests (1):
  CIRCT :: Conversion/HandshakeToHW/test_buffer.mlir
```

- The failing expectation is in the Handshake-to-HW buffer lowering test, where
  the patched lowering emits `hw.constant 0 : i0` instead of the older checked
  `hw.constant false`.

Key metrics:

- `ELAPSED=803.01`
- `RSS_KB=421760`
- CIRCT regression summary:
  - `Passed: 1163`
  - `Failed: 1`
  - `Expectedly Failed: 6`
  - `Unsupported: 39`

Files:

- [build.log](build.log)
