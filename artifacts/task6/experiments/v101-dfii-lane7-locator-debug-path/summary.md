# v101 DFII lane7 locator on debug-port path

## Source snapshot

- source_commit: `ac9cd25 task6-ddr3: put v101 lane7 locator on debug path`
- target: `task6-ypcb-litedram-no-odelay-lowrate-lane7-locator-init-bandwidth-probe-bitstream`
- bitstream: `/nix/store/48mrh0ypa10lvvclzv0vbmxvc9x3qjms-task6-ypcb-litedram-no-odelay-lowrate-lane7-locator-init-bandwidth-probe.bit`
- bitstream_sha256: `a787d3e38ed0f368c0dacc60edeba7f221844de6ca184bbeb63b6e1eb52ac063`
- programmed_with: `openFPGALoader -c digilent_hs3 --ftdi-serial 210299BF3824`
- probe: `artifacts/task6/experiments/v101-dfii-lane7-locator-debug-path/probe.json`

## Controlled change from v100

v100 revealed that the lane7 locator Nix target used the plain LiteDRAM RTL elaboration and omitted `-DTASK6_LITEDRAM_DEBUG_PORTS`, unlike the v97/v99 init-clean byte-phase target. v101 changed only that target construction to use the same debug-port elaboration recipe.

## Result

Status: `FAIL_UNINTERPRETABLE`

The corrected-path locator target programmed and exposed debug version `101`, but still did not reach the locator payload:

- `state=PROBE_ERROR`
- `init_state=INIT_ERROR`
- `init_done=false`
- `init_seq_done=false`
- `init_seq_error=true`
- `wb_timeout_seen=true`
- `pll_locked=true`
- `dfii_edge_lane7_locator_probe_only=1`
- `dfii_displacement_observed=[]`
- all `dfii_rddata_0..19=0`
- all byte/association masks zero

## Interpretation

The debug-port construction mismatch was real and has been corrected, but it was not the reason the standalone lane7 locator failed. The remaining difference from the v99 init-clean run is the standalone locator probe mode and its sequence/control path, not the DFI-debug build path.

## Decision

Do not infer a lane7 mapping and do not change DDR packing. The next surgical experiment should stop using the standalone lane7 locator mode and instead fold a minimal lane7 tag into the already init-clean byte-phase association target, preserving the v99 `DFII_BYTE_PHASE_ASSOC_MATRIX_ONLY` sequence path.
