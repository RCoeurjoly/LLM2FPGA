# v105 source7 intent mask

## Purpose

Check whether the exact v99 byte/phase association build can remain init-clean while exposing the expected source7 slot intent for the missing byte/phase locations.

This was built from the exact v99 result baseline with only a debug-payload change:

- source worktree: `/tmp/task6-v105-source7-intent`
- source commit: `9db4592 task6-ddr3: expose v105 source7 intent mask`
- base result commit: `cecae7b`
- bitstream: `/nix/store/m8cqha2v7aswx1zbhl53mm9lx3nb4gyg-task6-ypcb-litedram-no-odelay-lowrate-byte-phase-assoc-matrix-init-bandwidth-probe.bit`
- bitstream sha256: `0fcecda9913a49e06a4c888e98771bd008aab6815c14fcdfd08ad52f69f7edce`

## Hardware result

- `version`: `105`
- `state`: `PROBE_DFII_DONE`
- `pll_locked`: `true`
- `init_done`: `true`
- `init_error`: `false`
- `init_seq_done`: `true`
- `init_seq_error`: `false`
- `wb_timeout_seen`: `false`
- `dfii_addr_match_masks`: `0x10080`
- `dfii_addr_nonzero_masks`: `0x10080`

The expected source7 intent mask is therefore visible in hardware:

```text
source7 expected slots: [7, 16]
source7 expected mask: 0x10080
```

The observed byte/phase association readback still omits source7:

```text
source7 readback match mask:   0x00000
source7 readback nonzero mask: 0x00000
```

The rest of the matrix matches the v99/v103 shape:

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

This rules out a route regression for this tiny v105 debug change: the bitstream is init-clean and reaches the same DFII done state as v99/v103.

It also confirms that the expected source7 positions are `[7, 16]`, encoded as `0x10080`, while the readback matrix still reports no source7 data.

This v105 marker is an expected-intent exposure, not a live tap of the exact DFII write-data bus. The next surgical boundary test should expose the live source7 DFII write-data word/mask immediately before the DFII CSR write. If that live tap is `0x10080` and readback remains zero, the fault is downstream of write-data construction.
