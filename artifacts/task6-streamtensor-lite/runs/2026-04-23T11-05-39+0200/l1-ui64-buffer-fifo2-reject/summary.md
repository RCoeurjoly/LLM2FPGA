# Class-Wide `ui64` FIFO2 Rejection

## Commands

`/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-ui64-buffer-fifo2-sv-sim --no-link -L`

## Logs

- `task6-l1-c-fc-redirect-ui64-buffer-fifo2-sv-sim`
  - `Timeout waiting for redirected GEMV completion`
  - `ELAPSED=42.50`
  - `RSS_KB=437644`

## Metrics

- DSP: `n/a`
- BRAM36: `n/a`
- LUT: `n/a`
- FF: `n/a`
- wall-clock runtime:
  - Verilator check: `42.50 s`
- large weights emitted as RTL constants: `no`, unchanged from accepted `L1`
- Verilator passed: `no`
- Yosys stat finished within budget: `yes`, unchanged from accepted `L1` at `4.07 s`

## Verdict

This is the third failure of the same whole-class `ui64` buffer replacement
idea. The strict one-slot override, the fall-through one-slot override, and now
the class-wide FIFO2 override all fail the `L1` kernel contract, so the lane
should stop spending slices on whole-class buffer swaps.

## Next Action

Move to selective local replacement only. Keep the accepted `L1` contract as the
gate and widen from `handshake_buffer165` only within the same loop-index spine.
