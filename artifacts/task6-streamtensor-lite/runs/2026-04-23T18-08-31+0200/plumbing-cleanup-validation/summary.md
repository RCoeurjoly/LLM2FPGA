# Plumbing Cleanup Validation

## Commands

- Legacy whole-class wrapper validation:
  - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-ui64-buffer-fifo2-utilization --no-link --print-out-paths -L`
- Frozen `L1` reference validation:
  - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-ring3-postbranch-outbuf-fifo2-abc9-utilization --no-link --print-out-paths -L`
- Active tiled `L2` reference validation:
  - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2-abc9-utilization --no-link --print-out-paths -L`
- Active tiled `L2` cached Verilator build validation:
  - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2-sv-sim --no-link -L`
- Active tiled `L2` direct Verilator rerun:
  - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' /nix/store/4hdp3s5lqqwqkpwqwy6mxwc634fk5ixd-task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2-sim-main/obj_dir/sim_main`

## Logs

- [l1-ui64-wholeclass-utilization.log](/home/roland/LLM2FPGA_task6_streamtensor_lite/artifacts/task6-streamtensor-lite/runs/2026-04-23T18-08-31+0200/plumbing-cleanup-validation/l1-ui64-wholeclass-utilization.log)
- [l1-reference-abc9-utilization.log](/home/roland/LLM2FPGA_task6_streamtensor_lite/artifacts/task6-streamtensor-lite/runs/2026-04-23T18-08-31+0200/plumbing-cleanup-validation/l1-reference-abc9-utilization.log)
- [l2-tiled-reference-abc9-utilization.log](/home/roland/LLM2FPGA_task6_streamtensor_lite/artifacts/task6-streamtensor-lite/runs/2026-04-23T18-08-31+0200/plumbing-cleanup-validation/l2-tiled-reference-abc9-utilization.log)
- [l2-tiled-reference-sv-sim.log](/home/roland/LLM2FPGA_task6_streamtensor_lite/artifacts/task6-streamtensor-lite/runs/2026-04-23T18-08-31+0200/plumbing-cleanup-validation/l2-tiled-reference-sv-sim.log)
- [l2-tiled-reference-direct-sim.log](/home/roland/LLM2FPGA_task6_streamtensor_lite/artifacts/task6-streamtensor-lite/runs/2026-04-23T18-08-31+0200/plumbing-cleanup-validation/l2-tiled-reference-direct-sim.log)

## Metrics

- Legacy class-wide wrapper still builds through the wrapper alias:
  - `23,161 LUT / 27,591 FF / 4 DSP / 0 BRAM`
  - wall-clock / RSS:
    - `3.12 s` / `563,116 KB`
- Frozen `L1` reference is unchanged:
  - `29,778 LUT / 46,352 FF / 4 DSP / 0 BRAM`
  - wall-clock / RSS:
    - `3.09 s` / `563,200 KB`
- Active tiled `L2` reference is unchanged:
  - `31,907 LUT / 45,932 FF / 4 DSP / 0 BRAM`
  - mapped wall-clock / RSS:
    - `3.12 s` / `563,188 KB`
- Verilator passed:
  - `yes`
  - cached build wall-clock / RSS:
    - `2.29 s` / `437,948 KB`
  - direct rerun wall-clock / RSS:
    - `2.23 s` / `5,292 KB`
- Yosys stat finished within budget:
  - `not rerun`
- Large weights emitted as RTL constants:
  - `no`

## Verdict

- The probe-plumbing cleanup is now validated:
  - `task6_ui64_fifo2_buffer.sv` is the canonical FIFO2 helper
  - `handshake_buffer_in_ui64_out_ui64_2slots_seq_fifo2.sv` is only a wrapper
  - the site rewrites now come from one small Nix patch map instead of
    repeated inline site lists
- Accepted Task 6 reference points did not move:
  - frozen `L1` still maps to `29,778 LUT / 46,352 FF / 4 DSP / 0 BRAM`
  - active tiled `L2` still maps to `31,907 LUT / 45,932 FF / 4 DSP / 0 BRAM`
- The rejected legacy whole-class wrapper path also still builds correctly
  through the wrapper alias, so the cleanup did not strand old evidence.

## Next Action

- Use the cleaned plumbing to test one new bounded `L2 tile64` seam
  hypothesis:
  - the remaining cost is likely in the mixed data/control store-path cluster
    around `handshake_buffer246`, `247`, `255`, and `handshake_fork50`,
    `51`, `52`, not in another `ui64` buffer-only rewrite
