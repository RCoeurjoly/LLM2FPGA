# L2 Tile4x64 Postbranch-Outbuf FIFO2 Proof

## Commands

- `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2-sv-sim --no-link -L`
- `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' /nix/store/363slmdlg8mv44sqxczkd0vbp9sji7ig-task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2-sim-main/obj_dir/sim_main`
- `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2-abc9-utilization --no-link --print-out-paths -L`

## Logs

- `sv-sim.log`
- `abc9-utilization.log`

## Metrics

- output:
  - `/nix/store/cj1s942zmpcwg0xz73g86k58idwavari-task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2-abc9-utilization`
- Verilator:
  - `PASS: stores 256 outputs 256`
  - build-time `ELAPSED = 85.86 s`
  - build-time `RSS_KB = 437,444`
  - direct rerun `ELAPSED = 2.25 s`
  - direct rerun `RSS_KB = 5,224`
- mapped resources:
  - `CLB LUTs = 31,907`
  - `CLB FFs = 45,932`
  - `DSP48E1 = 4`
  - `BRAM36 = 0`
  - `Estimated number of LCs = 28,653`
  - `ELAPSED = 94.03 s`
  - `RSS_KB = 562,812`
- large weights emitted as RTL constants:
  - `no`
- Yosys stat finished within budget:
  - inherited tile-kernel `yosys-stat` remains `16.09 s`

## Verdict

- The bounded tile-kernel post-branch/output hypothesis survives full `L2`
  replay.
- Delta versus the prior tiled `L2` reference:
  - `32,460 -> 31,907 LUT` (`-553`)
  - `46,740 -> 45,932 FF` (`-808`)
- This is the new tiled `L2` reference, but it still misses the first-proof
  LUT ceiling by `2,047`.

## Next Action

- Do not reopen monolithic `L2 c_fc` micro-surgery.
- Do not reopen the seam-only line.
- Treat this amended one-probe plan as spent until a stronger structural
  hypothesis exists.
