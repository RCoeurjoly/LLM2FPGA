# L2 Stage-Local Runner

## Stage

- rung: `L2`
- title: Reduced-vocab single-block replay
- model target: `tiny-stories-v1k-h64-l1 tiled 4 x 64 wrapper around one reused 64 -> 64 kernel`
- status: `running`

## Commands

- `/usr/bin/time -f ELAPSED=%e RSS_KB=%M nix build .#task6-l2-c-fc-redirect-tile64-yosys-stat --no-link --print-out-paths -L`
- `/usr/bin/time -f ELAPSED=%e RSS_KB=%M nix build .#task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2-sv-sim --no-link --print-out-paths -L`
- `/usr/bin/time -f ELAPSED=%e RSS_KB=%M nix build .#task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2-abc9-utilization --no-link --print-out-paths -L`

## Logs

- `yosys-stat.log`
- `sv-sim.log`
- `utilization.log`

## Structural Summary

- status: ok
- Yosys completed and emitted a stat report for the emitted SystemVerilog bundle.
- sv bundle: 50 files, 1,072,608 bytes total, main.sv 7,039 lines / 775,633 bytes
- memory modules: 1, 2,048 bits total, largest four 2,048 bits (100.00%)
- largest memories: handshake_memory_out_f32_id3=2,048 bits
- design cells: 11,471
- top cell types: $mux=3,343, $and=2,627, $not=2,336, $dff=2,049, $or=699

## Metrics

- Yosys stat wall-clock: 3.11 s
- Yosys stat peak RSS: 563,904 KB
- Verilator wall-clock: 2.25 s
- Verilator peak RSS: 437,824 KB
- Verilator result: `PASS: stores 256 outputs 256`
- sv-sim output: `/nix/store/i92k16cnynr5phh0j7krqmwpb0ijz8wv-task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2-sv-sim.json`
- CLB LUTs: 31,907
- CLB FFs: 45,932
- DSP48E1: 4
- BRAM36: 0
- large weights emitted as RTL constants: no
- LUT ceiling check: fail (`29,860`)
- FF ceiling check: pass (`59,720`)
- utilization output: `/nix/store/rpmkz3b66ph97dyxcmsylicqcb0ij9ki-task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2-abc9-utilization`
- yosys-stat output: `/nix/store/m5pz5l2ynkv9fr1b54xb3lbhl0xchvhz-task6-l2-c-fc-redirect-tile64-yosys.stat`

## Verdict

- `fail-lut`

## Next Action

- Keep tiled L2 as the only active mainline; L3 remains blocked until this rung clears the LUT ceiling or a new structural hypothesis replaces it.
