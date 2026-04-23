# Selector Cluster FIFO2 Proof

## Commands

`/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-ring3-selectcluster-fifo2-sv-sim --no-link -L`

`/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-ring3-selectcluster-fifo2-abc9-utilization --no-link --print-out-paths`

## Logs

- `task6-l1-c-fc-redirect-index-ring3-selectcluster-fifo2-sv-sim`
  - `PASS: stores 16 outputs 16`
  - `ELAPSED=149.01`
  - `RSS_KB=437064`
- `task6-l1-c-fc-redirect-index-ring3-selectcluster-fifo2-abc9-utilization`
  - output: `/nix/store/9d5q0szcjv49jmnwjnr5v2hz8jliffqd-task6-l1-c-fc-redirect-index-ring3-selectcluster-fifo2-abc9-utilization`
  - `ELAPSED=147.09`
  - `RSS_KB=562120`

## Metrics

- DSP: `4`
- BRAM36: `0`
- LUT: `30,358`
- FF: `47,392`
- wall-clock runtime:
  - Verilator check: `149.01 s`
  - mapped utilization: `147.09 s`
- large weights emitted as RTL constants: `no`
- Verilator passed: `yes`
- Yosys stat finished within budget: `yes`, inherited from accepted `L1` at `4.07 s`

## Verdict

Replacing the local selector-side `buffer255 -> fork46` chain with one helper
is functionally safe but not a fit win. Under `abc9`, the probe lands at
`30,358` LUT / `47,392` FF with `4 DSP48E1`, tying the earlier `fork49`
statevec helper and still missing the frozen ring-3 reference at
`30,320` LUT / `47,392` FF by `38` LUT.

## Next Action

Keep `task6-l1-c-fc-redirect-index-ring3-fifo2-abc9` frozen as the current
`L1` reference. Stop spending effort on the selector-control tree and move to a
different non-selector fit lever instead.
