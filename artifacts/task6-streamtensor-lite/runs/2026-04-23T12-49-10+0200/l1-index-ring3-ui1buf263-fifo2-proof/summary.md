# UI1 Selector Buffer263 FIFO2 Proof

## Commands

`/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-ring3-ui1buf263-fifo2-sv-sim --no-link -L`

`/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-ring3-ui1buf263-fifo2-abc9-utilization --no-link --print-out-paths`

## Logs

- `task6-l1-c-fc-redirect-index-ring3-ui1buf263-fifo2-sv-sim`
  - `PASS: stores 16 outputs 16`
  - `ELAPSED=150.24`
  - `RSS_KB=436780`
- `task6-l1-c-fc-redirect-index-ring3-ui1buf263-fifo2-abc9-utilization`
  - output: `/nix/store/ga92apld656zs2h1w0515iw76yr9ppmm-task6-l1-c-fc-redirect-index-ring3-ui1buf263-fifo2-abc9-utilization`
  - `ELAPSED=150.20`
  - `RSS_KB=561796`

## Metrics

- DSP: `4`
- BRAM36: `0`
- LUT: `30,370`
- FF: `47,388`
- wall-clock runtime:
  - Verilator check: `150.24 s`
  - mapped utilization: `150.20 s`
- large weights emitted as RTL constants: `no`
- Verilator passed: `yes`
- Yosys stat finished within budget: `yes`, inherited from accepted `L1` at `4.07 s`

## Verdict

Replacing only `handshake_buffer263`, the local `ui1` selector buffer between
`arith_cmpi5` and `handshake_fork49`, is functionally safe but not a fit win.
Under `abc9`, the probe lands at `30,370` LUT / `47,388` FF with `4 DSP48E1`,
which is `50` LUT worse than the frozen ring-3 reference at
`30,320` LUT / `47,392` FF.

## Next Action

Keep `task6-l1-c-fc-redirect-index-ring3-fifo2-abc9` frozen as the current
`L1` reference. Treat local `ui1` selector-buffer trimming as another weak
signal rather than the next default lane direction.

