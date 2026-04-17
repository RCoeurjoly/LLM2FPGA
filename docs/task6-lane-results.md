# Task 6 Quantization Lane Results

Date: 2026-04-17

Baseline bundle:
`artifacts/task6/baselines/tiny-stories-1m-baseline-float-selftest-all-memory-utilization`

Baseline resource picture:
- LUTs: 40,416,086 / 298,600
- FFs: 58,072,527 / 597,200
- BRAM36 equivalent: 0 / 955
- DSPs: 0 / 1,920
- Limiting story: the copied baseline is overwhelmingly LUT/FF bound, not BRAM
  bound.

Route wiring snapshot:
- `tiny-stories-1m` uses `registerQuantizedModel`, so it is the only route on
  the LSQ handshake path (`cf_to_handshake_lsq.sh`).
- `tiny-stories-1m-dynamic-int8` and `tiny-stories-1m-torchao` use the
  standard `registerModel` path.
- The current default flake still points at `torch-mlir-unpatched`; the patched
  build is exported separately as `torch-mlir-patched`.

Overall call:
- `tiny-stories-1m` is the strongest route in the current branch because it is
  the only quantized full-model path that clearly gets past frontend lowering.
- None of the three routes currently produce a new resource report that can be
  compared numerically against the copied baseline bundle, so today they change
  model representation more than they change the measured FPGA resource story.

## `tiny-stories-1m`

- Farthest confirmed successful stage: `cf-stats`
- First failing stage: none confirmed yet in this lane; an attempted
  `handshake` build was interrupted during the shared CIRCT/LLVM bootstrap, so
  there is no route-specific backend failure log from this worktree yet.
- Current viability: `conditional`
- Baseline comparison:
  - stronger than the other two quantization routes on stage reach
  - weaker than the copied baseline bundle on measurement maturity, because it
    still has no synthesized utilization artifact in this branch
  - the current `cf-stats` output still contains substantial float residue
    (`arith.addf`, `arith.divf`, `arith.maximumf`, `arith.minimumf`,
    `math.exp`, `math.rsqrt`, `math.tanh`), so there is no evidence yet that
    it materially changes the baseline LUT/FF explosion
- Extra patch burden:
  - medium to high
  - frontend export works today, but the route still carries partially traced
    quantized matmuls at `linalg`
  - likely follow-up work is in the standard PT2E-static float islands
    (normalization, softmax, scale/clamp scaffolding) rather than in basic
    export plumbing
  - environment burden is also higher than the other routes because this is the
    only path that needs the LSQ/CIRCT backend stack before it can be
    classified further

## `tiny-stories-1m-dynamic-int8`

- First failing stage: `torch`
- Failure detail:
  - `tiny-stories-1m-dynamic-int8-torch-input.mlir` fails while lowering
    TorchFX IR to Torch backend IR
  - the concrete error is `failed to legalize operation 'torch.operator' that
    was explicitly marked illegal`
  - the failing callsite is rooted in `torch.nn.Linear` inside the GPT-Neo
    model path
- Current viability: `reject`
- Baseline comparison:
  - strictly worse than the copied baseline bundle on stage reach
  - no downstream IR, SV, or utilization report exists, so this route does not
    currently change the measured resource story at all
- Extra patch burden:
  - high
  - the current unpatched default `torch-mlir` cannot even import the dynamic
    quantized operator mix into the route's public `torch` artifact
  - this is a compiler legalization problem first, not a downstream hardware
    optimization problem

## `tiny-stories-1m-torchao`

- First failing stage: `torch`
- Failure detail:
  - `tiny-stories-1m-torchao-torch-input.mlir` fails while lowering TorchFX IR
    to Torch backend IR
  - the concrete error is again `failed to legalize operation 'torch.operator'
    that was explicitly marked illegal`
  - in this route the failing callsite is rooted in `torch.nn.Embedding`, which
    matches the expected TorchAO custom-op/import gap around quantized
    embeddings
- Current viability: `reject`
- Baseline comparison:
  - strictly worse than the copied baseline bundle on stage reach
  - like dynamic-int8, it never reaches a stage that can say anything concrete
    about LUT/FF relief versus the baseline bundle
- Extra patch burden:
  - high
  - this route needs importer/compiler support for TorchAO-specific quantized
    operators before normal downstream classification can even start
  - historical work in `task3-experiments` suggests a patched path exists, but
    that is not the current default lane configuration

## Immediate follow-up in this lane

As of 2026-04-17, this branch now flips the lane-local default from
`torch-mlir-unpatched` to `torch-mlir-patched`.

Reason:

- the overnight run already established that `dynamic-int8` and `torchao` are
  blocked first by importer/legalization failures on the unpatched path
- repeating that exact configuration is low value
- the next useful quantization check is whether the patched path reclassifies
  either route from "frontend reject" into a later-stage problem
