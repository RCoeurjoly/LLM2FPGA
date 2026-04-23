# L2 Post-Branch FIFO2 Replay

## Commands

- Functional proof:
  - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l2-c-fc-redirect-postbranch-fifo2-sv-sim --no-link -L`
- Mapped utilization:
  - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l2-c-fc-redirect-postbranch-fifo2-abc9-utilization --no-link --print-out-paths -L`

## Logs

- [sv-sim.log](/home/roland/LLM2FPGA_task6_streamtensor_lite/artifacts/task6-streamtensor-lite/runs/2026-04-23T14-23-08+0200/l2-postbranch-fifo2-proof/sv-sim.log)
- [abc9-utilization.log](/home/roland/LLM2FPGA_task6_streamtensor_lite/artifacts/task6-streamtensor-lite/runs/2026-04-23T14-23-08+0200/l2-postbranch-fifo2-proof/abc9-utilization.log)

## Metrics

- DSP:
  - `4`
- BRAM36:
  - `0`
- LUT:
  - `51,622`
- FF:
  - `64,873`
- Verilator passed:
  - `yes`
- Yosys stat finished within budget:
  - `not rerun`
- Large weights emitted as RTL constants:
  - `no`
- Verilator wall-clock / RSS:
  - `77.00 s` / `437,400 KB`
- `abc9` wall-clock / RSS:
  - `255.15 s` / `563,416 KB`
- Delta vs existing `L2` kernel:
  - `LUT +1,387`
  - `FF -650`
- Delta vs current `L1` reference:
  - `LUT +21,844`
  - `FF +18,521`

## Verdict

- This aligned replay preserves the `L2` kernel contract and keeps external
  weights plus `4 DSP48E1`, but it does not preserve the `L1` fit win.
- The first structurally aligned `L2` replay already worsens LUT, so this
  exact replay path should be closed instead of widened blindly.

## Next Action

- If `L2` work continues, target the changed downstream neighborhood around
  `buffer272..280` instead of reusing the `L1` patch literally.
