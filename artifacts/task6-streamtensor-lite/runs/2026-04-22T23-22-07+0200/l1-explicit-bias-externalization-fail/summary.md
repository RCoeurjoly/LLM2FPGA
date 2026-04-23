# L1 Explicit-Bias Externalization Failure

## Commands

- `nix path-info .#task6-l1-c-fc-redirect-torch`
- `nix path-info .#task6-l1-c-fc-redirect-linalg`
- `nix path-info .#task6-l1-c-fc-redirect-cf`
- `nix path-info .#task6-l1-c-fc-redirect-handshake`
- `nix path-info .#task6-l1-c-fc-redirect-hw-clean`

## Log

- The explicit bias input existed through the early IR:
  - `func.func @main(%arg0: tensor<1x5xf32>, %arg1: tensor<5x16xf32>, %arg2: tensor<16xf32>)`
  - the body showed `linalg.matmul` followed by a bias add
- The externalization proof failed later in lowering:
  - handshake still mentioned `%arg2` but showed `extmemory[ld = 0, st = 0]`
    for the bias memref
  - the `hw-clean` top-level module exposed only activation load, weight load,
    store, and start-token ports
  - an internal `handshake_memory_out_f32_id*` block appeared instead of a
    surfaced bias load interface

## Metrics

- DSP / BRAM / LUT / FF:
  - not recorded because the path was rejected before synthesis promotion
- Wall-clock runtime:
  - inspection-only stop point, not a timed build result
- Large weights emitted as RTL constants:
  - no, weights still stayed on an external load path
- Verilator passed:
  - not attempted
- Yosys stat finished within budget:
  - not attempted

## Verdict

- reject
- This counts as the single explicit externalization attempt for the L1 bias
  path. The compiler did not preserve bias as a top-level external memory
  interface.

## Next Action

- Move to the mission fallback:
  - use a kernel-only testbench on the pre-bias `batch_matmul` boundary
