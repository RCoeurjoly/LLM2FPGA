# L2 Tile64 Store-Path Fork-Only Probe

## Commands

- Functional proof:
  - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l2-c-fc-redirect-tile64-storepath-forks-sv-sim --no-link -L`

## Logs

- [sv-sim.log](/home/roland/LLM2FPGA_task6_streamtensor_lite/artifacts/task6-streamtensor-lite/runs/2026-04-23T18-18-28+0200/l2-tile64-storepath-forks-proof/sv-sim.log)

## Metrics

- Verilator passed:
  - `no`
- Observed stores:
  - `64`
- Expected stores:
  - `256`
- Wall-clock / RSS:
  - `83.16 s` / `438,492 KB`
- Yosys stat finished within budget:
  - `not rerun`
- Large weights emitted as RTL constants:
  - `no`

## Verdict

- Keeping `handshake_buffer246`, `247`, and `255` unchanged does not fix the
  seam.
- The fork-helper-only follow-up reproduces the same early-abort signature as
  the wider cluster probe, so the current local store-path helper line is
  closed.

## Next Action

- Do not spend another local `tile64` seam slice on helper replacements in
  this neighborhood.
- Any further `L2 c_fc` work now needs a new structural hypothesis that is
  different from store-path helper substitution.
