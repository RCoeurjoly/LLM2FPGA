# v106 live source7 write tap

## Purpose

Move the v105 source7 check from an expected-intent marker to a live write-side tap.

This experiment latches the actual data presented to the DFII write-data CSR path for source7 while the byte/phase matrix sequencer is issuing acknowledged Wishbone writes.

The existing decoded address-matrix fields are repurposed for this experiment:

```text
dfii_addr_mismatch_masks = source7 live write-word ack mask
dfii_addr_nonzero_masks  = source7 live write-side nonzero byte-slot mask
dfii_addr_match_masks    = source7 live write-side source7-tag byte-slot mask
```

## Source

- source worktree: `/tmp/task6-v106-live-source7-tap`
- source commit: `f7eb24c task6-ddr3: add v106 live source7 write tap`
- base result commit: `cecae7b`
- bitstream: `/nix/store/ylmmfifwdwc0jqmd1zx3nlmlafmg9y3r-task6-ypcb-litedram-no-odelay-lowrate-byte-phase-assoc-matrix-init-bandwidth-probe.bit`
- bitstream sha256: `93743bd554740701a5b9282057b4898fe5c6e244c2c68bc29b2df3698bbba319`

## Hardware result

- `version`: `106`
- `state`: `PROBE_DFII_DONE`
- `pll_locked`: `true`
- `init_done`: `true`
- `init_error`: `false`
- `init_seq_done`: `true`
- `init_seq_error`: `false`
- `wb_timeout_seen`: `false`

Live source7 write tap:

```text
source7 write-word ack mask:        0xfffff
source7 write-side nonzero mask:    0x00080
source7 write-side tag-match mask:  0x00080
```

Readback matrix:

```text
source7 readback match mask:        0x00000
source7 readback nonzero mask:      0x00000
```

Full readback matrix remains v99/v103-shaped:

```text
source0: 0x00201
source1: 0x00402
source2: 0x00804
source3: 0x01008
source4: 0x02010
source5: 0x04020
source6: 0x08040
source7: 0x00000
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

v106 is init-clean and reaches `PROBE_DFII_DONE`, so this live tap did not reproduce the v100-v102 route-sensitive init failure.

The source7 write construction is alive:

```text
all source7 write-data CSR words were acknowledged
the live source7 tag byte was emitted at write-side byte slot 7
```

The missing source7 is therefore not caused by the RTL failing to generate source7 data for the DFII write-data CSR path. The fault boundary moves downstream of acknowledged DFII write-data CSR issuance:

```text
DFII CSR write acceptance -> DFI write-data capture -> PHY/DDR write -> PHY/DFI readback
```

Note: v105 used `0x10080` as an inferred read-side association expectation from the v99/v103 observed rule. v106 reports a live write-side byte-slot mask; for source7's generated write word, the expected live tag slot is `0x00080`.

## Next decision

The next surgical test should expose the actual DFI/PHY write-data bus at the write command boundary for the source7 run, or equivalently force the source7 tag through a known-good source slot and check whether the disappearance follows the tag value or the write-side byte slot.
