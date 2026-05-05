# v99 DFII byte-phase wide matrix

Hypothesis: extending the byte-phase association matrix onto the five-word DFII CSR path will reveal whether the v98 fanout/missing slots are caused by the omitted word4/ninth-byte path.

Source commit:
- feccb96 task6-ddr3: add v99 wide byte-phase matrix

Bitstream:
- /nix/store/qmzhnmwwybzmi2cyf3xncj3p1nirz46f-task6-ypcb-litedram-no-odelay-lowrate-byte-phase-assoc-matrix-init-bandwidth-probe.bit
- sha256: b02f9444f17ea595c45e6110867dbb4fe09bc9b4658af3bd7582eee629d0e116
- target: task6-ypcb-litedram-no-odelay-lowrate-byte-phase-assoc-matrix-init-bandwidth-probe-bitstream
- seed: 13
- generated core: task6YpcbLiteDramNoOdelayLowrateDfiDebugRtlElaboration
- top define: TASK6_LITEDRAM_DEBUG_PORTS

Execution:
- Programmed via openFPGALoader on Digilent HS3 serial 210299BF3824.
- JTAG probe captured to probe.json.
- Promoted matrix artifact written to artifacts/task6/parallel-hypotheses/h2-litedram-dfii-byte-phase-association-matrix.json.

Result:
- status: FAIL
- probe version: 99
- pll_locked: true
- init_done: true
- init_error: false
- init_seq_done: true
- init_seq_error: false
- wb_timeout_seen: false
- state: PROBE_DFII_DONE
- dfii_seq_state: DFII_SEQ_DONE
- DFII matrix ran to completion on the wide five-word path.

Observed combined 20-slot match masks:
- source 0: 0x00201
- source 1: 0x00402
- source 2: 0x00804
- source 3: 0x01008
- source 4: 0x02010
- source 5: 0x04020
- source 6: 0x08040
- source 7: 0x00000
- source 8: 0x20100
- source 9: 0x00000
- source 10: 0x00000
- source 11: 0x00000
- source 12: 0x00000
- source 13: 0x00000
- source 14: 0x00000
- source 15: 0x00000

Interpretation:
- The previous v98 16-slot pattern was incomplete: source slot 8 also appears in word4 slot 17 when the matrix reads all five DFII CSR words.
- Source slots 0 through 6 still fan out to two logical slots each.
- Source slot 7 still has no observed match, even with word4 visible.
- This does not justify a native DDR logic change yet.
- Next surgical step: create a source-side matrix that writes candidate slots 16 and 17 explicitly, or reuse the lane7 locator path to identify the write source for missing lane7 before applying a permanent packing transform.
