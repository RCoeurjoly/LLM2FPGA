# v112 Probe framing and IR sweep on seed-13 init-status-only target (Board A)

## Hypothesis

If this unstable behavior is a probe-path/IR framing issue rather than a DDR3 regression, then changing probe bit-width and IR configuration against the same seed-13 init-status-only bitstream should reproduce deterministic framing modes and eventually return a valid magic/status envelope.

## Controlled input

- Date: `2026-05-06T18:03:44+02:00`
- Source commit: `6a227af`
- Source bitstream (from v110/v111 control build): `/nix/store/1vd7z7ysz5s7alslq1l121alz26bpg0r-task6-ypcb-litedram-no-odelay-lowrate-init-status-only-init-bandwidth-probe.bit`
- Seed: `13`
- Target: `task6-ypcb-litedram-no-odelay-lowrate-init-status-only-init-bandwidth-probe`
- Serial: `210299BF3824`

## Commands

- Programmer:
  - `openFPGALoader -c digilent_hs3 --ftdi-serial 210299BF3824 /nix/store/1vd7z7ysz5s7alslq1l121alz26bpg0r-task6-ypcb-litedram-no-odelay-lowrate-init-status-only-init-bandwidth-probe.bit`
- Probe sweep:
  - `python3 scripts/task6/read_litedram_probe_jtag_ftdi.py --serial 210299BF3824 --freq-hz 6000000 --bits 32 --poll --poll-count 10 --poll-interval 0.2 --json-only --user-ir 0x02 --ir-len 6`
  - `python3 scripts/task6/read_litedram_probe_jtag_ftdi.py --serial 210299BF3824 --freq-hz 6000000 --bits 64 --poll --poll-count 10 --poll-interval 0.2 --json-only --user-ir 0x02 --ir-len 6`
  - `python3 scripts/task6/read_litedram_probe_jtag_ftdi.py --serial 210299BF3824 --freq-hz 6000000 --bits 4672 --poll --poll-count 10 --poll-interval 0.2 --json-only --user-ir 0x02 --ir-len 6`
  - `python3 scripts/task6/read_litedram_probe_jtag_ftdi.py --serial 210299BF3824 --freq-hz 6000000 --bits 4672 --poll --poll-count 10 --poll-interval 0.2 --json-only --user-ir 0x02 --ir-len 5`
  - `python3 scripts/task6/read_litedram_probe_jtag_ftdi.py --serial 210299BF3824 --freq-hz 6000000 --bits 4672 --poll --poll-count 10 --poll-interval 0.2 --json-only --user-ir 0x01 --ir-len 6`
  - `python3 scripts/task6/read_litedram_probe_jtag_ftdi.py --serial 210299BF3824 --freq-hz 6000000 --bits 4672 --poll --poll-count 10 --poll-interval 0.2 --idcode-only --json-only --user-ir 0x02 --ir-len 6`

## Results

- `idcode.json`: `0xba8849ff`
- `probe_bits32.json`: `magic_ok=False`, `pll_locked=False`, `init_done=False`, `init_error=False`, `dfii_seq_state=UNKNOWN_-1`, `state=UNKNOWN_-1`, `attempts=10`
- `probe_bits64.json`: `magic_ok=False`, `pll_locked=False`, `init_done=True`, `init_error=True`, `dfii_seq_state=UNKNOWN_-1`, `state=UNKNOWN_183`, `attempts=1`
- `probe_bits4672.json`: `magic_ok=False`, `pll_locked=False`, `init_done=True`, `init_error=True`, `dfii_seq_state=DFII_SEQ_IDLE`, `state=UNKNOWN_183`, `timeout_seen=True`, `attempts=1`
- `probe_irlen5.json`: `magic_ok=False`, `pll_locked=False`, `init_done=False`, `init_error=False`, `dfii_seq_state=DFII_SEQ_IDLE`, `state=PROBE_RESET`, `attempts=10`
- `probe_userir1.json`: `magic_ok=False`, `pll_locked=False`, `init_done=False`, `init_error=False`, `dfii_seq_state=DFII_SEQ_IDLE`, `state=PROBE_RESET`, `probe_error=True`, `attempts=1`

## Interpretation

This confirms the previous failure mode persists under explicit framing variation: no configuration yields `magic_ok=True` or clean init (`pll_locked=1`, `init_error=0`).

- Wide reads (`64`, `4672`) can drive `init_done=1` once, but always with `init_error=1`.
- Narrow read (`32`, IR len 5/6) tends to stay in `PROBE_RESET`/`UNKNOWN_*` with no lock and no init.
- IR/user variations changed decoded state labels but did not recover a valid, stable status stream.

This strongly suggests the problem remains in probe namespace/tap selection or payload framing expectations (or board-level state) rather than the current DFII/DDR hypothesis.

## Next action

1. Keep this as the reproducibility checkpoint.
2. Run/inspect the existing `jtag_debug_shift` instruction decode against the fixed `idcode` path to confirm the active IR instruction mapping.
3. Only then resume DFII byte/phase matrix work on a board instance with proven payload framing.
