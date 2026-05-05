# v108 Board B cross-board reproducibility check

## Hypothesis

Programming the exact init-clean Board A DDR3 probe bitstream on Board B should reproduce the v99 init-clean byte/phase matrix if the source7 failure is design/toolchain-level rather than board-specific.

## Controlled input

- Board: Board B, connected through Digilent HS3 serial `210299BF3824`
- Bitstream: exact v99 Board A init-clean artifact
- Bitstream path: `/nix/store/qmzhnmwwybzmi2cyf3xncj3p1nirz46f-task6-ypcb-litedram-no-odelay-lowrate-byte-phase-assoc-matrix-init-bandwidth-probe.bit`
- Bitstream SHA256: `b02f9444f17ea595c45e6110867dbb4fe09bc9b4658af3bd7582eee629d0e116`
- RTL/probe changes: none

## JTAG detection

Board B is visible on JTAG as the expected Kintex-7 target:

```text
idcode 0x23751093
manufacturer xilinx
family kintex7
model xc7k480t
irlength 6
```

## Programming/probe result

The exact v99 bitstream did not leave Board B configured:

```text
MMCM lock 0x0
EOS 0x0
INIT Complete 0x0
Done 0x0
```

The subsequent probe returned an all-zero payload:

```text
magic_ok=false
version=0
magic=0
pll_locked=false
init_done=false
init_error=false
sys_rstn=false
state=PROBE_RESET
```

Raw probe artifact:

```text
artifacts/task6/experiments/v108-board-b-cross-board-repro/v99-probe.json
```

## Interpretation

This is not a DDR3 byte/phase result. Board B did not reach a comparable configured state with the exact known-good v99 Board A bitstream.

The useful conclusion is that the board swap currently exposes a configuration/comparability problem, not evidence for or against the source7 DDR hypothesis.

## Decision

Stop the cross-board DDR comparison until Board B can be configured by the exact v99 bitstream or a board-specific incompatibility is identified.

Do not run v106/v107 on Board B yet; those results would be low-information while `DONE=0` for v99.
