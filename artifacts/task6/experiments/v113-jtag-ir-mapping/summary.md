# v113 JTAG IR mapping and namespace probe on seed-13 init-status-only target

## Hypothesis

IR mapping is the root cause if no opcode maps to the expected `JTAG_DEBUG_MAGIC` payload. This experiment systematically sweeps instruction values and checks which IR instruction and IR length combination can produce valid debug payload from the same seed-13 init-status-only bitstream.

## Controlled input

- Date: `2026-05-06T18:10:xx+02:00`
- Source commit: `090f344`
- Target bitstream (same as v110/v111 control): `/nix/store/1vd7z7ysz5s7alslq1l121alz26bpg0r-task6-ypcb-litedram-no-odelay-lowrate-init-status-only-init-bandwidth-probe.bit`
- Serial: `210299BF3824`
- Board: Board A

## Commands

- Programmer:
  - `openFPGALoader -c digilent_hs3 --ftdi-serial 210299BF3824 /nix/store/1vd7z7ysz5s7alslq1l121alz26bpg0r-task6-ypcb-litedram-no-odelay-lowrate-init-status-only-init-bandwidth-probe.bit`
- IR sweep scripts (created inline for this pass):
  - sweep IR=0..2^6-1, `read_payload(..., bits=32)` and `read_idcode(..., ir_len=6)`
  - sweep IR=0..2^6-1, `bits=4672` candidate decode summary
  - sweep IR=0..2^6-1 for `ir_len=5` and `ir_len=6` short reads
  - sweep IR in `{0x00,0x02,0x05,0x07,0x08,0x09,0x0b,0x25,0x26,0x27,0x30,0x32,0x34,0x35,0x3f}` with `bits=4672`

## Findings

- Full 6-bit IR sweep confirms `read_idcode` returns the expected FPGA IDCODE value for `IR=0x09` and also echoes idcode-like values for `IR=0x25` and `IR=0x37`.
- Most IR values return constant/near-constant short DR words such as `0x7d`/`0x7c`/`0x7f` for 32-bit reads.
- In one-shot long-read tests (4,672 bits), no IR produced `magic_ok=True`, no candidate showed `JTAG_DEBUG_MAGIC` (`0x54364A44`) in any bit position (tested directly on raw int and byte search), including IR values that were idcode-like at 32-bit access.
- Nonzero payload activity with 4,672-bit reads is split across a few IR values but remains inconsistent and does not resemble the expected DDR/debug payload schema (e.g., many IRs have only tiny, low-entropy values in trailing words).

## Recorded data

- `artifacts/task6/experiments/v113-jtag-ir-mapping/irlen6.json`
- `artifacts/task6/experiments/v113-jtag-ir-mapping/irlen5.json`
- `artifacts/task6/experiments/v113-jtag-ir-mapping/ir_long_candidates.json`
- `artifacts/task6/experiments/v113-jtag-ir-mapping/ir_len6_4672_summary.json`

## Interpretation

This run strengthens the conclusion that we are not targeting the intended LiteDRAM debug DR namespace with this probe setup, not just toggling the wrong probe mode.

- `IR` value changes affect readback shape, but none map to `magic_ok` payload.
- Expected FPGA IDCODE is still readable, which means JTAG transport and TAP-level shifting are fundamentally working.
- Next step should be to verify BSCANE2 instruction mapping expectations in RTL generation path (`JTAG_CHAIN` and debug-port IR decode expectations), and/or compare against a build that is known to emit a valid `magic_ok` via the same readers.
