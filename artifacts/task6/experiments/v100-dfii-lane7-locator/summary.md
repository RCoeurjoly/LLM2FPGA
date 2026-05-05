# v100 DFII lane7 locator

## Source snapshot

- source_commit: `3ca71f4 task6-ddr3: prepare v100 lane7 locator`
- target: `task6-ypcb-litedram-no-odelay-lowrate-lane7-locator-init-bandwidth-probe-bitstream`
- bitstream: `/nix/store/zjinzswqqnxcw2wzm4dikn8hyzmnqsz3-task6-ypcb-litedram-no-odelay-lowrate-lane7-locator-init-bandwidth-probe.bit`
- bitstream_sha256: `06f454702976dee9a2373f67a8cb48eed9df97594a8f13c5353c42d18435ef1b`
- programmed_with: `openFPGALoader -c digilent_hs3 --ftdi-serial 210299BF3824`
- probe: `artifacts/task6/experiments/v100-dfii-lane7-locator/probe.json`

## Result

Status: `FAIL_UNINTERPRETABLE`

The locator target programmed, exposed debug version `100`, and reported `pll_locked=true`, but the probe did not reach the lane7 locator payload:

- `state=PROBE_ERROR`
- `init_state=INIT_ERROR`
- `init_done=false`
- `init_seq_done=false`
- `init_seq_error=true`
- `wb_timeout_seen=true`
- `dfii_edge_lane7_locator_probe_only=1`
- `dfii_displacement_observed=[]`
- all `dfii_rddata_0..19=0`
- all byte/association masks zero

## Interpretation

This result does not falsify the v99 byte/phase observation. It only says the standalone lane7 locator target, as routed in v100, did not reproduce the clean init/probe path. No lane7 mapping should be inferred from this run.

## Decision

Do not change DDR packing or byte transforms based on v100. The next surgical step should restore init cleanliness for the locator by making the locator run through the exact v99 clean target construction, or by folding the locator tags into the already init-clean v99 byte-phase matrix target rather than using this standalone locator target.
