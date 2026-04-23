# Direct `abc9` Mapper Check

## Commands

`/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l0-gemv64-abc9-utilization --no-link --print-out-paths`

`/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-abc9-utilization --no-link --print-out-paths`

## Logs

- `task6-l0-gemv64-abc9-utilization`
  - output: `/nix/store/mp68ywi5hy4zr5ldvjmm0zib5a5anddh-task6-l0-gemv64-abc9-utilization`
  - `ELAPSED=94.83`
  - `RSS_KB=561388`
- `task6-l1-c-fc-redirect-abc9-utilization`
  - output: `/nix/store/iamh08ddr6pahr3py2ach61abzpxbrqs-task6-l1-c-fc-redirect-abc9-utilization`
  - `ELAPSED=94.27`
  - `RSS_KB=561892`

## Metrics

- `L0` direct `abc9`
  - DSP: `4`
  - BRAM36: `0`
  - LUT: `32,478`
  - FF: `46,736`
  - wall-clock runtime: `94.83 s`
  - large weights emitted as RTL constants: `no`
  - Verilator passed: `yes`, inherited from `task6-l0-gemv64-sv-sim`
  - Yosys stat finished within budget: `yes`, inherited from `task6-l0-gemv64-yosys-stat` at `9.23 s`
- `L1` direct `abc9`
  - DSP: `4`
  - BRAM36: `0`
  - LUT: `32,236`
  - FF: `51,296`
  - wall-clock runtime: `94.27 s`
  - large weights emitted as RTL constants: `no`
  - Verilator passed: `yes`, inherited from `task6-l1-c-fc-redirect-sv-sim`
  - Yosys stat finished within budget: `yes`, inherited from `task6-l1-c-fc-redirect-yosys-stat` at `4.07 s`

## Verdict

- `L0`: reject mapper-only change as a fit tactic because LUT slightly worsens
  from `32,449` to `32,478`
- `L1`: keep as the best mapped result so far because LUT improves from
  `33,116` to `32,236`, but the lane still misses the ceiling by `2,376`

## Next Action

Move to RTL-structural LUT reduction on the shared float kernel path, not more
direct mapper-only variants.
