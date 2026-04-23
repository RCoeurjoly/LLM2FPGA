# Deliberate Control-Merge Hotspot Proof

## Commands

`nix-store --delete /nix/store/1xphnja7abzdswcfxqmhcfz3lj0y1wja-task6-l1-c-fc-redirect-index-ring3-ctrlmerge-fifo2-sim-main /nix/store/llngvrfdwz6a78hwml7ia2k6pam9i56c-task6-l1-c-fc-redirect-index-ring3-ctrlmerge-fifo2-sv-sim.json >/dev/null`

`/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-ring3-ctrlmerge-fifo2-sv-sim --no-link -L`

`/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-ring3-ctrlmerge-fifo2-abc9-utilization --no-link --print-out-paths`

## Logs

- `task6-l1-c-fc-redirect-index-ring3-ctrlmerge-fifo2-sv-sim`
  - `PASS: stores 16 outputs 16`
  - `ELAPSED=149.22`
  - `RSS_KB=436284`
- `task6-l1-c-fc-redirect-index-ring3-ctrlmerge-fifo2-abc9-utilization`
  - output: `/nix/store/h6mh3s3skf8spnczfabhl71khhb6asgv-task6-l1-c-fc-redirect-index-ring3-ctrlmerge-fifo2-abc9-utilization`
  - `ELAPSED=156.72`
  - `RSS_KB=562952`

## Metrics

- DSP: `4`
- BRAM36: `0`
- LUT: `30,360`
- FF: `47,384`
- wall-clock runtime:
  - Verilator check: `149.22 s`
  - mapped utilization: `156.72 s`
- large weights emitted as RTL constants: `no`
- Verilator passed: `yes`
- Yosys stat finished within budget: `yes`, inherited from accepted `L1` at `4.07 s`

## Verdict

Replacing the nearby control/merge buffers `194`, `220`, `229`, and `237` on
top of the frozen ring-3 region is functionally safe, but it does not improve
fit. Under `abc9`, the hotspot lands at `30,360` LUT / `47,384` FF with
`4 DSP48E1`, which is `40` LUT worse than the frozen
`task6-l1-c-fc-redirect-index-ring3-fifo2-abc9` reference at
`30,320` LUT / `47,392` FF.

## Next Action

Keep `task6-l1-c-fc-redirect-index-ring3-fifo2-abc9` frozen as the current
`L1` reference. Close this local control/merge branch and run the pending
one-block-top Yosys gate before any promotion discussion.

