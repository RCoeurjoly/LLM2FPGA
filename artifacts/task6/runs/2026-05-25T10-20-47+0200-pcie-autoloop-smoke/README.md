# PCIe Autonomous Loop

- started: 2026-05-25T10:20:47+02:00
- port BDF: `0000:41:00.0`
- endpoint regex: `10ee:|Xilinx|0480|9999`
- interval seconds: `1`
- iterations: `2`
- bitstream: `none`
- loader: `/home/roland/openFPGALoader/build/openFPGALoader`
- sudo: not used

Each `iter-NNNN` directory contains unprivileged captures of `boltctl`,
`lspci -Dnn`, `lspci -tv`, `lspci -vvv -s 0000:41:00.0`, best-effort
kernel journal output, optional JTAG detect, and diffs against the previous
iteration. `summary.jsonl` records one JSON object per iteration.
