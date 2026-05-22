# YPCB DDR3 BIST_MODE=2 known-good-equivalent Nix gate

Date: 2026-05-23

Upstream input:

- `uberDdr3` pinned to `RCoeurjoly/UberDDR3` commit `8e6b0bb9ed38a97505b29b28a6d2689746470e7b`.

Target:

- `.#task6-ypcb-uberddr3-bist-2lane-mode2-known-good-seed18-bitstream`
- bitstream: `/nix/store/vxfdhyzdfmff9c2apfsyxraqylsclfif-task6-ypcb-uberddr3-bist-2lane-mode2-known-good-seed18.bit`

Known-good-equivalent configuration:

- `BYTE_LANES=2`
- `BIST_MODE=2`
- `BIST_TEST_DATAMASK=0`
- `DLL_OFF=0`
- `SPEED_BIN=1`
- `SDRAM_CAPACITY=4`
- controller clock period: `12_000 ps`
- DDR3 clock period: `3_000 ps`
- PLL divisors: controller `/12`, DDR `/3`, ref `/5`, DDR90 `/3`

Build result:

- route completed
- post-route `controller_clk`: 124.13 MHz PASS at 25 MHz

Board result:

- FPGA programmed successfully with Digilent HS3 serial `210299BF3824`
- direct BIST-schema JTAG read after programming:
  - `magic=0x54364a44`
  - `version=0x20`
  - `status=0xd3`
  - `debug1=0x00000017`
  - `debug1[4:0]=23`
  - `calib_seen_cycle=0x2e46a698`

Conclusion:

This Nix-built target proves the upstream BIST_MODE=2 fix in the LLM2FPGA flow when the wrapper matches the upstream known-good YPCB shape. The previous one-lane slow-clock BIST_MODE=2 target remained at state 17 because it was not equivalent: it left DM/datamask BIST enabled and used the older one-lane slow-clock debug configuration.
