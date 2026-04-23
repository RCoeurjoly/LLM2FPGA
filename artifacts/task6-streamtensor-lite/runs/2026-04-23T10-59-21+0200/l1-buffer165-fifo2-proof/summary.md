# Selective `buffer165` FIFO2 Proof

## Commands

`/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-buffer165-fifo2-sv-sim --no-link -L`

`/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-buffer165-fifo2-utilization --no-link --print-out-paths`

## Logs

- `task6-l1-c-fc-redirect-buffer165-fifo2-sv-sim`
  - `PASS: stores 16 outputs 16`
  - `ELAPSED=56.13`
  - `RSS_KB=437056`
- `task6-l1-c-fc-redirect-buffer165-fifo2-utilization`
  - output: `/nix/store/ay0550kjz47qmv3ig0wrr212sflz78fd-task6-l1-c-fc-redirect-buffer165-fifo2-utilization`
  - `ELAPSED=66.21`
  - `RSS_KB=562608`

## Metrics

- DSP: `4`
- BRAM36: `0`
- LUT: `33,020`
- FF: `51,292`
- wall-clock runtime:
  - Verilator check: `56.13 s`
  - mapped utilization: `66.21 s`
- large weights emitted as RTL constants: `no`
- Verilator passed: `yes`
- Yosys stat finished within budget: `yes`, inherited from accepted `L1` at `4.07 s`

## Verdict

Selective replacement is structurally viable. Swapping only `handshake_buffer165`
to the lean FIFO2 implementation preserves the kernel proof and gives a small
mapped win over the accepted non-`abc9` `L1` baseline: `33,116 -> 33,020` LUT
and `51,296 -> 51,292` FF. The improvement is too small to matter on its own,
but it proves that local site-by-site reduction is safer than another whole-class
override.

## Next Action

Widen the same FIFO2 replacement only within the local loop-index distribution
spine around `handshake_buffer165`, keeping Verilator as the immediate gate
before mapped utilization.
