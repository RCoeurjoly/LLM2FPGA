# Upstream Toolchain Warm L0

## Why This Slice Ran

The first post-switch `top4-memory` rerun was blocked before it reached the
model stages. The cheapest follow-up was therefore to use a tiny CIRCT-dependent
Task 6 target to test whether the blocker was global toolchain bootstrap rather
than the shell lane itself.

## Command

```bash
/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' \
  nix build .#task6-l0-gemv64-yosys-stat --no-link --print-out-paths -L
```

## Direct Result

- measured wall-clock from run-dir timestamp to final log mtime:
  - `32.17 s`
- emitted store path:
  - none

## What Happened

- The run did not reach the Task 6 `L0` Yosys-stat derivation.
- It again re-entered the upstream toolchain stack first:
  - `llvm-tblgen-23.0.0-20260312_7cb3005`
  - `llvm-23.0.0-20260312_7cb3005`
  - `mlir-23.0.0-20260312_7cb3005`
  - `circt-1.144.0g20260424_d07f832`
- The deepest progress captured before the manual stop was:
  - `llvm-tblgen` configure finished at log line `430`
- The log ended with:
  - `error: interrupted by the user`

## Verdict

- `blocked-upstream-toolchain-bootstrap`
- This confirms the blocker is not specific to the baseline `top4-memory`
  shell.
- On this machine, any new CIRCT-dependent Task 6 run now first pays the full
  upstream LLVM/MLIR/CIRCT bootstrap after the `llvm/circt` switch.

## Next Action

- Do not spend more experiment slots on restarted Task 6 targets until one full
  upstream bootstrap is allowed to complete.
- After that warm-up lands once, rerun the monitored baseline
  `tiny-stories-1m-baseline-float-selftest-top4-memory-*` pass.
