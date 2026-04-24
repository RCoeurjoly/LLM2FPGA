# PT2E-Static Quantized Bounded Pass

## Commands

```bash
nix build .#tiny-stories-1m-cf-stats --no-link --print-out-paths
nix build .#tiny-stories-1m-cf --no-link --print-out-paths
nix build .#tiny-stories-1m-handshake --no-link --print-out-paths
/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#tiny-stories-1m-cf-stats --no-link --print-out-paths
/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#tiny-stories-1m-handshake --no-link --print-out-paths
```

## Outputs

- `cf-stats`:
  - `/nix/store/zz6f4lb25aiajxwg3qipcwvky2q2fzcr-tiny-stories-1m-cf.stats`
- `cf`:
  - `/nix/store/m6a5fb7i1bxn2dyb6bidj3f7fkjvbkq7-tiny-stories-1m-cf.mlir`
- `handshake`:
  - `/nix/store/00bda3b97cnrgfi002d0hwjckkak25xg-tiny-stories-1m-handshake.mlir`

## Metrics

- `cf` artifact size: `28,826,105` bytes
- `handshake` artifact size: `500,285,892` bytes
- cache-hot replay timings:
  - `cf-stats`: `ELAPSED=1.60`, `RSS_KB=294,732`
  - `handshake`: `ELAPSED=0.26`, `RSS_KB=37,024`
- live frontier sample during the first `handshake` build:
  - `circt-opt` RSS around `3,195,504 KB`

## Structural Note

- The surviving quantized route is still `tiny-stories-1m` PT2E-static.
- It now reaches real `handshake`, not just `cf-stats`.
- The quantized `handshake` lowering currently uses:
  - `scripts/pipeline/cf_to_handshake_lsq.sh`
  - `circt-opt ... --lower-cf-to-handshake=lsq -handshake-insert-buffers`

This means the live quantized route is already using the LSQ handshake path.

## Verdict

`helpful`

- The surviving quantized route advanced beyond the older `cf-stats` frontier.
- `dynamic-int8` and `torchao` remain frozen.

## Next Action

- Keep `tiny-stories-1m` active.
- Do not widen this quant route blindly into heavier stages yet.
- Use this result to define the next alternate-lowering A/B so the contract and
  representation are aligned tightly enough to isolate the lowering question.
