# Selective Index-Fanout FIFO2 `abc9` Proof

## Commands

`/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-fanout-fifo2-sv-sim --no-link -L`

`/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-fanout-fifo2-abc9-utilization --no-link --print-out-paths`

## Logs

- `task6-l1-c-fc-redirect-index-fanout-fifo2-sv-sim`
  - `PASS: stores 16 outputs 16`
  - `ELAPSED=65.50`
  - `RSS_KB=436664`
- `task6-l1-c-fc-redirect-index-fanout-fifo2-abc9-utilization`
  - output: `/nix/store/adf0la4c5xkqdmvc6n5i37db5zaz929x-task6-l1-c-fc-redirect-index-fanout-fifo2-abc9-utilization`
  - `ELAPSED=93.49`
  - `RSS_KB=563372`

## Metrics

- DSP: `4`
- BRAM36: `0`
- LUT: `31,309`
- FF: `49,342`
- wall-clock runtime:
  - Verilator check: `65.50 s`
  - mapped utilization: `93.49 s`
- large weights emitted as RTL constants: `no`
- Verilator passed: `yes`
- Yosys stat finished within budget: `yes`, inherited from accepted `L1` at `4.07 s`

## Verdict

The safe local FIFO2 region extends through the immediate `173..182` branch
fanout ring. Under `abc9`, that wider local cluster improves the previous best
from `32,036` LUT / `50,642` FF to `31,309` LUT / `49,342` FF while keeping
`4 DSP48E1`. This is now the strongest `L1` fit point in the lane.

## Next Action

Probe one more adjacent local hop only if it is directly downstream or upstream
of this same region. If the next hop does not produce another meaningful drop,
stop widening and preserve this cluster as the best current fit-first path.
