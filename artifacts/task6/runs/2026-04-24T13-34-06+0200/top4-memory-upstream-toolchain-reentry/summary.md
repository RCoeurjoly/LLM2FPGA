# Top4-Memory Upstream Toolchain Reentry

## Why This Slice Ran

The amended Task 6 plan makes the baseline `top4-memory` / DDR3 shell evidence
the first active architecture track. This was the first rerun after switching
the branch from the local CIRCT fork to upstream `llvm/circt` and refreshing
`flake.lock`.

## Command

```bash
/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' \
  nix build .#tiny-stories-1m-baseline-float-selftest-top4-memory-external-memory-plan \
  --no-link --print-out-paths -L
```

## Direct Result

- `ELAPSED`: no final `/usr/bin/time` line was emitted because the build was
  interrupted before the wrapped command returned
- measured wall-clock from run-dir timestamp to final log mtime:
  - `77.96 s`
- emitted store path:
  - none

## What Happened

- The build did not reach the `top4-memory` model derivation.
- It first re-entered the upstream toolchain bootstrap introduced by the new
  flake inputs:
  - `llvm-tblgen-src-23.0.0-20260312_7cb3005`
  - `llvm-tblgen-23.0.0-20260312_7cb3005`
  - `llvm-23.0.0-20260312_7cb3005`
  - `mlir-23.0.0-20260312_7cb3005`
  - `circt-1.144.0g20260424_d07f832`
- The log reached:
  - `llvm-tblgen` configure completion at line `446`
  - active `llvm-tblgen` compile progress through `[221/388]` at line `703`
- The run was then stopped manually and the log ended with:
  - `error: interrupted by the user`

## Verdict

- `blocked-upstream-toolchain-bootstrap`
- This run does not say anything new about DDR3 shell fit.
- It only shows that the first architecture-level re-entry after the upstream
  CIRCT switch is paying the LLVM/MLIR/CIRCT rebuild cost before the branch can
  produce fresh `top4-memory` evidence.

## Next Action

- Warm the upstream LLVM/MLIR/CIRCT stack once on this branch, then rerun the
  monitored `tiny-stories-1m-baseline-float-selftest-top4-memory-*` pass.
- Do not record this as a `top4-memory` negative; record it as a toolchain
  blocker on the first post-switch rerun.
