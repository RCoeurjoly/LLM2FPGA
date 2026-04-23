# L2 Tile64 Seam Proof

## Commands

- `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l2-c-fc-redirect-tile64-abc9-utilization --no-link --print-out-paths -L`

## Logs

- `tile64-abc9-utilization.log`

## Metrics

- output:
  - `/nix/store/1jsmab9fgsjdv0n4czy9pqcgmy9l6rns-task6-l2-c-fc-redirect-tile64-abc9-utilization`
- mapped resources:
  - `CLB LUTs = 32,478`
  - `CLB FFs = 46,736`
  - `DSP48E1 = 4`
  - `BRAM36 = 0`
  - `Estimated number of LCs = 29,116`
- runtime:
  - `ELAPSED = 92.53 s`
  - `RSS_KB = 563,708`
- large weights emitted as RTL constants:
  - `no`
- Verilator:
  - not run in this step
- Yosys stat finished within budget:
  - already established earlier for `task6-l2-c-fc-redirect-tile64-yosys-stat`

## Verdict

- The wrapper seam is not the dominant tiled `L2` cost center.
- Compared against the current tiled wrapper reference
  (`32,460 LUT / 46,740 FF`), the seam delta is only:
  - `-18 LUT`
  - `+4 FF`

## Next Action

- Spend the single bounded follow-up probe on the tile kernel, not on another
  seam-only edit.

