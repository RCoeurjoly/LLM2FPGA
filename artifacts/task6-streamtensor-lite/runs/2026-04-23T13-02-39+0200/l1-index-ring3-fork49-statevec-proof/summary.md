# Fork49 Statevec Proof

## Commands

`/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-ring3-fork49-statevec-sv-sim --no-link -L`

`/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-ring3-fork49-statevec-abc9-utilization --no-link --print-out-paths`

## Logs

- `task6-l1-c-fc-redirect-index-ring3-fork49-statevec-sv-sim`
  - `PASS: stores 16 outputs 16`
  - `ELAPSED=147.32`
  - `RSS_KB=437320`
- `task6-l1-c-fc-redirect-index-ring3-fork49-statevec-abc9-utilization`
  - output: `/nix/store/gii6p7aprr0szvjfr8vg6m1sylywa081-task6-l1-c-fc-redirect-index-ring3-fork49-statevec-abc9-utilization`
  - `ELAPSED=144.56`
  - `RSS_KB=562532`

## Metrics

- DSP: `4`
- BRAM36: `0`
- LUT: `30,358`
- FF: `47,392`
- wall-clock runtime:
  - Verilator check: `147.32 s`
  - mapped utilization: `144.56 s`
- large weights emitted as RTL constants: `no`
- Verilator passed: `yes`
- Yosys stat finished within budget: `yes`, inherited from accepted `L1` at `4.07 s`

## Verdict

Replacing only `handshake_fork49`, the five-way local `ui1` selector fork after
`handshake_buffer263`, is functionally safe but not a fit win. Under `abc9`,
the probe lands at `30,358` LUT / `47,392` FF with `4 DSP48E1`, which is `38`
LUT worse than the frozen ring-3 reference at `30,320` LUT / `47,392` FF.

## Next Action

Keep `task6-l1-c-fc-redirect-index-ring3-fifo2-abc9` frozen as the current
`L1` reference. Treat this as the third deliberate post-ring-3 hotspot miss and
move on to a different fit lever instead of more local buffer or fork surgery.
