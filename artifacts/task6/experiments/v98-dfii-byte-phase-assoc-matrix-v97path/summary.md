# v98 DFII byte-phase association matrix rebuilt on v97 target path

Hypothesis: DFII byte/phase writes map to a fixed physical-to-logical byte/phase association.

Source commit:
- 5a1ed0e task6-ddr3: rebuild v98 on v97 target path

Bitstream:
- /nix/store/d1vxw6kym8805n9zmm9j5pp97f8sw2ic-task6-ypcb-litedram-no-odelay-lowrate-byte-phase-assoc-matrix-init-bandwidth-probe.bit
- sha256: d7f8df3babe99f78606add8df68a4c148804195ef34aa62f20c4f17ca60033f2
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
- probe version: 98
- pll_locked: true
- init_done: true
- init_error: false
- init_seq_done: true
- init_seq_error: false
- wb_timeout_seen: false
- state: PROBE_DFII_DONE
- dfii_seq_state: DFII_SEQ_DONE
- dfii_data_failed: true
- DFII matrix ran to completion.

Observed match masks:
- source 0: 0x0201
- source 1: 0x0402
- source 2: 0x0804
- source 3: 0x1008
- source 4: 0x2010
- source 5: 0x4020
- source 6: 0x8040
- source 7: 0x0000
- source 8: 0x0100
- source 9: 0x0000
- source 10: 0x0000
- source 11: 0x0000
- source 12: 0x0000
- source 13: 0x0000
- source 14: 0x0000
- source 15: 0x0000

Interpretation:
- Rebuilding v98 on the v97 DFI-debug target path restored init and DFII execution.
- The previous v98 init failure was a target-construction/reproducibility issue.
- The byte-phase matrix is not bijective: several source bytes fan out to two logical slots, and several source slots vanish.
- Do not proceed to native BIST yet.
- Next surgical step: inspect/apply the implied shifted/fanout association in the DFII byte-lane/phase packing logic, or extend the matrix to include the missing high/ninth-byte lane before changing native DDR logic.
