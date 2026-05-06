# v111 Rebuild v110 init-status-only board run (Seed 13, Board A)

## Hypothesis

Re-run the target `task6-ypcb-litedram-no-odelay-lowrate-init-status-only-init-bandwidth-probe` (seed-13, DFII init-status-only mode) on Board A and verify that the canonical v98-v110 seed-13 control path is still preserved after the previous repository updates.

## Controlled input

- Date: `2026-05-06T18:00:43+02:00`
- Source commit: `44ff959885dec48d55a994570d19d3b70c2727a9`
- Bitstream: `/nix/store/1vd7z7ysz5s7alslq1l121alz26bpg0r-task6-ypcb-litedram-no-odelay-lowrate-init-status-only-init-bandwidth-probe.bit`
- Seed: `13`
- Target: `task6-ypcb-litedram-no-odelay-lowrate-init-status-only-init-bandwidth-probe`
- Probe command:
  - `python3 scripts/task6/read_litedram_probe_jtag_ftdi.py --serial 210299BF3824 --freq-hz 6000000 --bits 4672 --poll --poll-count 5 --poll-interval 0.2 --json-only`
- Programmer command:
  - `openFPGALoader -c digilent_hs3 --ftdi-serial 210299BF3824 /nix/store/1vd7z7ysz5s7alslq1l121alz26bpg0r-task6-ypcb-litedram-no-odelay-lowrate-init-status-only-init-bandwidth-probe.bit`

## Result

- `status`: `fail`
- `magic_ok`: `False`
- `version`: `42`
- `state`: `UNKNOWN_183`
- `pll_locked`: `False`
- `init_done`: `True`
- `init_error`: `True`
- `dfii_seq_state`: `DFII_SEQ_IDLE`
- `attempts`: `1`

## Interpretation

This board run reproduces the same transport-level/logic mismatch as earlier archived artifacts (v98/v99/v100): `magic_ok=False`, `version=42`, and `init_error=True`.

There is still a reproducibility gap between expected/desired seed-13 control behavior and observed probe decodes. Given this result appears identical across multiple re-loads, the next likely action is to validate whether we are exercising the intended JTAG payload/bitstream path vs an alternative design/debug namespace before any additional DDR3-level changes.

## Next action

- Capture the same experiment with `--bits 32`/`bits 64` sanity reads and a single explicit IR sweep, then compare against a build that is guaranteed to emit `magic_ok=True`.
- If that still fails, inspect `jtag_debug_shift` instruction selection and top-level reader decode script framing before touching DDR3 logic.
