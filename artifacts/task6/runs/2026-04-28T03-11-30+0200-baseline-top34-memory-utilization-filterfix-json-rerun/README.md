# 2026-04-28 baseline `top34-memory` utilization JSON rerun after GC

Setup:

- Temporarily preserved the completed `stage8h` output with a Nix GC root.
- Ran `nix-store --gc --max-freed 64424509440`.
- GC freed `60.8 GiB`.

Command:

```sh
MONITOR_GLOBAL_PGREP_PATTERN='default-builder.sh|yosys -q -s run.ys|yosys-abc|.yosys-wrapped' \
  scripts/pipeline/monitor_build.sh \
  artifacts/task6/runs/2026-04-28T03-11-30+0200-baseline-top34-memory-utilization-filterfix-json-rerun \
  5 -- \
  nix build .#tiny-stories-1m-baseline-float-selftest-top34-memory-utilization \
    --no-link --print-out-paths -L
```

Result:

- exit status: `0`
- wall time: `294` seconds
- peak sampled `VmRSS`: `22,539,800 KiB`
- peak sampled `VmHWM`: `23,849,916 KiB`
- final monitor stage line: `stage9 write_json`
- output:
  - `/nix/store/lnzv5y9vj69s8hhg3zp0x35hrmzmrrzz-tiny-stories-1m-baseline-float-selftest-top34-memory-utilization`
- durable copy in this artifact directory:
  - `utilization/summary.txt`
  - `utilization/summary.json`
  - `utilization/stat.json`

Mapped utilization:

- `clb_luts`: `56,899,009 / 298,600` (`19055.26%`)
- `clb_ffs`: `58,496,710 / 597,200` (`9795.16%`)
- `slices_lower_bound`: `7,312,089 / 74,650` (`9795.16%`)
- `dsp`: `0 / 1920` (`0.00%`)
- `bram36`: `0 / 955` (`0.00%`)

Delta versus copied all-memory baseline:

- `clb_luts`: `+16,482,923` (`+40.78%`)
- `clb_ffs`: `+424,183` (`+0.73%`)
- `dsp`: unchanged at `0`
- `bram36`: unchanged at `0`

Largest remaining non-top mapped owners by LUT count:

- `handshake_memory_out_f32_id77`: `631,072` LUTs, `8,360` FFs
- `math_fpowi_in_f32_ui64_out_f32`: `370,334` LUTs, `0` FFs
- `handshake_memory_out_f32_id25`: `340,924` LUTs, `2,437` FFs
- `handshake_memory_out_f32_id72`: `47,456` LUTs, `8,212` FFs
- `handshake_memory_out_f32_id37`: `34,955` LUTs, `2,132` FFs

Interpretation:

- The production filter fix is verified: `stage9 write_json` completed and produced the utilization bundle.
- `top34-memory` is a toolchain-frontier win because it clears the prior `stage6a` and `stage8b` OOM/frontier points.
- It is not a mapped-resource win versus the copied all-memory baseline; LUT usage is materially worse.
