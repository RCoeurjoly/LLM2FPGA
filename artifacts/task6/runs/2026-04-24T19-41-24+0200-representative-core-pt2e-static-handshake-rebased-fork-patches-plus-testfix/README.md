# 2026-04-24 representative-core PT2E-static `handshake` with rebased fork patches plus buffer-test fix

Command:

```bash
/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' \
  nix build .#tiny-stories-1m-representative-core-pt2e-static-handshake \
    --no-link --print-out-paths -L
```

Verdict:

- `block-missing-lsq-option`

What happened:

- The rebased local `/home/roland/circt` patch stack plus the matching
  `test_buffer.mlir` update now builds CIRCT completely under `circt-nix`.
- The patched CIRCT package reaches `fixupPhase`, so:
  - the old upstream `flatten-memref` crash is no longer the active blocker
  - the earlier `check-circt` failure on
    `Conversion/HandshakeToHW/test_buffer.mlir` is also resolved
- The representative-core quantized `handshake` derivation then fails one step
  later, in the Task 6 lowering itself:

```text
error: <Pass-Options-Parser>: no such option lsq
error: failed to add `lower-cf-to-handshake` with options `lsq`
```

- So the new blocker is not CIRCT stability. It is that this patched upstream
  stack still does not provide the LSQ-specific `lower-cf-to-handshake=lsq`
  option expected by the quantized representative-core route.

Key metrics:

- `ELAPSED=829.21`
- `RSS_KB=421940`

Files:

- [build.log](build.log)
