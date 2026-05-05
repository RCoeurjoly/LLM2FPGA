# v102 DFII byte-phase matrix with folded lane7 locator payload

## Source snapshot

- source_commit: `6648032 task6-ddr3: fold lane7 locator into byte-phase path`
- target: `task6-ypcb-litedram-no-odelay-lowrate-byte-phase-assoc-matrix-init-bandwidth-probe-bitstream`
- bitstream: `/nix/store/kdjp6v91lbsbp2ndqibbs3p9k1qv7cxz-task6-ypcb-litedram-no-odelay-lowrate-byte-phase-assoc-matrix-init-bandwidth-probe.bit`
- bitstream_sha256: `51a85571197a1f8178a5dbe3eefecbe737af779613cf17775f6391e552658883`
- programmed_with: `openFPGALoader -c digilent_hs3 --ftdi-serial 210299BF3824`
- probe: `artifacts/task6/experiments/v102-dfii-byte-phase-lane7-folded/probe.json`

## Controlled change from v99/v101

v102 stopped using the standalone lane7 locator mode. It built the known v99 byte-phase association target and changed only source slot 7 in the byte-phase write path to emit the existing lane7 locator payload across the 20 DFII write-data words.

## Result

Status: `FAIL_UNINTERPRETABLE`

The target programmed and exposed debug version `102`, but did not reach the byte-phase/locator payload:

- `state=PROBE_ERROR`
- `init_state=INIT_ERROR`
- `init_done=false`
- `init_seq_done=false`
- `init_seq_error=true`
- `wb_timeout_seen=true`
- `pll_locked=true`
- `dfii_edge_lane7_locator_probe_only=0`
- `dfii_assoc_flags=0`
- `dfii_displacement_observed=[]`
- all `dfii_rddata_0..19=0`
- all byte/association masks zero

## Interpretation

v102 confirms the clean v99 behavior is sensitive to even small probe-logic changes. This run does not provide lane7 mapping evidence and should not be used to alter DDR packing.

## Decision

Stop adding RTL locator logic until reproducibility is restored. The next surgical path should return to the exact v99 source/bitstream construction and either:

1. extract more from already captured v99 data using host-side analysis only, or
2. replay the exact v99 source with no RTL changes before any new locator payload is attempted.
