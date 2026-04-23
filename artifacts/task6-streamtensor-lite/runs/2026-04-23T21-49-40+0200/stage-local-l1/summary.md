# L1 Stage-Local Runner

## Stage

- rung: `L1`
- title: TinyStories single linear op
- model target: `block-0 mlp.c_fc extracted from tiny-stories-1m-representative-core-v64-h4`
- status: `frozen reference`

## Commands

- `/usr/bin/time -f ELAPSED=%e RSS_KB=%M nix build .#task6-l1-c-fc-redirect-yosys-stat --no-link --print-out-paths -L`
- `/usr/bin/time -f ELAPSED=%e RSS_KB=%M nix build .#task6-l1-c-fc-redirect-index-ring3-postbranch-outbuf-fifo2-sv-sim --no-link --print-out-paths -L`
- `/usr/bin/time -f ELAPSED=%e RSS_KB=%M nix build .#task6-l1-c-fc-redirect-index-ring3-postbranch-outbuf-fifo2-abc9-utilization --no-link --print-out-paths -L`

## Logs

- `yosys-stat.log`
- `sv-sim.log`
- `utilization.log`

## Structural Summary

- status: ok
- Yosys completed and emitted a stat report for the emitted SystemVerilog bundle.
- sv bundle: 52 files, 1,106,535 bytes total, main.sv 7,664 lines / 810,433 bytes
- memory modules: 1, 512 bits total, largest four 512 bits (100.00%)
- largest memories: handshake_memory_out_f32_id3=512 bits
- design cells: 12,611
- top cell types: $mux=3,722, $and=2,873, $not=2,561, $dff=2,269, $or=763

## Metrics

- Yosys stat wall-clock: 3.13 s
- Yosys stat peak RSS: 564,012 KB
- Verilator wall-clock: 2.26 s
- Verilator peak RSS: 438,320 KB
- Verilator result: `PASS: stores 16 outputs 16`
- sv-sim output: `/nix/store/5lbl4wdrz6amzwn27bm4vb51sjdqdk0n-task6-l1-c-fc-redirect-index-ring3-postbranch-outbuf-fifo2-sv-sim.json`
- CLB LUTs: 29,778
- CLB FFs: 46,352
- DSP48E1: 4
- BRAM36: 0
- large weights emitted as RTL constants: no
- LUT ceiling check: pass (`29,860`)
- FF ceiling check: pass (`59,720`)
- utilization output: `/nix/store/f6baka1zy33z4ynj88001ildj6dbp02b-task6-l1-c-fc-redirect-index-ring3-postbranch-outbuf-fifo2-abc9-utilization`
- yosys-stat output: `/nix/store/nd4zhda53wr5psq2jl0k9fa9dkg8s95x-task6-l1-c-fc-redirect-yosys.stat`

## Verdict

- `pass`

## Next Action

- Keep this as the L1 gold reference and do not reopen local hotspot surgery unless L2 forces a boundary rethink.
