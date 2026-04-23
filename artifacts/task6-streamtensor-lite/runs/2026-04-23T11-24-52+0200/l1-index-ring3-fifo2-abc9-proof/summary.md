# Selective Index Ring-3 FIFO2 `abc9` Proof

## Commands

`/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-ring3-fifo2-sv-sim --no-link -L`

`/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-ring3-fifo2-abc9-utilization --no-link --print-out-paths`

## Logs

- `task6-l1-c-fc-redirect-index-ring3-fifo2-sv-sim`
  - `PASS: stores 16 outputs 16`
  - `ELAPSED=82.55`
  - `RSS_KB=437104`
- `task6-l1-c-fc-redirect-index-ring3-fifo2-abc9-utilization`
  - output: `/nix/store/y57gd36j5fbplkw51iv6if0cflppn052-task6-l1-c-fc-redirect-index-ring3-fifo2-abc9-utilization`
  - `ELAPSED=93.19`
  - `RSS_KB=563112`

## Metrics

- DSP: `4`
- BRAM36: `0`
- LUT: `30,320`
- FF: `47,392`
- wall-clock runtime:
  - Verilator check: `82.55 s`
  - mapped utilization: `93.19 s`
- large weights emitted as RTL constants: `no`
- Verilator passed: `yes`
- Yosys stat finished within budget: `yes`, inherited from accepted `L1` at `4.07 s`

## Verdict

The connected `213..219` mux-return ring is still safe under the `L1` contract
and improves the previous best from `30,762` LUT / `48,302` FF to
`30,320` LUT / `47,392` FF while keeping `4 DSP48E1`. This is the best `L1`
fit point in the lane so far, but it still misses the LUT target by `460`.

## Next Action

Stop blind ring-by-ring widening here. The next step should be a deliberate
probe of the remaining nearby control or merge sites, or a decision to accept
this as the best current structural point and switch to a different fit lever.
