# L1 `c_proj` Redirect `yosys-stat`

## Commands

- `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-proj-redirect-yosys-stat --no-link -L`

## Logs

- [yosys-stat.log](/home/roland/LLM2FPGA_task6_streamtensor_lite/artifacts/task6-streamtensor-lite/runs/2026-04-23T14-51-00+0200/l1-cproj-redirect-yosys-stat-proof/yosys-stat.log)

## Metrics

- Wall-clock / RSS:
  - `17.52 s` / `563,732 KB`
- Uses `$mul`:
  - `1`
- Uses `arith_mulf_in_f32_f32_out_f32`:
  - `1`
- Uses `arith_addf_in_f32_f32_out_f32`:
  - `1`
- `handshake_buffer_in_ui64_out_ui64_2slots_seq`:
  - `204`
- `handshake_load_in_ui64_f32_none_out_f32_ui64`:
  - `4`
- `handshake_store_in_ui64_f32_none_out_f32_ui64`:
  - `3`

## Verdict

- The first redirected `L1 c_proj` kernel compiles through the inherited flow
  cleanly and stays inside the `< 30 s` micro-proof budget.
- This step does not make any mapped-fit claim yet; it only proves that the new
  redirected kernel is structurally live and still carries the expected float
  arithmetic extern signature.

## Next Action

- Add the minimal `L1 c_proj` Verilator and mapped-utilization surfaces using
  the new `c_proj` contract and weight-pack artifacts.
