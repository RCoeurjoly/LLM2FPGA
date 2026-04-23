# L1 Folded-Bias Replay Failure

## Commands

- `nix build .#task6-l1-c-fc-redirect-sv --no-link -L`
- `nix build .#task6-l1-c-fc-redirect-yosys-stat --no-link -L`
- `nix build .#task6-l1-c-fc-redirect-sv-sim --no-link -L`

## Log

- Structural path succeeded:
  - the redirected `sv` export built
  - the kernel still exposed external load/store plumbing
- Exact replay failed at simulation:
  - `FAIL: addr 0 expected 0x3d085992 got 0x3d082000`
  - `FAIL: addr 1 expected 0x3d2a1d92 got 0x3d29e000`
  - `...`
  - `Result check failed with 0 missing and 16 mismatched outputs`
- Error scale:
  - `max_abs_error = 0.000075929`

## Metrics

- DSP / BRAM / LUT / FF:
  - not recorded for this stop point because the path was rejected on replay
    semantics before mapped utilization was promoted
- Wall-clock runtime:
  - not captured for this failed intermediate variant
- Large weights emitted as RTL constants:
  - no, the wrapper still used an external weight load interface
- Verilator passed:
  - no
- Yosys stat finished within budget:
  - yes

## Verdict

- reject
- Folding bias into an augmented dot product is not an exact replay of the
  captured site after lowering through the current float primitive path.

## Next Action

- Try an explicit external bias input instead of algebraically folding bias into
  the weight matrix.
