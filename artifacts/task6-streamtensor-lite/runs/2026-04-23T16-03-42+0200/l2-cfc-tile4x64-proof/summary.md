# L2 C_FC Tile4x64 Proof

## Commands

- Cheap kernel gate:
  - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l2-c-fc-redirect-tile64-yosys-stat --no-link -L`
- Full-contract Verilator proof:
  - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l2-c-fc-redirect-tile4x64-sv-sim --no-link -L`
- Mapped utilization:
  - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l2-c-fc-redirect-tile4x64-abc9-utilization --no-link --print-out-paths -L`

## Logs

- [tile64-yosys-stat.log](/home/roland/LLM2FPGA_task6_streamtensor_lite/artifacts/task6-streamtensor-lite/runs/2026-04-23T16-03-42+0200/l2-cfc-tile4x64-proof/tile64-yosys-stat.log)
- [tile4x64-sv-sim.log](/home/roland/LLM2FPGA_task6_streamtensor_lite/artifacts/task6-streamtensor-lite/runs/2026-04-23T16-03-42+0200/l2-cfc-tile4x64-proof/tile4x64-sv-sim.log)
- [tile4x64-abc9-utilization.log](/home/roland/LLM2FPGA_task6_streamtensor_lite/artifacts/task6-streamtensor-lite/runs/2026-04-23T16-03-42+0200/l2-cfc-tile4x64-proof/tile4x64-abc9-utilization.log)

## Metrics

- DSP:
  - `4`
- BRAM36:
  - `0`
- LUT:
  - `32,460`
- FF:
  - `46,740`
- Estimated mapped LCs:
  - `29,089`
- Verilator passed:
  - `yes`
- Yosys stat finished within budget:
  - `yes`
  - `16.09 s`
- Large weights emitted as RTL constants:
  - `no`
- Tile64 Yosys stat wall-clock / RSS:
  - `16.09 s` / `561,720 KB`
- Verilator wall-clock / RSS:
  - `161.55 s` / `437,564 KB`
- `abc9` wall-clock / RSS:
  - `153.09 s` / `563,056 KB`
- Delta vs existing `L2` kernel:
  - `LUT -17,775`
  - `FF -18,783`
- Delta vs current `L1` reference:
  - `LUT +2,682`
  - `FF +388`

## Verdict

- The bounded tiled-wrapper hypothesis is supported.
- Reusing one external-weight `64 -> 64` kernel across four phases removes most
  of the monolithic `L2` wrapper overhead while keeping `4 DSP48E1` and the
  full `L2` contract.
- This is the new best `L2 c_fc` point, but it still misses the `29,860` LUT
  ceiling, so `L3` remains blocked.

## Next Action

- Freeze `task6-l2-c-fc-redirect-tile4x64-abc9-utilization` as the new `L2`
  reference.
- If continuing on `L2 c_fc`, spend at most one more bounded probe on the
  reusable `64 -> 64` tile kernel or tile/wrapper seam, not the abandoned
  monolithic `64 -> 256` path.
