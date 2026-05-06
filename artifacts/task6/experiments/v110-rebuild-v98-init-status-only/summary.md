# v110 Rebuild v98 on v97 target path with DFII_INIT_STATUS_ONLY

## Hypothesis

Rebuilding the v98 experiment on the exact v97-style target-construction path with seed 13 and only toggling the probe mode to DFII-init-status-only should preserve INIT clean behavior (`pll_locked=1`, `init_done=1`, `init_error=0`) while skipping the expensive DFII sequence.

## Controlled input

- Source commit: `59fe7e94bf29faba8b8983348f47e42113582f61`
- Modified files:
  - `flake.nix`
  - `fpga/rtl/task6_ypcb_litedram_init_bandwidth_probe_top.sv`
- Flake target: `.#task6-ypcb-litedram-no-odelay-lowrate-init-status-only-init-bandwidth-probe`
- Bitstream:
  - `/nix/store/1vd7z7ysz5s7alslq1l121alz26bpg0r-task6-ypcb-litedram-no-odelay-lowrate-init-status-only-init-bandwidth-probe.bit`
- SHA256: `c588950865f0d291881b4570d80f7d4ea86b97b4b9d685cd481f29eb55e26e83`
- Seed: `13`
- `DFII_INIT_STATUS_ONLY` top-level parameter is set in the synthesized variant.

## Build result

`nix build .#task6-ypcb-litedram-no-odelay-lowrate-init-status-only-init-bandwidth-probe -L` completed successfully and produced `result`.

## Probe status

No new board probe was run for this pass in this step.

## Decision

Use this bitstream as the regression-control baseline before any further DFII mapping changes. Next step is to program Board A and verify:
- `pll_locked`
- `init_done`
- `init_error`
- `dfii_seq_state`

against prior v98-v97-path behavior.
