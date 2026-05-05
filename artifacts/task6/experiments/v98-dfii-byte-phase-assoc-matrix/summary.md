# v98 DFII byte-phase association matrix

Hypothesis: DFII byte/phase writes map to a fixed physical-to-logical byte/phase association.

Source commits:
- aeca82e task6-ddr3: prepare v98 DFII byte-phase matrix
- a2e24a0 task6-ddr3: fix v98 matrix summarizer input

Bitstream:
- /nix/store/nkv5jgd6ppdbf6d0pa16alyyc12npzhc-task6-ypcb-litedram-no-odelay-lowrate-byte-phase-assoc-matrix-init-bandwidth-probe.bit
- sha256: 10f15198105da24fa4ea2c89ca62f0cbbf741b830a6b2b3431c4be079ba6597f
- target: task6-ypcb-litedram-no-odelay-lowrate-byte-phase-assoc-matrix-init-bandwidth-probe-bitstream
- seed: 13

Execution:
- Programmed via openFPGALoader on Digilent HS3 serial 210299BF3824.
- JTAG probe captured to probe.json.
- Promoted matrix artifact written to artifacts/task6/parallel-hypotheses/h2-litedram-dfii-byte-phase-association-matrix.json.

Result:
- status: FAIL
- probe version: 98
- pll_locked: true
- state: PROBE_ERROR
- init_state: INIT_ERROR
- init_error: false
- init_seq_error: true
- wb_timeout_seen: true
- DFII sequence did not run; all association masks remained zero.

Decision:
- Do not interpret this as a byte/phase association result.
- The next surgical step is to restore reproducible init for the v98 DFII-only target, likely by comparing the target construction against the known init-clean seed-13 addrwalk/native construction and generated-core variant before changing DDR logic.
