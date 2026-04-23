# L0 Stage-Local Runner

## Stage

- rung: `L0`
- title: Synthetic 64x64 GEMV smoke
- model target: `task6-l0-gemv64 external-weight kernel`
- status: `running`

## Commands

- `/usr/bin/time -f ELAPSED=%e RSS_KB=%M nix build .#task6-l0-gemv64-yosys-stat --no-link --print-out-paths -L`
- `/usr/bin/time -f ELAPSED=%e RSS_KB=%M nix build .#task6-l0-gemv64-sv-sim --no-link --print-out-paths -L`
- `/usr/bin/time -f ELAPSED=%e RSS_KB=%M nix build .#task6-l0-gemv64-utilization --no-link --print-out-paths -L`

## Logs

- `yosys-stat.log`
- `sv-sim.log`
- `utilization.log`

## Structural Summary

- status: ok
- Yosys completed and emitted a stat report for the emitted SystemVerilog bundle.
- sv bundle: 50 files, 980,110 bytes total, main.sv 7,039 lines / 711,807 bytes
- memory modules: 1, 2,048 bits total, largest four 2,048 bits (100.00%)
- largest memories: handshake_memory_out_f32_id3=2,048 bits
- design cells: 11,471
- top cell types: $mux=3,343, $and=2,627, $not=2,336, $dff=2,049, $or=699

## Metrics

- Yosys stat wall-clock: 3.17 s
- Yosys stat peak RSS: 561,868 KB
- Verilator wall-clock: 2.26 s
- Verilator peak RSS: 438,160 KB
- Verilator result: `PASS: stores 64 outputs 64`
- sv-sim output: `/nix/store/49n76ar5b42sd0mjqcapd3v4spwzm571-task6-l0-gemv64-sv-sim.json`
- CLB LUTs: 32,449
- CLB FFs: 46,736
- DSP48E1: 4
- BRAM36: 0
- large weights emitted as RTL constants: no
- LUT ceiling check: fail (`29,860`)
- FF ceiling check: pass (`59,720`)
- utilization output: `/nix/store/l92sjk0mk573gq1wk6fysp3ljxg05krl-task6-l0-gemv64-utilization`
- yosys-stat output: `/nix/store/a9li9yklyp404pz3lvsximh35kp1kvda-task6-l0-gemv64-yosys.stat`

## Verdict

- `fail-lut`

## Next Action

- Use only for kernel plumbing and DSP validation; do not treat it as a scorecard-cleared reference while LUT stays above the ceiling.
