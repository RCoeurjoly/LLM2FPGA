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

## First Nix-backed torch-mlir result

Date: 2026-04-12

The branch now exposes both `torch-mlir-patched` and `torch-mlir-unpatched`,
and the default Task 3 pipeline package was switched to the upstream-unpatched
variant for verification.

Observed result for the current baseline-float reviewer path:

- `nix build .#tiny-stories-1m-baseline-float-sv -L --no-link`: success
- `nix build .#tiny-stories-1m-baseline-float-il -L --no-link`: success
- `nix build .#tiny-stories-1m-baseline-float-yosys-stat -L --no-link`: success

Realized output paths:

- `sv`:
  `/nix/store/4g21jbn2h8zcmgr89pf1i02dvxwmcwc0-tiny-stories-1m-baseline-float-sv`
- `il`:
  `/nix/store/xvg1zq6lcbmrm4333sn83k5flr2f7d0m-tiny-stories-1m-baseline-float.il`
- `yosys-stat`:
  `/nix/store/hmbpnyfdj9m8d4pkv6y938bg5fmraldi-tiny-stories-1m-baseline-float-yosys.stat`

Observed behavior:

- unpatched upstream `torch-mlir` built successfully in Nix
- the real Nix-backed baseline-float pipeline still reached SystemVerilog
- the real Nix-backed baseline-float pipeline still reached RTLIL
- the Yosys stat/report path still completed

Interpretation:

- for the current `tiny-stories-1m-baseline-float` reviewer path, the full
  checked-in `torch-mlir` patch stack is not justified by the real Nix-backed
  evidence we have now
- this does not yet prove that the PT2E static-quant or TorchAO experimental
  routes can also drop those patches
- the next cleanup target should therefore be the CIRCT patch stack, while
  treating quantized frontend experiments as a separate follow-up check

## First CIRCT reduction result

Date: 2026-04-13

Experiment:

- removed `patches/circt-task3-rfp/0014-update-buffer-lowering-test-for-constant-order.patch`
- reran `nix build .#tiny-stories-1m-baseline-float-sv -L --no-link`

Observed result:

- CIRCT compiled successfully
- the Task 3-relevant code in `FlattenMemRefs`, `CFToHandshake`, and
  `HandshakeToHW` still compiled and linked successfully
- the build failed in CIRCT `checkPhase`, not in the Task 3 pipeline itself

Exact blocker:

- failed test:
  `CIRCT :: Conversion/HandshakeToHW/test_buffer.mlir`
- failing command:
  `/build/source/build/bin/circt-opt -lower-handshake-to-hw --split-input-file /build/source/test/Conversion/HandshakeToHW/test_buffer.mlir | FileCheck /build/source/test/Conversion/HandshakeToHW/test_buffer.mlir`
- failure form:
  `CHECK: expected string not found in input`
- the mismatch is the order of emitted constants in the expected test output:
  the test still expects `hw.constant false` before `hw.constant 0`

Interpretation:

- `0014` is not needed to compile CIRCT or to build the Task 3 runtime path
- `0014` is needed to keep the pinned CIRCT package tests green under Nix
- until the corresponding expected output is updated another way, `0014`
  remains justified as a small test-only patch

## Baseline-float CIRCT scout

Date: 2026-04-13

Before removing the next CIRCT runtime patch, the current baseline-float path
was re-run locally to inspect the real intermediate IR with the pinned Nix
toolchain:

- command:
  `CIRCT_OPT=$(nix build --print-out-paths --no-link .#circt)/bin/circt-opt MLIR_OPT=$(nix build --print-out-paths --no-link .#torch-mlir-mlir)/bin/mlir-opt ./scripts/dev/run-baseline-float-local-pipeline.sh --out-dir /tmp/ts-baseline-float-patch-scout --stop-after hw0`
- generated artifacts:
  `/tmp/ts-baseline-float-patch-scout/{cf.mlir,handshake.mlir,hs-ext.mlir,hw0.mlir}`

Observed behavior:

- `cf.mlir` still contains `cf.assert`
- `handshake.mlir` still contains float and math operations such as
  `arith.addf`, `arith.divf`, `arith.maximumf`, `arith.cmpf`, `math.exp`,
  `math.fpowi`, `math.rsqrt`, and `math.tanh`
- the initial `handshake.func @main` signature is memref-heavy
- `hs-ext.mlir` still contains memref globals and memref-valued memory ops
- `hw0.mlir` still contains float extern modules such as
  `@arith_addf_in_f32_f32_out_f32` and `@math_exp_in_f32_out_f32`
- `hw0.mlir` still contains a `builtin.unrealized_conversion_cast` from
  `memref<50257xf32>` to `!esi.channel<memref<50257xf32>>`
- no `lazy_fork` occurrences were found in `handshake.mlir`, `hs-ext.mlir`, or
  `hw0.mlir`

Interpretation:

- patches related to float externs, math/assert legality, memref lowering, and
  unrealized cast handling remain hot candidates for the current
  `tiny-stories-1m-baseline-float` reviewer path
- `0007-lower-lazy-fork-to-hw.patch` is the first runtime patch with concrete
  evidence that it may be unnecessary for this path, so it is the next removal
  candidate to test

## CIRCT reduction result for 0007

Date: 2026-04-13

Experiment:

- removed `patches/circt-task3-rfp/0007-lower-lazy-fork-to-hw.patch`
- reran the real Nix-backed baseline-float reviewer path:
  - `nix build .#tiny-stories-1m-baseline-float-sv -L --no-link`
  - `nix build .#tiny-stories-1m-baseline-float-yosys-stat -L --no-link`

Observed result:

- CIRCT rebuilt successfully
- CIRCT passed `checkPhase`
- `tiny-stories-1m-baseline-float-sv` succeeded
- `tiny-stories-1m-baseline-float-yosys-stat` also succeeded

Realized output paths:

- `sv`:
  `/nix/store/f03znsa4wcilh34g1b3ps91l88gq7p2f-tiny-stories-1m-baseline-float-sv`
- `yosys-stat`:
  `/nix/store/r2bvkx5iw6h7r2akh4jsanqw1rvswa4l-tiny-stories-1m-baseline-float-yosys.stat`

Interpretation:

- for the current `tiny-stories-1m-baseline-float` reviewer path,
  `0007-lower-lazy-fork-to-hw.patch` is not justified by the evidence we have
- the branch can keep this patch removed unless a different Task 3 path later
  proves it is still required

## Retained patch bar

Any retained patch should have all of the following written down nearby in the
repo or commit message:

- what exact failure it fixes
- which Task 3 path needs it
- the smallest reproducer or command
- why a smaller or more upstream-shaped fix was not used instead
