# Task 6 Quantization Lane

This worktree owns quantization-based resource reduction for Task 6.

## Scope

- evaluate the full-model TinyStories quantization routes already imported into
  `task6`
- continue mining `task3-experiments` only when the full-model routes need
  follow-up or reduction
- compare quantized routes against the copied baseline bundle, not against a
  rebuilt `/nix/store` path

## Baseline

Use:

- `artifacts/task6/baselines/tiny-stories-1m-baseline-float-selftest-all-memory-utilization`

Always record:

- first failing stage
- resource deltas versus baseline
- extra patch burden or environment burden

## Immediate TODO

1. Check which of these routes currently evaluates and how far each gets:
   - `tiny-stories-1m`
   - `tiny-stories-1m-dynamic-int8`
   - `tiny-stories-1m-torchao`
2. For each route, capture whether the first failure is in export, lowering,
   handshake, SV emission, or later reporting.
3. If one route reaches farther downstream than the others, treat it as the
   primary quantization candidate.
4. Only import Stage E debug reproducers if the full-model route fails and the
   failure cannot be isolated from current artifacts.

## Questions to answer

- Which quantization route gives the best resource reduction story?
- Which route has the lowest compiler patch burden?
- Does quantization reduce the limiting FPGA resource, or only model size?

## Out of scope

- DDR3 / off-chip memory placement experiments
- eqmap or general RTL cleanup experiments
- reviewer-facing plan edits

## Exit condition

This lane is ready to merge back when it can classify at least one quantization
route as `recommended`, `conditional`, or `reject` with an explicit baseline
comparison.
