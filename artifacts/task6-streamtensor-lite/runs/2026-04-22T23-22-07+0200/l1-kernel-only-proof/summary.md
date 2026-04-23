# L1 Kernel-Only Redirected Proof

## Commands

- `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-yosys-stat --no-link -L`
- `nix build .#task6-l1-c-fc-redirect-utilization --no-link --print-out-paths -L`
- `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-sv-sim --no-link -L`
- `rg -n "in0_ld0|in1_ld0|in2_st0|in3_valid" /nix/store/s9qsbk2f6c6hzf0agwz2bb8sripvnzx8-task6-l1-c-fc-redirect-hw-clean.mlir`
- `sed -n '1,120p' /nix/store/4mv58wx99a3sisz68xxrby10wih1mzpa-task6-l1-c-fc-redirect-sv/sv/main.sv`

## Log

- `yosys-stat` passed:
  - `num_cells = 12611`
  - `num_memory_bits = 512`
  - `num_cells_by_type` included:
    - `$mul: 1`
    - `arith_mulf_in_f32_f32_out_f32: 1`
    - `arith_addf_in_f32_f32_out_f32: 1`
  - `/usr/bin/time`: `ELAPSED=4.07 RSS_KB=564032`
- Mapped utilization output:
  - `/nix/store/cgk31f78g5c0rd8bwyw98v1p38m0vz4f-task6-l1-c-fc-redirect-utilization`
  - `summary.txt` reported:
    - `clb_luts: 33116`
    - `clb_ffs: 51296`
    - `dsp: 4`
    - `bram36: 0`
  - `/usr/bin/time`: `ELAPSED=64.82 RSS_KB=562944`
- External-weight evidence:
  - `hw.module @main` exposes `in0_ld0.*`, `in1_ld0.*`, `in2_st0`, and `in3`
  - `main.sv` shows separate top-level weight load ports:
    - `input [31:0] in1_ld0_data`
    - `output [5:0] in1_ld0_addr`
    - `output in1_ld0_addr_valid`
- Verilator replay passed on the accepted kernel-only path:
  - `PASS: stores 16 outputs 16`
  - `/usr/bin/time`: `ELAPSED=61.91 RSS_KB=437820`
  - replay uses `ABS_TOL = 1.0e-4` because the visible float primitive path
    quantizes at `q16.16` scale

## Metrics

- DSP:
  - `4`
- BRAM36:
  - `0`
- LUT:
  - `33,116`
- FF:
  - `51,296`
- Wall-clock runtime:
  - `4.07 s` for `yosys-stat`
  - `64.82 s` for mapped utilization
  - `61.91 s` for Verilator package build plus run
- Large weights emitted as RTL constants:
  - no
- Verilator passed:
  - yes
- Yosys stat finished within budget:
  - yes

## Verdict

- accept
- The redirected pre-bias kernel is a valid `L1` structural proof:
  - DSP requirement passes
  - weight externalization passes
  - Verilator proof passes with an explicit tolerance matched to the observed
    `q16.16` arithmetic behavior
- The fit-first path is still not scorecard-clear because mapped LUT usage is
  above the `29,860` ceiling.

## Next Action

- Move to `L2` using the same kernel-only redirect pattern at the existing
  `64 -> 256` `tiny-stories-v1k-h64-l1` `c_fc` site.
