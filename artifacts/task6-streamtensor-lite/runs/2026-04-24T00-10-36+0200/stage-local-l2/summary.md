# L2 Stage-Local Runner

## Stage

- rung: `L2`
- title: Reduced-vocab single-block replay
- model target: `tiny-stories-v1k-h64-l1 tiled 4 x 64 wrapper around one reused 64 -> 64 kernel`
- status: `running`

## Commands

- `/usr/bin/time -f ELAPSED=%e RSS_KB=%M nix build .#task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2-yosys-stat --no-link --print-out-paths -L`
- `/usr/bin/time -f ELAPSED=%e RSS_KB=%M nix build .#task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2-sv-sim --no-link --print-out-paths -L`
- `/usr/bin/time -f ELAPSED=%e RSS_KB=%M nix build .#task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2-abc9-utilization --no-link --print-out-paths -L`

## Logs

- `yosys-stat.log`
- `sv-sim.log`
- `utilization.log`

## Structural Summary

- status: ok
- Yosys completed and emitted a stat report for the emitted SystemVerilog bundle.
- sv bundle: 52 files, 1,079,243 bytes total, main.sv 128 lines / 5,381 bytes
- memory modules: 1, 2,048 bits total, largest four 2,048 bits (100.00%)
- largest memories: handshake_memory_out_f32_id3=2,048 bits
- design cells: 11,265
- top cell types: $mux=3,233, $and=2,595, $not=2,272, $dff=2,012, $or=683

## Metrics

- measurement mode: `cache-hit status replay`
- timing note: replay timings are status-surface timings and are not comparable to frontier experiment timings in the main ledger
- Yosys stat replay wall-clock: 3.17 s
- Yosys stat replay peak RSS: 564,112 KB
- Verilator replay wall-clock: 2.42 s
- Verilator replay peak RSS: 437,840 KB
- Verilator result: `PASS: stores 256 outputs 256`
- sv-sim output: `/nix/store/i92k16cnynr5phh0j7krqmwpb0ijz8wv-task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2-sv-sim.json`
- utilization replay wall-clock: 3.16 s
- utilization replay peak RSS: 563,344 KB
- CLB LUTs: 31,907
- CLB FFs: 45,932
- DSP48E1: 4
- BRAM36: 0
- large weights emitted as RTL constants: no
- LUT ceiling check: fail (`29,860`)
- FF ceiling check: pass (`59,720`)
- utilization output: `/nix/store/rpmkz3b66ph97dyxcmsylicqcb0ij9ki-task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2-abc9-utilization`
- yosys-stat output: `/nix/store/sj67p7fax7x31g3canm358c6xxsnwj2c-task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2-yosys.stat`

## Verdict

- `fail-lut`

## Next Action

- Keep tiled L2 as the only active mainline; L3 remains blocked until this rung clears the LUT ceiling or a new structural hypothesis replaces it.
