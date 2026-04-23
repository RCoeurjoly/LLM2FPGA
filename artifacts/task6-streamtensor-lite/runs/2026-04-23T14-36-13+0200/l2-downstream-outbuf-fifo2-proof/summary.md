# L2 Downstream Out-Buffer FIFO2 Probe

## Commands

- Functional proof:
  - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l2-c-fc-redirect-downstream-outbuf-fifo2-sv-sim --no-link -L`
- Mapped utilization:
  - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l2-c-fc-redirect-downstream-outbuf-fifo2-abc9-utilization --no-link --print-out-paths -L`

## Logs

- [sv-sim.log](/home/roland/LLM2FPGA_task6_streamtensor_lite/artifacts/task6-streamtensor-lite/runs/2026-04-23T14-36-13+0200/l2-downstream-outbuf-fifo2-proof/sv-sim.log)
- [abc9-utilization.log](/home/roland/LLM2FPGA_task6_streamtensor_lite/artifacts/task6-streamtensor-lite/runs/2026-04-23T14-36-13+0200/l2-downstream-outbuf-fifo2-proof/abc9-utilization.log)

## Metrics

- DSP:
  - `4`
- BRAM36:
  - `0`
- LUT:
  - `51,832`
- FF:
  - `64,743`
- Estimated mapped LCs:
  - `47,802`
- Verilator passed:
  - `yes`
- Yosys stat finished within budget:
  - `not rerun`
- Large weights emitted as RTL constants:
  - `no`
- Verilator wall-clock / RSS:
  - `80.01 s` / `437,188 KB`
- `abc9` wall-clock / RSS:
  - `261.04 s` / `563,320 KB`
- Delta vs existing `L2` kernel:
  - `LUT +1,597`
  - `FF -780`
- Delta vs aligned `L2` replay:
  - `LUT +210`
  - `FF -130`
- Delta vs current `L1` reference:
  - `LUT +22,054`
  - `FF +18,391`

## Verdict

- This first `L2`-native probe keeps external weights, `4 DSP48E1`, and the
  kernel contract, but it still loses on the official scorecard metric.
- The mapped `Estimated number of LCs` improves to `47,802`, but official CLB
  LUTs rise again to `51,832`, so this is another clean `L2 c_fc` miss rather
  than a fit win.

## Next Action

- Stop `L2 c_fc` micro-surgery after this second clean move-on signal and pivot
  within StreamTensor-lite to the reserve fallback boundary `mlp.c_proj`.
