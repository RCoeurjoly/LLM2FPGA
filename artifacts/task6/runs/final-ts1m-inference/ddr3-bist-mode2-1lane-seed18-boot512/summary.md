# YPCB DDR3 BIST_MODE=2 one-lane seed18 gate

Date: 2026-05-22

Bitstream:

`/nix/store/f7ffi8czaxs1lal4bscvl1i1bjd5mznf-task6-ypcb-uberddr3-bist-1lane-mode2-seed18.bit`

Target:

`.#task6-ypcb-uberddr3-bist-1lane-mode2-seed18-bitstream`

Change under test:

- `BIST_MODE=2`
- `BYTE_LANES=1`
- repo-local read probe disabled for this target, so the user Wishbone port does not interfere with the upstream BIST run
- normal read-probe targets now gate on upstream BIST done (`debug1[4:0] == 23`) rather than only `calib_complete`

Build result:

- route completed
- post-route `controller_clk`: 122.38 MHz PASS at 25 MHz

Board result:

- FPGA programmed successfully with openFPGALoader and Digilent HS3 serial `210299BF3824`
- direct JTAG read at roughly 11 seconds after programming:
  - `magic=0x54364a44`
  - `version=0x20`
  - BIST-specific `debug1=0x003c1e31`
  - `debug1[4:0]=17`
- direct JTAG read after an additional 300 seconds:
  - `magic=0x54364a44`
  - `version=0x20`
  - BIST-specific `debug1=0xaa3cb031`
  - `debug1[4:0]=17`
  - repo-local probe counters remained at zero

Conclusion:

BIST_MODE=2 has not been proven on this YPCB one-lane seed18 build. It remains in state 17 after the long gate and does not reach the known BIST done state 23. This result does not invalidate the earlier BIST_MODE=1 one-lane proof; it says the stronger upstream BIST_MODE=2 gate is currently not passing or not reaching the same done state within the tested window.
