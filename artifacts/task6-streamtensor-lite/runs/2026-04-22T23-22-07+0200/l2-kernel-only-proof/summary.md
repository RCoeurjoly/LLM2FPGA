# L2 Kernel-Only Redirected Proof

## Commands

- `nix build .#task6-l2-c-fc-redirect-tb-data-sv --no-link --print-out-paths`
- `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l2-c-fc-redirect-yosys-stat --no-link -L`
- `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l2-c-fc-redirect-utilization --no-link --print-out-paths -L`
- `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l2-c-fc-redirect-sv-sim --no-link -L`
- `rg -n "hw.module @main|in0_ld0|in1_ld0|in2_st0|in3_valid" /nix/store/wsx6b3f25cc4wfaaifw68qa6im2cvfjx-task6-l2-c-fc-redirect-hw-clean.mlir`
- `sed -n '1,40p' /nix/store/pr5bkq5bqfjnnn5fmj4ydqhbhsm5jwpx-task6-l2-c-fc-redirect-sv/sv/main.sv`

## Log

- Manifest alignment passed:
  - `tb-data-sv` built at
    `/nix/store/kv3li6fbzgj3w1sp5zzypvrh23a7c62g-task6-l2-c-fc-redirect-tb-data-sv`
- `yosys-stat` passed:
  - `num_cells = 13703`
  - `num_memory_bits = 8192`
  - `num_cells_by_type` included:
    - `$mul: 1`
    - `arith_mulf_in_f32_f32_out_f32: 1`
    - `arith_addf_in_f32_f32_out_f32: 1`
  - `/usr/bin/time`: `ELAPSED=9.13 RSS_KB=563512`
- Mapped utilization output:
  - `/nix/store/2sfssv27f1ijhwlwzaxsny76ixvjrzmn-task6-l2-c-fc-redirect-utilization`
  - `summary.txt` reported:
    - `clb_luts: 50235`
    - `clb_ffs: 65523`
    - `dsp: 4`
    - `bram36: 0`
  - `/usr/bin/time`: `ELAPSED=88.93 RSS_KB=562776`
- External-weight evidence:
  - `hw.module @main` exposes `in0_ld0.*`, `in1_ld0.*`, `in2_st0`, and `in3`
  - `main.sv` shows separate weight load ports:
    - `input [31:0] in1_ld0_data`
    - `output [13:0] in1_ld0_addr`
    - `output in1_ld0_addr_valid`
- Verilator replay:
  - first run failed only on the flat timeout budget:
    - `Timeout waiting for redirected GEMV completion`
  - after scaling the timeout with external traffic volume, the rerun passed:
    - `PASS: stores 256 outputs 256`
    - `/usr/bin/time`: `ELAPSED=47.06 RSS_KB=437352`

## Metrics

- DSP:
  - `4`
- BRAM36:
  - `0`
- LUT:
  - `50,235`
- FF:
  - `65,523`
- Wall-clock runtime:
  - `9.13 s` for `yosys-stat`
  - `88.93 s` for mapped utilization
  - `47.06 s` for Verilator package build plus run
- Large weights emitted as RTL constants:
  - no
- Verilator passed:
  - yes
- Yosys stat finished within budget:
  - yes

## Verdict

- accept-structural reject-fit
- The `L2` redirected kernel is functionally and structurally valid:
  - external weights: pass
  - mapped DSP use: pass
  - Verilator proof: pass
- It is not promotable as a fit-first step:
  - mapped LUT usage grows to `50,235`
  - mapped FF usage grows to `65,523`
  - both are worse than the already-failing `L1` fit signature

## Next Action

- Stop spending more time on larger-lane redirect bring-up and focus the next
  slice on fit reduction, starting from the cheaper `L1` proof rather than the
  worse-fitting `L2` proof.
