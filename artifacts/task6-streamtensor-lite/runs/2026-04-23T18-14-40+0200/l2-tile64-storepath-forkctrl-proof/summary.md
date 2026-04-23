# L2 Tile64 Store-Path Fork/Ctrl Probe

## Commands

- Functional proof:
  - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l2-c-fc-redirect-tile64-storepath-forkctrl-sv-sim --no-link -L`

## Logs

- [sv-sim.log](/home/roland/LLM2FPGA_task6_streamtensor_lite/artifacts/task6-streamtensor-lite/runs/2026-04-23T18-14-40+0200/l2-tile64-storepath-forkctrl-proof/sv-sim.log)

## Metrics

- Verilator passed:
  - `no`
- Observed stores:
  - `64`
- Expected stores:
  - `256`
- Wall-clock / RSS:
  - `80.97 s` / `438,164 KB`
- Yosys stat finished within budget:
  - `not rerun`
- Large weights emitted as RTL constants:
  - `no`

## Verdict

- The seam-local combined helper is not a valid drop-in.
- Replacing `fork50`, `fork51`, `fork52`, and the zero-width control buffers
  `246`, `247`, `255` together breaks the tiled `L2` contract early, with only
  `64` observed stores.

## Next Action

- Narrow the same seam to a fork-state-only follow-up:
  - keep the zero-width control buffers untouched
  - isolate `fork50`, `fork51`, and `fork52` as the next bounded probe
