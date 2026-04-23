# Selective Index Ring-2 FIFO2 `abc9` Proof

## Commands

`/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-ring2-fifo2-sv-sim --no-link -L`

`/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-ring2-fifo2-abc9-utilization --no-link --print-out-paths`

## Logs

- `task6-l1-c-fc-redirect-index-ring2-fifo2-sv-sim`
  - `PASS: stores 16 outputs 16`
  - `ELAPSED=69.90`
  - `RSS_KB=436804`
- `task6-l1-c-fc-redirect-index-ring2-fifo2-abc9-utilization`
  - output: `/nix/store/saahgj5jaiv7bvhxjds1qypv62q57wbg-task6-l1-c-fc-redirect-index-ring2-fifo2-abc9-utilization`
  - `ELAPSED=93.67`
  - `RSS_KB=563284`

## Metrics

- DSP: `4`
- BRAM36: `0`
- LUT: `30,762`
- FF: `48,302`
- wall-clock runtime:
  - Verilator check: `69.90 s`
  - mapped utilization: `93.67 s`
- large weights emitted as RTL constants: `no`
- Verilator passed: `yes`
- Yosys stat finished within budget: `yes`, inherited from accepted `L1` at `4.07 s`

## Verdict

The safe local FIFO2 region extends through `handshake_buffer185..192`. Under
`abc9`, that wider cluster improves the previous best from `31,309` LUT /
`49,342` FF to `30,762` LUT / `48,302` FF while keeping `4 DSP48E1`. This is
the strongest `L1` mapped point in the lane so far and leaves only `902` LUT
over the target ceiling.

## Next Action

Probe the connected `213..219` mux-return buffers only if they still count as
the same local region. If that hop does not produce another meaningful drop,
stop widening and preserve this cluster as the best current fit-first path.
