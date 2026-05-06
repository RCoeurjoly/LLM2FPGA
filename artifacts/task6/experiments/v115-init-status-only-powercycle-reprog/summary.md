# v115 init-status-only post power-cycle, reprogram + 4672-bit probe (seed-13 path, Board A)

## Actions performed
- Bitstream loaded after power cycle:
  - `/nix/store/bcbgyc1z5ks35n1rkcl1rsq8cbgps4v5-task6-ypcb-litedram-no-odelay-lowrate-init-status-only-init-bandwidth-probe.bit`
  - `openFPGALoader -c digilent_hs3 --ftdi-serial 210299BF3824 --skip-load-bridge --write-sram <bitstream>`
- Probe read:
  - `python3 scripts/task6/read_litedram_probe_jtag_ftdi.py --serial 210299BF3824 --freq-hz 6000000 --bits 4672 --poll --poll-count 10 --poll-interval 0.2 --json-only --user-ir 0x02 --ir-len 6`
- IDCODE check:
  - `python3 scripts/task6/read_litedram_probe_jtag_ftdi.py --serial 210299BF3824 --freq-hz 6000000 --idcode-only --json-only --user-ir 0x02 --ir-len 6`

## Result
- IDCODE: `0xba8849ff`
- Probe (attempts=1):
  - `magic_ok=false`
  - `version=42`
  - `pll_locked=false`
  - `init_done=true`
  - `init_error=true`
  - `init_seq_done=true`
  - `init_seq_running=false`
  - `timeout_seen=true`
  - `dfii_data_pass=true`
  - `dfii_data_failed=false`
  - `dfii_seq_state=DFII_SEQ_IDLE`
  - `read_target_seen=false`
  - `outstanding_full=true`
  - `status.state=UNKNOWN_183`
  - `failed=true`
  - `wb_ack_count=3584`, `wb_wait_count=10752`

## Interpretation
Post-power-cycle reload still deterministically lands in the same `version=42`/`magic_ok=false` decode path with `init_error=true` and timeout. The board accepted the bitstream (IDCODE valid), so this is now consistent with the previous “active wrapper mismatch” pattern rather than a flaky transport.
