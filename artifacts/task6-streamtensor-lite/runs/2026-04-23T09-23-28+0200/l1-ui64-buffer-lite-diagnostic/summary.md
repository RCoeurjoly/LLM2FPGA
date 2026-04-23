# `ui64` Buffer-Lite Diagnostic

## Commands

`/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-ui64-buffer-lite-sv-sim --no-link -L`

`/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-ui64-buffer-lite-utilization --no-link --print-out-paths`

## Logs

- tracked-file reminder:
  - the first sim rerun failed until `rtl/task6/handshake_buffer_in_ui64_out_ui64_2slots_seq.sv`
    was git-tracked, because untracked files are excluded from the flake source
    snapshot
- functional attempts:
  - strict one-slot FIFO override: timed out
  - fall-through one-slot FIFO override: timed out
- final sim result:
  - `Timeout waiting for redirected GEMV completion`
  - `ELAPSED=22.69`
  - `RSS_KB=437508`
- utilization result:
  - output: `/nix/store/aw5y4ri37p3zp0dksym0y2f2agm5p5ax-task6-l1-c-fc-redirect-ui64-buffer-lite-utilization`
  - `ELAPSED=53.61`
  - `RSS_KB=562884`

## Metrics

- DSP: `4`
- BRAM36: `0`
- LUT: `20,725`
- FF: `15,731`
- wall-clock runtime:
  - Verilator check: `22.69 s`
  - mapped utilization: `53.61 s`
- large weights emitted as RTL constants: `no`
- Verilator passed: `no`, kernel proof timed out
- Yosys stat finished within budget: `yes`, inherited from the accepted `L1` proof at `4.07 s`

## Verdict

This is fit-only evidence, not an accepted lane proof. The `ui64` two-slot
buffers clearly dominate area, because replacing that class alone drops the
mapped design from `32,236` LUT best validated `L1` to `20,725` LUT while
keeping `4 DSP`. But both one-slot replacements time out the kernel-only
contract, so the current override is not functionally valid.

## Next Action

Stop spending more slices on generic one-slot `ui64` drop-ins. The next useful
attempt is a semantically closer reduction of `ui64` buffer state on a subset of
sites, with the `L1` contract test kept as the immediate gate.
