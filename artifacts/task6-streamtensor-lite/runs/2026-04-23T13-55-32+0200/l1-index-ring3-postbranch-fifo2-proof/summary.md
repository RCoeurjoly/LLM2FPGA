# L1 Post-Branch FIFO2 Proof

## Commands

- Functional proof:
  - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-ring3-postbranch-fifo2-sv-sim --no-link -L`
- Mapped utilization:
  - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-ring3-postbranch-fifo2-abc9-utilization --no-link --print-out-paths`

## Logs

- [sv-sim.log](/home/roland/LLM2FPGA_task6_streamtensor_lite/artifacts/task6-streamtensor-lite/runs/2026-04-23T13-55-32+0200/l1-index-ring3-postbranch-fifo2-proof/sv-sim.log)
- [abc9-utilization.log](/home/roland/LLM2FPGA_task6_streamtensor_lite/artifacts/task6-streamtensor-lite/runs/2026-04-23T13-55-32+0200/l1-index-ring3-postbranch-fifo2-proof/abc9-utilization.log)

## Metrics

- DSP:
  - `4`
- BRAM36:
  - `0`
- LUT:
  - `29,967`
- FF:
  - `46,612`
- Verilator passed:
  - `yes`
- Yosys stat finished within budget:
  - `yes`
- Large weights emitted as RTL constants:
  - `no`
- Verilator wall-clock / RSS:
  - `149.45 s` / `437,752 KB`
- `abc9` wall-clock / RSS:
  - `149.96 s` / `562,980 KB`
- Delta vs frozen ring-3 reference:
  - `LUT -353`
  - `FF -780`

## Verdict

- The downstream post-branch `ui64` data cluster is a real non-selector fit
  lever.
- This cut is still `107 LUT` above the `L1` ceiling, so it is a strong but
  not yet scorecard-clearing result.

## Next Action

- Extend the same bounded fit lever only through the immediate post-fork
  `ui64` out-buffers `279` and `280`.
