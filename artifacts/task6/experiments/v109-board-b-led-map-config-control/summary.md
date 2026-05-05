# v109 Board B LED-map configuration control

## Hypothesis

If Board B is generally configurable through the openXC7/openFPGALoader path, then a small non-DDR YPCB LED-map bitstream should assert FPGA `DONE`.

This isolates configuration from DDR3, LiteDRAM, DFII, and debug-probe logic.

## Source/control input

- Source commit: `33d6252`
- Flake target: `.#task6-led-map-bitstream`
- Built bitstream: `/nix/store/wxmy0chrhz9kbb4dx0yjfhmf4sn5535q-task6-led-map.bit`
- Bitstream SHA256: `41798a2cfe76d85adef246ac7507ab6115c36b32df7cbfbac58fcb3d09c99874`
- Board: Board B
- JTAG adapter: Digilent HS3 serial `210299BF3824`
- DDR3 usage: none
- LiteDRAM usage: none
- BSCAN/debug probe usage: none

## Programming result

openFPGALoader transferred the bitstream to SRAM, but status still reported:

```text
ir: 1 isc_done 0 isc_ena 0 init 0 done 0
Register raw value: 0x0
CRC Error       No CRC error
ID Error        No ID error
INIT Complete   0x0
Done            0x0
```

## Interpretation

This is not a DDR3 failure. A small non-DDR design produces the same `DONE=0` symptom seen with the exact v99 DDR probe bitstream.

The current Board B problem is therefore below the DDR3 layer:

- board configuration mode/jumper/power/reset issue,
- board-specific programming/status-read behavior,
- openFPGALoader/status interaction with this board setup,
- or physical setup difference between Board A and Board B.

## Decision

Do not run DDR3 experiments on Board B until a non-DDR bitstream reaches a trustworthy configured state.

Next diagnostic should compare Board B physical/configuration setup against Board A or try a vendor-known/simple bitstream/programmer path that can independently confirm `DONE`.
