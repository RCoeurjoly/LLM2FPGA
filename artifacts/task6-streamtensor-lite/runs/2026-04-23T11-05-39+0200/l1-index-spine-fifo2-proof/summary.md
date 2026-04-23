# Selective Index-Spine FIFO2 Proof

## Commands

`/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-spine-fifo2-sv-sim --no-link -L`

`/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-spine-fifo2-utilization --no-link --print-out-paths`

## Logs

- `task6-l1-c-fc-redirect-index-spine-fifo2-sv-sim`
  - `PASS: stores 16 outputs 16`
  - `ELAPSED=58.30`
  - `RSS_KB=437376`
- `task6-l1-c-fc-redirect-index-spine-fifo2-utilization`
  - output: `/nix/store/dkwlcml8ckf8gg5kx2c3v4w8d5yq43i6-task6-l1-c-fc-redirect-index-spine-fifo2-utilization`
  - `ELAPSED=64.88`
  - `RSS_KB=563044`

## Metrics

- DSP: `4`
- BRAM36: `0`
- LUT: `32,808`
- FF: `50,642`
- wall-clock runtime:
  - Verilator check: `58.30 s`
  - mapped utilization: `64.88 s`
- large weights emitted as RTL constants: `no`
- Verilator passed: `yes`
- Yosys stat finished within budget: `yes`, inherited from accepted `L1` at `4.07 s`

## Verdict

Replacing the local `handshake_buffer160..165` loop-index spine with the lean
FIFO2 buffer is functionally safe and improves the mapped non-`abc9` `L1`
signature from `33,116` LUT / `51,296` FF to `32,808` LUT / `50,642` FF while
keeping `4 DSP48E1`. This is a real improvement over the single-site probe but
still not enough to clear the LUT ceiling or beat the direct `abc9` result.

## Next Action

Test whether the safe local spine reduction stacks with `abc9`. If it does not,
record the selective buffer path as too weak to justify broader widening.
