# LSQ L1 Alternate-Lowering Proof

## Commands

```bash
/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-lsq-index-ring3-postbranch-outbuf-fifo2-yosys-stat --no-link --print-out-paths -L |& tee artifacts/task6/runs/2026-04-24T11-40-03+0200/lsq-l1-alternate-lowering-proof/yosys-stat.log
/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-lsq-index-ring3-postbranch-outbuf-fifo2-abc9-utilization --no-link --print-out-paths -L |& tee artifacts/task6/runs/2026-04-24T11-40-03+0200/lsq-l1-alternate-lowering-proof/utilization.log
/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-lsq-index-ring3-postbranch-outbuf-fifo2-sv-sim --no-link --print-out-paths -L |& tee artifacts/task6/runs/2026-04-24T11-40-03+0200/lsq-l1-alternate-lowering-proof/sv-sim.log
```

## Outputs

- raw LSQ `sv` bundle:
  - `/nix/store/vv4bdibfff16bqg6vbv16dn7amxy2nmq-task6-l1-c-fc-redirect-lsq-sv`
- `yosys-stat`:
  - `/nix/store/zpimvrnbsi6yzg8iwzdi9f2lhqajn83f-task6-l1-c-fc-redirect-lsq-index-ring3-postbranch-outbuf-fifo2-yosys.stat`
- `sim_main`:
  - `/nix/store/zrvkisdq6476jccidssq8mr4y421wl7i-task6-l1-c-fc-redirect-lsq-index-ring3-postbranch-outbuf-fifo2-sim-main/obj_dir/sim_main`
- mapped utilization:
  - `/nix/store/3agxx5vklnklbz91mw1rgkj6sijsmcyh-task6-l1-c-fc-redirect-lsq-index-ring3-postbranch-outbuf-fifo2-abc9-utilization`
- logs:
  - `./yosys-stat.log`
  - `./utilization.log`
  - `./sv-sim.log`

## Metrics

- filtered LSQ-selective `ui64` patch sites:
  - index ring 3: `160,161,162,165,173,177,178,179,180,181,182,185,186,187,188,189,190,191,213,214,215,217,218,219`
  - post-branch: `264,265,266,269`
  - post-branch out-buffer: `279`
- raw `sv` bundle size:
  - LSQ `main.sv`: `8,241` lines, `896,749` bytes
  - LSQ total `sv`: `54` files, `1,185,425` bytes
  - frozen stock reference `main.sv`: `7,664` lines, `809,614` bytes
  - frozen stock reference total `sv`: `54` files, `1,109,724` bytes
- `yosys-stat`:
  - `ELAPSED=4.69`
  - `RSS_KB=564,140`
  - `num_cells=12,222`
  - `num_memory_bits=512`
  - top cell types: `$mux=3,440`, `$and=2,845`, `$not=2,459`, `$dff=2,181`, `$or=722`
- frozen stock `yosys-stat` reference:
  - `num_cells=11,519`
- mapped `abc9` utilization:
  - `ELAPSED=89.23`
  - `RSS_KB=563,056`
  - `DSP=4`
  - `BRAM36=0`
  - `CLB LUTs=29,329`
  - `CLB FFs=46,570`
  - dominant mapped leaf types: `LUT6=14,399`, `LUT3=7,653`, `LUT2=3,329`, `LUT5=2,568`, `LUT4=1,380`, `FDRE=46,567`, `RAM32M=6`
- frozen stock mapped reference:
  - `DSP=4`
  - `BRAM36=0`
  - `CLB LUTs=29,778`
  - `CLB FFs=46,352`
- `sv-sim`:
  - `ELAPSED=82.09`
  - `RSS_KB=437,484`
  - failure: `Timeout waiting for redirected GEMV completion`
  - fatal location: `task6_contract_gemv_tb_main.sv:259`

## Structural Note

- The strengthened `ui64` site-verification check exposed that the historical
  `L1` site-map names were not stage-pure on the LSQ path.
- Several previously listed hotspot IDs are not `ui64` buffers on the LSQ
  `sv` bundle:
  - ctrl buffers: `163,164,174,175,192,270`
  - `ui1` buffers: `176,271,280`
  - `f32` buffer: `216`
- This pass therefore used only the filtered patchable `ui64` subset above.

## Verdict

`reject-drop-in`

- The bounded alternate-lowering slice is structurally interesting:
  - it lowers mapped LUT from `29,778` to `29,329` on the same `L1 c_fc`
    contract while preserving `4 DSP / 0 BRAM`
- It is not an accepted replacement because the identical redirected contract
  times out under Verilator.
- The one-pass alternate-lowering comparison is therefore spent and closed as
  not drop-in-safe.

## Next Action

- Keep the result recorded as a negative A/B, not as the new mainline.
- Do not run a second alternate-lowering pass without a stronger structural
  hypothesis.
- Continue with quantized extracted-op parity on the same Task 6 proof harness.
