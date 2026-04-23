# L1 `c_proj` Redirect Proof

## Commands

- Functional proof:
  - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-proj-redirect-sv-sim --no-link -L`
- Mapped utilization:
  - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-proj-redirect-utilization --no-link --print-out-paths -L`

## Logs

- [sv-sim.log](/home/roland/LLM2FPGA_task6_streamtensor_lite/artifacts/task6-streamtensor-lite/runs/2026-04-23T15-01-29+0200/l1-cproj-redirect-proof/sv-sim.log)
- [utilization.log](/home/roland/LLM2FPGA_task6_streamtensor_lite/artifacts/task6-streamtensor-lite/runs/2026-04-23T15-01-29+0200/l1-cproj-redirect-proof/utilization.log)

## Metrics

- DSP:
  - `4`
- BRAM36:
  - `0`
- LUT:
  - `32,393`
- FF:
  - `50,864`
- Verilator passed:
  - `yes`
- Yosys stat finished within budget:
  - `yes`
  - inherited `task6-l1-c-proj-redirect-yosys-stat` remained at `17.52 s`
- Large weights emitted as RTL constants:
  - `no`
- Verilator wall-clock / RSS:
  - `106.74 s` / `437,244 KB`
- Mapped-utilization wall-clock / RSS:
  - `97.85 s` / `562,712 KB`
- Delta vs raw `L1 c_fc` redirect:
  - `LUT -723`
  - `FF -432`
- Delta vs frozen `L1 c_fc` reference:
  - `LUT +2,615`
  - `FF +4,512`

## Verdict

- The first redirected `L1 c_proj` kernel is a real executable fallback proof:
  it passes the captured contract and keeps `4 DSP48E1` with external weights.
- It is not a mainline fit win. The base mapped result is still well above the
  LUT ceiling and clearly behind the frozen `L1 c_fc` reference.

## Next Action

- Run exactly one cheap mapper-only discriminator on the untouched `L1 c_proj`
  kernel, then keep it reserve-only unless that result changes the lane order.
