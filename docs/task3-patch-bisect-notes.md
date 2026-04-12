# Task 3 Patch Bisect Notes

Date: 2026-04-12

## Goal

Reduce the Task 3 patch burden as far as possible.

Preferred end state:

- zero downstream compiler patches
- if zero is not possible, keep only the smallest well-scoped patches with a
  clear reproducer and justification

## Current branch reality

- Immediate priority is to reach a mapped utilization artifact first and defer
  patch cleanup until after that result exists.
- The working reviewer-visible path is the baseline-float route:
  `tiny-stories-1m-baseline-float-sv -> il -> yosys-stat`
- A mapped utilization artifact now exists for the shellized baseline-float
  route:
  `tiny-stories-1m-baseline-float-selftest-all-memory-utilization`
- Realized output path on 2026-04-12:
  `/nix/store/z57z4k4vmp6x40k724h9lrz7lhb04m50-tiny-stories-1m-baseline-float-selftest-all-memory-utilization`
- The direct full-model mapped route
  `tiny-stories-1m-baseline-float-utilization-*` is still a separate path and
  should not be conflated with the successful shellized artifact above.
- Staged `synth_xilinx` now has real derivation checkpoints instead of one long
  monolithic derivation.

Useful package entry points:

- `nix build .#tiny-stories-1m-baseline-float-utilization-stage1 -L --no-link`
- `nix build .#tiny-stories-1m-baseline-float-utilization-stage4 -L --no-link`
- `nix build .#tiny-stories-1m-baseline-float-utilization-stage8 -L --no-link`
- `nix build .#tiny-stories-1m-baseline-float-utilization-stage9 -L --no-link`
- `nix build .#tiny-stories-1m-baseline-float-selftest-all-memory-utilization -L --no-link`
- `nix build .#tiny-stories-1m-selftest-all-memory-utilization -L --no-link`

Important implementation note:

- The shellized mapped JSON for baseline-float is about `2.3G`.
- The original `mkMappedJsonUtilizationReport` implementation used
  `yosys read_json -> stat -json`, which was killed with exit code `137` on
  that artifact.
- The current implementation computes top-module cell counts by streaming over
  the mapped JSON directly and expanding submodule counts hierarchically, which
  avoids re-importing the full JSON into Yosys and allows the utilization
  derivation to complete.

The canonical PT2E static-quant path and the baseline-float path should be
treated separately when judging patch necessity.

## Patch reduction policy

- Prefer compiling outside Nix for patch bisect work when that materially
  reduces rebuild time.
- Use binary bisecting where possible instead of removing patches one by one.
- Judge necessity against the specific Task 3 path being tested, not against
  unrelated experimental routes.
- Record the exact failing command, the first failing stage, and the smallest
  reproducer before deciding a patch is required.

## Suggested bisect order

1. Test the baseline-float reviewer path without the `torch-mlir` patch stack.
2. If baseline-float still works, keep `torch-mlir` patch reduction separate
   from PT2E quantized-path work.
3. Bisect the CIRCT stack next.
4. Preserve the float-extern lowering patch until a concrete test proves it is
   unnecessary.
5. Only keep patches that remain necessary for the refined Task 3 claim.

## Local fast-loop workflow

Use the new helper:

- `scripts/dev/run-baseline-float-local-pipeline.sh`

This script runs the real baseline-float Task 3 path locally:

- `torch -> linalg -> cf -> cf-stats -> handshake -> hs-ext -> hw0 -> hw -> hw-clean -> sv -> il -> yosys-stat`

It is intended for patch bisects, not for canonical reviewer builds. The
canonical reviewer path remains the Nix-backed commands in the Task 3
checklist.

Recommended usage:

1. Enter the pinned tool environment:
   `nix develop`
2. For `torch-mlir` patch bisects, point `TORCH_MLIR_OPT` at the local binary:
   `TORCH_MLIR_OPT=/home/roland/torch-mlir/build-local-devshell-2/bin/torch-mlir-opt`
3. For CIRCT patch bisects, point `CIRCT_OPT` at the local binary:
   `CIRCT_OPT=/home/roland/circt/build-local-23/bin/circt-opt`
4. Stop at the first stage you care about:
   - `--stop-after linalg` for frontend / torch-mlir checks
   - `--stop-after sv` for CIRCT checks
   - `--stop-after il` or `yosys-stat` for downstream checks

The helper writes all artifacts into one output directory and records the exact
tool paths used in `toolchain.env`. That should make bisect failures easier to
compare and easier to write up once a patch is proven necessary.

## First local torch-mlir result

Date: 2026-04-12

Using a detached upstream `torch-mlir` worktree at the pinned Task 3 revision
`59c249e5` with the repo patch stack removed:

- worktree: `/home/roland/torch-mlir-bisect`
- local binary:
  `/home/roland/torch-mlir-bisect/build-no-patches/bin/torch-mlir-opt`
- local python sources:
  `/home/roland/torch-mlir-bisect/python`

Local build notes:

- the clean upstream tree needed a local build shim to compile outside Nix:
  - `TORCH_MLIR_ENABLE_STABLEHLO=OFF`
  - absolute `mlir-tblgen` from
    `/nix/store/qlkklrgiqi1paa25gpmk02d2sf6hnjc9-llvm-tblgen-23.0.0-unstable-2026-01-20/bin/mlir-tblgen`
  - compatibility symlinks for the generated `include/.../mlir-tblgen`
    dependencies in the out-of-tree build directory
- this shim is for the local bisect harness only, not a reviewer-facing claim

Observed result against the baseline-float path, with the real downstream tool
versions from the repo pipeline:

- `torch-mlir-opt`: clean upstream local build from `59c249e5`
- `mlir-opt`: `/nix/store/qfhb8ajk2kw32lrmk8xqaa1g6h7w95p8-mlir-21.1.2/bin/mlir-opt`
- `circt-opt`:
  `/nix/store/xczyaxcqdm86pqhng55fiv9wy7ir5f66-circt-1.143.0g20260320_34e5533/bin/circt-opt`
- `yosys`:
  `/nix/store/7hbi77b6hi6zncfd3jw5bgw6y8sa1591-yosys-with-plugins-0.62/bin/yosys`
- `yosys-slang`:
  `/nix/store/wga1hnian30asym9hma6829qzmbcf4af-yosys-slang-flake-input/share/yosys/plugins/slang.so`

Results:

- the clean no-patch `torch-mlir` path reaches `linalg`
- the clean no-patch `torch-mlir` path reaches `sv`
- the clean no-patch `torch-mlir` `sv` bundle passes direct `sv_to_il.sh`
- direct IL output was written to:
  `/tmp/ts-baseline-float-no-torch-mlir-patches-sv-mlir21/design.il`

Interpretation:

- for the current `tiny-stories-1m-baseline-float` reviewer path, the full
  checked-in `torch-mlir` patch stack now looks likely unnecessary
- this is not yet a Nix-packaged proof; it is a local bisect-harness result
- the next confirming step should be to disable the `torch-mlir` patch list in
  `torch-mlir.nix` and re-run:
  - `tiny-stories-1m-baseline-float-sv`
  - `tiny-stories-1m-baseline-float-il`
  - `tiny-stories-1m-baseline-float-yosys-stat`

## Retained patch bar

Any retained patch should have all of the following written down nearby in the
repo or commit message:

- what exact failure it fixes
- which Task 3 path needs it
- the smallest reproducer or command
- why a smaller or more upstream-shaped fix was not used instead
