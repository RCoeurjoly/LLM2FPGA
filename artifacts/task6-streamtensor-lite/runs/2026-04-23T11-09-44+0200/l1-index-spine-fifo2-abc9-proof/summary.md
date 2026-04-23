# Selective Index-Spine FIFO2 `abc9` Proof

## Commands

`/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-spine-fifo2-abc9-utilization --no-link --print-out-paths`

## Logs

- `task6-l1-c-fc-redirect-index-spine-fifo2-abc9-utilization`
  - output: `/nix/store/0hxm9fclxr0sgg5wl6nq2w0r7f568p60-task6-l1-c-fc-redirect-index-spine-fifo2-abc9-utilization`
  - `ELAPSED=92.79`
  - `RSS_KB=562772`

## Metrics

- DSP: `4`
- BRAM36: `0`
- LUT: `32,036`
- FF: `50,642`
- wall-clock runtime:
  - mapped utilization: `92.79 s`
- large weights emitted as RTL constants: `no`
- Verilator passed: `yes`, inherited from `task6-l1-c-fc-redirect-index-spine-fifo2-sv-sim`
- Yosys stat finished within budget: `yes`, inherited from accepted `L1` at `4.07 s`

## Verdict

The safe local `handshake_buffer160..165` FIFO2 reduction and `abc9` do stack.
The combined point improves the accepted base `L1` proof from `33,116` LUT /
`51,296` FF to `32,036` LUT / `50,642` FF while keeping `4 DSP48E1`. It also
beats plain `abc9` by `200` LUT, so the selective buffer path is no longer just
noise.

## Next Action

Try one more adjacent local buffer cluster under the same `abc9` recipe. If the
next cluster does not produce another meaningful drop, stop widening and record
the selective buffer path as useful but insufficient for the current ceiling.
