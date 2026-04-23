# L2 Tile64 Kernel Postbranch-Outbuf FIFO2 Proof

## Commands

- `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l2-c-fc-redirect-tile64-postbranch-outbuf-fifo2-abc9-utilization --no-link --print-out-paths -L`

## Logs

- `build.log`

## Metrics

- output:
  - `/nix/store/jxgi6fqjd9hivzhkgmjqpnm1m4ghkwx9-task6-l2-c-fc-redirect-tile64-postbranch-outbuf-fifo2-abc9-utilization`
- mapped resources:
  - `CLB LUTs = 31,968`
  - `CLB FFs = 45,928`
  - `DSP48E1 = 4`
  - `BRAM36 = 0`
  - `Estimated number of LCs = 28,689`
- runtime:
  - `ELAPSED = 93.06 s`
  - `RSS_KB = 563,328`
- large weights emitted as RTL constants:
  - `no`
- Verilator:
  - not run at the kernel gate
- Yosys stat finished within budget:
  - inherited tile-kernel `yosys-stat` remains `16.09 s`

## Verdict

- The bounded tile-kernel probe is a real fit win.
- Delta versus the untouched `64 -> 64` tile kernel:
  - `32,478 -> 31,968 LUT` (`-510`)
  - `46,736 -> 45,928 FF` (`-808`)

## Next Action

- Replay the same bounded tile-kernel cut into the full `4 x 64` wrapper.

