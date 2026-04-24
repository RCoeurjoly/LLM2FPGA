# 2026-04-24 representative-core PT2E-static `cf-stats` first attempt

Command:

```bash
/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' \
  nix build .#tiny-stories-1m-representative-core-pt2e-static-cf-stats \
    --no-link --print-out-paths -L
```

Verdict:

- `block-untracked-quant-surface`

What happened:

- The new minimized representative-core PT2E-static quant surface is wired, but
  the first Nix evaluation fails before PyTorch export because the new adapter
  file is untracked and therefore omitted from the flake source snapshot.

Key metrics:

- `ELAPSED=1.24`
- `RSS_KB=184688`

Files:

- [build.log](build.log)
