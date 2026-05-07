# Deliverable 2d: FPGA integration + bring-up

Reference:

- docs/project-plan<sub>v2</sub>.org:149

Goal:

- Build FPGA bitstream from the matmul design and load it on hardware.

Hardware:

- Board: YPCB-00338-1P1
- Programmer: openFPGALoader + Digilent HS3
- Enclosure: OWC Mercury Helios 3S

Main files:

- 'fpga/rtl/matmul<sub>selftesttop</sub>.sv'
- 'fpga/constraints/matmul<sub>selftest</sub>.xdc'
- 'flake.nix' packages:
  - '.#matmul-selftest-bitstream'

Commands:

``` bash
nix build .#matmul-selftest-bitstream -L
openFPGALoader -c digilent_hs3 --ftdi-serial 210299BF3824 -m result # maybe execute with sudo
```

Result:

- Bitstream build: PASS
- Board programming: PASS
- Self-test on board: PASS

Demo video:

- <https://youtu.be/NURqxN0HnFM>

Status:

- Deliverable 2d complete.
