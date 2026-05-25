# PCIe Autonomous Loop

- started: 2026-05-25T10:49:13+02:00
- port BDF: `0000:41:00.0`
- endpoint regex: `Xilinx|\[10ee:`
- interval seconds: `5`
- iterations: `6`
- bitstream: `none`
- loader: `/home/roland/openFPGALoader/build/openFPGALoader`
- sudo: not used
- pcie jtag status: `1`
- pcie tdo bit: `7`

Each `iter-NNNN` directory contains unprivileged captures of `boltctl`,
`lspci -Dnn`, `lspci -tv`, `lspci -vvv -s 0000:41:00.0`, best-effort
kernel journal output, optional JTAG detect, and diffs against the previous
iteration. `summary.jsonl` records one JSON object per iteration.
