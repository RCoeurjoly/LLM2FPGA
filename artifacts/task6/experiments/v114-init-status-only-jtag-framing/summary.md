# v114 Init-status-only JTAG framing sweep (seed-13 path, Board A)

## Hypothesis

If this instability is primarily a JTAG payload/probe decode issue, sweeping bit widths and IR framing against the exact seed-13 `task6-ypcb-litedram-no-odelay-lowrate-init-status-only-init-bandwidth-probe` build should produce deterministic `magic_ok=True` if the capture path is now correct.

## Controlled input

- Date: `2026-05-06T18:35:30+02:00`
- Source commit: `44fbcab7f74a8190807d60ca7aa07095d5945d81`
- Bitstream target: `task6-ypcb-litedram-no-odelay-lowrate-init-status-only-init-bandwidth-probe`
- Seed: `13`
- Build result: `/nix/store/bcbgyc1z5ks35n1rkcl1rsq8cbgps4v5-task6-ypcb-litedram-no-odelay-lowrate-init-status-only-init-bandwidth-probe.bit`
- Board: A
- Serial: `210299BF3824`
- Programmer command:
  - `openFPGALoader -c digilent_hs3 --ftdi-serial 210299BF3824 --skip-load-bridge --write-sram /nix/store/bcbgyc1z5ks35n1rkcl1rsq8cbgps4v5-task6-ypcb-litedram-no-odelay-lowrate-init-status-only-init-bandwidth-probe.bit`
- Probe commands:
  - `python3 scripts/task6/read_litedram_probe_jtag_ftdi.py --serial 210299BF3824 --freq-hz 6000000 --bits 4672 --poll --poll-count 10 --poll-interval 0.2 --json-only --user-ir 0x02 --ir-len 6 --json-out artifacts/task6/experiments/v114-init-status-only-jtag-framing/probe_bits4672_ir6.json`
  - `python3 scripts/task6/read_litedram_probe_jtag_ftdi.py --serial 210299BF3824 --freq-hz 6000000 --bits 64 --poll --poll-count 10 --poll-interval 0.2 --json-only --user-ir 0x02 --ir-len 6 --json-out artifacts/task6/experiments/v114-init-status-only-jtag-framing/probe_bits64_ir6.json`
  - `python3 scripts/task6/read_litedram_probe_jtag_ftdi.py --serial 210299BF3824 --freq-hz 6000000 --bits 32 --poll --poll-count 10 --poll-interval 0.2 --json-only --user-ir 0x02 --ir-len 6 --json-out artifacts/task6/experiments/v114-init-status-only-jtag-framing/probe_bits32_ir6.json`
  - `python3 scripts/task6/read_litedram_probe_jtag_ftdi.py --serial 210299BF3824 --freq-hz 6000000 --bits 4672 --poll --poll-count 10 --poll-interval 0.2 --json-only --user-ir 0x02 --ir-len 5 --json-out artifacts/task6/experiments/v114-init-status-only-jtag-framing/probe_bits4672_ir5.json`
  - `python3 scripts/task6/read_litedram_probe_jtag_ftdi.py --serial 210299BF3824 --freq-hz 6000000 --bits 4672 --poll --poll-count 10 --poll-interval 0.2 --json-only --user-ir 0x02 --ir-len 6 --tdo-0 --json-out artifacts/task6/experiments/v114-init-status-only-jtag-framing/probe_bits4672_tdo0_ir6.json`

## Result

- `probe_bits32_ir6.json`:
  - `attempts=10`, `magic_ok=False`, `pll_locked=False`, `init_done=False`, `init_error=False`, `state=UNKNOWN_-1`, `dfii_seq_state=UNKNOWN_-1`, `dfii_data_pass=False`, `dfii_data_failed=False`
- `probe_bits64_ir6.json`:
  - `attempts=10`, `magic_ok=False`, `pll_locked=False`, `init_done=False`, `init_error=False`, `state=PROBE_RESET`, `dfii_seq_state=UNKNOWN_-1`, `dfii_data_pass=False`, `dfii_data_failed=False`
- `probe_bits4672_ir6.json`:
  - `attempts=10`, `magic_ok=False`, `pll_locked=False`, `init_done=False`, `init_error=False`, `state=PROBE_RESET`, `dfii_seq_state=DFII_SEQ_IDLE`, `dfii_data_pass=False`, `dfii_data_failed=False`
- `probe_bits4672_tdo0_ir6.json`:
  - `attempts=10`, `magic_ok=False`, `pll_locked=False`, `init_done=False`, `init_error=False`, `state=PROBE_RESET`, `dfii_seq_state=DFII_SEQ_IDLE`, `dfii_data_pass=False`, `dfii_data_failed=False`
- `probe_bits4672_ir5.json`:
  - Capture file is empty (size 0) and should be re-run after rerooting the FTDI client if this variant is needed.
- `idcode_default.json`:
  - `idcode=0xba8849fd`
- `idcode_ir6.json` (`--user-ir 0x02 --ir-len 6`):
  - `idcode=0xba8849fd`
- `idcode_ir5.json` (`--user-ir 0x02 --ir-len 5`):
  - `idcode=0x000000fe`

## Interpretation

This run is a reproducible no-progress checkpoint for the same symptom pattern seen in v111/v112:
- no `magic_ok`
- no PLL lock
- no native DDR traffic (`dfii_data_*` all false)
- no stable `INIT` completion state

Unlike prior v97/v98 pass/fail transitions, this sweep did **not** reproduce `init_error=1` or any data-bearing phase, reinforcing the hypothesis that the active JTAG/debug instruction path remains decoupled from the expected DDR status register path on this board context.

## Next action

- Re-run `probe_bits4672_ir5.json` with a clean FTDI client (ensure no competing daemon)
- Then keep only two canonical payloads for v114+: `bits64` + `bits4672/ir=6` with/without `--tdo-0`, and compare against a known-good `jtag_debug_shift` mapping against stable `idcode` sequence.
