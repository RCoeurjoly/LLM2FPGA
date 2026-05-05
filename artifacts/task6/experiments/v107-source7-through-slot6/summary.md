# v107 source7 through slot6

## Purpose

Discriminate whether the missing source7 is caused by the `0xa7` source/tag identity or by the original write-side byte slot 7.

This experiment keeps the source7 tag value but emits it through source6's known-good byte placement in the wide byte-phase helper:

```text
source7 tag:        0xa7
original placement: byte slot 7
forced placement:   byte slot 6
```

## Source

- source worktree: `/tmp/task6-v107-source7-through-slot6`
- source commit: `fa198df task6-ddr3: add v107 source7 slot6 force`
- base result commit: `cecae7b`
- bitstream: `/nix/store/rmcdd6bh8x0fcf6fbxpl2lj1yhr8zj9h-task6-ypcb-litedram-no-odelay-lowrate-byte-phase-assoc-matrix-init-bandwidth-probe.bit`
- bitstream sha256: `8d45a217035f5befb50ae70a396bef0cc16b753c94eb9b766bcf9a6b254b41b1`

## Hardware result

- `version`: `107`
- `state`: `PROBE_DFII_DONE`
- `pll_locked`: `true`
- `init_done`: `true`
- `init_error`: `false`
- `init_seq_done`: `true`
- `init_seq_error`: `false`
- `wb_timeout_seen`: `false`

Source7 readback:

```text
source7 readback match mask:   0x08040
source7 readback nonzero mask: 0x08040
```

Full readback matrix:

```text
source0: 0x00201
source1: 0x00402
source2: 0x00804
source3: 0x01008
source4: 0x02010
source5: 0x04020
source6: 0x08040
source7: 0x08040
source8: 0x20100
source9: 0x00000
source10: 0x00000
source11: 0x00000
source12: 0x00000
source13: 0x00000
source14: 0x00000
source15: 0x00000
```

## Interpretation

v107 is init-clean and reaches `PROBE_DFII_DONE`.

The `0xa7` source7 tag survives when emitted through source6's known-good byte placement. Therefore the v99/v103/v105/v106 missing source7 is not caused by the source7 tag value or source7 sweep identity.

The fault follows the original write-side byte slot 7.

This tightens the boundary:

```text
not source7 tag/source identity
not DFII write-data CSR acknowledgement
not general word1 path
specific to original byte slot 7 / byte-lane position 3 of word1
```

## Next decision

The next surgical test should move another known-good tag into original byte slot 7. If the known-good tag disappears there too, byte slot 7 is confirmed bad. If it survives, the failure is a narrower interaction between source7's original placement and the later read association.
