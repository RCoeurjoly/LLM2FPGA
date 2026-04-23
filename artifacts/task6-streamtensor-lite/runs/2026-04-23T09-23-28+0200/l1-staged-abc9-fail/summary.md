# Staged `abc9` Failure

## Commands

`/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-staged-abc9-utilization --no-link --print-out-paths`

## Logs

- build runtime:
  - `ELAPSED=15.14`
  - `RSS_KB=564392`
- failure point:
  - `task6-l1-c-fc-redirect-staged-abc9-stage8.il`
- key error:
  - `ERROR: Module \`FDRE' is used with parameters but is not parametric!`

## Metrics

- DSP: `n/a`, no mapped JSON produced
- BRAM36: `n/a`, no mapped JSON produced
- LUT: `n/a`, no mapped JSON produced
- FF: `n/a`, no mapped JSON produced
- wall-clock runtime: `15.14 s`
- large weights emitted as RTL constants: `no`, unchanged from accepted `L1` kernel proof before staged mapping
- Verilator passed: `yes`, inherited from `task6-l1-c-fc-redirect-sv-sim`
- Yosys stat finished within budget: `yes`, inherited from `task6-l1-c-fc-redirect-yosys-stat` at `4.07 s`

## Verdict

Reject the staged micro-flow for now. It fails before mapped utilization, and
fixing the `FDRE` parameter handling would be flow plumbing rather than a
fit-first Task 6 proof step.

## Next Action

Keep direct `abc9` as the best available mapped `L1` result and move the next
slice to structural LUT reduction in the kernel RTL path.
