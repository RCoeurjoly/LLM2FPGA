# Seed16 Pinned UberDDR3 Baseline Bundle

This bundle preserves the known-good YPCB/UberDDR3 baseline copied from
`/home/roland/UberDDR3` on 2026-05-10.

Contents:

- `source/`: copied pinned UberDDR3 source bundle used by the passing build.
- `standalone-uberddr3-flake.nix`: standalone flow that produced the baseline.
- `standalone-uberddr3-flake.lock`: lock file for that standalone flow.
- `ypcb-uberddr3-bist-seed16-passing.bit`: copied passing seed16 bitstream.

Primary proof:

- `artifacts/task6/runs/2026-05-10T21-04-07+0200-ypcb-ddr3-pinned-source-seed16-baseline-a00`

That run programmed the copied bitstream on YPCB-00338-1P1, wrote USER2 command
byte `0x5a` at address `0x00`, and read USER1 payload with `--tdo-bit 7` and
`--bits 1024`. The verdict reports calibration pass, command gate pass,
`read_byte=0x5a`, `expected=0x5a`, `ack_count=2`, and `err_count=0`.

Scope:

- Useful for proving DDR3 calibration plus controlled low-byte JTAG write/read.
- Not a sustained sequential read streamer and not an LLM weight integration.
- Incomplete streamer/address-probe attempts remain experimental evidence only.
