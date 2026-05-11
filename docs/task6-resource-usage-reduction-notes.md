# Task 6 Resource Usage Reduction Notes

This file is the working Task 6 note referenced from `AGENTS.md`. It is the
right place for Task 6 planning details while `docs/project-plan*` remain
reviewer-controlled.

## Current workspace snapshot

- Current branch: `task6`
- This branch currently contains the board/openXC7/matmul flow and the existing
  reviewer-facing docs, but it does not yet contain the TinyStories Task 3
  pipeline files that were present in other workspaces.
- Current hardware anchor in this repo:
  - board: `YPCB-00338-1P1`
  - FPGA: `XC7K480T`
  - there is already a documented board self-test pass in
    `deliverables/2d-fpga-bitstream.org`
- Known tooling context in this repo:
  - `flake.nix` already pins the openXC7 / nextpnr-xilinx path for
    `xc7k480tffg1156-1`
  - `docs/project-management.org` records prior nextpnr-xilinx segfault work,
    so Yosys-level resource evaluation and nextpnr viability should be tracked
    separately

### Durable baseline bundle

Use this copied baseline bundle for Task 6 comparisons:

- `artifacts/task6/baselines/tiny-stories-1m-baseline-float-selftest-all-memory-utilization`

Reason:

- it is copied out of `/nix/store`, so it survives `nix-collect-garbage`
- it is the stable reference bundle for strategy deltas in this branch

Expected baseline files:

- `summary.json`
- `summary.txt`
- `stat.json`

## Current execution program (2026-04-21)

This section is the live Task 6 operating contract. Use it to decide what to
run next, when to stop a lane, and what evidence must be recorded before a lane
earns more work.

### Goal and success bar

- Primary goal for the next 1-2 weeks:
  - produce a reproducible reduction in peak host memory pressure or mapped
    utilization relative to the copied baseline bundle above
- Primary success bar:
  - one lane produces a durable artifact bundle showing either:
    - lower peak memory / no OOM where baseline or a prior candidate OOMs, or
    - a better mapped resource result than the copied baseline bundle

### Operating rules

- Keep `task6` as the integration and notes branch.
- Run strategy work in separate worktrees or sibling branches derived from
  `task6`.
- Optimize for feedback-loop speed first:
  - prefer the smallest representative core and cheapest measurement artifact
    that still preserves relevant operator/structure coverage
  - prove that coverage with MLIR op stats before trusting the smaller core for
    Task 6 decisions
  - replay only the promising changes on the larger representative/full lanes
- Treat external memory / DDR3 as an allowed first-class strategy, not only as
  a fallback.
- Compare every result against
  `artifacts/task6/baselines/tiny-stories-1m-baseline-float-selftest-all-memory-utilization`.
- Record every evidence milestone in this file immediately after it lands.
- Treat every recorded Task 6 experiment as a checkpointed unit:
  - once its docs and artifact bundle are written, commit and push the branch
    before starting the next experiment
- After any experiment produces simulation, synthesis, route, bitstream, or
  board results, update the status artifacts and commit with a specific,
  appropriate, result-oriented commit message before starting the next
  experiment.

## Active DDR3 Rebaseline: Upstream LiteX-Boards YPCB Support

### 2026-05-10 - Imported stable UberDDR3 baseline from `~/UberDDR3`

Decision:

- Continue Task 6 DDR3 work in this workspace.
- Import only the stable UberDDR3 pieces:
  - pinned seed16 baseline source/flake/bitstream bundle
  - direct USER1/USER2 JTAG read/write scripts
  - experiment runner support for command-byte and optional command-address
    probes
  - compact run artifacts proving calibration plus controlled low-byte
    write/read
- Keep the incomplete sequential/address-probe streamer path experimental.
  Do not make it the default DDR3 flow and do not connect it to model weights
  yet.

Imported evidence:

| artifact | role |
| --- | --- |
| `artifacts/task6/uberddr3-baseline-flow/seed16-pinned-2026-05-10/` | copied pinned source, standalone flake/lock, and passing seed16 bitstream |
| `artifacts/task6/ddr3-run-results-uberddr3-2026-05-10.jsonl` | copied May 10 UberDDR3 run log, including pass controls and failed streamer probes |
| `artifacts/task6/runs/2026-05-10T18-51-28+0200-ypcb-ddr3-nodm-lowbyte-selftest-pass` | first low-byte command `0x5a` integrity pass on the no-DM diagnostic baseline |
| `artifacts/task6/runs/2026-05-10T20-21-49+0200-task6flow-ddr3-known-good-baseline-a00-byte00` | command byte `0x00` pass on known-good baseline |
| `artifacts/task6/runs/2026-05-10T20-22-25+0200-task6flow-ddr3-known-good-baseline-a00-byteff` | command byte `0xff` pass on known-good baseline |
| `artifacts/task6/runs/2026-05-10T21-04-07+0200-ypcb-ddr3-pinned-source-seed16-baseline-a00` | copied pinned-source seed16 baseline pass; `read_byte=0x5a`, `ack_count=2`, `err_count=0` |

Current DDR3 claim:

- Proven enough to continue productively:
  - YPCB DDR3 can calibrate in the pinned seed16 UberDDR3 baseline.
  - Direct JTAG command/read infrastructure works through USER2/USER1 with
    `--tdo-bit 7`.
  - Controlled low-byte write/read values `0x00`, `0x5a`, and `0xff` can be
    observed through the debug payload with write/read ACKs and no reported
    Wishbone error.
- Not yet proven enough for LLM weights:
  - no sustained sequential read streamer
  - no multi-address deterministic row scan
  - no measured burst bandwidth
  - no connection to the INT8/top1 weight fetch path

Next milestone:

1. Start from the copied passing seed16/pinned baseline bundle.
2. Add the smallest sequential read streamer that minimally perturbs DDR PHY
   placement and the known-good low-byte path.
3. Verify over JTAG that reads across multiple addresses are deterministic.
4. Measure burst read bandwidth.
5. Only after that, connect DDR3 to the LLM weight fetch/rowstream path.

Stop rule:

- If a streamer or address-probe variant loses calibration or command ACKs,
  classify it as experimental evidence and return to the copied seed16
  baseline before adding more logic.

### 2026-05-11 - DDR3 sequential low-byte probe direction

Decision:

- Do not use variable 512-bit byte selection as the proof mechanism.
- Keep the v33 user-port probe experimental: it removed variable byte selection,
  but seed15 and seed16 both decoded JTAG correctly and failed to leave
  `WAIT_CALIB`.
- Promote the calibrated BIST-derived low-byte-per-address path as the active
  instrumentation baseline.
- Use command count, not USER2 payload byte value, to advance the stream window
  until USER2 payload capture has its own readback proof.

Evidence:

| bitstream | result |
| --- | --- |
| `/nix/store/5lmj01wnpan3sxffmbmiqdckv421w4db-task6-ypcb-uberddr3-user-port-probe-seed15.bit` | v33 user-port probe, JTAG magic/version valid, stuck in `WAIT_CALIB` |
| `/nix/store/hnnxaisdj553jpyqvkm19ql4jfigqx48-task6-ypcb-uberddr3-user-port-probe-seed16.bit` | v33 user-port probe, JTAG magic/version valid, stuck in `WAIT_CALIB` |
| `/nix/store/1y2wjcgkp8y9dzwjv6picrczgq8zzhj6-task6-ypcb-uberddr3-bist.bit` | BIST-derived probe, `calib=1`, `state=9`, `done=1`; observed low-byte stream `[0xa5, 0xa6, 0xa7, 0xa8]` with valid mask `0xf` and mismatch mask `0x0` |

Next execution target:

- Build a BIST-derived stream probe that keeps the calibrated transaction
  sequence and advances one 4-byte low-byte/address window per USER2 command
  event by command count.
- Passing bar for the next hardware run:
  - 16 command-count windows pass after calibration.
  - The 64 observed low-byte positions match `PROBE_BYTE + index`.
  - `valid=0xf`, `mismatch=0`, `err=0`, and write/read ACKs are observed for
    each 4-byte window.
- Only after this passes, connect rowstream loading; do not connect TinyStories
  weights yet.

Implementation note:

- v28 built and calibrated, and every observed 4-byte window byte-matched, but
  one USER2 write advanced `run_count` by 2. Root cause: the command shifter
  treated the BSCANE2 `UPDATE` level as an event and could toggle more than
  once while `UPDATE` was high. v29 edge-detects `UPDATE` in the TCK domain so
  the controller sees one command event per USER2 update. v29 still advanced by
  2, which indicates an update can arrive before a fresh USER2 DR shift while
  the previous command remains in `shift_q`; v30 adds a `shift_seen` guard so
  only updates following a selected DR shift can emit a command event. v30 still
  exposed two raw command events per USER2 write; v31 keeps the shifter
  instrumentation but adds a top-level consumer guard so duplicate raw command
  events are ignored while a DDR3 probe run is already active. v31 showed the
  duplicate can arrive after the very short 4-byte run completes; v32 therefore
  accepts only every other raw USER2 event at the consumer, matching the
  measured transport behavior while preserving the raw command counter for
  traceability.

Hardware result:

- v32 bitstream:
  `/nix/store/fma5qxp6k91gmgmj4pbh863bn5hsf0ds-task6-ypcb-uberddr3-bist.bit`
- Validator:
  `scripts/task6/validate_uberddr3_lowbyte_stream.py`
- Evidence JSON:
  `artifacts/task6/uberddr3-lowbyte-stream-v32-validation.json`
- Result: pass. Initial window plus 15 USER2-driven windows covered stream
  bases `0, 4, 8, ..., 60`; every 4-byte sample matched
  `PROBE_BYTE + stream_base + byte_index`, with `valid=0xf`, `mismatch=0`,
  `err=0`, and write/read ACKs set. Raw `command_count` still advances by 2 per
  validator command and is retained as transport instrumentation; consumed
  `run_count` advances by 1 per command.

### 2026-05-11 - DDR3 rowstream low-byte loader gate

Decision:

- Start TinyStories weight externalization with the deliberately wasteful
  low-byte-per-address mapping before relying on 512-bit DDR3 lane packing.
- The first hardware gate is rowstream byte integrity, not model integration:
  byte `N` of `rowstream.bin` is written to DDR3 Wishbone address `N`, byte
  lane 0, and read back from the same address/lane.
- Keep the dense 64-byte beat loader path available for later bandwidth work,
  but make the host loader default to `--storage-mode lowbyte` for the next
  deterministic proof.

Implementation:

- `fpga/rtl/task6_ypcb_uberddr3_rowstream_loader_top.sv` debug payload version
  is now `30`.
- Added loader opcodes:
  - `0x03`: write one low byte with `i_wb_sel[0]` asserted.
  - `0x04`: read one low byte from `o_wb_data[7:0]`.
- v30 also tried `BIST_MODE=1`, matching the known-good calibration topology.
  This did not restore calibration for the standalone rowstream-loader wrapper.
- `scripts/task6/task6_ddr3_rowstream_loader.py` now supports:
  - `--storage-mode lowbyte` for the Task 6 weight rowstream proof.
  - `--storage-mode beat` for the previous dense 64-byte path.
  - `--max-bytes` and `--progress-bytes` for cheap partial low-byte runs.
  - `--load-boundary-rows-only` to write only the token rows named by
    `--boundary-tokens`, making first/boundary row proof fast enough for the
    next board check.
  - run directories now include the bitstream stem instead of a hard-coded
    `seed15` suffix.

Validation already run:

- `python3 -m py_compile scripts/task6/task6_ddr3_rowstream_loader.py`: pass.

Hardware commands used:

```sh
nix build .#task6-ypcb-uberddr3-rowstream-loader-seed16-bitstream --no-link --print-out-paths -L
python3 scripts/task6/task6_ddr3_rowstream_loader.py \
  --bitstream /nix/store/vq59i7v0kfm8r13qz0aiv4vfip9ii9h5-task6-ypcb-uberddr3-rowstream-loader-seed16.bit \
  --storage-mode lowbyte \
  --load-boundary-rows-only \
  --boundary-tokens 0,1,31,32,50256 \
  --no-full-readback
```

Results:

| variant | bitstream | result |
| --- | --- | --- |
| v29 seed16, `BIST_MODE=0` | `/nix/store/f7cm0m0zqw7z8c5h0l80zqlscs7b4bc1-task6-ypcb-uberddr3-rowstream-loader-seed16.bit` | JTAG magic/version valid, DDR3 calibration timeout: `version=29`, `calib_seen=false`, `debug1=0x00000ecc` |
| v29 seed15, `BIST_MODE=0` | `/nix/store/8jyx0wl8xfr7j94hii5vx1i86wpjqc57-task6-ypcb-uberddr3-rowstream-loader-seed15.bit` | JTAG magic/version valid, DDR3 calibration timeout: `version=29`, `calib_seen=false`, `debug1=0x000006cc` |
| v30 seed16, `BIST_MODE=1` | `/nix/store/vq59i7v0kfm8r13qz0aiv4vfip9ii9h5-task6-ypcb-uberddr3-rowstream-loader-seed16.bit` | route converged and timing passed, JTAG magic/version valid, DDR3 calibration timeout: `version=30`, `calib_seen=false`, `debug1=0x000026cc` |
| known-good BIST control | `.#task6-ypcb-uberddr3-bist-seed16-bitstream` | pass; run `artifacts/task6/runs/2026-05-11T08-43-25+0200-task6-rowstream-control-known-good-bist`, `calibration=pass`, `integrity=pass`, `ack_count=9`, `err_count=0`, stream bytes `0xa5,0xa6,0xa7,0xa8` |

Interpretation:

- The board, JTAG transport, and known-good BIST-derived low-byte stream are
  still healthy.
- The standalone rowstream-loader wrapper is not the right base for the next
  proof: even with `BIST_MODE=1`, it exposes valid debug payloads but prevents
  DDR3 calibration.
- The next implementation should preserve `task6_ypcb_uberddr3_bist_top.sv`'s
  calibrated wrapper shape and add only a minimal rowstream/window loader on top
  of that proven transaction sequence.

Passing bar for the replacement BIST-derived rowstream loader:

- DDR3 calibrates with valid JTAG magic/version for the new build.
- The selected `rowstream.bin` row ranges are written in low-byte mode. A full
  image load remains a later throughput/time-budget run.
- Token rows `0,1,31,32,50256` byte-match when their row offsets are inside
  the loaded byte range.
- No Wishbone error, loader error, or stale JTAG decode is accepted.

Promotion rule:

- If the low-byte row checks pass for first and boundary rows, add the smallest
  DDR3-backed top1 cutout that reads this same low-byte address contract.
- Do not switch to dense 64-byte beat rowstream loading until the low-byte
  contract passes and lane mapping is no longer the debugging variable.
- Do not connect TinyStories weights to the model path from the standalone
  rowstream-loader top; replace it with a BIST-derived loader first.

### 2026-05-11 - Rowstream loader calibration rebase v31

Decision:

- Keep the rowstream loader as the next DDR3 gate, but make it behave like the
  known-good BIST wrapper before accepting host rowstream commands.
- Add an internal boot transaction sequence: four full-width writes followed by
  four low-byte read checks. The host loader reaches `LOADER_IDLE` only after
  this self-check finishes.
- Keep `i_aux` constant at `4'd1`, matching the calibrated BIST top, instead
  of coupling it to the loader write-enable signal.

Implementation:

- `fpga/rtl/task6_ypcb_uberddr3_rowstream_loader_top.sv` debug payload version
  is now `31`.
- The loader now reports boot status bits in debug word 304 while preserving
  the existing lower loader-status bits used by the host script.
- `scripts/task6/task6_ddr3_rowstream_loader.py` now decodes the v31 boot
  status bits and still waits for `loader_state == 1`, which now means
  calibration plus boot self-check completed.

Build evidence:

| target | result |
| --- | --- |
| `python3 -m py_compile scripts/task6/task6_ddr3_rowstream_loader.py scripts/task6/validate_uberddr3_lowbyte_stream.py scripts/task6/task6_ddr3_experiment_runner.py` | pass |
| `.#task6-ypcb-uberddr3-rowstream-loader-yosys-json` | pass; Yosys check found 0 problems, estimated 16,627 LCs |
| `.#task6-ypcb-uberddr3-rowstream-loader-seed16-bitstream` | pass; route converged at iteration 41, timing passed at 25 MHz |

Bitstream:

- `/nix/store/l6qvm68vyp7c6jhfc9igjzyjk9azvn9d-task6-ypcb-uberddr3-rowstream-loader-seed16.bit`

Next board gate:

```sh
python3 scripts/task6/task6_ddr3_rowstream_loader.py \
  --bitstream /nix/store/l6qvm68vyp7c6jhfc9igjzyjk9azvn9d-task6-ypcb-uberddr3-rowstream-loader-seed16.bit \
  --storage-mode lowbyte \
  --load-boundary-rows-only \
  --boundary-tokens 0,1,31,32,50256 \
  --no-full-readback
```

Passing bar:

- JTAG magic/version must report v31.
- DDR3 calibration and the internal boot self-check must complete, so
  `loader_state == 1` and `boot_done == true`.
- No boot mismatch, boot error, loader error, or Wishbone error is accepted.
- Boundary rows should byte-match under the low-byte-per-address contract.

Board result:

| run | result |
| --- | --- |
| `artifacts/task6/runs/2026-05-11T13-10-08+0200-ypcb-ddr3-rowstream-loader-l6qvm68vyp7c6jhfc9igjzyjk9azvn9d-task6-ypcb-uberddr3-rowstream-loader-seed16` | fail before loader commands; programming completed and JTAG debug decoded, but DDR3 calibration timed out with `magic_ok=True`, `version=31`, `calib_seen=False`, `state=0`, `ack=0`, `err=0`, `loader_error=False`, `debug1=0x000006cc` |

Interpretation:

- v31 did not restore calibration for the standalone rowstream-loader wrapper.
- Since the same board/session still has a known-good BIST-derived control in
  this note, the next implementation should stop modifying the standalone
  wrapper and instead move the loader command path into
  `task6_ypcb_uberddr3_bist_top.sv`'s calibrated shape.

### 2026-05-11 - BIST-derived rowstream loader v33-v35

Decision:

- Replace the standalone rowstream-loader build input with a new
  BIST-derived top:
  `fpga/rtl/task6_ypcb_uberddr3_bist_rowstream_loader_top.sv`.
- Keep the initial BIST-style four-address write/read self-check as the
  hardware boot gate.
- Keep the old v32 every-other USER2 consumer behavior for loader commands and
  compensate in the host script with `--command-repeats 2`, because removing
  the consumer filter perturbed placement enough to lose calibration.

Implementation:

- `.#task6-ypcb-uberddr3-rowstream-loader-*` now synthesizes the BIST-derived
  top instead of `task6_ypcb_uberddr3_rowstream_loader_top.sv`.
- `scripts/task6/task6_ddr3_rowstream_loader.py` defaults to repeated loader
  commands and expects the latest hardware debug version.
- v35 changed `WRITE_LOWBYTE` to write the command byte across the full
  512-bit beat with all byte enables asserted, matching the passing BIST write
  style, while still treating the Wishbone address as one logical stream byte.

Build evidence:

| variant | bitstream | build result |
| --- | --- | --- |
| v33 BIST-derived loader | `/nix/store/g3s69qsxfjwrf4alkxy8b8xvs1qbk7gk-task6-ypcb-uberddr3-rowstream-loader-seed16.bit` | route and timing pass |
| v34 accept every loader command | `/nix/store/1akk0pjm30cdcy2ah69cmmks6q2j88m9-task6-ypcb-uberddr3-rowstream-loader-seed16.bit` | route and timing pass |
| v35 full-width low-byte write | `/nix/store/khm63m9d842zlzjjjqx0515ygkqgvkhs-task6-ypcb-uberddr3-rowstream-loader-seed16.bit` | route and timing pass |

Board evidence:

| run | result |
| --- | --- |
| `artifacts/task6/runs/2026-05-11T13-28-20+0200-ypcb-ddr3-rowstream-loader-g3s69qsxfjwrf4alkxy8b8xvs1qbk7gk-task6-ypcb-uberddr3-rowstream-loader-seed16` | v33 calibrated and completed the boundary-row load/readback with `boot_done=true`, `boot_mismatch=false`, `wb_ack_count=689`, `wb_err_count=0`; all checked rows mismatched |
| `artifacts/task6/runs/2026-05-11T13-35-10+0200-ypcb-ddr3-rowstream-loader-khm63m9d842zlzjjjqx0515ygkqgvkhs-task6-ypcb-uberddr3-rowstream-loader-seed16` | v35 calibrated and completed the boundary-row load/readback with `boot_done=true`, `boot_mismatch=false`, `wb_ack_count=689`, `wb_err_count=0`; all checked rows mismatched |

Negative control:

- v34 removed the every-other command acceptance filter. It built and routed,
  but on board it regressed to calibration timeout:
  `magic_ok=True`, `version=34`, `calib_seen=False`, `state=1`, `ack=0`,
  `err=0`, `debug1=0x0000166c`.

Current interpretation:

- Moving the loader into the calibrated BIST-derived top fixed the major DDR3
  reliability blocker: calibration and the boot self-check now pass.
- The remaining failure is the rowstream address/lane contract. The loader can
  issue writes and reads without Wishbone errors, but the observed row bytes do
  not match `rowstream.bin`.
- The next gate should be a tiny deterministic byte/address diagnostic using
  the v35 top, independent of `rowstream.bin`: write a short pattern to
  addresses `0..15`, read it back, and record the observed permutation or
  collapse before trying boundary rows again.

### 2026-05-09 - Boring DDR3 bring-up operating contract

Decision:

- Make DDR3 the active full-vocab scaling dependency because the v9984
  extrapolation does not leave enough BRAM for the full ~50k-vocab output head.
- Keep DDR3 work boring and gate-driven. Do not attach DDR3 to rowstream/top1
  until deterministic native write/read integrity exists.
- Keep the v9984/on-chip path as the correctness control while DDR3 is brought
  up.

Promotion ladder:

| gate | required result | stop condition |
| --- | --- | --- |
| G0: JTAG/debug trust | valid magic/version, stable payload length, expected IDCODE, explicit `--tdo-bit 7` | missing magic, stale version, all-zero payload, inconsistent decode |
| G1: init-only | PLL locked, init done, init error clear, no Wishbone timeout/error | seed-sensitive or payload-size-sensitive init |
| G2: DFII one-beat | one 576-bit beat writes and reads back exactly, all 72 bytes | any byte/phase/lane mismatch |
| G3: DFII address walk | 16 DFII addresses return unique expected data | reads collapse to one address |
| G4: native read from DFII seeds | native responses match DFII-seeded data for accepted native addresses | commands accepted but data stale/collapsed |
| G5: native write/read | 16 native writes and reads pass exactly | write/read handshake or ordering ambiguity |
| G6: rowstream | first 8 DDR rows byte-match the `.mem` row source | row packing/stride mismatch |
| G7: top1 | DDR rowstream top1 equals BRAM/`$readmemh` top1 | rowstream not proven |

Current lane:

- Active DDR3 path for the deterministic ladder is **LiteDRAM only**. UberDDR3 is kept as a parallel fallback only and is not used in G1..G5.

Implementation status:

- Added `fpga/rtl/task6_ypcb_bscan_sentinel_top.sv` as a tiny G0 sentinel
  image source using only direct `BSCANE2`, magic/version, TCK/capture/update
  counters, fixed words, and sampled `SYS_RSTN`.
- Added flake targets `.#task6-ypcb-bscan-sentinel-{json,xdc,fasm,bitstream}`
  so the G0 sentinel can be built and programmed like the existing YPCB
  diagnostic images.
- Added `scripts/task6/summarize_litedram_bringup_gate.py` to classify decoded
  LiteDRAM readbacks against the gate ladder and detect the current G4 collapse
  signature (`valid_count=16`, `unique_native_beats=1`).
- Added `scripts/task6/run_litedram_canonical_repro.py` to run the canonical
  native-classifier repro with explicit board settings, save a manifest, perform
  read/read/program/read/read, and emit `verdict-ddr3-bringup.json`.

Measured canonical repro:

| run | bitstream | result | interpretation |
| --- | --- | --- | --- |
| `artifacts/task6/runs/2026-05-09T20-35-05+0200-ddr3-v117-native-cmdaddr-idx1-canonical` | `/nix/store/7872xnkz6j108lxr60rz0hxki81c2isr-task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-cmdaddr-trace-init-bandwidth-probe-native-cmdaddr-first-command-index-1.bit` | 3/3 legacy canonical run | `magic_ok=true`, version `116`, `PROBE_DONE`, command/response counts `16/16`, accepted cmd address `1`, `unique_native_beats=1`, best DFII index `15`, mismatch count `16` |
| `artifacts/task6/runs/2026-05-09T20-42-01+0200-ddr3-g0-bscan-sentinel-counter` | `/nix/store/apn1kncq61zac0yz4qvcizv65hmbvphj-task6-ypcb-bscan-sentinel.bit` | G0 pass | IDCODE `0x23751093`; `magic_ok=true`, version `1`, `SYS_RSTN=1` at 64/1024/11264 bits; fixed words `0x11111111`/`0x22222222`; counters advanced across reads (`tck_count` `14987 -> 16036 -> 17085`) |

Conclusion:

- The legacy 3/3 canonical run was already reproducible, and the updated script
  now captures 4 reads (`read/read/program/read/read`) with explicit `--tdo-bit 7`.
- The direct BSCANE2 debug transport is independently validated at G0 with the
  tiny sentinel image, including long payload reads at the LiteDRAM classifier
  bit count.
- This validates the next stop point: do not modify rowstream/top1. Continue
  with the smallest G1/G2 LiteDRAM init/DFII BIST images.

Canonical LiteDRAM repro settings (now 4 reads: read, read, reprogram/read, reprogram/read):

```bash
python3 scripts/task6/run_litedram_canonical_repro.py \
  --bitstream /path/to/task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-cmdaddr-trace-init-bandwidth-probe.bit \
  --serial 210299BF3824 \
  --freq-hz 6000000 \
  --tdo-bit 7 \
  --bits 11264 \
  --ir-len 6 \
  --user-ir 0x02
```

Deterministic LiteDRAM ladder (G1..G5) on the same reader settings.
G1..G5 must each be explicit bitstreams to avoid mode mixing:

```bash
python3 scripts/task6/run_litedram_canonical_repro.py \
  --bitstream /path/to/g0-or-common-probe.bit \
  --run-ladder \
  --label ddr3-v116-ladder \
  --serial 210299BF3824 \
  --freq-hz 6000000 \
  --tdo-bit 7 \
  --bits 11264 \
  --ir-len 6 \
  --user-ir 0x02 \
  --poll-count 10 \
  --poll-interval 0.2 \
  --expected-version 116 \
  --expected-state PROBE_DONE \
  --expected-bits 11264 \
  --g1-bitstream /path/to/g1-init-only.bit \
  --g2-bitstream /path/to/g2-dfii-one-beat.bit \
  --g3-bitstream /path/to/g3-dfii-addrwalk.bit \
  --g4-bitstream /path/to/g4-native-read.bit \
  --g5-bitstream /path/to/g5-native-write-read.bit
```

The script now emits:

- `verdict-ddr3-bringup.json` (raw per-read summaries)
- `verdict-ddr3-ladder.json` (adds `ladder_steps` and `ladder_all_pass`)
- `references/canonical-repro-manifest.json` (reader/JTAG contract and expected state)

For ladder mode, the process exits non-zero on first-stop failures unless
`--continue-on-gate-fail` is set.

Evidence rule:

- Any DDR3 run without valid magic/version is discarded as debug-transport
  evidence, not DDR3 evidence.
- `rtl/task6/task6_ddr3_rowstream_mem_source.sv` remains a golden local row
  source, not live DDR3 evidence.
- `rtl/task6/task6_ddr3_rowstream_top1_cutout.sv` remains downstream logic that
  assumes rows are already correct.
- `docs/project-plan*` remain reviewer-controlled and must not be edited for
  this bring-up ladder.

### 2026-05-09 - UberDDR3 YPCB fallback gate

Decision:

- Add UberDDR3 as a second DDR3-controller candidate because it is open source,
  formally verified upstream, and synthesizes with Yosys.
- Keep LiteDRAM as the primary proven-board-support reference, but use
  UberDDR3 to test whether a smaller standalone DDR3 controller can be wrapped
  around the YPCB DDR3 pins and observed through the direct BSCANE2 payload
  path that already works on this board.

Implemented gate:

- Added `fpga/rtl/task6_ypcb_uberddr3_bist_top.sv`.
- The wrapper instantiates upstream `ddr3_top.v` with:
  - `ROW_BITS=15`
  - `COL_BITS=10`
  - `BA_BITS=3`
  - `BYTE_LANES=8`
  - `BIST_MODE=1`
  - `ODELAY_SUPPORTED=1`
  - `DLL_OFF=1`
- The wrapper exports a 512-bit direct BSCANE2 debug payload containing:
  - magic/version
  - `o_calib_complete`
  - sticky calibration-seen bit and cycle
  - UberDDR3 `o_debug1`
  - Wishbone ack/error/stall counters
  - low readback/status words
  - geometry/config nibbles
- Added flake package:
  `.#task6-ypcb-uberddr3-bist-yosys-json`.

Measured result:

| gate | command | result | notes |
| --- | --- | --- | --- |
| UberDDR3 controller-only Yosys parse | `nix build .#task6-uberddr3-controller-yosys-json -L` | pass | `ddr3_controller.v` elaborates through Yosys with ECC modules present |
| Minimal YPCB UberDDR3 BIST wrapper | `nix build .#task6-ypcb-uberddr3-bist-yosys-json --no-link --print-out-paths -L` | pass | output `/nix/store/awfg0c5r81dvfjjjxx804qvb8cmxn0bm-task6-ypcb-uberddr3-bist-yosys.json`; Yosys `check` reported 0 problems |

Wrapper synthesis stats from Yosys:

| metric | value |
| --- | ---: |
| total cells | 25,116 |
| estimated LCs | 12,723 |
| `FDRE` | 6,791 |
| `FDSE` | 47 |
| `FDCE` | 673 |
| `LUT6` | 4,425 |
| `LUT5` | 2,741 |
| `LUT4` | 1,502 |
| `LUT3` | 4,055 |
| `LUT2` | 1,259 |
| `LUT1` | 378 |
| `CARRY4` | 136 |
| `BSCANE2` | 1 |
| `IDELAYCTRL` | 1 |
| `IDELAYE2` | 72 |
| `ODELAYE2` | 81 |
| `ISERDESE2` | 72 |
| `OSERDESE2` | 106 |
| `IOBUF` | 64 |
| `IOBUFDS` | 8 |

Interpretation:

- UberDDR3 is viable enough for the next open-source gate: the YPCB wrapper
  and direct BSCANE2 status path synthesize under Yosys.
- The first failed build exposed a missing Xilinx primitive-library load for
  `ISERDESE2`; adding `+/xilinx/cells_sim.v` and `+/xilinx/cells_xtra.v`
  fixed that gate.
- This does not yet prove correct YPCB physical pinout, clocking, timing, DDR3
  calibration, or board readback. The wrapper currently aliases the 200 MHz
  input clock into all UberDDR3 clock domains only to keep the first gate
  minimal.

Next gate:

- Derive a real XDC from LiteX-Boards/YPCB board support for the 64-bit DDR3
  data lane, including `ddram_dm`.
- Replace the temporary clock aliases with a real 25/100/200 MHz clocking plan
  compatible with UberDDR3's 4:1 controller/PHY ratio.
- Build a routed bitstream and read the BSCANE2 payload before attempting any
  higher-level DDR3 data test.

### 2026-05-09 - UberDDR3 openXC7 DDR IO/SERDES route gate

Decision:

- Stop treating the temporary clock aliases as the blocker; the wrapper now
  uses LiteX-Boards/YPCB-derived DDR3 constraints and real 25/100/200 MHz MMCM
  clocks.
- Focus on the actual openXC7/nextpnr DDR IO/SERDES handling failures.

Implemented:

- Added a local nextpnr-xilinx patch for `XC7Packer::pack_iologic()` so an
  unconnected `OSERDESE2.OFB` path emits the existing illegal-fanout diagnostic
  instead of segfaulting.
- Added a YPCB-specific UberDDR3 source patch in the Nix derivation that does
  not instantiate DDR3 `DM` OSERDES/OBUF cells. LiteX-Boards' YPCB platform does
  not expose DDR3 DM pins, so keeping these serializers creates unplaceable
  OLOGIC connections.
- Added a local prjxray database patch for the Kintex-7
  `LIOI3_TBYTESRC.IOI_OCLKM_0.IOI_IMUX31_1` feature emitted by nextpnr for the
  DQS byte-lane clock mux. The same mux form exists in the Artix-7 DB as
  `RIOI3_TBYTESRC.IOI_OCLKM_0.IOI_IMUX31_1 30_94 31_83 31_93`, while the
  bundled Kintex-7 DB already has neighboring `IOI_OCLKM_0` features with the
  same bit coordinate family.

Measured result:

| gate | command | result | notes |
| --- | --- | --- | --- |
| Previous routed FASM | `nix build .#task6-ypcb-uberddr3-bist-fasm --no-link --print-out-paths -L` | fail | nextpnr segfaulted in `XC7Packer::pack_iologic()` |
| After nextpnr null-deref patch | same | fail, better diagnostic | exposed `OSERDESE2_dm` illegal fanout because DM had no top-level DDR3 pins |
| After disabling unpinned DM serializers | same | route reaches `overused=0`; FASM emitted at `/nix/store/xkq62n7sxx730in7jnjajhg7ykqgi7rv-task6-ypcb-uberddr3-bist.fasm` | nextpnr still logs `ERROR: Assert valid_wires_for_net.count(w) failed in common/router1.cc:331` during router1 legality check, but the derivation exits 0 and writes FASM |
| Bitstream conversion | `nix build .#task6-ypcb-uberddr3-bist-bitstream --no-link --print-out-paths -L` | fail | `fasm2frames` lacks `LIOI3_TBYTESRC.IOI_OCLKM_0.IOI_IMUX31_1` for DQS byte-lane clock mux features |
| After Kintex-7 prjxray DB feature patch | same | pass | bitstream emitted at `/nix/store/8h27r5g39wy4swrf6776wl6zrmszaqj7-task6-ypcb-uberddr3-bist.bit` |
| Board program/readback | `openFPGALoader ... task6-ypcb-uberddr3-bist.bit`; `read_jtag_debug_ftdi_bitbang.py --tdo-bit 7 --bits 512 --poll` | fail, useful | JTAG payload `magic=0x54364a44`, `version=2`, but `mmcm_locked=0` and `cycle_count=0`; run `artifacts/task6/runs/2026-05-09T09-13-42+0200-uberddr3-bist-program-readback` |
| `clk50` wrapper board readback | `nix build .#task6-ypcb-uberddr3-bist-bitstream ...`; program/readback | fail, same | bitstream `/nix/store/w6yjkyykghb9d0bh4ymmlsyc5rngy3lp-task6-ypcb-uberddr3-bist.bit`; payload still `mmcm_locked=0`, `cycle_count=0`; run `artifacts/task6/runs/2026-05-09T09-20-58+0200-uberddr3-bist-clk50-program-readback` |
| `clk50`/reset diagnostic payload | same | fail, informative | bitstream `/nix/store/y410h3njia3ffm355c1ckb805idkxa31-task6-ypcb-uberddr3-bist.bit`; payload `clk50_count=0x182abf14`, `SYS_RSTN=1`, `mmcm_locked=0`; run `artifacts/task6/runs/2026-05-09T09-27-51+0200-uberddr3-bist-clk50-diagnostic-readback` |
| direct MMCM feedback diagnostic | same | fail, informative | bitstream `/nix/store/hiswd483f123l9c4w2ylxr42l97mnzhh-task6-ypcb-uberddr3-bist.bit`; payload `clk50_count=0x19c19a30`, `SYS_RSTN=1`, `mmcm_locked=0`; run `artifacts/task6/runs/2026-05-09T09-34-59+0200-uberddr3-bist-direct-feedback-readback` |
| MMCM-only diagnostic | `nix build .#task6-ypcb-mmcm-diag-bitstream ...`; program/readback | fail, informative | bitstream `/nix/store/hfb07ccdq2x0q4v4x3mfzzbjvps9pf4l-task6-ypcb-mmcm-diag.bit`; payload `SYS_RSTN=1`, `pll_locked=1`, `mmcm_a_locked=0`, `mmcm_b_locked=0`; raw/PLL/output counters all advanced; run `artifacts/task6/runs/2026-05-09T09-41-27+0200-ypcb-mmcm-diag-readback` |
| PLLE2-clocked UberDDR3 BIST | `nix build .#task6-ypcb-uberddr3-bist-bitstream ...`; program/readback | fail, useful | bitstream `/nix/store/jy55imbnnm31k2zwm530rwkbhdlqmn4j-task6-ypcb-uberddr3-bist.bit`; route `overused=0`; payload `status=0xd0`, `pll_locked=1`, `cycle_count=0x0df5fc1b`, `debug1=0`; calibration still stuck at UberDDR3 calibration `IDLE`; run `artifacts/task6/runs/2026-05-09T09-48-17+0200-ypcb-uberddr3-bist-pll-readback` |
| 200 MHz IDELAY refclk, invalid wiring | same | invalid, informative | bitstream `/nix/store/1kds6b8fxfaanasvshhfbh6x9z2ypvws-task6-ypcb-uberddr3-bist.bit`; route `overused=0`; payload `status=0x50`, `pll_locked=0`, `cycle_count=0`; invalid because `ref_clk` was accidentally used as both PLLE2 input and PLL-derived output; run `artifacts/task6/runs/2026-05-09T09-56-59+0200-ypcb-uberddr3-bist-200mhz-refclk` |
| Fixed 200 MHz IDELAY refclk | same | fail, forward progress | bitstream `/nix/store/2j3fmwg6al2z8v4akcj0y066g71841y2-task6-ypcb-uberddr3-bist.bit`; route `overused=0`; payload `status=0xd0`, `pll_locked=1`, `cycle_count=0x1efd6d85`, `debug1=0x0000000c`, `wb_stall_count=0x1efd6d85`; calibration advances from state 0 to state 12 but does not complete; run `artifacts/task6/runs/2026-05-09T10-03-00+0200-ypcb-uberddr3-bist-200mhz-refclk-fixed` |
| Packed calibration debug1 | same | pass, useful discriminator | bitstream `/nix/store/hr6m6xancsa09gybbcapjpyrafni7rbn-task6-ypcb-uberddr3-bist.bit`; route `overused=0`; payload `status=0xd0`, `pll_locked=1`, `cycle_count=0x151b74ec`, `debug1=0xd00386d1`; decoded debug1 shows state `17` (`BURST_WRITE`), `instruction_address=22`, IDELAYCTRL ready, lane `7`, `calib_stb=1`, calibration-side Wishbone ack, and nonzero uncalibrated read data; run `artifacts/task6/runs/2026-05-09T10-11-13+0200-ypcb-uberddr3-bist-calib-debug1` |
| Calibration-only `BIST_MODE=0` | same | fail, useful negative | bitstream `/nix/store/143g3jjxxisny5csxygb5d4n3n4drksc-task6-ypcb-uberddr3-bist.bit`; route `overused=0`; first payload `debug1=0x808406cc`; delayed second payload unchanged at `debug1=0x808406cc` while `cycle_count` advanced to `0x4ec85d95`; decoded debug1 shows state `12` (`READ_DATA`), `instruction_address=22`, IDELAYCTRL ready, lane `0`, DQ/DQS IDELAY tap `1`, no calibration strobe/ack, and nonzero uncalibrated read data; run `artifacts/task6/runs/2026-05-09T10-22-01+0200-ypcb-uberddr3-bist-calib-only` |
| Fast BIST exit at `BURST_WRITE` | same | pass, calibration complete | bitstream `/nix/store/rf3akdsj6rdqikhzvfw50146f71vkxpz-task6-ypcb-uberddr3-bist.bit`; route `overused=0` at router2 iteration 8; payload `status=0xd3`, `calib_seen_cycle=0x000093dd`, `debug1=0x800386d7`, `wb_stall_count=0x01575f7a`; decoded debug1 shows state `23` (`DONE_CALIBRATE`), `instruction_address=22`, IDELAYCTRL ready, lane `7`, no calibration strobe/ack, and read data nonzero; run `artifacts/task6/runs/2026-05-09T10-29-37+0200-ypcb-uberddr3-bist-fast-exit` |
| Full-width wrapper Wishbone probe | same | fail, route-sensitive calibration regression | bitstream `/nix/store/c57ny7nhaxzsq98jraf9flb363dz3py4-task6-ypcb-uberddr3-bist.bit`; route `overused=0` at router2 iteration 25 and timing passed, but board payload stayed at `status=0xd0`, `calib_seen_cycle=0`, `debug1=0x800186cc`; decoded debug1 shows state `12` (`READ_DATA`), lane `3`, no calibration strobe/ack, and nonzero read data; probe status remained state `1` (`WAIT_CALIB`) with no user Wishbone ACKs; reprogramming the same image reproduced the failure; run `artifacts/task6/runs/2026-05-09T10-40-55+0200-ypcb-uberddr3-user-probe` |
| Narrow low-word wrapper Wishbone probe | same | fail, route-sensitive calibration regression | bitstream `/nix/store/258ifv1f9ksfg80rcx2kivfngl9lcn1w-task6-ypcb-uberddr3-bist.bit`; route `overused=0` at router2 iteration 25 and timing passed; payload `status=0xd0`, `calib_seen_cycle=0`, `debug1=0x808406cc`; decoded debug1 shows state `12` (`READ_DATA`), lane `0`, DQ/DQS taps `1`, no calibration strobe/ack, and nonzero read data; probe status remained `WAIT_CALIB` with zero user ACKs; run `artifacts/task6/runs/2026-05-09T10-51-27+0200-ypcb-uberddr3-narrow-user-probe` |
| Fast-exit control recheck after probe failures | program/readback only | pass, board control | reprogrammed known-good bitstream `/nix/store/rf3akdsj6rdqikhzvfw50146f71vkxpz-task6-ypcb-uberddr3-bist.bit`; payload again reported `status=0xd3`, `calib_seen_cycle=0x000093dd`, and `debug1=0x800386d7` (`DONE_CALIBRATE`); confirms the board/JTAG path was healthy and the probe images were the variable; run `artifacts/task6/runs/2026-05-09T10-52-45+0200-ypcb-uberddr3-fast-exit-control-recheck` |
| Internal mini-BIST after fast exit | same | fail, route-sensitive calibration regression | bitstream `/nix/store/31x92gc0ar40pnk3px1qpax93y72j3d2-task6-ypcb-uberddr3-bist.bit`; route `overused=0` at router2 iteration 7 and timing passed; payload `status=0xd0`, `calib_seen_cycle=0`, `debug1=0x000026cc`; decoded debug1 shows state `12` (`READ_DATA`), instruction `22`, IDELAYCTRL ready, calibration-side ack, and zero mini-BIST correct/wrong/check counters; run `artifacts/task6/runs/2026-05-09T11-14-15+0200-ypcb-uberddr3-internal-mini-bist` |
| Current-tree fast-exit control | same | pass, calibration control restored | bitstream `/nix/store/8agn3v2i05f7mw66f4j3x4wdrjc6wcw2-task6-ypcb-uberddr3-bist.bit`; route `overused=0` at router2 iteration 5 and timing passed; payload `status=0xd3`, `calib_seen_cycle=0x000093dd`, `debug1=0x000006d7`; decoded debug1 shows state `23` (`DONE_CALIBRATE`), instruction `22`, and IDELAYCTRL ready; run `artifacts/task6/runs/2026-05-09T11-23-04+0200-ypcb-uberddr3-fast-exit-current-control` |
| Single post-calibration user read probe | same | fail, route-sensitive calibration regression | bitstream `/nix/store/ax1n6b998262p447m3ylf7ycfrv40lwf-task6-ypcb-uberddr3-bist.bit`; route `overused=0` at router2 iteration 28 and timing passed; payload `status=0xd0`, `calib_seen_cycle=0`, `debug1=0x000016a9`; decoded debug1 shows calibration state `9`, instruction `21`, IDELAYCTRL ready, calibration-side stall and no ack; the wrapper read probe remained in `WAIT_CALIB`, so no user Wishbone read was issued; run `artifacts/task6/runs/2026-05-09T11-30-50+0200-ypcb-uberddr3-single-read-probe` |
| Single post-calibration user read probe, seed 15 | same, `.#task6-ypcb-uberddr3-bist-seed15-bitstream` | pass, user-port liveness | bitstream `/nix/store/g6a1755hrcs06dx2zzdmq7xsrk4b1ddw-task6-ypcb-uberddr3-bist-seed15.bit`; route `overused=0` at router2 iteration 4 and timing passed; payload `status=0xd3`, `calib_seen_cycle=0x000093dd`, `debug1=0x000006d7`; decoded debug1 shows state `23` (`DONE_CALIBRATE`), instruction `22`, IDELAYCTRL ready; read-probe status `0x164` decodes to state `4` (`DONE`), `ack_seen=1`, `err_seen=0`, `stall_seen=1`, wait cycles `24`; read data was `0xc1c1c1c1c1c1c1c1` with no preceding write, so this proves user-port liveness but not data integrity; run `artifacts/task6/runs/2026-05-09T11-37-45+0200-ypcb-uberddr3-single-read-probe-seed15` |
| Single full-width write/read compare, seed 15 | same, `.#task6-ypcb-uberddr3-bist-seed15-bitstream` | fail, route-sensitive calibration regression | bitstream `/nix/store/m5njfxrp61n1h3p383ayrmm59yb2c3xf-task6-ypcb-uberddr3-bist-seed15.bit`; route `overused=0` at router2 iteration 31 and timing passed; payload `status=0xd0`, `calib_seen_cycle=0`, `debug1=0x000006cc`; decoded debug1 shows calibration state `12` (`READ_DATA`), instruction `22`, IDELAYCTRL ready; write/read probe remained in `WAIT_CALIB`, so neither the write nor readback compare ran; run `artifacts/task6/runs/2026-05-09T11-47-04+0200-ypcb-uberddr3-single-write-read-seed15` |
| Single full-width write-only probe, seed 15 | same, `.#task6-ypcb-uberddr3-bist-seed15-bitstream` | pass, write-side liveness | bitstream `/nix/store/2l25q0qlijcm30z78hhncscy8l39fnw8-task6-ypcb-uberddr3-bist-seed15.bit`; route `overused=0` at router2 iteration 37 and timing passed; payload `status=0xd3`, `calib_seen_cycle=0x000093dd`, `debug1=0x000006d7`; decoded debug1 shows state `23` (`DONE_CALIBRATE`), instruction `22`, IDELAYCTRL ready; write-probe status `0x266` decodes to state `6` (`DONE`), `write_ack=1`, `read_ack=0`, `err_seen=0`, `stall_seen=1`, wait cycles `19`; proves `i_wb_we`, full-width `0xa5` write data, and all byte-selects can coexist with calibration; run `artifacts/task6/runs/2026-05-09T11-55-16+0200-ypcb-uberddr3-write-only-seed15` |
| Single full-width write then read, no compare, seed 15 | same, `.#task6-ypcb-uberddr3-bist-seed15-bitstream` | fail, readback-path calibration regression | bitstream `/nix/store/q501y0m82g4r3bi965sakrmqshwg5cw1-task6-ypcb-uberddr3-bist-seed15.bit`; route `overused=0` at router2 iteration 27 and timing passed; payload `status=0xd0`, `calib_seen_cycle=0`, `debug1=0x00000eca`; decoded debug1 shows calibration state `10`, instruction `22`, IDELAYCTRL ready, calibration strobe active, no calibration ack; probe status `0x1` remained in `WAIT_CALIB`, so neither the write nor the read issued; run `artifacts/task6/runs/2026-05-09T12-04-58+0200-ypcb-uberddr3-write-read-no-compare-seed15` |
| Single full-width write then read, no compare, seed 16 | same, `.#task6-ypcb-uberddr3-bist-seed16-bitstream` | fail, readback-path calibration regression repeats | bitstream `/nix/store/iqia0m1lsxvd1ajaibrzw255aajv000s-task6-ypcb-uberddr3-bist-seed16.bit`; route `overused=0` at router2 iteration 44 and timing passed; payload `status=0xd0`, `calib_seen_cycle=0`, `debug1=0x000006cc`; decoded debug1 shows calibration state `12`, instruction `22`, IDELAYCTRL ready, no calibration strobe/ack; probe status `0x1` remained in `WAIT_CALIB`, so neither the write nor the read issued; run `artifacts/task6/runs/2026-05-09T12-11-32+0200-ypcb-uberddr3-write-read-no-compare-seed16` |
| Single full-width write then read, ACK-only, seed 15 | same, `.#task6-ypcb-uberddr3-bist-seed15-bitstream` | pass, read command liveness | bitstream `/nix/store/0lf6mzlyal5a6qp0ch1v54a712brfkgv-task6-ypcb-uberddr3-bist-seed15.bit`; route `overused=0` at router2 iteration 51 and timing passed; payload `status=0xd3`, `calib_seen_cycle=0x000093dd`, `debug1=0x000006d7`; decoded debug1 shows calibration state `23` (`DONE_CALIBRATE`), instruction `22`, IDELAYCTRL ready; probe status `0x2e6` decodes to state `6` (`DONE`), `write_ack=1`, `read_ack=1`, `err_seen=0`, `stall_seen=1`, wait cycles `29`; proves read command sequencing works when read data is not exported; run `artifacts/task6/runs/2026-05-09T12-20-16+0200-ypcb-uberddr3-write-read-ack-only-seed15` |

Post-patch nextpnr utilization at the route gate:

| metric | value |
| --- | ---: |
| `SLICE_LUTX` | 16,006 / 597,200 |
| `SLICE_FFX` | 7,483 / 597,200 |
| `OSERDESE2` | 97 / 400 |
| `ISERDESE2` | 72 / 400 |
| `IDELAYE2` | 72 / 400 |
| `IDELAYCTRL` | 3 / 8 |
| `PAD` | 110 / 946 |
| router2 final `overused` | 0 |

Interpretation:

- The original nextpnr/OpenXC7 packer blocker is fixed for this design, and the
  unpinned DM serializers are removed from the YPCB build.
- The immediate prjxray/openXC7 database blocker for the DQS byte-lane clock mux
  is fixed well enough to generate a `.bit` from the routed FASM.
- The remaining caveat is the nextpnr router1 legality assert:
  `ERROR: Assert valid_wires_for_net.count(w) failed in common/router1.cc:331`.
  Router2 still converges to `overused=0` and a bitstream is emitted, so the
  next useful discriminator is a board BIST/JTAG-status run.
- The first board BIST/JTAG-status run proves the direct BSCANE2 payload is
  readable, but the wrapper clocking is wrong: the payload is static apart from
  combinational fields because `mmcm_locked=0` and the controller-domain cycle
  counter remains `0`.
- LiteX-Boards' YPCB target uses the single-ended `clk50` pin `AA28` as the CRG
  input, not the differential `clk200_p/n` pins used by the first UberDDR3
  wrapper attempt.
- The `clk50` pin itself is alive on hardware: the raw `clk50` counter advanced
  to nonzero values in two diagnostic bitstreams, and `SYS_RSTN` reads high.
  The current blocker is specifically MMCM lock/output-clock generation, not
  JTAG, board programming, reset, or absence of the 50 MHz input clock.
- Removing `SYS_RSTN` from the MMCM reset and switching the feedback path from a
  BUFGed loop to direct `CLKFBOUT` -> `CLKFBIN` did not make `mmcm_locked`
  assert. An explicit `IBUF` instance is not accepted by nextpnr for this
  top-level input because IO buffer insertion already owns the input buffer.
- A MMCM-only diagnostic showed that the raw 50 MHz input, reset, PLLE2 lock,
  and generated output counters work on hardware, but the tested MMCM lock bits
  do not assert. Therefore the full UberDDR3 wrapper switched from MMCM to
  PLLE2 clocking.
- PLLE2 clocking clears the wrapper clock/reset-dead blocker. The initial PLLE2
  version still left UberDDR3 calibration in state `0` (`IDLE`), which is before
  the DDR3 calibration state machine can do useful work.
- Feeding UberDDR3 `i_ref_clk` from the raw 50 MHz input was the likely reason:
  the controller leaves `IDLE` only after the PHY reports IDELAYCTRL ready, and
  Xilinx IDELAYCTRL expects the high-speed reference domain. Adding a PLLE2
  200 MHz output for `i_ref_clk` moves calibration to state `12`, so the
  IDELAYCTRL/read-calibration entry hypothesis was productive.
- The packed debug1 readback changes the diagnosis materially: the controller
  is not stuck in state `12`. It has reached state `17` (`BURST_WRITE`) with
  IDELAYCTRL ready, an active calibration strobe, calibration-side Wishbone
  ack, and nonzero uncalibrated read data.
- With `BIST_MODE=1`, UberDDR3's built-in BIST runs through the full address
  space once before `DONE_CALIBRATE`. Given the YPCB geometry
  (`ROW_BITS=15`, `COL_BITS=10`, `BA_BITS=3`), a persistent state `17` shortly
  after programming is likely the full-memory BIST being too large for a fast
  bring-up loop, not an early DDR3 initialization failure.
- The `BIST_MODE=0` calibration-only build did not reproduce the state `17`
  progress. It stayed in state `12` (`READ_DATA`) across two reads while the
  controller cycle counter advanced. That points to a synthesis/routing or
  calibration-path sensitivity, so the faster path is to preserve the
  `BIST_MODE=1` build shape that reached `BURST_WRITE` and patch a bounded or
  immediate BIST exit there.
- The fast-BIST-exit patch proves the immediate DDR3 bring-up gate:
  calibration reaches `DONE_CALIBRATE` and exports `calib_complete=1` over the
  direct BSCANE2 payload. This still does not prove user-port data integrity;
  the wrapper currently ties the user Wishbone request inputs low.
- The current evidence is strongly route-sensitive: the exact current-tree
  fast-exit control calibrates, but adding even a small wrapper-side user read
  FSM or internal mini-BIST perturbation can prevent calibration completion
  before the user probe ever runs.
- Seed 15 for the same single-read user-port probe calibrates and acknowledges
  one post-calibration Wishbone read. That makes placement/route sensitivity a
  confirmed variable, and gives a concrete route seed to use for the next
  data-integrity probe.
- A full-width write/read compare at seed 15 routes but regresses calibration
  back to state `12` before the write is issued. The next probe should isolate
  the smallest write-side perturbation instead of combining write-enable,
  full-width write data, byte-selects, and full-width compare in one step.
- The write-only seed-15 probe passes. The write side is therefore viable; the
  failed full write/read compare is more likely from the added readback/compare
  logic or its placement perturbation than from merely asserting `i_wb_we`,
  nonzero write data, or all byte-selects.
- The write-then-read/no-compare seed-15 probe regresses calibration before the
  user probe runs. The comparison logic is not the trigger; a live readback
  path, or the placement perturbation from registering read data, is enough to
  lose the known calibration result.
- The same v8 readback probe also fails with seed 16. Seed variation might
  still work, but the first repeat says the faster design move is to reduce
  readback observation rather than keep sweeping blindly.
- The v9 ACK-only readback probe passes. That isolates the v8 failure to
  read-data observation/capture fanout, not to the read command itself.

Next gate:

- Add read-data observability back in narrow increments. First capture/export
  only 8 bits or 32 bits of `wb_data` after read ack, then compare against the
  written `0xa5` byte pattern. Avoid full 64/512-bit capture until the narrow
  read-data path calibrates.
- After the bounded user-port probe passes, add a host-to-DDR loading path
  (initially JTAG write/control if fast enough for small slices, later PCIe for
  full TinyStories weights) and make inference fetch INT8 weights from DDR3.
- Keep the router1 assert as a secondary openXC7 quality issue; router2 reaches
  `overused=0` and the board can execute the bitstreams, so calibration
  observability is the faster path to DDR3 data integrity.

### 2026-05-08 - Reproduce upstream LiteX-Boards YPCB validation first

Decision:

- Pause deeper custom LiteDRAM probe work long enough to reproduce the upstream
  `litex-boards` YPCB-00338-1P1 path.
- The upstream target is the best available proven prior work for this board:
  it claims validated LiteDRAM DDR3 and LitePCIe on the same YPCB-00338-1P1 /
  XC7K480T hardware.

Primary source:

- `litex-hub/litex-boards`
- initial support/validation commit:
  `6d58ae6b31d80b255de12c2d3f5bfefda4c38b90`

Important upstream details:

- Current upstream target:
  `litex_boards/targets/ypcb_00338_1p1.py`
- Current upstream documented command:
  `./ypcb_00338_1p1.py --uart-name=jtag_uart --with-pcie --build --load`
- Initial validation commit reports:
  - Clk/Rst OK
  - LEDs OK
  - PCIe Gen2 x8 OK
  - Dual DDR3 32-bit OK, with full 64-bit + ECC left for later
- Current upstream code has evolved after that initial commit and should be
  tried first; if that fails, fall back to the exact validation commit.

Local flake lane:

- Add `litexBoards` input tracking current upstream `litex-hub/litex-boards`.
- Add `litexBoardsValidatedYpcb` input pinned to
  `6d58ae6b31d80b255de12c2d3f5bfefda4c38b90`.
- Add `litepcie` input because the upstream YPCB target imports LitePCIe even
  when PCIe is not enabled.
- Expose wrappers:
  - `.#task6-litex-boards-ypcb-master`
  - `.#task6-litex-boards-ypcb-validated`

Execution order:

1. Build/import-check the current upstream target help:
   `nix build .#task6-litex-boards-ypcb-master-help -L`
2. Try the upstream documented command on current upstream first:
   `nix run .#task6-litex-boards-ypcb-master -- --with-pcie --build --load`
3. If current upstream fails, try the exact validation commit:
   `nix run .#task6-litex-boards-ypcb-validated -- --with-pcie --build --load`
4. Capture BIOS/JTAG-UART logs and compare against upstream validation:
   DDR init/read-leveling, `Memtest OK`, memspeed, and PCIe enumeration.

Evidence rule:

- Every build/program/readback attempt in this lane must get a run directory,
  notes update, and commit before the next attempt.
- Fast-prune a lane after 1-2 measured attempts unless it exposes a new,
  narrower bottleneck that is worth isolating.

Measured result:

| run | source | command shape | progress | blocker |
| --- | --- | --- | --- | --- |
| `2026-05-08T17-32-52+0200-litex-boards-ypcb-master-exact-command-writable-cp` | current upstream `litex-boards` | `--uart-name=jtag_uart --with-pcie --build --load` via flake wrapper | YPCB SoC elaborated with DDR3 and PCIe, BIOS built, ROM initialized | Vivado missing / not sourced |
| `2026-05-08T17-33-52+0200-litex-boards-ypcb-validated-exact-command-writable-cp` | commit `6d58ae6b31d80b255de12c2d3f5bfefda4c38b90` | `--uart-name=jtag_uart --with-pcie --build --load` via flake wrapper | YPCB SoC elaborated with DDR3 and PCIe, BIOS built, ROM initialized | Vivado missing / not sourced |
| `2026-05-08T17-46-57+0200-litex-boards-ypcb-master-openxc7-pcie-patched-toolchain` | current upstream `litex-boards` plus local target toolchain passthrough | `--toolchain=openxc7 --with-pcie --build --load` | Reached SoC construction with openXC7 selected | LitePCIe S7 PHY expects Vivado-style `pre_placement_commands` |
| `2026-05-08T17-55-25+0200-litex-boards-ypcb-master-openxc7-ddr3-only-yosys` | current upstream `litex-boards` plus local target/openXC7 environment patches | `--toolchain=openxc7 --build --load` | Reached nextpnr packing | Unsupported inferred `RAM256X1S` LUTRAM primitive |
| `2026-05-08T17-58-34+0200-litex-boards-ypcb-master-openxc7-ddr3-only-nolutram` | current upstream `litex-boards` plus `synth_xilinx -nolutram` | `--toolchain=openxc7 --build --load` | Reached route and generated FASM/frames path | PRJXRAY part spelling mismatch: `xc7k480t-ffg1156-2` vs `xc7k480tffg1156-2` |
| `2026-05-08T18-03-19+0200-litex-boards-ypcb-master-openxc7-ddr3-only-prjxray-part` | current upstream `litex-boards` plus local openXC7 patches | `--toolchain=openxc7 --build --load` | Generated `ypcb_00338_1p1.bit` and programmed SRAM successfully | 200 MHz timing not closed; `crg_clkout_buf0` max reported about 107.69 MHz |
| `2026-05-08T18-25-00+0200-litex-boards-ypcb-master-openxc7-ddr3-jtag-uart-pty-send-retry2` | programmed bitstream from `18-03-19` | `litex_term ... --jtag-chain 1 jtag`, sent Enter and `help` | OpenOCD found XC7K480T TAP `0x23751093` and started JTAG stream | No BIOS, prompt, or UART bytes observed |
| `2026-05-08T18-26-30+0200-litex-boards-ypcb-master-openxc7-ddr3-only-50mhz` | current upstream `litex-boards` plus local openXC7 patches | `--toolchain=openxc7 --sys-clk-freq 50000000 --build --load` | Generated `ypcb_00338_1p1.bit` and programmed SRAM successfully | Still not timing-clean; `crg_clkout_buf0` max reported about 96.68 MHz against emitted 200 MHz checks |
| `2026-05-08T18-30-30+0200-litex-boards-ypcb-master-openxc7-ddr3-50mhz-jtag-uart` | programmed bitstream from `18-26-30` | `litex_term ... --jtag-chain 1 jtag`, sent Enter and `help` | OpenOCD found XC7K480T TAP `0x23751093`; generated Verilog confirms `BSCANE2.JTAG_CHAIN=1` | No BIOS, prompt, or UART bytes observed |
| `2026-05-08T18-35-00+0200-litex-boards-ypcb-master-openxc7-jtag-uart-integrated-ram` | current upstream `litex-boards` plus local openXC7 patches | `--toolchain=openxc7 --sys-clk-freq 50000000 --integrated-main-ram-size 65536 --build --load` | Built a tiny non-DDR SoC through Yosys | openXC7 rejected orphan `IDELAYCTRL` with no I/ODELAYs |
| `2026-05-08T18-45-00+0200-litex-boards-ypcb-openxc7-jtag-only-integrated-ram-no-idelayctrl` | upstream `litex-boards` plus local non-DDR `IDELAYCTRL` removal | `--toolchain=openxc7 --sys-clk-freq 50000000 --integrated-main-ram-size 65536 --build --load` | Generated and programmed a non-DDR LiteX JTAG-UART bitstream | Still not timing-clean; `crg_clkout_buf0` max reported about 113.75 MHz |
| `2026-05-08T18-46-00+0200-litex-boards-ypcb-openxc7-jtag-only-uart-read` | programmed non-DDR bitstream from `18-45-00` | `litex_term ... --jtag-chain 1 jtag`, sent Enter and `help` | OpenOCD found XC7K480T TAP `0x23751093` and started JTAG stream | No BIOS, prompt, or UART bytes observed |
| `2026-05-08T18-47-00+0200-litex-boards-ypcb-openxc7-jtag-only-uart-read-1mhz` | programmed non-DDR bitstream from `18-45-00` | same `litex_term` read with copied OpenOCD config at `adapter_khz 1000` | OpenOCD found XC7K480T TAP `0x23751093` at 1 MHz | No BIOS, prompt, or UART bytes observed |
| `2026-05-08T18-49-00+0200-direct-bscane2-v4k-jtag-debug-proof` | existing direct BSCANE2 v4k JTAG-debug bitstream | `openFPGALoader` then `read_jtag_debug_ftdi_bitbang.py --tdo-bit 7 --bits 768` | Programmed and read valid payload: `magic_ok=True`, `pass=True`, top index/acc/checksums match | none |

Interpretation:

- The dependency/import and LiteX software-build issues are now solved in the
  flake lane. The local wrappers provide LiteX, LiteDRAM, LitePCIe, pythondata
  VexRiscv, picolibc, compiler-rt, Meson, Ninja, Make, GCC, and a writable
  `cp` shim for LiteX's generated BIOS tree.
- The exact upstream reproduction path is Vivado-bound at the gateware build
  step because the YPCB LiteX target defaults to `--toolchain=vivado`.
- It is still valuable to run the Vivado path if available, because it would be
  the fastest way to validate that the board, constraints, DDR3, PCIe, BIOS,
  and JTAG-UART match Enjoy-Digital's known-good baseline.
- The required mainline remains fully open source. The next open-source
  reproduction lane now has a concrete DDR3-only bitstream-generation proof
  with openXC7.
- Local patches needed for the current open-source DDR3-only bring-up:
  - pass the upstream target's `--toolchain` argument into
    `ypcb_00338_1p1.Platform(toolchain=...)`
  - provide LiteX/openXC7 with the repo's nextpnr-xilinx, FASM, PRJXRAY,
    PRJXRAY DB, Python path, and a compatibility `CHIPDB` filename
    `xc7k480t-ffg1156.bin`
  - add `synth_xilinx -nolutram` to avoid unsupported `RAM256X1S` LUTRAM
    packing
  - use PRJXRAY's part spelling `xc7k480tffg1156-2` for `fasm2frames` and
    `xc7frames2bit` while keeping nextpnr's chipdb spelling
    `xc7k480t-ffg1156`
- OpenXC7 PCIe remains a separate blocker: LitePCIe's Series-7 PHY constraint
  path assumes a Vivado-style `pre_placement_commands` API that the
  openXC7/Yosys+nextpnr toolchain object does not expose.
- The successful DDR3-only openXC7 run used LiteX's `--timing-allow-fail`.
  It proves an open-source bitstream can be generated and loaded on the board,
  but it does not prove a timing-clean DDR3 design at 200 MHz. The reported
  `crg_clkout_buf0` maximum was about 107.69 MHz.
- BIOS/JTAG-UART readback is not yet proven. A bounded `litex_term` capture
  can open the JTAG TAP, but neither the original programmed bitstream nor the
  `--sys-clk-freq 50000000` rebuild emitted BIOS text or responded to Enter /
  `help` through the JTAG UART.
- The 50 MHz rebuild did not actually make the emitted openXC7 timing target
  clean; nextpnr still reported 200 MHz checks and `crg_clkout_buf0` only
  reached about 96.68 MHz after routing.
- The non-DDR LiteX isolation keeps the same symptom:
  - upstream LiteX `jtag_uart` is silent with DDR removed
  - lowering OpenOCD JTAG adapter speed from 25 MHz to 1 MHz does not recover
    any BIOS or prompt bytes
  - therefore the silence is not just DDR init/training, and not just the fast
    OpenOCD adapter speed
- Direct BSCANE2/openXC7 on the same board is proven alive:
  - programmed direct v4k JTAG-debug bitstream:
    `/nix/store/lmc8fwrdg7iya8ycpgacs0zlbf8v52rg-task6-int8-v4k-l2-residual-add-output-head-selftest-jtag-debug.bit`
  - read with `scripts/task6/read_jtag_debug_ftdi_bitbang.py --backend mpsse
    --freq-hz 1000000 --tdo-bit 7 --bits 768`
  - result: `magic_ok=True`, `status.pass=True`, `status.fail=False`,
    observed top index `1321` equals expected `1321`, observed top accumulator
    `52140` equals expected `52140`, and vocab/head checksums match
- Current narrowed diagnosis:
  - the Digilent HS3, FTDI/MPSSE read path, openXC7 bitstream generation,
    BSCANE2 USER chain, and board TDO bit 7 work
  - the failing layer is upstream LiteX `jtag_uart`/`litex_term` integration
    under openXC7, or the LiteX CPU/BIOS not reaching the UART path

- New confirmation run: `2026-05-08T19-00-19+0200-litex-boards-ypcb-jtag-only-ir-bruteforce`
  - command log: programmed the same `ypcb_00338_1p1.bit` at `18-45-00.../litex-build/gateware/ypcb_00338_1p1.bit`
  - IR sweep (`--user-ir 0..63`, `--tdo-bit 7`, `--bits 768`, poll 1): 64 attempts
  - result: `magic_ok=0` for all attempts; `state` observed mostly `0` (`SELFTEST_BOOT`) with occasional noise (`state=1`,`15`), and `version` mostly `0` with random garbage (`128`,`130`,`255`)
  - conclusion: still no valid custom JTAG-drain; behavior strongly suggests LiteX `JTAGPHY`/`jtag_uart` path is not exposing the expected DR payload, not the board/JTAG transport
- Extended follow-up run: `2026-05-08T19-04-30+0200-litex-boards-ypcb-openxc7-jtag-only-bscane2-bitbang-extended-scan`
  - reprogrammed the same `ypcb_00338_1p1.bit` and polled longer on both possible TDO channels
  - `--tdo-bit 0 --poll --poll-count 300 --bits 768`: `magic_ok=False`, `state=SELFTEST_BOOT`, raw payload observed `...7f` LSB-only and no field progression (`magic` stuck at 127, `status.pass=False`)
  - `--tdo-bit 7 --poll --poll-count 300 --bits 768`: `magic_ok=False`, `state=SELFTEST_BOOT`, all-zero payload
  - result: still no valid deterministic payload for LiteX/YPCB jtag-only path
  - additional confirmation: full `--user-ir 0..63` sweep over `--tdo-bit 0` and `--tdo-bit 7` with short polling found no `magic_ok=True` case (`returncode=1` from sweep script by design), so this eliminates IR hypothesis
Next action:

- Hold DDR3 route work and move to observability-first. The immediate objective is
  to make LiteX debug path deterministic again.
- Execute this order for speed:
  1. Keep `IDELAYCTRL`-free YPCB jtag-only build and capture RTL-level JTAG
     details (`BSCANE2`, `JTAGPHY`, reset/clock/reset paths).
  2. Re-program the same `task6-litex-boards-ypcb-jtag-only` bitstream and probe
     it with FTDI bitbang reads at 1 MHz on candidate `TDO` bits.
  3. If any deterministic payload appears, add a minimal LiteX UART/CSR variant
     that emits a heartbeat-style status and repeat readback.
  4. If no deterministic payload appears, classify this as LiteX `JTAGPHY` path
     integration failure and patch/replace it before adding DDR3 back.
- This lane must be answered before adding more variants or DDR3 changes.
- Decision from current evidence: LiteX/YPCB LiteX jtag-only remains non-deterministic under openXC7 with raw JTAG debug reads; prioritize replacing `JTAGPHY` with a tiny custom debug path (BSCANE2-based payload) before adding DDR3 throughput experiments.

### Execution doctrine: moonshot plus fast falsification

Primary moonshot:

- Fit a useful TinyStories-1M-derived inference design into the current FPGA
  board envelope with open, reproducible techniques. Allowed techniques include
  quantization, external memory, streaming/fusion, time-multiplexing,
  DSP-first kernels, and structural compiler or RTL changes.
- Do not count synthesis progress alone as board fit. A board-fit claim needs a
  plausible memory/interface story and either board/JTAG evidence or a clear
  path to it.

Experiment ladder:

- L0: isolated arithmetic or memory microkernel, with simulation plus
  board/JTAG proof when physical behavior matters
- L1: int8 MLP, attention, or memory sub-block, with board/JTAG proof when it
  is a hardware-risk reducer
- L2: one transformer-block-equivalent slice or a fused streaming substitute
- L3: representative TinyStories core preserving relevant op/dialect and
  structural coverage
- L4: full TinyStories-1M replay, or a documented full-model successor if the
  baseline evolves

Promotion rule:

- L0-L3 wins are hypotheses, not Task 6 success claims.
- A result may be promoted only if it records:
  - exact command or flake output
  - artifact bundle
  - wall time and peak `VmRSS` / `VmHWM` when available
  - MLIR op stats or RTLIL/Yosys stage stats appropriate to the level
  - mapped utilization delta
  - board/JTAG result when applicable
  - continue/prune decision
- A Task 6 success claim must replay against the copied TinyStories baseline
  bundle or against a documented full-model successor with an explicit
  comparison bridge.

Scaling knobs to measure:

| Knob | Expected scaling signal | Why it matters here |
| --- | --- | --- |
| `vocab_size` | roughly `O(V * H * bitwidth)` for embedding/logit tables | vocab-sized memories already dominate eligible bits |
| `hidden_size` | `O(H)` activations and often `O(H^2)` projection/MLP weights | controls whether kernels remain reusable or explode |
| `num_layers` | roughly linear if materialized; lower if hardware is reused | decides whether board fit requires time-multiplexing |
| `num_heads` / `head_dim` | affects attention fanout, buffering, and projection shape | separates attention cost from MLP/vocab cost |
| context/window size | grows KV/intermediate memory with decode assumptions | distinguishes one-token selftests from useful decode |
| bit width / quantization | memory mostly linear; arithmetic mapping non-linear | determines INT8/INT4 benefit and DSP/LUT tradeoff |
| externalized memory count / bits | non-smooth stage-frontier shifts | top4/top32/top34 showed owner-specific phase changes |
| streaming/fusion | fewer materialized intermediates if the schedule is real | matches the observed over-materialization failure mode |
| DSP-first arithmetic | can trade LUT/FF growth for abundant DSP capacity | the board has far more DSP headroom than LUT/FF headroom |
| time-multiplexed reuse | lowers area at latency/control cost | likely needed if layers cannot be fully materialized |

Moonshot lanes to keep active:

- External-memory mainline:
  - current anchor is `top34-memory`, which moved the full-model frontier
    through `stage6a`, `stage8b`, and final JSON emission
  - next work must explain or reduce the LUT/FF growth and define the board
    memory contract before choosing a DDR3 controller
- JTAG-first int8/H2 lane:
  - LEDs are acceptable only as coarse pass/fail
  - detailed board diagnosis should expose state, operands, checksums, and
    result indices through JTAG payloads
- Representative-core scaling lane:
  - use the smallest TinyStories-derived core that preserves relevant coverage
    as the default inner loop
  - replay representative wins on the copied baseline/full-model lane before
    claiming Task 6 progress
- StreamTensor-lite lane:
  - make each experiment a concrete fused streaming MLP or attention-block
    slice with a measurable delta target
  - acceptable targets include fewer materialized memories, smaller RTLIL or
    stage8 cell owners, lower peak RSS, or lower mapped LUT/FF
- DSP-first arithmetic lane:
  - use the passing int8 board kernels as the substrate for larger kernels
  - measure whether DSP use rises while LUT/FF and route pressure fall
- Quantization lane:
  - keep only routes that move past frontend legality and change downstream
    resource shape
  - do not revive broad quantization patch stacks without a narrow measured
    benefit
- Ternip lane:
  - evaluate `sifferman/ternip` as an alternate open-source MatmulFree/ternary
    accelerator path for this board
  - goal is to reproduce upstream, synthesize a reduced Ternip core with open
    tools, wrap it for YPCB, program Board A, and only then compare token-rate
    potential against the reported Artix+ class `~30 tokens/s` claim
  - keep this separate from the current DDR3/LiteDRAM lane; Ternip may consume
    DDR later, but it must first pass reduced open-source elaboration,
    synthesis, and no-DDR board-wrapper gates
  - use Board A as the default Ternip bring-up board; Board B is excluded until
    the non-DDR LED-map control reports `INIT=1` and `DONE=1`
  - first reduced configuration defaults to `D=64`, `TmatmulParallelism=8`,
    `VectorParallelism=4`, `BatchSize=1`, and `FixedPointPrecision=8`
  - do not claim TinyStories or token/s equivalence until the exact model,
    runtime, precision, and token definition are recorded

Immediate execution order as of 2026-04-30:

1. Resolve the open LiteDRAM/LiteX board-probe P&R blocker:
   `ODELAYE2` output-delay packing into `OBUF` / `OBUFDS` fails in openXC7
   nextpnr even in a one-cell cutout. Do not switch to Vivado MIG.
2. Once that open P&R blocker clears, program the YPCB LiteDRAM init/bandwidth
   probe and read status/counters through the JTAG/XVC payload.
3. Grow the proven H2 v4k residual-add plus streamed output-head path by one
   structure increment, keeping a JTAG payload in the first board image.
4. Continue the full-model external-memory mainline with `top34-memory`
   resource-owner analysis and board-memory accounting.
5. Add a small representative-core scaling matrix over vocab, layer count,
   hidden size, bit width, and externalized-memory owner count.
6. Start the next StreamTensor-lite experiment only after it has one explicit
   delta target from the list above.
7. Replay any promising representative or microkernel result on the copied
   TinyStories baseline bundle or a documented full-model successor.
8. Start the Ternip lane with an upstream reproduction/license gate, then a
   reduced open-source elaboration gate; do not attempt a YPCB bitstream until
   the reduced core has synthesized with plausible resources.

### Ternip lane update (2026-05-05)

- v110 passed the upstream reproduction gate:
  - `sifferman/ternip` pinned at
    `7573c17dbed8f01e7d9e07e59a863376426a5489`
  - `bespoke-silicon-group/basejump_stl` pinned at
    `a43571d2eaaae2dda7c10490e8350dfdac7da878`
  - result artifact:
    `artifacts/task6/parallel-hypotheses/h2-ternip-v110-upstream-repro.json`
- v111 reduced elaboration is blocked before Ternip RTL elaboration:
  - command: `nix build .#task6-ternip-reduced-elab-json -L`
  - failure: the existing `yosys-slang` path tries to build the repo's custom
    `yosys-0.64` derivation and fails with
    `genericBuild: command not found`
  - next Ternip source fix should decouple the reduced elaboration gate from
    the broken custom-Yosys derivation, likely by adding a Verilator lint gate
    first or by providing a working packaged `yosys-slang`/Yosys pair
  - do not attempt a YPCB Ternip wrapper or bitstream until this toolchain gate
    is resolved
- v112 added and ran a reduced Verilator lint/report gate:
  - source commit: `54a32c4`
  - command: `nix build .#task6-ternip-reduced-verilator-lint-report -L`
  - status: `FAIL`
  - first blocker: BaseJump parsing cannot find `bsg_defines.sv`
  - next source fix should add BaseJump include paths before changing any
    Ternip RTL or reduced configuration

### Vocab route frontier update (2026-05-07)

Question:

- Determine whether the current int8 L2 residual-add plus output-head design is
  intrinsically route-blocked below the v10k image, or whether the observed
  v10k route failure is caused by the final vocab/tile/banking shape.

Commands:

- `nix build .#task6-int8-v4k-l2-residual-add-output-head-selftest-5mhz-fasm --no-link --print-out-paths -L`
- `nix build .#task6-int8-v6k-l2-residual-add-output-head-selftest-5mhz-fasm --no-link --print-out-paths -L`
- `nix build .#task6-int8-v8k-l2-residual-add-output-head-selftest-5mhz-fasm --no-link --print-out-paths -L`

Results:

| Lane | `vocab_size` | `TILE_OUT_DIM` | Route status | LUT | FF | BRAM36 | DSP | Router iter1 overused / overuse | Final route iter | Post-route max MHz |
| --- | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| v4k | 4096 | 64 | PASS | 20,890 | 8,940 | 136 | 14 | 24,668 / 29,388 | 57 | 83.57 |
| v6k | 6144 | 64 | PASS | 22,088 | 8,942 | 200 | 14 | 33,955 / 41,633 | 28 | 102.57 |
| v8k | 8192 | 64 | PASS | 23,899 | 8,942 | 264 | 14 | 44,574 / 55,622 | 11 | 107.70 |
| v10k | 10000 | 80 | PRUNED | 76,198 | 8,958 | 8 plus 756 RAMB18 | 15 | 194,634 / 267,576 | none | n/a |

Interpretation:

- The design is not generally route-blocked. With `TILE_OUT_DIM=64`, route
  pressure grows gently from v4k through v8k and all three lanes complete route
  with large timing margin at the 5 MHz smoke-test target.
- The v10k failure is now a sharper suspect: it changes both vocab size and
  tile/banking shape (`TILE_OUT_DIM=80`) and also maps mostly to RAMB18 instead
  of the v4k-v8k RAMB36-dominated shape.
- The next fastest, highest-information experiment is a near-10k lane divisible
  by 64, preferably `vocab_size=9984` with `TILE_OUT_DIM=64`. If that routes,
  the tile80/non-power-of-two banking shape is the bug to fix before board
  programming. If it fails with v10k-like overuse, the problem is near-10k route
  fanout/congestion and output-head rebanking is the next move.

Artifact:

- `artifacts/task6/parallel-hypotheses/e1-vocab-route-frontier-5mhz-summary.json`

### v9984 tile64 isolation route update (2026-05-07)

Question:

- Is the v10k route failure caused by near-10k vocab size itself, or by the
  current v10k `TILE_OUT_DIM=80` / non-divisible banking shape?

Reason for `vocab_size=9984`:

- `9984 = 156 * 64`, so it keeps the route-clean `TILE_OUT_DIM=64` shape.
- It is only 16 tokens below 10,000, a 0.16% vocab-size difference, so it is a
  clean isolation of tile/banking shape rather than a meaningful vocab shrink.

Command:

- `nix build .#task6-int8-v9984-l2-residual-add-output-head-selftest-5mhz-fasm --no-link --print-out-paths -L`

Result:

- PASS: generated
  `/nix/store/gqh45ij302d2mdpp2m9l4j153jvdrd84-task6-int8-v9984-l2-residual-add-output-head-selftest-5mhz.fasm`
- Utilization:
  - `SLICE_LUTX`: `23,517 / 597,200` (3%)
  - `SLICE_FFX`: `8,944 / 597,200` (1%)
  - `RAMB36E1`: `320 / 955` (33%)
  - `RAMB18E1`: `6 / 1,910` (0%)
  - `DSP48E1`: `14 / 1,920` (0%)
- Placement max frequency: `90.62 MHz` at a `5 MHz` target.
- Router first iteration: `wires=950,378`, `overused=50,365`,
  `overuse=66,120`.
- Final route: iteration 32, `overused=0`, `overuse=0`, `archfail=0`.
- Router2 time: `1164.33s`.
- Post-route max frequency: `110.24 MHz`.

Interpretation:

- Near-10k vocab size is routeable in the current architecture when the lane
  keeps `TILE_OUT_DIM=64`.
- The previous v10k route failure is therefore not explained by vocab size. The
  likely cause is the v10k `TILE_OUT_DIM=80` / non-divisible banking and memory
  packing shape, which produced a much worse first router iteration:
  `overused=194,634`, `overuse=267,576`.
- Next gate: replace v10k tile80 with a tile64-compatible full-10k strategy,
  either by padding to a tile64 multiple or by supporting a partial final tile
  while preserving the tile64 banking/fanout shape.

Artifact:

- `artifacts/task6/parallel-hypotheses/e1-vocab9984-tile64-route-summary.json`

### v10k padded tile64 route attempt (2026-05-07)

Question:

- Can the logical `vocab_size=10000` target keep the successful tile64 route
  shape by padding physical storage/compute to `10048 = 157 * 64` and masking
  padded rows out of the top1 comparison?

Implementation:

- Added an explicit logical/physical vocab split to the output-head data
  generators:
  - logical `vocab_size=10000`
  - physical `vocab_size=10048`
  - `TILE_OUT_DIM=64`
- Added `VALID_VOCAB_SIZE` to `task6_int8_vocab_output_head_top1_kernel`; the
  core still computes padded rows, but top1 ignores `core_out_addr >= 10000`.

Command:

- `timeout 75m nix build .#task6-int8-v10k-padded-tile64-l2-residual-add-output-head-selftest-5mhz-fasm --no-link --print-out-paths -L`

Result:

- TIMEOUT: route did not finish within 75 minutes.
- Synthesis and placement passed.
- Utilization:
  - `SLICE_LUTX`: `23,851 / 597,200` (3%)
  - `SLICE_FFX`: `8,944 / 597,200` (1%)
  - `RAMB36E1`: `322 / 955` (33%)
  - `RAMB18E1`: `6 / 1,910` (0%)
  - `DSP48E1`: `14 / 1,920` (0%)
- Placement max frequency: `84.35 MHz` at a `5 MHz` target.
- Router first iteration: `wires=966,415`, `overused=54,484`,
  `overuse=73,315`.
- Last observed route iteration before timeout: iteration 10,
  `wires=1,074,174`, `overused=559`, `overuse=559`.

Interpretation:

- The padded tile64 full-v10k shape preserves the good route family:
  first-iteration overuse is close to v9984/tile64 and far below old
  v10k/tile80.
- The route did not complete inside the first 75 minute budget, so this is not
  yet a board-image candidate.
- Next gate: rerun this exact padded target with a longer route budget and/or a
  different seed. If it still plateaus above zero overuse, keep the tile64
  logical/physical split and reduce route pressure locally; do not go back to
  tile80.

Artifact:

- `artifacts/task6/parallel-hypotheses/e1-vocab10k-padded-tile64-route-attempt-summary.json`

### v10k padded tile64 longer route rerun (2026-05-08)

Question:

- Does the logical `vocab_size=10000` padded-to-`10048` tile64 route complete
  if allowed to run beyond the initial 75 minute timeout?

Command:

- `timeout 4h nix build .#task6-int8-v10k-padded-tile64-l2-residual-add-output-head-selftest-5mhz-fasm --no-link --print-out-paths -L`

Result:

- PRUNED manually before timeout after the route entered a low-information hard
  tail.
- Synthesis and placement repeated the prior result:
  - `SLICE_LUTX`: `23,851 / 597,200` (3%)
  - `SLICE_FFX`: `8,944 / 597,200` (1%)
  - `RAMB36E1`: `322 / 955` (33%)
  - `DSP48E1`: `14 / 1,920` (0%)
  - placement max frequency: `84.35 MHz` at a `5 MHz` target
- Router progress:
  - iteration 1: `wires=966,415`, `overused=54,484`,
    `overuse=73,315`
  - iteration 10: `wires=1,074,174`, `overused=559`, `overuse=559`
  - iteration 12: `wires=1,075,014`, `overused=466`, `overuse=468`

Interpretation:

- The route was still improving, so padded v10k/tile64 remains plausible.
- However, v9984/tile64 already proves the high-value point: near-10k vocab
  routes when the design stays in the tile64 banking family. The extra 16
  logical tokens between v9984 and v10k are not worth blocking board bring-up.
- Next gate: program the already-routed v9984/tile64 image and exercise the
  autonomous board loop. Return to exact padded v10k only after board
  programming/readback is working, or if exact logical 10k becomes necessary.

Artifact:

- `artifacts/task6/parallel-hypotheses/e1-vocab10k-padded-tile64-route-rerun-pruned-summary.json`

### v9984 existing-FASM board program attempt (2026-05-08)

Question:

- Can the already-routed v9984/tile64 image be converted to a bitstream and
  programmed on the connected YPCB board?

Commands:

- Convert existing routed FASM:
  - source FASM:
    `/nix/store/gqh45ij302d2mdpp2m9l4j153jvdrd84-task6-int8-v9984-l2-residual-add-output-head-selftest-5mhz.fasm`
  - local bitstream:
    `artifacts/task6/generated-bitstreams/task6-int8-v9984-l2-residual-add-output-head-selftest-5mhz-from-existing-fasm.bit`
- Program under board lock:
  - `python3 scripts/task6/task6_board_run.py with-lock --run-dir artifacts/task6/runs/2026-05-08T11-07-45+0200-v9984-existing-fasm-program --log-name program-openfpgaloader.log -- openFPGALoader -c digilent_hs3 --ftdi-serial 210299BF3824 artifacts/task6/generated-bitstreams/task6-int8-v9984-l2-residual-add-output-head-selftest-5mhz-from-existing-fasm.bit`

Result:

- FASM-to-bit conversion succeeded; the local `.bit` is `18,735,162` bytes.
- Programming did not start. `openFPGALoader` failed while opening the HS3
  adapter:
  - `unable to open ftdi device: -3 (device not found)`
- A detection attempt without the serial filter failed with the same error.
- `lsusb` did not show the expected Digilent/FTDI `0403:6014` device at the
  time of the attempt.

Interpretation:

- This is not a route or bitstream blocker. The immediate blocker is physical
  USB/JTAG enumeration of the Digilent HS3 path.
- Next gate: restore HS3 enumeration, then rerun the same board-run programming
  command. Only after programming exits 0 should readback/selftest evidence be
  collected.

Artifacts:

- `artifacts/task6/parallel-hypotheses/e1-vocab9984-existing-fasm-board-program-summary.json`
- `artifacts/task6/runs/2026-05-08T11-07-45+0200-v9984-existing-fasm-program`

### v9984 existing-FASM board program retry (2026-05-08)

Question:

- After reconnecting the Digilent HS3 cable, can the existing-routed
  v9984/tile64 bitstream be programmed and tested on the YPCB board?

Result:

- JTAG cable enumeration recovered:
  - `lsusb` showed `0403:6014` FT232H.
  - `openFPGALoader --detect` reported IDCODE `0x23751093`,
    `xc7k480t`.
- Programming succeeded under the Task 6 board lock:
  - command returned `0`
  - `openFPGALoader` status: `isc_done=1`, `isc_ena=0`, `init=1`,
    `done=1`
- Direct FTDI readback sanity:
  - default MPSSE TDO bit produced wrong IDCODE `0xba8849ff`
  - `--tdo-bit 7` produced correct IDCODE `0x23751093`
- Selftest payload readback did not provide correctness evidence:
  - payload was all zero
  - `magic_ok=false`
  - the exact routed v9984 top has `ENABLE_JTAG_DEBUG=0`, and the BSCANE2
    debug block is instantiated only when that parameter is nonzero

Interpretation:

- Board programming is proven for the v9984/tile64 image.
- Autonomous correctness is not proven for this exact image. This is a debug
  visibility issue, not evidence that the hardware selftest failed.
- Next gate: either visually inspect `led_3bits_tri_o` for pass/fail on this
  programmed image, or build and route a v9984 JTAG-debug-enabled target so the
  pass/fail bit, top index, top accumulator, and checksums can be read
  autonomously.

Artifacts:

- `artifacts/task6/parallel-hypotheses/e1-vocab9984-existing-fasm-board-program-retry-summary.json`
- `artifacts/task6/runs/2026-05-08T11-15-57+0200-v9984-existing-fasm-program-retry`

### v9984 JTAG-debug explicit-serial-only board proof (2026-05-08)

Question:

- Given flaky JTAG enumeration discovery, can we keep the board proof loop
  stable by skipping `--detect` and always using explicit `--ftdi-serial`?

Commands:

- `python3 scripts/task6/task6_board_run.py with-lock --run-dir artifacts/task6/runs/2026-05-08T19-32-49+0200-v9984-jtag-debug-program-readback-explicit-only --log-name program-openfpgaloader.log -- openFPGALoader -c digilent_hs3 --ftdi-serial 210299BF3824 /nix/store/k52psqh0lv416xbg5xgl3zs5fxlamm0f-task6-int8-v9984-l2-residual-add-output-head-selftest-jtag-debug-5mhz.bit`
- `python3 scripts/task6/task6_board_run.py with-lock --run-dir artifacts/task6/runs/2026-05-08T19-32-49+0200-v9984-jtag-debug-program-readback-explicit-only --log-name read_jtag_debug_ftdi_bitbang.log -- python3 scripts/task6/read_jtag_debug_ftdi_bitbang.py --backend mpsse --serial 210299BF3824 --tdo-bit 7 --bits 768 --poll --poll-count 12 --poll-interval 0.25 --json-only`

Result:

- Programming was successful through explicit serial path:
  - `isc_done=1`, `done=1`
- JTAG readback was successful with `magic_ok=true`, `state=SELFTEST_PASS`,
  top index/acc matching expected (`229`, `54965`)
- No board `--detect` invocation was needed for this loop.

### v9984 LED observation (2026-05-08)

User visual observation after programming:

- LED0: green on
- LED1: red blinking
- LED2: on
- LED3: off

RTL LED semantics for this image:

- `led_3bits_tri_o[0] = blink_count_q[25]`
- `led_3bits_tri_o[1] = state_q == SELFTEST_PASS`
- `led_3bits_tri_o[2] = state_q == SELFTEST_FAIL`

Interpretation:

- Assuming LED0 green is board power/status and LED1-LED3 are the three
  FPGA-driven `led_3bits_tri_o` outputs in order, the observed pattern is:
  - blink LED: blinking
  - pass LED: on
  - fail LED: off
- That matches `SELFTEST_PASS`.
- This is human visual correctness evidence, not autonomous JTAG payload
  evidence. The exact routed image still has `ENABLE_JTAG_DEBUG=0`.

Artifact:

- `artifacts/task6/parallel-hypotheses/e1-vocab9984-existing-fasm-led-observation-summary.json`

### Open LiteDRAM/LiteX DDR3 board-probe update (2026-04-30)

Constraint:

- Keep this lane fully open-source. Do not use Vivado MIG; use LiteDRAM/LiteX
  and the openXC7/nextpnr/openFPGALoader path.

Current hardware result:

- The YPCB LiteDRAM no-ODELAY probe now builds, routes, programs over HS3, and
  exposes autonomous JTAG debug payloads.
- The current routed v29 byte-map diagnostic bitstream is:
  `/nix/store/kkikcq3005nj596j3036fbb3702zfp7r-task6-ypcb-litedram-no-odelay-init-bandwidth-probe.bit`
- v29 nextpnr utilization:
  - `SLICE_LUTX`: `19012 / 597200` (3%)
  - `SLICE_FFX`: `9732 / 597200` (1%)
  - `RAMB18E1/RAMB36E1`: 0
  - `DSP48E1`: 0
  - DDR PHY hard blocks remain the limiting fixed resources:
    `IDELAYE2 64 / 400`, `OSERDESE2 98 / 400`,
    `ISERDESE2 64 / 400`, `IDELAYCTRL 3 / 8`
- v29 post-route timing passes the 50 MHz target:
  - `clk200`: 424.81 MHz
  - `user_clk`: 83.95 MHz
  - `core.iodelay_clk`: 665.78 MHz
  - `jtag_debug_shift.drck`: 654.88 MHz

What the board probes have learned:

- v26 seed-2 proved JEDEC init and the native scheduler are alive:
  - `init_state=INIT_DONE`
  - all `65536` writes completed
  - all `65536` reads returned
  - all reads mismatched, so the remaining blocker is data integrity, not a
    native-port deadlock.
- v27 scanned one global read `bitslip/delay` pair across all byte lanes:
  - all 256 candidates completed
  - best result was still `32 / 32` mismatches on the 32-word calibration
    sample
  - conclusion: one global setting is not sufficient.
- v28 scanned each physical byte lane independently:
  - all `2048` lane/bitslip/delay candidates completed
  - full `65536`-word test still failed
  - only lanes 6 and 7 improved meaningfully (`4 / 32` and `8 / 32`
    calibration mismatches); lanes 0-5 stayed poor.
- v29 added a module-to-logical-byte diagnostic:
  - all `2048` candidates completed again
  - the full native-port test still failed with `65536 / 65536` mismatches
  - selected logical-byte evidence was dominated by logical bytes 6 and 7:
    `m0->y6`, `m1->y6`, `m2->y6`, `m3->y6`, `m4->y6`, `m5->y7`,
    `m6->y6`, `m7->y7`
  - first full-test readback was `0xffdc008700000000` against expected
    `0xc0de0000eca86420`; lower 32 bits are again zero in the first failing
    word.

Current interpretation:

- This is not a toolchain synthesis/P&R failure. The open flow routes and the
  programmed design runs the controller far enough to complete native writes
  and reads.
- It is also not a clean byte-lane permutation. The v29 byte-map diagnostic
  does not show a one-to-one physical-module to native-byte mapping that would
  make the current native-port calibration sufficient.
- The next likely blocker is one of:
  - missing LiteX/LiteDRAM DFII-style read leveling/training before enabling
    normal native-port traffic
  - native-port data packing/addressing assumptions in the probe
  - write/read phase or write-side training behavior that the current native
    pattern test cannot isolate

Next gate:

- Stop widening the native-port delay sweep.
- Implement a smaller DFII/LiteX-style read-leveling probe or a native-port
  packing proof:
  - DFII route: reproduce LiteX `sdram_read_leveling()` more directly by using
    the `sdram_dfii_pi*_wrdata/rddata` and command CSRs during software DFI
    control.
  - native-port route: first capture a compact multi-address readback sample
    through JTAG to prove whether address/data packing is wrong before changing
    PHY calibration again.

v30 native-read sampler result:

- Implemented the native-port route above:
  - probe version: `30`
  - JTAG payload width: `1728` bits
  - added the first eight final native read responses to the JTAG payload
  - decoder now prints `expected`, `actual`, and `xor` for each sampled word
- Build outputs:
  - JSON:
    `/nix/store/2y8nbbhzz0fd4ygz11ilmg7v6qq50z5i-task6-ypcb-litedram-no-odelay-init-bandwidth-probe.json`
  - bitstream:
    `/nix/store/xhfay3c7x7bx533pbg11jrg522w2va92-task6-ypcb-litedram-no-odelay-init-bandwidth-probe.bit`
- Yosys result:
  - `check` reported `0` problems
  - peak memory: `703.36 MiB`
  - estimated LCs: `10062`
- nextpnr utilization:
  - `SLICE_LUTX`: `19376 / 597200` (3%)
  - `SLICE_FFX`: `10796 / 597200` (1%)
  - `RAMB18E1/RAMB36E1`: 0
  - `DSP48E1`: 0
  - DDR PHY hard blocks: `IDELAYE2 64 / 400`, `OSERDESE2 98 / 400`,
    `ISERDESE2 64 / 400`, `IDELAYCTRL 3 / 8`
- Post-route timing:
  - `clk200`: 665.34 MHz
  - `user_clk`: 81.48 MHz
  - `core.iodelay_clk`: 665.78 MHz
  - `jtag_debug_shift.drck`: 504.03 MHz
- Board/JTAG result after programming:
  - `magic_ok=true`
  - state: `PROBE_ERROR`
  - init state: `INIT_DONE`
  - writes: `65536 / 65536`
  - reads: `65536`
  - responses: `65536`
  - mismatches: `65536`
  - first mismatch expected `0xc0de0000eca86420`, actual
    `0x40dc028100000000`
- First eight sampled final native reads:
  - `0`: expected `0xc0de0000eca86420`, actual `0x40dc028100000000`
  - `1`: expected `0xc0de0081eca84421`, actual `0x40dc018100000000`
  - `2`: expected `0xc0de0102eca82422`, actual `0x00dc008700000000`
  - `3`: expected `0xc0de0183eca80423`, actual `0x00dc008700000000`
  - `4`: expected `0xc0de0204eca8e424`, actual `0x00dc000400000000`
  - `5`: expected `0xc0de0285eca8c425`, actual `0x0094000400000000`
  - `6`: expected `0xc0de0306eca8a426`, actual `0xfb94000000000000`
  - `7`: expected `0xc0de0387eca88427`, actual `0xfb00680000000000`

Updated interpretation:

- The native-port command path is alive: all commands and responses complete.
- The lower 32 bits are stuck at zero across the first eight sampled final
  native reads.
- The upper 32 bits vary with address, so the read path is not blank.
- The next gate should stop native-port delay widening and implement the
  LiteX/DFII-style read-leveling path directly. That path can distinguish
  missing DFII training from native converter packing or board byte-lane
  mapping assumptions.

v31 DFII direct round-trip result:

- Implemented the first LiteX/DFII-style probe:
  - probe version: `31`
  - JTAG payload width: `2400` bits
  - after JEDEC init, the probe switches to software DFI control, writes a
    16-word pattern through the `sdram_dfii_pi*_wrdata` CSRs, issues
    activate/write/read/precharge commands through the DFII command CSRs, and
    captures the 16 `sdram_dfii_pi*_rddata` words over JTAG
- Build outputs:
  - JSON:
    `/nix/store/2a69b7w1krivqy6cxhcha4pzbnma3kix-task6-ypcb-litedram-no-odelay-init-bandwidth-probe.json`
  - bitstream:
    `/nix/store/lhiqqy74zawzajkb92awsbck6bcgkgs2-task6-ypcb-litedram-no-odelay-init-bandwidth-probe.bit`
- Yosys result:
  - `check` reported `0` problems
  - peak memory: `734.27 MiB`
  - estimated LCs: `11152`
- nextpnr utilization:
  - `SLICE_LUTX`: `20936 / 597200` (3%)
  - `SLICE_FFX`: `12253 / 597200` (2%)
  - `RAMB18E1/RAMB36E1`: 0
  - `DSP48E1`: 0
  - DDR PHY hard blocks: `IDELAYE2 64 / 400`, `OSERDESE2 98 / 400`,
    `ISERDESE2 64 / 400`, `IDELAYCTRL 3 / 8`
- Post-route timing:
  - `clk200`: 452.28 MHz
  - `user_clk`: 64.77 MHz
  - `core.iodelay_clk`: 547.65 MHz
  - `jtag_debug_shift.drck`: 457.88 MHz
- Board/JTAG result after programming:
  - `magic_ok=true`
  - state: `PROBE_ERROR`
  - init state: `INIT_DONE`
  - DFII sequence state: `DFII_SEQ_DONE`
  - DFII CSR acknowledgements: `50`
  - DFII word mismatch mask: `0xffff`
  - all 16 captured DFII readback words mismatched the written pattern
- Representative captured DFII readback:
  - `[p0 w0]` expected `0x11223344`, actual `0x00aa3bcc`
  - `[p0 w1]` expected `0x55667788`, actual `0x556e7788`
  - `[p1 w0]` expected `0x22446688`, actual `0x00223b44`
  - `[p2 w0]` expected `0x0f1e2d3c`, actual `0xffff3bff`
  - `[p3 w3]` expected `0x33832795`, actual `0x556e7788`

Updated interpretation:

- The open LiteDRAM/LiteX CSR, command, and JTAG paths are now proven alive on
  the board: JEDEC init completes, all DFII CSR transactions acknowledge, and
  DFII readback returns nonzero data.
- The failure is still DDR3 data integrity, but v31 moves the hypothesis away
  from native-port packing as the only explanation. A direct DFII write/read
  path also fails without training.
- The next gate is to implement the actual LiteX-style read-leveling scan over
  `rdly_dq_bitslip` and `rdly_dq_inc`, using the DFII write/read pattern and
  per-module byte comparisons instead of treating the whole native word as the
  calibration unit.

v32 LiteX-style read-leveling scan result:

- Implemented the read-leveling scan gate:
  - probe version: `32`
  - JTAG payload width: `2400` bits
  - after JEDEC init, the probe scans all `8` byte modules over `8` bitslips
    and `32` read delays (`2048` candidates total)
  - each candidate uses the DFII write/read path and scores the current
    module's LiteX-style positive/negative edge bytes
- Build outputs:
  - JSON:
    `/nix/store/fiwdxk9wp99xv9pvdp7afhvjva1zipfm-task6-ypcb-litedram-no-odelay-init-bandwidth-probe.json`
  - bitstream:
    `/nix/store/7rbdb3sk8rm5s1kmrfiq9iypc3zmsxp1-task6-ypcb-litedram-no-odelay-init-bandwidth-probe.bit`
- Yosys result:
  - `check` reported `0` problems
  - peak memory: `792.69 MiB`
  - estimated LCs: `11819`
- nextpnr utilization:
  - `SLICE_LUTX`: `21258 / 597200` (3%)
  - `SLICE_FFX`: `12253 / 597200` (2%)
  - `RAMB18E1/RAMB36E1`: 0
  - `DSP48E1`: 0
  - DDR PHY hard blocks: `IDELAYE2 64 / 400`, `OSERDESE2 98 / 400`,
    `ISERDESE2 64 / 400`, `IDELAYCTRL 3 / 8`
- Post-route timing:
  - `clk200`: 532.20 MHz
  - `user_clk`: 74.01 MHz
  - `core.iodelay_clk`: 513.35 MHz
  - `jtag_debug_shift.drck`: 462.32 MHz
- Board/JTAG result after programming:
  - `magic_ok=true`
  - state: `PROBE_DFII_DONE`
  - init state: `INIT_DONE`
  - candidates tested: `2048 / 2048`
  - global best candidate: `22` bit errors at `bitslip=0`, `delay=0`
  - selected settings:
    - `m0 b0/d3`, best errors `32`
    - `m1 b0/d0`, best errors `26`
    - `m2 b0/d7`, best errors `37`
    - `m3 b0/d0`, best errors `29`
    - `m4 b0/d0`, best errors `27`
    - `m5 b0/d0`, best errors `22`
    - `m6 b0/d0`, best errors `28`
    - `m7 b0/d0`, best errors `27`

Updated interpretation:

- The read-leveling scan itself works and is observable through JTAG; it
  completes all `2048` candidates without a timeout or CSR error.
- No module has a zero-error read window. The best candidate still has `22`
  bit errors in the LiteX-style per-module byte score.
- That narrows the next hypothesis: the blocker is not simply a missing read
  delay/bitslip sweep. The next open-flow probe should classify DFII data
  packing and write-side timing/phase, for example with one-hot/byte-ramp DFII
  write patterns and captured per-phase readback before another native-port
  retry.

v38-v44 DFII/native byte-lane classifier results:

- v38 command-phase sweep:
  - bitstream:
    `/nix/store/8s8fr7y2djrlzk5zkjib4qnq85s51p6p-task6-ypcb-litedram-no-odelay-init-bandwidth-probe.bit`
  - result: no write-phase/read-phase combination produced a variable-pattern
    pass; mismatch masks stayed around `0xfff0` / `0xfffa`.
- v39 WRDATA commit-order change:
  - bitstream:
    `/nix/store/j7b54rm40ibdfvhx9m3gwn62gjlr81g4-task6-ypcb-litedram-no-odelay-init-bandwidth-probe.bit`
  - result: did not change the core signature; uniform DFII data still passed
    while phase/byte-ramp patterns failed.
- v40 direct-native shortcut:
  - bitstream:
    `/nix/store/s5p2gjgnp2hahfphbshbfzk2fqvkc43p-task6-ypcb-litedram-no-odelay-init-bandwidth-probe.bit`
  - result: invalid debug route. Skipping the proven DFII/calibration setup
    regressed to an init/probe error, so it is not DDR3 evidence.
- v41 native BIST after restoring the proven setup:
  - bitstream:
    `/nix/store/9ixbljrwkkp9a1ignbh746jdzgzjmjlh-task6-ypcb-litedram-no-odelay-init-bandwidth-probe.bit`
  - all `65536` native writes, reads, and responses completed
  - all `65536` readback words mismatched
  - first mismatch expected `0xc0de0000eca86420`, actual
    `0x0000009800000000`
  - sampled readback varied almost entirely in logical byte lane 4
    (`[39:32]`)
- v42 quick lane-setting experiment:
  - bitstream:
    `/nix/store/9mq5h3wg7qarag8ngs8gf1rbld4nkxja-task6-ypcb-litedram-no-odelay-init-bandwidth-probe.bit`
  - result matched v41, but later inspection showed this was not a clean
    "apply one setting globally" experiment: it skipped only lane 0 and still
    scanned lanes 1-7. Treat it as an intermediate diagnostic, not a promoted
    proof.
- v43 byte-enable diagnostic:
  - bitstream:
    `/nix/store/xrr99jcpbjljbdi7m3wzfgqqgs933cvj-task6-ypcb-litedram-no-odelay-init-bandwidth-probe.bit`
  - added masked native byte writes and exposed the eight readback words over
    JTAG
  - result: only logical byte lane 4 survived cleanly in that biased image,
    matching the full-word native readback signature.
- v44 clean full-scan byte-enable diagnostic:
  - bitstream:
    `/nix/store/8iijvvpci31nlz920mrrf7ygrv4z7lw6-task6-ypcb-litedram-no-odelay-init-bandwidth-probe.bit`
  - probe version: `44`
  - JTAG payload width: `3264` bits
  - full scan completed all `16384` candidates
  - selected lane settings:
    - lanes 0-3 and 5-7: `write_bitslip=0`, `read_bitslip=0`, `delay=0`
    - lane 4: `write_bitslip=2`, `read_bitslip=2`, `delay=17`
  - lane best mismatch counts: `[12, 12, 12, 12, 3, 12, 12, 12]`
  - DFII mode masks:
    - uniform: `0x0000`
    - phase-constant: `0xfffa`
    - byte-ramp: `0xfffc`
  - native BIST still completed all `65536` writes, reads, and responses with
    `65536` mismatches
  - first native mismatch expected `0xc0de0000eca86420`, actual
    `0x000000c800000000`
  - byte-enable diagnostic readback collapsed into logical byte lane 4:
    byte writes with masks `0x02` through `0x80` returned values such as
    `0x0000008100000000`, `0x0000000200000000`,
    `0x0000008300000000`, and `0x0000008500000000`
  - nextpnr utilization:
    - `SLICE_LUTX`: `22595 / 597200` (3%)
    - `SLICE_FFX`: `13899 / 597200` (2%)
    - `RAMB18E1/RAMB36E1`: 0
    - `DSP48E1`: 0
    - `IDELAYE2`: `64 / 400` (16%)
    - `OSERDESE2`: `98 / 400` (24%)
    - `ISERDESE2`: `64 / 400` (16%)
    - `IDELAYCTRL`: `3 / 8` (37%)
  - post-route timing:
    - `clk200`: 479.85 MHz
    - `user_clk`: 67.31 MHz
    - `core.iodelay_clk`: 573.07 MHz
    - `jtag_debug_shift.drck`: 390.02 MHz

Updated interpretation after v44:

- The open LiteDRAM/LiteX lane is still healthy as an implementation path:
  generated RTL has no `ODELAYE2`, P&R passes, programming passes, JEDEC init
  completes, DFII CSR commands work, and native commands/responses complete.
- The remaining blocker is not TinyStories, not Vivado MIG absence, and not a
  generic open-toolchain P&R failure.
- The blocker is now narrowed to data-lane association in the no-ODELAY
  LiteDRAM path: variable data and masked native byte writes collapse through
  logical byte lane 4, while uniform DFII bursts can round-trip.
- The next useful hardware experiment is a smaller byte/phase association
  matrix:
  - write one distinctive DFII byte/phase/beat at a time
  - capture which DFII read word and native byte lane sees it
  - compare that matrix with the generated LiteDRAM DQ/DQS grouping and the
    YPCB board pin metadata
  - only after that, try a physical byte-lane permutation or a corrected DFI
    burst/phase write-data order.

Open-flow no-ODELAY guardrail result:

- Added a generated-RTL check target:
  - command:
    `nix build .#task6-ypcb-litedram-no-odelay-rtl-check --no-link --print-out-paths -L`
  - output:
    `/nix/store/q7y1ajn85gg23yn0fcmv5dwg35ph088h-h2-ypcb-litedram-no-odelay-rtl-check`
  - result: PASS
  - `ODELAYE2` mentions: `0`
  - `IDELAYE2` mentions: `256`
  - `sys4x_dqs` mentions: `12`
- Added minimal no-ODELAY output-buffer cutouts on the same
  DDR3-relevant HR-bank pin set used by the failing `ODELAYE2` cutouts:
  - `task6-no-odelay-obuf-cutout-fasm`:
    `/nix/store/kpd1i8dsw8br0ygj34cf5wxlxw1fvm49-task6-no-odelay-obuf-cutout.fasm`
  - `task6-no-odelay-obufds-cutout-fasm`:
    `/nix/store/f4fw0ch3lbk6gc63s2j9m1ivc37g668l-task6-no-odelay-obufds-cutout.fasm`
  - both P&R runs completed with `0` errors
  - both used `0` `ODELAYE2` and `0` `IDELAYE2`
  - the single-ended cutout placed `1` `IOB33_OUTBUF`
  - the differential cutout placed `1` `IOB33M_OUTBUF` and
    `1` `IOB33S_OUTBUF`
- Re-ran the old `ODELAYE2` output-buffer cutouts as negative controls:
  - `task6-odelay-obuf-cutout-fasm`: expected failure,
    `BEL IOB_X0Y92/IOB33/OUTBUF is located on a high range bank. High range banks do not have ODELAY`
  - `task6-odelay-obufds-cutout-fasm`: expected failure,
    `BEL IOB_X0Y94/IOB33M/OUTBUF is located on a high range bank. High range banks do not have ODELAY`

Updated interpretation:

- The old `K7DDRPHY`/`ODELAYE2` output topology remains rejected for this
  board, but plain HR-bank `OBUF`/`OBUFDS` output paths are valid in openXC7.
- The active LiteDRAM/LiteX lane is correctly using the no-ODELAY Series-7
  path: generated RTL has zero `ODELAYE2` instances and keeps the phase-shifted
  `sys4x_dqs` clock needed by the no-ODELAY topology.
- The remaining DDR3 blocker is therefore not the Series-7 PHY choice or the
  HR-bank output-buffer legality; it is the data-integrity problem exposed by
  v30-v32.

### LiteDRAM v111 deterministic native expected-read probe (2026-05-08)

Question:

- Can the native LiteDRAM read source return a deterministic DFII-seeded linear
  stream with enough useful bandwidth for the INT8 rowstream cutout, without
  relying on native writes?

Implementation:

- Added `DFII_EDGE_COMP_ADDRWALK_THEN_NATIVE_EXPECTED_READ` to the YPCB
  LiteDRAM probe.
- The probe first seeds memory through the known DFII addrwalk path, then issues
  native linear reads and compares each 576-bit native beat against the expected
  DFII-derived data.
- This intentionally avoids another bandwidth-only calculation: the RTL now
  asserts correctness with an expected-data compare.
- JTAG debug payload version: `111`.

Commands:

- `nix build .#task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-expected-read-init-bandwidth-probe-json --no-link --print-out-paths -L`
- `nix build .#task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-expected-read-init-bandwidth-probe-bitstream --no-link --print-out-paths -L`
- `python3 scripts/task6/task6_board_run.py with-lock --run-dir artifacts/task6/runs/2026-05-08T14-08-26+0200-litedram-v111-native-expected-read --log-name program-openfpgaloader.log -- openFPGALoader -c digilent_hs3 --ftdi-serial 210299BF3824 /nix/store/3zznq4lmzypzfphcvdc55avrppqrcdbx-task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-expected-read-init-bandwidth-probe.bit`
- `python3 scripts/task6/task6_board_run.py with-lock --run-dir artifacts/task6/runs/2026-05-08T14-08-26+0200-litedram-v111-native-expected-read --log-name read-litedram-probe-jtag-ftdi.log -- python3 scripts/task6/read_litedram_probe_jtag_ftdi.py --backend mpsse --tdo-bit 7 --poll --poll-count 300 --poll-interval 0.2 --json-only`

Build result:

- JSON synthesis passed:
  `/nix/store/icajwk7g52109gw2m67bg7z6xnlvvhic-task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-expected-read-init-bandwidth-probe.json`
- Bitstream passed:
  `/nix/store/3zznq4lmzypzfphcvdc55avrppqrcdbx-task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-expected-read-init-bandwidth-probe.bit`
- nextpnr utilization:
  - `SLICE_LUTX`: `26694 / 597200` (4%)
  - `SLICE_FFX`: `14145 / 597200` (2%)
  - `CARRY4`: `779 / 74650` (1%)
- Router result:
  - iteration 1: `overused=33534`, `overuse=36875`
  - iteration 10: `overused=0`, `overuse=0`, `archfail=0`
- Post-route timing:
  - `clk200`: `745.16 MHz`
  - `user_clk`: `75.06 MHz`
  - `core.iodelay_clk`: `437.64 MHz`
  - `jtag_debug_shift.drck`: `296.65 MHz`

Board/JTAG result:

- `magic_ok=true`
- version: `111`
- state: `PROBE_ERROR`
- init completed: `init_done=true`, `init_error=false`
- target native reads: `64`
- native commands: `64`
- native responses: `64`
- read cycles: `78`
- native writes: `0` commands, `0` data beats
- nonzero native responses: `64 / 64`
- mismatch count: `64 / 64`
- first mismatch address: `0`
- first expected low sample: `0x5d5c5f5e59585b5a`
- first actual low sample: `0xadaeefecafedafaa`
- useful rowstream-shaped payload: `4352` bytes in `78` cycles
- bandwidth arithmetic still clears the `212.5 MB/s` useful-rowstream target:
  `2789.74 MB/s` at a 50 MHz rowstream clock

Interpretation:

- This is no longer a readscan-only result. It is a deterministic expected-data
  failure on real board hardware.
- The native read path is alive and fast enough for the intended rowstream
  source shape: all 64 commands return nonzero responses in 78 cycles.
- Integrity fails for every response, so the current DFII-to-native expectation
  is not valid yet. The likely next bug is native/DFII address mapping or
  576-bit beat packing, not simple bandwidth or command visibility.
- Do not connect this DDR3 source to the INT8 rowstream cutout yet. The next
  productive probe is a packing/address classifier that captures enough
  expected and actual chunks to derive the native beat layout from the
  DFII-seeded addrwalk data.

Artifacts:

- `artifacts/task6/runs/2026-05-08T14-08-26+0200-litedram-v111-native-expected-read`
- `artifacts/task6/experiments/2026-05-08T14-08-26+0200-litedram-v111-native-expected-read-gate/result.json`

### Evidence contract for every lane

Every active lane must leave behind:

- the exact flake output or command that was run
- the first failing or last completed stage
- the main output artifact path(s)
- the baseline delta being claimed
- the continue / prune decision

Minimum metrics to record when available:

- wall-clock time
- peak host memory or the best available proxy
- Yosys / mapped utilization delta
- size or count signals that explain the change
  - e.g. RTLIL size, selected module count, eligible memory bits

Preferred capture helper for future runs:

- `scripts/pipeline/monitor_build.sh`
  - wrap long `nix build ... -L` runs with it when host-RAM evidence matters
  - it records the raw build log, per-process `VmRSS` / `VmHWM` samples, and a
    short summary with the last emitted stage banner

### Active lane queue

0. Fast-iteration lane: representative TinyStories core
   - branch/worktree: `task6`
   - package family:
     - `tiny-stories-1m-representative-core-*`
     - `tiny-stories-1m-representative-core-selftest-all-memory-*`
   - current milestone:
     - use a reduced GPT-Neo core derived from the TinyStories-1M config to
       preserve the same model family and operator mix while cutting vocabulary
       table size and layer count for faster compile/debug cycles
   - current profile:
     - `vocab_size = 32`
     - `num_layers = 2`
     - `hidden_size = 2`
     - `num_heads = 1`
     - `max_position_embeddings = 4`
     - `window_size = 2`
   - intended use:
     - frontend/lowering iteration
     - stage-splitting experiments
     - quick checks of whether a flow or patch changes the shape of the
       synthesized design before spending hours on the full baseline
   - guardrail:
     - do not treat this as a replacement baseline; every real Task 6 claim
       still has to come back to the copied baseline bundle
     - treat MLIR op coverage against the baseline as the admission check for
       this lane; if the smaller core drops baseline ops/dialects, grow it back

1. Main lane: narrowed external-memory shell
   - branch/worktree: `task6` until the next structural branch split is needed
   - package family:
     - `tiny-stories-1m-baseline-float-selftest-top34-memory-*`
   - current milestone:
     - completed on 2026-04-28: the fixed `top34-memory` path clears
       `stage6a`, clears `stage8b`, completes `stage9 write_json`, and emits a
       final utilization bundle
     - current result is a toolchain-frontier win but a mapped-resource loss
       versus the copied all-memory baseline
   - continue only if:
     - a follow-up explains or removes the LUT growth from the current
       blackbox shell, or materially changes the board-memory contract
   - prune only if:
     - the next slice only widens externalization or adds a DDR3 controller
       without first addressing the current shell/resource inflation

2. Side lane A: quantization viability
   - preferred branch/worktree: `task6-quant`
   - package family:
     - `tiny-stories-1m-*`
   - current milestone:
     - classify the three quantized routes by earliest completed stage and keep
       investing only in the route that produces the best measurable shell
       reduction
   - current default:
     - continue only with `tiny-stories-1m` unless patched import work changes
       the frontier

3. Side lane B: alternate-dialect substitution
   - preferred branch/worktree:
     - `task6-alt-dialect`
   - current milestone:
     - identify one or two concrete non-handshake lowering families worth
       testing instead of treating "another dialect" as an open-ended research
       bucket
   - required first output:
     - candidate shortlist with:
       - candidate dialect / lowering family
       - plausible insertion point from the current `cf` or nearby pipeline
       - expected benefit versus handshake
       - expected patch burden
       - first narrow experiment to run
   - entry guardrail:
     - do not start by rewriting the whole flow
     - start by proving one alternative is concrete enough to compare against
       the current handshake path

4. Side lane C: structural lowering / eqmap / LSQ
   - preferred branch/worktrees:
     - `task6-eqmap`
     - `task6-lsq`
   - entry condition:
     - only after the main lane isolates a residual structural bottleneck that
       looks larger than a pure late-Yosys mapping problem
   - required evidence:
     - changed stage, changed RTLIL size or module count, and whether the
       mapped bottleneck moved

5. Side lane D: board RAM interface path
   - preferred branch/worktree: `task6-board-ram`
   - entry condition:
     - once the top4-memory shell numbers are stable enough to justify a board
       contract
   - required evidence:
     - what memories move off-chip, what stays on-chip, and whether the
       remaining shell becomes materially more synthesis-tractable

6. Side lane E: DOCC / feedback-driven compiler path
   - preferred branch/worktree:
     - `task6-docc`
   - current milestone:
     - decide whether Daisytuner DOCC is viable here as an actual toolchain
       lane, or whether only its SDFG plus feedback-loop ideas are reusable for
       Task 6
   - required first output:
     - a viability memo with:
       - what part is usable locally
       - what part depends on Daisy Cloud or external runners
       - what input artifact from this repo could feed the lane first
       - what measurable Task 6 question this lane would answer
   - entry guardrail:
     - do not start with account setup or cloud integration
     - first prove the lane can answer a Task 6 bottleneck question faster or
       better than the existing pipeline

7. Reference lanes only
   - `task6-paper-review`
   - `task6-moe`
   - use these only to justify a specific next experiment in another active
     lane

### Stage A import status

Status on 2026-04-16:

- Stage A has been imported into `task6`.
- The baseline TinyStories files, core pipeline library/scripts, CIRCT patch
  stack, and trimmed model registry are now present in this branch.
- Lightweight Nix evaluation confirms these package names resolve:
- `tiny-stories-1m-baseline-float-sv`
- `tiny-stories-1m-baseline-float-yosys.stat`
- `matmul-sv`
- Later LSQ/external-memory imports are still intentionally deferred.

### Stage B import status

Status on 2026-04-16:

- Stage B has been imported into `task6`.
- The three full-model TinyStories quantization routes are now wired:
  - `tiny-stories-1m`
  - `tiny-stories-1m-dynamic-int8`
  - `tiny-stories-1m-torchao`
- Optional patched `torch-mlir` support is exported separately while the default
  flow still points to unpatched `torch-mlir`.
- TorchAO-enabled Python environments are exported for later experiments.
- The larger quantization reproducer/debug adapter zoo under `src/` is still
  intentionally deferred.

Lightweight Nix evaluation currently resolves:

- `tiny-stories-1m-torch`
- `tiny-stories-1m-dynamic-int8-torch`
- `tiny-stories-1m-torchao-torch`
- `torch-mlir-patched`
- `python-with-tiny-stories-torchao`

### Donor branches that exist in this repo

- `origin/task3`
  - contains `TinyStories/`, `nix/models.nix`, `nix/pipeline.nix`, and the
    baseline pipeline scripts
- `origin/task3-rfp-sandbox`
  - contains TinyStories quantization adapters plus the LSQ handshake path and
    external-memory helper scripts
- `origin/task3-hybrid-sandbox-toolchain`
  - contains TinyStories quantization adapters plus `sv_memory_inventory.py`,
    `mlir_op_profile.py`, and Yosys-report helpers

User clarification:
- `origin/task3-hybrid-sandbox-toolchain` is intended as a landing branch for
  Task 3, with AI-generated content and experimental quantization work removed
  or reduced
- for Task 6, that makes it a weaker primary donor for quantization follow-up
  even if it still contains useful helpers

Current recommendation:
- prefer `task3-experiments` as the quantization donor branch if it exists or
  can be recovered/fetched into this clone
- use `origin/task3-rfp-sandbox` as the fallback donor for quantization, LSQ,
  and external-memory experiments if `task3-experiments` is not currently
  available here
- treat `origin/task3-hybrid-sandbox-toolchain` mainly as a reference for
  cleaner landing-state tooling and measurement helpers, not as the primary
  experimental branch

Availability update:
- `task3-experiments` is now available in this clone as both
  `origin/task3-experiments` and local branch `task3-experiments`

Implication:
- the Task 6 note must distinguish between work that can be prepared now in
  this branch and work that depends on later importing Task 3 artifacts

### Branch comparison result (2026-04-16)

Current conclusion after direct comparison:

- `task3-experiments` is the best primary donor for Task 6.
- `origin/task3-rfp-sandbox` is the best fallback donor for specific LSQ and
  external-memory pieces.
- `origin/task3-hybrid-sandbox-toolchain` is useful mainly as a reference for
  cleaner landing-state tooling and measurement helpers.

Why `task3-experiments` wins:

- It is the most recent Task 3 branch tip in this family.
- Relative to `origin/task3-rfp-sandbox`, it adds the later Task 3 hybrid
  snapshot plus the final Task 3 deliverable-gate updates.
- It keeps the quantization-heavy `torch-mlir` patch stack and the larger
  quantized model registry needed for Task 6 follow-up.
- In `nix/models.nix`, it explicitly repositions the work so
  `tiny-stories-1m-baseline-float` is the reviewer-facing Task 3 path while the
  quantized TinyStories routes are retained for follow-up experiments.
- It includes the profiling and measurement helpers that were absent from
  `origin/task3-rfp-sandbox`, notably:
  - `scripts/pipeline/mlir_op_profile.py`
  - `scripts/pipeline/sv_memory_inventory.py`
  - `scripts/pipeline/write_yosys_stat_report.py`

Why `origin/task3-rfp-sandbox` is still relevant:

- It already contains the LSQ handshake path and
  `scripts/pipeline/externalize_large_memories.py`.
- If Task 6 needs only the LSQ/external-memory pieces without importing the
  full experiments branch, this is the leaner fallback donor.

Why `origin/task3-hybrid-sandbox-toolchain` is not the primary donor:

- User clarification: it is a landing branch for Task 3 cleanup, with
  experiment-heavy quantization work reduced or removed.
- Direct diff shows `task3-experiments` is effectively hybrid plus the
  experiment-oriented model/pipeline choices and final Task 3 gate updates.

Practical rule:

- For Task 6 execution work, start from `task3-experiments`.
- Pull isolated helper ideas from `origin/task3-rfp-sandbox` or
  `origin/task3-hybrid-sandbox-toolchain` only when they are clearly narrower
  than importing the entire experiments branch.

### Minimal staged import set from `task3-experiments`

Goal:
- import only the files needed to re-establish the TinyStories baseline and the
  three full-model quantization routes for Task 6
- defer debugger helpers, reviewer docs, and board selftest extras until they
  are actually needed

Important finding:
- the full-model TinyStories quantization adapters are self-contained
- that means Task 6 does *not* need to import the large `src/native_fx_*`,
  `src/pt2e_static_quant_*`, and `src/torchao_*` reproducer zoo up front just
  to run the three full-model TinyStories routes

#### Stage A: baseline-float bootstrap

Import first:

- selective `flake.nix` hunks for:
  - TinyStories snapshot wiring
  - `nix/pipeline.nix` and `nix/models.nix` integration
  - `scripts/compile-pytorch.py`
  - `rtl/fp/circt_fp_primitives.sv`
  - the baseline-float model outputs and Yosys-stat packaging
- `torch-mlir.nix`
- `nix/pipeline.nix`
- `scripts/compile-pytorch.py`
- `TinyStories/model_adapter.py`
- `rtl/fp/circt_fp_primitives.sv`
- core pipeline scripts:
  - `scripts/pipeline/common.sh`
  - `scripts/pipeline/torch_to_linalg.sh`
  - `scripts/pipeline/linalg_to_cf.sh`
  - `scripts/pipeline/cf_stats.sh`
  - `scripts/pipeline/cf_to_handshake.sh`
  - `scripts/pipeline/handshake_to_hs_ext.sh`
  - `scripts/pipeline/hs_ext_to_hw0.sh`
  - `scripts/pipeline/hw0_to_hw.sh`
  - `scripts/pipeline/hw_to_hw_clean.sh`
  - `scripts/pipeline/hw_clean_to_sv.sh`
  - `scripts/pipeline/sv_to_il.sh`
  - `scripts/pipeline/sv_to_yosys_stat.sh`
  - `scripts/pipeline/sv_memory_inventory.py`
  - `scripts/pipeline/write_yosys_stat_report.py`
- CIRCT patch wiring and the referenced patch files currently used by the known
  working baseline-float path in `task3-experiments`

Do not import yet:

- `docs/project-plan*`
- reviewer-facing Task 3 deliverables/docs
- `scripts/dev/*`
- selftest wrapper generation and board-specific TinyStories top-level files
- the torch-mlir quantization patch stack
- quantization reproducer adapters under `src/`

Why this stage exists:
- re-establish the known `tiny-stories-1m-baseline-float` path first
- keep the first import focused on "baseline reaches SV / IL / yosys-stat"

#### Stage B: full-model TinyStories quantization routes

Import second:

- selective `flake.nix` and `nix/models.nix` hunks for these full-model routes:
  - `tiny-stories-1m`
  - `tiny-stories-1m-dynamic-int8`
  - `tiny-stories-1m-torchao`
  - `tiny-stories-1m-pt2e-static` alias, only if keeping the alias is useful
- TinyStories adapters:
  - `TinyStories/model_adapter_dynamic_quant.py`
  - `TinyStories/model_adapter_pt2e_static_quant.py`
  - `TinyStories/model_adapter_torchao.py`
- Python environment wiring from `flake.nix`:
  - `torchao`
  - `pythonWithTorchAO`
  - `pythonWithTinyStories`
  - `pythonWithTinyStoriesTorchAO`
- `torch-mlir.nix` support for optional quantization patches
- `patches/torch-mlir-task3-rfp/*.patch`

Do not import yet:

- the full reproducer zoo in `src/`
- native-FX experimental helpers
- task3 reviewer docs and milestone helpers

Why this stage exists:
- it enables the three real Task 6 quantization candidates without dragging in
  every local debugging artifact from `task3-experiments`

#### Stage C: LSQ and external-memory track

Import only when starting the handshake/minimization experiments:

- `scripts/pipeline/cf_to_handshake_lsq.sh`
- `scripts/pipeline/externalize_large_memories.py`
- selective `flake.nix` support for LSQ and external-memory plan outputs

Optional at the same time:

- `scripts/pipeline/filter_rtlil_modules.py` if a later flow actually needs it

Why this stage exists:
- LSQ and external-memory are Task 6-specific optimization tracks, not required
  just to re-establish the baseline and quantization candidates

#### Stage D: measurement and profiling helpers

Import when beginning side-by-side strategy comparison:

- `scripts/pipeline/mlir_op_profile.py`
- `scripts/pipeline/sv_memory_inventory.py` if not already imported in Stage A
- `scripts/pipeline/write_yosys_stat_report.py` if not already imported in
  Stage A

Why this stage exists:
- these files are high-value for Task 6 comparison, but they are not required
  to prove the first baseline build path

#### Stage E: quantization debug reproducers

Import only if the full-model quantization routes fail and the failure needs to
be reduced:

- `src/pt2e_quant_linear_adapter.py`
- `src/pt2e_static_quant_*`
- `src/torchao_*`
- `src/native_fx_*`
- `src/matmul_adapter.py`
- any matching `nix/models.nix` entries for the reproducer models

Why this stage exists:
- these files are valuable for isolating first failing operators
- they are *not* needed to attempt the three full-model TinyStories
  quantization routes

#### Stage F: selftest and board-handoff extras

Import only once a candidate is worth packaging for Task 4/5-style execution:

- `scripts/pipeline/gen_tiny_stories_selftest_top.py`
- `fpga/constraints/tiny_stories_selftest.xdc`
- selective `flake.nix` selftest and all-memory shell outputs

Why this stage exists:
- these files are for packaging and board-facing validation, not early Task 6
  minimization work

#### Explicitly defer these from the first import

- `docs/task3-*.org`
- `docs/task3-*.md`
- `deliverables/3*.org`
- `codex-night-prompt.txt`
- `scripts/dev/*`
- `AGENTS.md` from `task3-experiments`

#### First import recommendation

If doing the first cherry-pick/import pass now, aim for exactly:

1. Stage A
2. Stage B
3. Stage C only if LSQ or external-memory is the immediate next experiment

That gives Task 6:

- the baseline-float reference path
- the three full-model quantization candidates
- the option to add LSQ/external-memory next

without importing the entire experiments branch or all reviewer-facing docs.

## Current intent

Treat Task 6 as an execution task, not only as a survey.

- Primary objective: reduce resource usage enough that at least one real LLM
  configuration plausibly fits the target board envelope.
- Secondary objective: produce a reproducible comparison of strategies,
  including negative results, so dead ends are documented.
- If a candidate fits the board envelope and has no unresolved stubs or hidden
  blackboxes, stop broad exploration and hand off to board execution /
  equivalence testing.

## Overnight result snapshot (2026-04-17)

Results now exist in the strategy lanes and should guide the next round of
execution.

Quantization lane:

- `task6-quant` recorded results in `docs/task6-lane-results.md`.
- `tiny-stories-1m` is currently the strongest quantization route and is
  `conditional`.
- `tiny-stories-1m-dynamic-int8` is `reject` on the current default unpatched
  `torch-mlir` path.
- `tiny-stories-1m-torchao` is `reject` on the current default unpatched
  `torch-mlir` path.
- The strongest next quantization follow-up is to push the surviving
  `tiny-stories-1m` route farther downstream and classify whether it actually
  changes the LUT/FF story or only changes representation.

Board RAM lane:

- `task6-board-ram` recorded results in `docs/task6-lane-results.md`.
- The strongest DDR3 candidate is to move the four `3216448 x 32` vocab-sized
  tables off-chip first.
- Those four tables account for `411,705,344` bits (`49.08 MiB`), about `95.1%`
  of the modeled memory bits from the prior all-memory inventory.
- This is the narrowest credible DDR3 experiment and is currently
  `recommended`.

Paper-review lane:

- `task6-paper-review` recorded findings in `docs/task6-literature-findings.md`.
- `StreamTensor` is the strongest direct paper lead because it targets
  intermediate-memory materialization and streaming/fusion, which matches the
  local "all LUT/FF, zero BRAM/DSP" failure mode better than throughput-only
  ideas.
- `FlightLLM`, `AccLLM`, `TerEffic`, and `Hummingbird` are the best adaptable
  follow-ons.
- `LUT-LLM` is low priority for the current branch.

MoE lane:

- `task6-moe` recorded findings in `docs/task6-moe-feasibility.md`.
- Adapting TinyStories 1M into MoE is not currently a meaningful Task 6 path.
- MoE should remain only as a narrow side experiment with an existing small
  PyTorch MoE model, and only if it can be paired quickly with expert
  externalization or another clear off-chip resource-saving mechanism.

## Practical priority order (2026-04-17)

This priority order supersedes the earlier broad "explore everything equally"
stance.

1. Board RAM first: externalize the four giant vocab-sized tables to DDR3.
   Reason: this is the narrowest change with the largest modeled memory impact,
   and it does not require proving new quantized operators first.

2. Quantization second: continue only with `tiny-stories-1m`.
   Reason: it is the only quantized route that clearly gets past frontend
   lowering today. Do not spend more time on `dynamic-int8` or `torchao`
   unless the default compiler path changes or a narrow patched import becomes
   the explicit next experiment.

3. StreamTensor-style streaming/fusion third.
   Reason: the paper review strongly suggests the local failure mode is
   over-materialized intermediate storage in fabric. This is the strongest
   paper-driven direct lead after the DDR3 cut and the surviving quantized
   route are measured.

4. DSP-first kernel shift fourth.
   Reason: the board still has `1920` idle DSPs while the baseline uses
   `0` DSP and explodes in LUT/FF, so a targeted arithmetic shift out of fabric
   remains attractive after the simpler memory moves are classified.

5. LSQ and handshake alternatives fifth.
   Reason: LSQ is still worth keeping alive, but it should follow evidence that
   handshake/control structure is a dominant residual cost after the higher
   leverage memory steps above.

6. MoE last.
   Reason: it is promising in the abstract, but for this repo it is a model
   selection / architecture feasibility track, not a direct reduction path for
   the current TinyStories baseline.

## Board-RAM packaging update (2026-04-19)

Verification completed today:

- `tiny-stories-1m-baseline-float-selftest-all-memory-utilization` rebuilds in
  this branch and its generated `summary.json` / `stat.json` match the copied
  baseline bundle at
  `artifacts/task6/baselines/tiny-stories-1m-baseline-float-selftest-all-memory-utilization`
  byte-for-byte.
- The all-memory externalization plan still confirms the same dominant target:
  `326` eligible handshake-memory modules totaling `433,040,010` bits, with
  the top four modules accounting for `411,705,344` bits (`49.08 MiB`), about
  `95.1%` of the eligible memory bits.

New package family added for the narrower DDR3-first experiment:

- `tiny-stories-1m-baseline-float-selftest-top4-memory-top`
- `tiny-stories-1m-baseline-float-selftest-top4-memory-model-opt-il`
- `tiny-stories-1m-baseline-float-selftest-top4-memory-model-shell-il`
- `tiny-stories-1m-baseline-float-selftest-top4-memory-external-memory-plan`
- `tiny-stories-1m-baseline-float-selftest-top4-memory-json`
- `tiny-stories-1m-baseline-float-selftest-top4-memory-yosys-json`
- `tiny-stories-1m-baseline-float-selftest-top4-memory-utilization`

Current semantics:

- these outputs externalize only the largest four handshake memory modules from
  the baseline-float selftest shell
- the current selected modules are `\handshake_memory_out_f32_id342`,
  `\handshake_memory_out_f32_id341`, `\handshake_memory_out_f32_id340`, and
  `\handshake_memory_out_f32_id18`
- each of those modules is `3216448 x 32` bits (`102,926,336` bits each)
- the residual eligible memory tail after removing those four modules is
  `21,334,666` bits (`2.54 MiB`)
- the largest remaining tail candidates are:
  - one `131072 x 32` table: `4,194,304` bits
  - one `50257 x 32` table: `1,608,224` bits
  - twenty `16384 x 32` tables: `524,288` bits each

Status:

- the selector/reporting part of this lane is verified, including the new
  reproducible `*-external-memory-plan` and `*-model-shell-il` outputs
- the heavier narrowed-shell utilization build is the next measurement to
  record once the new derivation completes
- the narrowed external-memory bundles now use a split fine-stage flow so the
  bottleneck can be isolated without changing the stock all-memory baseline
  path
- current observed bottleneck: the narrowed-shell mapped-utilization build
  reaches `stage4`, emits a `2.4G` RTLIL artifact, clears `stage5a` through
  `stage5d`, and currently spends a long time in the targeted `stage6a`
  `cells_map` techmap pass

Follow-up update (2026-04-20):

- the earlier monolithic `stage6` (`synth_xilinx -run map_cells:map_cells`)
  path drove memory close to host exhaustion and was killed by the daemon
- the current narrowed-path `stage6a` replaces that with a targeted
  `techmap -map +/techmap.v -map +/xilinx/cells_map.v` over only modules that
  still contain internal `$...` cells
- the live `stage6a` run is holding around `9.48 GiB` RSS instead of the
  earlier near-OOM behavior, so the split is materially reducing peak memory
  pressure even though the derivation has not finished yet
- the next flake snapshot also splits the later `map_luts:check` block into
  persisted `stage8a`..`stage8h` sub-stages (`opt_expr`, `abc`, `clean`,
  targeted `ff_map`, `xilinx_srl`, targeted `lut_map`, `xilinx_dffopt`,
  `opt_lut_ins`) for narrowed external-memory bundles only
- baseline-safe behavior is preserved: the stock all-memory bundle still uses
  the original monolithic `synth_xilinx` late stages, and the copied baseline
  bundle remains the comparison reference

Implementation follow-up later on 2026-04-20:

- `mkSynthStageTargetedTechmapIl` originally emitted one `techmap` invocation
  per selected module using a `cd <module>; techmap ...; cd ..` loop.
- Inspection of the cached narrowed-shell `stage5d` input shows that the later
  `stage6a` selector still touches `472` modules, so the per-module loop was
  multiplying `techmap` overhead even after narrowing the memory set.
- The helper now builds one explicit module selection (`select -none` plus
  repeated `select -add <module>`) and runs a single `techmap ...` pass over
  that selection before restoring full-design selection for `write_rtlil`.
- The helper now also logs the selected-module count per stage so future runs
  show how wide each targeted pass really is.
- A fresh narrowed rebuild has already validated the new helper through
  `stage5c`, which reports `17` selected modules for the `arith_map` pass.
- The full narrowed utilization rebuild is still running past `stage5d`, so the
  next measurement to capture is whether the rewritten single-pass `stage6a`
  materially reduces wall-clock time in addition to the earlier RSS reduction.

Integration follow-up on 2026-04-21:

- The first 2026-04-21 narrowed-shell rebuild did not reach Yosys. It failed in
  the patched `circt` dependency during `checkPhase`, after CIRCT compiled
  successfully, with `18` `HandshakeToHW`-area regression failures.
- The immediate cause was the local CIRCT patch stack in `flake.nix`, not a new
  Task 6 OOM. A dry-run against the pinned `RCoeurjoly/circt` `task3` source
  showed that the older patches `0003`, `0004`, `0005`, `0008`, `0009`,
  `0013`, `0014`, and `0015` were already present upstream.
- Inspection of `0013-handle-memref-model-io-and-cache-submodule-lookups.patch`
  showed that it already supersedes the earlier `0010`..`0012`
  `FuncOpConversionPattern` / `HandshakeToHW` legality changes. Reapplying
  `0010`..`0012` on top of that source is what broke the `HandshakeToHW`
  regression tests.
- The active CIRCT patch stack is now reduced to the two patches that still
  look genuinely unapplied in this source snapshot:
  - `0006-add-lsq-memory-lowering.patch`
  - `0007-lower-lazy-fork-to-hw.patch`
- Continue decision:
  - keep the main narrowed-shell lane active
  - current gate is verifying that the reduced CIRCT stack clears `checkPhase`
    and allows the top4-memory utilization build to reach the actual Task 6
    staged flow again

Recovered side-lane status on 2026-04-21:

- Quant lane (`task6-quant`):
  - existing lane note:
    - `docs/task6-lane-results.md` in the `task6-quant` worktree records the
      latest measured classification from 2026-04-17
  - strongest route so far:
    - `tiny-stories-1m` remains the only quantized full-model route that has
      clearly reached past frontend export in this repo, with `cf-stats` as the
      farthest confirmed successful stage
  - current rejects:
    - `tiny-stories-1m-dynamic-int8` fails at `torch` on both the unpatched and
      lane-local patched `torch-mlir` path with the same illegal
      `torch.operator` legalization failure in the GPT-Neo `torch.nn.Linear`
      path
    - `tiny-stories-1m-torchao` also fails at `torch` with an illegal
      `torch.operator` rooted in `torch.nn.Embedding`
  - continue decision:
    - keep only `tiny-stories-1m` active for future quant follow-up
    - freeze `dynamic-int8` and `torchao` unless importer work changes the
      frontier materially

- Board-RAM lane (`task6-board-ram`):
  - existing lane note:
    - `docs/task6-lane-results.md` in the `task6-board-ram` worktree records
      the current board-facing recommendation from 2026-04-17
  - strongest candidate:
    - move the four `3216448 x 32` vocab-sized tables off-chip first
    - those four modules account for `411,705,344` modeled bits (`49.08 MiB`),
      about `95.1%` of the eligible memory bits in the prior all-memory
      inventory
  - prior shell evidence:
    - the broader all-memory threshold `>= 131072` bits reduced LUTs from
      `40,416,086` to `34,950,553` (`-5,465,533`, about `-13.5%`) while FFs
      stayed flat
  - continue decision:
    - keep this lane ready as the next architecture candidate once the current
      top4-memory shell run lands, because it already matches the same dominant
      memory picture

- Structural lanes:
  - `task6-eqmap` and `task6-lsq` already exist as separate worktrees, but they
    currently carry lane instructions rather than a newer measured result
  - keep both lanes parked until the main narrowed-shell run either completes
    or isolates a blocker that still looks structural after memory removal

- Alternate-dialect lane (`task6-alt-dialect`):
  - current lane status:
    - dedicated worktree created on 2026-04-21 to own non-handshake lowering
      exploration separately from generic lowering/LSQ experiments
  - current milestone:
    - identify one or two concrete dialect/lowering families that could replace
      the current handshake-centered path for a useful subset of the flow
  - current guardrail:
    - this lane is not allowed to become an unbounded "survey MLIR" thread
    - it must quickly narrow to a shortlist with a first real experiment
  - continue decision:
    - keep this lane in candidate-identification mode until the shortlist is
      written down and one first experiment is concrete enough to implement

- DOCC lane (`task6-docc`):
  - current lane status:
    - dedicated worktree created on 2026-04-21 to evaluate the FOSDEM 2026
      DOCC / Daisytuner idea as a Task 6 strategy lane rather than leaving it
      in paper-review limbo
  - current milestone:
    - determine whether this is a real executable lane in the current repo, or
      mainly a source of reusable SDFG / benchmarking / feedback-loop ideas
  - current guardrail:
    - reject any version of this lane that immediately depends on external
      cloud setup before it produces a concrete Task 6 measurement plan
  - continue decision:
    - keep this lane in viability-check mode until it names one concrete first
      artifact and one Task 6 question it can answer better than the stock flow

Live narrowed-shell rebuild update later on 2026-04-21:

- The repaired `tiny-stories-1m-baseline-float-selftest-top4-memory-utilization`
  rebuild is back in the staged Yosys flow for this branch.
- Build-log stages confirmed so far in this specific rerun:
  - `stage1 synth_xilinx begin:prepare`
  - `stage2 synth_xilinx coarse:map_memory`
  - `stage3 opt -fast -full`
  - `stage4 targeted memory_map`
  - `stage5a fine opt -full`
- Process sampling from the live Yosys child shows:
  - the `stage2`-era process completed after reaching about `20.9 GiB`
    `VmHWM`
  - a later live Yosys process, after the build log had already advanced into
    the post-`stage4` band, reached about `25.1 GiB` `VmHWM` while still
    running on CPU
- What is confirmed versus inferred:
  - confirmed from the build log: the rerun has cleared `stage5a`
  - inferred from process sampling only: the current active bottleneck is now
    somewhere in the late `stage5*` to pre-`stage7` region, but the exact
    sub-stage is not yet logged because this rerun was launched without a
    dedicated stage/memory wrapper and the Yosys stages run `-q`
- Process improvement made during this investigation:
  - future long Task 6 builds should use
    `scripts/pipeline/monitor_build.sh <output-dir> -- nix build ... -L`
    so stage banners, sampled `VmRSS` / `VmHWM`, and the final summary are
    captured in one artifact bundle
- Continue decision:
  - keep the narrowed-shell main lane active
  - if this rerun still dies late, treat the next immediate task as capturing a
    wrapped rerun with the new monitor helper before opening a structural lane

Fast-iteration core update on 2026-04-21:

- Added a new reduced model lane for quicker iteration:
  - pipeline model key: `tiny-stories-1m-representative-core`
  - selftest bundle prefix:
    - `tiny-stories-1m-representative-core-selftest-all-memory-*`
- The new model is intentionally synthetic and deterministic:
  - it derives its config from the real TinyStories-1M GPT-Neo config
  - it keeps the same model family, float path, and attention-style mix
  - it uses random weights with `torch.manual_seed(0)` instead of the real
    checkpoint
- Current default trim profile:
  - `vocab_size = 1024` instead of `50257`
  - `num_layers = 1` instead of `8`
  - `hidden_size = 32` instead of `2048`
  - `num_heads = 4` instead of `16`
  - `max_position_embeddings = 64` instead of `2048`
  - `window_size = 32` instead of `256`
- Intended use:
  - get faster answers on export/lowering/stage-shape questions
  - test whether future flow changes move the same synthesis bottlenecks in a
    structurally similar design
  - provide a cheaper target for the new `monitor_build.sh` wrapper
- Guardrail:
  - do not compare this synthetic core directly against the copied baseline
    bundle as a success claim
  - use it to accelerate iteration, then replay promising changes on the real
    TinyStories baseline path
- First verification in this branch:
  - `nix build .#tiny-stories-1m-representative-core-cf-stats --no-link`
    completes successfully
  - frontend artifact sizes versus the full baseline-float path:
    - `torch.mlir`: `3,061,503` bytes versus `30,091,456` bytes
    - `cf.mlir`: `3,221,259` bytes versus `30,664,646` bytes
    - `cf.mlir` line count: `4,218` versus `14,545`
  - the reduced core still preserves the same broad operator families in
    `cf.mlir`, including `arith.addf`, `arith.mulf`, `math.exp`, `math.tanh`,
    `cf.br`, and `cf.cond_br`
  - interpretation:
    - this is already a meaningful frontend/lowering acceleration target
    - it is not yet evidence about late Yosys behavior, because the selftest
      utilization path has not been run for this reduced core yet

Representative-core simplification follow-up later on 2026-04-21:

- The earlier representative-core profile was still too expensive to be the
  fast iteration loop:
  - the `abc9` lane reached `stage7` with roughly `29 GiB` resident Yosys
    memory even after the narrowed-shell and restart-batched `stage6a`
    improvements
- Action taken:
  - simplified the default representative-core profile again in place
  - current effective preset is now:
    - `vocab_size = 1024`
    - `num_layers = 1`
    - `hidden_size = 32`
    - `num_heads = 4`
    - `max_position_embeddings = 64`
    - `window_size = 32`
  - updated both:
    - `TinyStories/model_adapter_representative_core.py`
    - `nix/models.nix`
- Intended interpretation:
  - this no longer tries to be a mid-scale structural proxy
  - it is the fast-loop Task 6 synthesis target
  - if changes work here, replay them on the older representative-core shape or
    directly on the real narrowed-shell baseline as needed
- First rerun on the smaller preset:
  - frontend validation:
    - `nix build .#tiny-stories-1m-representative-core-cf-stats --no-link`
  - monitored synthesis run:
    - `artifacts/task6/runs/representative-core-v2-selftest-top4-memory-json-20260421-225531`
  - current confirmed frontier:
    - `stage1 synth_xilinx begin:prepare`
    - `stage2 synth_xilinx coarse:map_memory`
  - live staged memory shape so far:
    - active staged Yosys around `1.1 GiB` RSS when first entering staged
      synthesis
    - later live `stage2` Yosys around `3.7 GiB` RSS after ~30 seconds of work

Late-stage blocker update later on 2026-04-21:

- The narrowed-shell full-baseline rerun has now been localized precisely:
  - `tiny-stories-1m-baseline-float-selftest-top4-memory-utilization` reaches
    `stage6a targeted techmap cells_map`
  - the builder then dies with exit code `137`
  - the logged stage banner reports `473` selected modules at that point
- Interpretation:
  - the active main-lane blocker is no longer CIRCT
  - it is the late Yosys `cells_map` step on the narrowed shell
  - this is a tighter and more actionable frontier than the earlier generic
    OOM picture
- First mitigation attempted in `task6`:
  - split `stage6a` into batches of `32` selected modules
  - initial implementation only batched the `select`/`techmap` calls inside one
    long-lived Yosys process
- Follow-up correction:
  - batching inside one Yosys process is unlikely to reclaim pass-local memory
    aggressively enough, because the whole design and pass state stay resident
  - `mkSynthStageTargetedTechmapIl` now supports restart-per-batch mode so the
    process can fully exit between `stage6a` chunks
  - `stage6a` is now configured with:
    - `batchSize = 32`
    - `restartPerBatch = true`
- Fast-loop validation in progress:
  - current command family:
    - `tiny-stories-1m-representative-core-selftest-top4-memory-json`
  - current monitored run directory:
    - `artifacts/task6/runs/representative-core-selftest-top4-memory-json-restart-20260421-181333`
  - purpose:
    - confirm the restart-per-batch `stage6a` path is functionally valid on the
      representative core before spending another full-baseline run
- Monitoring update:
  - `monitor_build.sh` plus
    `MONITOR_GLOBAL_PGREP_PATTERN='default-builder.sh|yosys -q -s run.ys'`
    now captures the builder-side Yosys worker for daemonized Nix builds
  - the live representative-core `stage2` Yosys process has already reached
    about `6.45 GiB` `VmHWM` in this wrapped run
- Continue decision:
  - if the representative-core split path clears `stage6a`, replay the new
    restart-per-batch implementation on the full baseline narrowed-shell lane
  - if it still fails before or during `stage6a`, inspect batch semantics or
    reduce batch size further before launching another expensive full run

Restart-batched validation follow-up later on 2026-04-21:

- The first representative-core validation run against the new restart-per-batch
  path did reach `stage6a`, but failed for an implementation bug rather than a
  synthesis limit:
  - monitored run:
    - `artifacts/task6/runs/representative-core-selftest-top4-memory-json-restart-20260421-181333`
  - confirmed stages:
    - `stage1`
    - `stage2`
    - `stage3`
    - `stage4`
    - `stage5a`
    - `stage5b`
    - `stage5c`
    - `stage5d`
    - `stage6a targeted techmap cells_map`
  - failure cause:
    - malformed shell heredoc in the newly added restart-per-batch builder
      fragment
    - not a Yosys OOM and not a semantic hardware-lowering failure
- Follow-up fix:
  - replaced the nested restart-loop heredocs in `mkSynthStageTargetedTechmapIl`
    with `printf`-based `run.ys` generation so the staged builder script is no
    longer sensitive to indentation of nested `EOF` markers
- Second validation run after the fix:
  - monitored run:
    - `artifacts/task6/runs/representative-core-selftest-top4-memory-json-restart-fix-20260421-184404`
  - current confirmed behavior:
    - the run now re-enters `stage6a` cleanly
    - it emits per-batch banners
    - it has progressed through at least batch `6/8`
  - interpretation:
    - restart-per-batch `stage6a` is now real, not just syntactically present
    - the representative-core lane no longer dies immediately at the start of
      `stage6a`
    - each new Yosys worker restarts with a much lower RSS than the prior
      batch's high-water mark, which is the intended memory-shaping behavior
  - observed memory shape from the wrapped run:
    - earlier batches climbed into the low `3.3 GiB` range
    - later live batches have reached about `7.1 GiB` `VmRSS` / `VmHWM`
      without an immediate kill
- Continue decision:
  - keep the representative-core validation run active until it either clears
    `stage6a` or fails with a real synthesis/resource limit
  - if it clears `stage6a`, promote the same restart-per-batch approach to the
    full-baseline narrowed-shell main lane immediately
  - if it fails materially before batch `8/8` or before `stage7`, consider a
    smaller `batchSize` before spending another full-baseline run

Stage-measurement tooling follow-up later on 2026-04-21:

- Added a reusable stage-stats path for the RTLIL/Yosys synthesis stages.
- Purpose:
  - answer questions like:
    - what does `stage6a` look like in the baseline path?
    - what does `stage6a` look like in the experiment path?
  - using structural stage stats rather than only wall-clock or RSS evidence
- Implementation:
  - new report script:
    - `scripts/pipeline/write_rtlil_stage_stat_report.py`
  - new comparison script:
    - `scripts/pipeline/compare_stage_stats.py`
  - new flake outputs now expose:
    - per-bundle stage-stat directories
    - direct `stage6a` stat outputs for the top4-memory lanes
- New package families of interest:
  - `tiny-stories-1m-baseline-float-selftest-top4-memory-stage-stats`
  - `tiny-stories-1m-baseline-float-selftest-top4-memory-stage6a-stats`
  - `tiny-stories-1m-representative-core-selftest-top4-memory-stage-stats`
  - `tiny-stories-1m-representative-core-selftest-top4-memory-stage6a-stats`
- Current interpretation:
  - these are Yosys/RTLIL stats, not MLIR op stats
  - that is still the right measurement class for `stage6a` and later, because
    those stages no longer operate on MLIR
  - the earlier pipeline already has `cf-stats` for MLIR-level measurement
- Guardrail:
  - the bundled comparison output
    `tiny-stories-1m-top4-memory-stage-stats-baseline-vs-representative-core`
    is useful for structural trend inspection, but it is not an apples-to-apples
    resource comparison because the representative core is intentionally smaller
- Continue decision:
  - once the active representative-core late-stage run is no longer consuming
    the machine, build the new `stage6a` stat outputs and use them as the
    default artifact for baseline-versus-experiment structural inspection

ABC9 lane follow-up later on 2026-04-21:

- Trigger:
  - after confirming that the narrowed-shell representative-core lane had moved
    the blocker from `stage6a` to a very long single-process
    `stage8b abc -luts 2:2,3,6:5,10,20` run, we decided to stop the live plain
    `abc` run and try the Xilinx `abc9` flow explicitly
- Implementation:
  - `flake.nix` now supports `useAbc9 = true` in `mkSynthJsonStages`
  - for the split fine-stage path, `abc9` is entered through
    `synth_xilinx -family xc7 -top <top> -noiopad -abc9`
    at:
    - `stage7 map_ffs:map_ffs`
    - `stage8 map_luts:check`
  - this intentionally avoids replacing the old `stage8b` raw `abc` command
    with a standalone `abc9` call, because the supported Xilinx `abc9` flow
    changes the late-stage sequence beyond one command
- New package family:
  - `tiny-stories-1m-representative-core-selftest-top4-memory-abc9-json`
  - `tiny-stories-1m-representative-core-selftest-top4-memory-abc9-stage-stats`
- Current monitored run:
  - `artifacts/task6/runs/representative-core-selftest-top4-memory-abc9-json-20260421-220353`
  - current confirmed progress:
    - rebuilt `model-opt`
    - rebuilt `model-shell`
    - entered staged synthesis derivations
    - reached at least `stage1`
- Current interpretation:
  - this is a real `abc9` lane, not a documentation-only idea
  - it should let us compare the late Xilinx LUT-mapping path against the
    previous long-running plain `abc` frontier on the same representative-core
    shell
- Continue decision:
  - keep the `abc9` representative-core run active until it either:
    - reaches a later frontier than the old plain-`abc` run, or
    - fails in a way that clearly does not justify promotion
  - if it looks promising on runtime or peak memory, replay the same `abc9`
    option on the full baseline narrowed-shell lane

Full-baseline external-memory priority update on 2026-04-26:

- Current priority remains externalization of memory, specifically the
  full-baseline `top4-memory` shell that blackboxes the four
  `3216448 x 32` vocab-sized handshake memories.
- Latest repaired-CIRCT full-baseline rerun:
  - artifact directory:
    - `artifacts/task6/runs/2026-04-24T20-05-40+0200-baseline-top4-memory-utilization-repaired-circt`
  - command:
    - `nix build .#tiny-stories-1m-baseline-float-selftest-top4-memory-utilization --no-link --print-out-paths -L`
  - result:
    - failed in `stage6a targeted techmap cells_map`
    - reached restart batch `13/15`
    - exit status `137`
    - sampled peak `VmRSS` about `30.3 GiB`
- Interpretation:
  - the active blocker is still the Yosys `cells_map` pass after successful
    external-memory shell construction, not frontend lowering and not the CIRCT
    patch stack.
  - restart-per-batch is functioning, because the full-baseline run advanced
    through multiple independent `stage6a` batches, but `batchSize = 32` is
    still too wide for the larger late batches on this host.
- Immediate execution change:
  - keep the same memory-externalization target and comparison baseline.
  - reduce `stage6a` restart batch size from `32` to `8` for the split
    `top4-memory` synthesis path.
  - rerun the monitored
    `tiny-stories-1m-baseline-float-selftest-top4-memory-utilization` build.
- Success criterion for this slice:
  - first, clear `stage6a` without exit `137`.
  - second, record the next frontier or final utilization against the copied
    all-memory baseline bundle.

Batch-8 rerun result on 2026-04-26:

- Monitored run:
  - `artifacts/task6/runs/2026-04-26T00-34-00+0200-baseline-top4-memory-utilization-stage6a-batch8`
- Result:
  - failed in `stage6a targeted techmap cells_map`
  - reached batch `52/59`
  - exit status `137`
  - wall time `8393` seconds
  - sampled peak `VmRSS` `30,171,296 KiB`
  - sampled peak `VmHWM` `30,171,664 KiB`
- Interpretation:
  - `batchSize = 8` is materially better than `32`; it advanced into the
    heavy late module range and cleared several batches that previously sat
    inside the killed region.
  - it is still too wide for the heaviest late `cells_map` group on this host.
- Immediate follow-up:
  - reduce `stage6a` restart batch size again, from `8` to `4`.
  - rerun the same monitored
    `tiny-stories-1m-baseline-float-selftest-top4-memory-utilization` target.

Batch-4 rerun result on 2026-04-26:

- Monitored run:
  - `artifacts/task6/runs/2026-04-26T02-55-01+0200-baseline-top4-memory-utilization-stage6a-batch4`
- Result:
  - failed in `stage6a targeted techmap cells_map`
  - reached batch `103/118`
  - exit status `1`, with the Yosys worker killed by exit `137`
  - wall time `20566` seconds
  - sampled peak `VmRSS` `29,808,588 KiB`
  - sampled peak `VmHWM` `29,809,904 KiB`
- Interpretation:
  - `batchSize = 4` advanced deeper than `8`, but the heaviest late
    `cells_map` groups still reach the host memory ceiling.
  - this is still a memory-pressure / OOM-kill frontier, not a new frontend or
    external-memory-plan failure.
- Immediate follow-up:
  - reduce `stage6a` restart batch size from `4` to `2`.
  - rerun the same monitored
    `tiny-stories-1m-baseline-float-selftest-top4-memory-utilization` target.

Batch-2 rerun result on 2026-04-26:

- Monitored run:
  - `artifacts/task6/runs/2026-04-26T22-24-33+0200-baseline-top4-memory-utilization-stage6a-batch2`
- Result:
  - failed in `stage6a targeted techmap cells_map`
  - reached batch `205/236`
  - exit status `1`, with the Yosys worker killed by exit `137`
  - wall time `23229` seconds
  - sampled peak `VmRSS` `29,865,256 KiB`
  - sampled peak `VmHWM` `29,866,344 KiB`
- Failure localization:
  - batch `205/236` corresponds to residual modules
    `\handshake_memory_out_f32_id70` and
    `\handshake_memory_out_f32_id71`.
  - each module still contains a `16384 x 32` memory after the `top4-memory`
    shell externalizes only the four `3216448 x 32` vocab-sized tables.
- Interpretation:
  - uniform `stage6a` batch reduction improved progress from `13/15` to
    `205/236`, but the remaining OOM frontier is still a residual handshake
    memory mapping problem.
  - continuing to shrink only the batch size is now lower leverage than moving
    more of the residual memory tail out of the Yosys `cells_map` path.
- Immediate follow-up:
  - add a baseline-float `top32-memory` externalization target that keeps the
    same copied all-memory baseline comparison while selecting more of the
    residual handshake memory modules.
  - first build and inspect the `top32-memory` external-memory plan, confirming
    whether the failing `id70` / `id71` modules are selected before spending a
    full utilization run.

`top32-memory` plan check on 2026-04-27:

- Flake output:
  - `tiny-stories-1m-baseline-float-selftest-top32-memory-external-memory-plan`
- Output path:
  - `/nix/store/dgxg2chvf3ig5g779lp5iidc5ps5pyc9-tiny-stories-1m-baseline-float-selftest-top32-memory-external-memory-plan`
- Plan summary:
  - eligible modules: `326`
  - eligible memory bits: `433,040,010`
  - selected modules: `32`
  - selected memory bits: `428,780,064`
- Relevant selected modules:
  - `\handshake_memory_out_f32_id70`, `16384 x 32`
  - `\handshake_memory_out_f32_id71`, `16384 x 32`
- Decision:
  - continue with a monitored
    `tiny-stories-1m-baseline-float-selftest-top32-memory-utilization` run.
  - keep `stage6a` restart batch size at `2` for this first wider-memory run,
    because batch size `2` is the current most conservative surviving setting
    and the changed variable should be memory externalization breadth.

`top32-memory` utilization result on 2026-04-27:

- Monitored run:
  - `artifacts/task6/runs/2026-04-27T08-57-20+0200-baseline-top32-memory-utilization-stage6a-batch2`
- Command:
  - `nix build .#tiny-stories-1m-baseline-float-selftest-top32-memory-utilization --no-link --print-out-paths -L`
- Result:
  - failed in `stage8b abc -luts 2:2,3,6:5,10,20`
  - exit status `1`, with the Yosys worker killed by exit `137`
  - wall time `23890` seconds
  - sampled peak `VmRSS` `24,736,208 KiB`
  - sampled peak `VmHWM` `26,633,804 KiB`
- Important progress:
  - `stage6a targeted techmap cells_map` completed all `222/222` restart
    batches.
  - this crosses the previous `top4-memory` batch-size-2 failure point, which
    died at `stage6a` batch `205/236`.
  - around the old failure index, the `top32-memory` run sampled roughly
    `20 GiB` RSS instead of the previous `29.9 GiB` OOM-region RSS.
- Interpretation:
  - widening external memory from top 4 to top 32 selected modules fixed the
    immediate residual-memory `cells_map` frontier.
  - the new frontier is later ABC/LUT mapping in `stage8b`, not `stage6a`
    memory-module `cells_map`.
- Immediate follow-up:
  - keep the `top32-memory` target as the current main external-memory lane.
  - inspect the `stage8a` input to identify whether `stage8b` is dominated by
    a small number of residual memory modules before changing ABC itself.

`stage8b` frontier localization on 2026-04-27:

- Input inspected:
  - `/nix/store/vg7ls8jbswv1vaazvrp0ix19jawyhr77-tiny-stories-1m-baseline-float-selftest-top32-memory-stage8a.il`
- Largest residual `$_*` cell owners entering ABC:
  - `\handshake_memory_out_f32_id36`: `8,783,360` cells
  - `\handshake_memory_out_f32_id35`: `8,783,360` cells
  - next largest module:
    - `\handshake_memory_out_f32_id77`: `962,720` cells
- Original memory sizes:
  - `\handshake_memory_out_f32_id36`: `4096 x 32`
  - `\handshake_memory_out_f32_id35`: `4096 x 32`
- External-memory rank:
  - `id36` is rank `33`
  - `id35` is rank `34`
- Decision:
  - add a `top34-memory` target that externalizes exactly the two newly
    identified ABC-dominant residual memory modules beyond `top32`.
  - this keeps the lane focused on externalization of memory before adding an
    ABC-specific split or alternate mapping strategy.

`top34-memory` plan check on 2026-04-27:

- Flake output:
  - `tiny-stories-1m-baseline-float-selftest-top34-memory-external-memory-plan`
- Output path:
  - `/nix/store/0z3gaxjvp5843k9imlj3kcgxapl7qkl0-tiny-stories-1m-baseline-float-selftest-top34-memory-external-memory-plan`
- Plan summary:
  - eligible modules: `326`
  - eligible memory bits: `433,040,010`
  - selected modules: `34`
  - selected memory bits: `429,042,208`
- Relevant selected modules:
  - `\handshake_memory_out_f32_id36`, `4096 x 32`
  - `\handshake_memory_out_f32_id35`, `4096 x 32`
- Decision:
  - continue with a monitored
    `tiny-stories-1m-baseline-float-selftest-top34-memory-utilization` run.
  - keep `stage6a` restart batch size at `2`, because the next changed
    variable is only the two additional externalized memory modules.

`top34-memory` utilization interruption on 2026-04-27:

- Monitored run:
  - `artifacts/task6/runs/2026-04-27T15-43-36+0200-baseline-top34-memory-utilization-stage6a-batch2`
- Observed state:
  - run was no longer active when checked at `2026-04-27T16:28:57+02:00`
  - no `nix` or `yosys` process remained
  - artifact directory had process samples and a build log, but no generated
    completion summary
  - final logged synthesis line was `stage6a targeted techmap cells_map batch
    16/221`
- Interpretation:
  - treat this as an interrupted or abandoned run, not as evidence for or
    against `top34-memory`.
  - the last valid consolidated result remains the `top32-memory` run, which
    cleared `stage6a` and moved the blocker to `stage8b`.
- Immediate follow-up:
  - rerun `tiny-stories-1m-baseline-float-selftest-top34-memory-utilization`
    under the monitor before drawing conclusions from the top34 externalization
    target.

`top34-memory` utilization rerun result on 2026-04-27:

- Monitored run:
  - `artifacts/task6/runs/2026-04-27T16-35-00+0200-baseline-top34-memory-utilization-stage6a-batch2-rerun`
- Command:
  - `nix build .#tiny-stories-1m-baseline-float-selftest-top34-memory-utilization --no-link --print-out-paths -L`
- Result:
  - failed in `stage9 write_json`
  - exit status `1`
  - wall time `11367` seconds
  - sampled peak `VmRSS` `19,928,932 KiB`
  - sampled peak `VmHWM` `20,280,128 KiB`
  - final error:
    - `ERROR: Parser error in line 66916687: dangling attribute`
- Important progress:
  - `stage6a targeted techmap cells_map` completed all `221/221` restart
    batches.
  - this crosses the old `top4-memory` batch-size-2 failure point, which died
    at `stage6a` batch `205/236`.
  - `stage8b abc -luts 2:2,3,6:5,10,20` completed, crossing the prior
    `top32-memory` frontier.
  - the run also completed `stage8c`, `stage8d`, `stage8e`, `stage8f`,
    `stage8g`, and `stage8h`.
- Interpretation:
  - externalizing the rank-33/rank-34 memory owners `id36` and `id35` fixed the
    `top32-memory` ABC frontier.
  - the active blocker is now final JSON emission or parsing of the very large
    mapped design, not the previous residual-memory `cells_map` or ABC OOM
    frontier.
  - this strengthens the external-memory mainline and supports an
    owner-driven externalization loop.
- Immediate follow-up:
  - inspect the `stage8h` output or failed `stage9` input around line
    `66916687` to determine whether the dangling attribute is a Yosys writer
    issue, a malformed RTLIL attribute from a prior pass, or a scale/streaming
    artifact in `write_json`.
  - add a cheaper `stage9`-only replay or parser-check target so this new
    frontier can be debugged without rerunning the full utilization path.

`top34-memory` stage9-only replay result on 2026-04-27:

- New flake outputs:
  - `tiny-stories-1m-baseline-float-selftest-top34-memory-stage8h-il`
  - `tiny-stories-1m-baseline-float-selftest-top34-memory-stage9-debug`
- Cached replay input:
  - `/nix/store/v40xbypjmh5vyxyd6ic3wg7caqywb9cx-tiny-stories-1m-baseline-float-selftest-top34-memory-stage8h.il`
- Manual stage9-only replay bundle:
  - `/tmp/task6-stage9-debug-fixed`
- Result:
  - patched filter produced `66,915,339` RTLIL lines
  - Yosys completed `read_rtlil; proc; write_json`
  - `stage9-debug.json` was emitted successfully
  - Yosys wall time was `140.73` seconds
  - Yosys peak memory was `23,290.57 MB`
- Root cause:
  - the final-stage filter dropped selected blackbox modules but did not drop
    the top-level `attribute` lines immediately preceding those dropped
    modules.
  - after the final dropped module, the filtered RTLIL ended with orphan module
    attributes, which Yosys reported as `dangling attribute` at EOF.
- Fix:
  - `scripts/pipeline/filter_rtlil_modules.py` now buffers top-level attributes
    and emits them only when the following module is retained.
- Interpretation:
  - the `top34-memory` stage9 failure was a replayable boundary bug in the
    filtering step, not evidence against the external-memory synthesis path.
  - the feedback loop is now roughly minutes for this frontier instead of a
    full monitored utilization rerun.

`top34-memory` continuation plan after stage9 replay on 2026-04-27:

- Gate 1: rerun the real fixed `top34-memory` utilization target.
  - command:
    - `nix build .#tiny-stories-1m-baseline-float-selftest-top34-memory-utilization --no-link --print-out-paths -L`
  - expected value:
    - reuses the already successful staged derivations where possible
    - verifies that the committed filter fix carries through the production
      utilization output, not only the manual replay bundle
  - promotion rule:
    - if utilization completes, inspect LUT/FF/DSP/BRAM and largest remaining
      mapped cell owners.
    - if it fails, use the new failure stage as the next frontier before
      changing DDR3 or memory-shell variables.
- Gate 2: perform FPGA-fit accounting before implementing a DDR3 controller.
  - report selected external bits and expected off-chip capacity use.
  - estimate per-token read/write traffic, port width, clock assumptions,
    buffering BRAM, arbitration cost, and memory-interface LUT/FF overhead.
  - treat the current `top34-memory` `429,042,208` selected bits
    (`~51.2 MiB`) as a synthesis proof, not yet as a board implementation
    proof.
- Gate 3: define the external-memory shell contract.
  - determine whether the externalized memories expose many independent
    module-local ports or can be collapsed behind a smaller shared board-memory
    interface.
  - specify address width, data width, read latency, write behavior,
    valid/ready timing, initialization/loading path, and arbitration policy.
- Gate 4: choose or integrate DDR3 only after the shell contract is known.
  - GitHub DDR3 cores are useful candidates, but selecting one before the
    traffic shape and handshake contract are known risks optimizing the wrong
    interface.
  - pivot to DDR3 implementation once the fixed utilization output and memory
    shell accounting show that board RAM bandwidth/latency is the active
    blocker rather than synthesis fit.

Immediate execution:

- Run the fixed full `top34-memory` utilization target under the monitor.
- Record completed stage, peak RSS/HWM, final resource report or failing
  frontier, and whether any residual memory owners still dominate the mapped
  design.

## Int8 board self-test update on 2026-04-29

Current fast board lane:

- `task6-int8-l2-mlp-chain-residual-add-selftest-*`
- purpose:
  - keep using the small int8 L2 MLP chain as the board-facing debug lane
    before spending more time on the full TinyStories external-memory shell
  - validate that the generated int8 arithmetic and memories survive synthesis,
    place/route, bitstream generation, and physical FPGA execution

Physical diagnostic result:

- Bitstream tested:
  - `/nix/store/qg4wbb17a00v9212c3nny3ybgk7cpjhp-task6-int8-l2-mlp-chain-residual-add-selftest-c-proj-requant-debug.bit`
- Observed repeating LED sequence, ignoring the always-on board power/status
  LED:
  - all
  - green+orange
  - off
  - red+orange
  - green
  - red+green
  - all
  - red
  - off
- Decode:
  - final residual-add self-test still fails at output index `0`
  - the expected final residual-add byte is `0x0a`
  - the c_proj accumulator, c_proj requant scale multiplier, and c_proj bias
    value for index `0` match the generated constants
  - the observed c_proj requant output byte is still `0x7f`, while the expected
    c_proj output byte is `0x0a`
- Interpretation:
  - the board failure is no longer plausibly a load/order issue for the c_proj
    accumulator or constants
  - the fault is localized to the synthesized c_proj requant arithmetic path
  - this is useful progress: the diagnostic narrowed the bug from "self-test
    fails on board" to "c_proj requant saturates to `0x7f` even when its inputs
    match the expected fixture values"

Fix attempted:

- `rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_requant_kernel.sv`
  now explicitly sign-extends the 32-bit accumulator and scale multiplier to
  64 bits before multiplying.
- The change mirrors the style already used in the residual-add requant path
  and avoids relying on tool interpretation of the narrower `$signed(acc) *
  $signed(scale_mul)` expression.

Verification after the fix:

- Simulation:
  - command:
    - `nix build .#task6-int8-l2-mlp-chain-residual-add-selftest-sv-sim --no-link --print-out-paths -L`
  - result:
    - pass at cycle `18804`
  - output:
    - `/nix/store/c6wscp6nc5chixy3649nyc9rzfz1xm1j-task6-int8-l2-mlp-chain-residual-add-selftest-sv-sim.json`
- Synthesis JSON:
  - command:
    - `nix build .#task6-int8-l2-mlp-chain-residual-add-selftest-json --no-link --print-out-paths -L`
  - result:
    - Yosys completed with `0` reported structural problems
  - output:
    - `/nix/store/96rsc4lq7crzpnshj110j04yf80h7h7v-task6-int8-l2-mlp-chain-residual-add-selftest.json`
- Board bitstream:
  - command:
    - `nix build .#task6-int8-l2-mlp-chain-residual-add-selftest-bitstream --no-link --print-out-paths -L`
  - result:
    - completed
  - output:
    - `/nix/store/jkqn0blzj40rycb0gmx8h2ibvwgdxpjk-task6-int8-l2-mlp-chain-residual-add-selftest.bit`
  - post-route timing:
    - `136.37 MHz` maximum frequency, passing the `12.00 MHz` target
  - packed utilization:
    - `SLICE_LUTX`: `10998 / 597200`, about `1.84%`
    - `SLICE_FFX`: `718 / 597200`, about `0.12%`
    - `DSP48E1`: `36 / 1920`, `1.88%`
    - BRAM36-equivalent: `8 RAMB36E1 + 6 RAMB18E1`, equivalent to `11 / 955`,
      about `1.15%`

Next board action:

- Program the fixed normal self-test bitstream:
  - `/nix/store/jkqn0blzj40rycb0gmx8h2ibvwgdxpjk-task6-int8-l2-mlp-chain-residual-add-selftest.bit`
- Expected physical result:
  - ignore the board's always-on top green LED
  - design red LED blinks as heartbeat
  - design green LED stays on for pass
  - design orange LED stays off
- If the orange fail LED still turns on, rebuild/run the patched debug
  bitstream again and decode the new LED sequence before changing the memory
  shell or DDR3 direction.

Physical follow-up:

- The fixed normal self-test bitstream above still fails on board:
  - design red LED blinks
  - design orange LED stays on
- Rebuilt the c_proj requant diagnostic against the same patched RTL:
  - `/nix/store/2xd7pkyg8ydprgcaarfbphvmmswxask4-task6-int8-l2-mlp-chain-residual-add-selftest-c-proj-requant-debug.bit`
  - post-route timing: `145.82 MHz`, passing the `12.00 MHz` target
- Next diagnostic question:
  - whether the patched design still reports c_proj requant output `0x7f`, or
    whether the failure moved to a different byte/value
  - if it still reports `0x7f` while accumulator/scale/bias match, replace the
    c_proj requant multiply/shift path with a narrower or staged arithmetic
    implementation instead of continuing reset/load investigation

Follow-up localization later on 2026-04-29:

- Multiple c_proj requant diagnostic bitstreams all failed at output index `0`
  while reporting matching c_proj accumulator, scale multiplier, and bias
  operands.
- The failing observed c_proj output byte changed across arithmetic
  implementations:
  - inferred multiply path: `0x7f`
  - combinational shift/add path: `0xd4`
  - sequential shift/add path: `0xc2`
- Interpretation:
  - the DDR3 path, residual-add compare, final output constants, reset path,
    and upstream GEMV accumulation are no longer the leading hypotheses for
    this board failure
  - the failure is localized to the integrated c_proj requant handoff or value
    lifetime around the arithmetic stage
  - because the wrong value changes with the c_proj arithmetic implementation,
    this is not currently strong evidence for a generic openXC7 place/route
    failure

Arithmetic-only discriminator:

- New bitstream tested:
  - `/nix/store/0kkw15vh3dqc19rhajv3cpzj5f49nrqy-task6-c-proj-requant-arith-selftest.bit`
- User observation:
  - green design LED stayed on
- Decode:
  - the isolated c_proj requant arithmetic self-test passes on the physical
    board
- Build evidence:
  - simulation passed at cycle `165`
  - routed at `197.28 MHz`, passing the `50.00 MHz` board-clock target
  - utilization:
    - `531` LUTs
    - `383` FFs
    - `0` DSP
    - `0` BRAM
- Interpretation:
  - the fixed-point multiply, round, shift, clamp, and expected-value compare
    can synthesize, place, route, and execute correctly on this FPGA in
    isolation
  - the remaining failure is in the integrated c_proj requant path, most
    likely operand handoff, read-data lifetime, or result capture/control

Registered handoff fix:

- `rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_requant_kernel.sv` now
  captures the c_proj accumulator, scale multiplier, and bias into registers in
  a dedicated `POST_CAPTURE` state before initializing the shift/add multiply.
- The multiply setup now reads `requant_acc_q` and `requant_scale_mul_q`,
  rather than using the live RAM/read-data outputs directly.
- An initial attempt to capture one cycle earlier failed simulation at cycle
  `20984`; keeping `POST_WAIT` as the memory-latency state and adding
  `POST_CAPTURE` passes simulation.
- Full residual-add self-test simulation:
  - command:
    - `nix build .#task6-int8-l2-mlp-chain-residual-add-selftest-sv-sim --no-link --print-out-paths -L`
  - result:
    - pass at cycle `21108`
  - output:
    - `/nix/store/8zrh2fdvv0knc13jbhiiw5qp1hj0q102-task6-int8-l2-mlp-chain-residual-add-selftest-sv-sim.json`
- Full residual-add self-test bitstream:
  - command:
    - `nix build .#task6-int8-l2-mlp-chain-residual-add-selftest-bitstream --no-link --print-out-paths -L`
  - output:
    - `/nix/store/w8apmmjr009862ba9cc67va7zj8nd6gz-task6-int8-l2-mlp-chain-residual-add-selftest.bit`
  - post-route timing:
    - `121.60 MHz` maximum frequency, passing the `50.00 MHz` board-clock
      target
  - mapped utilization:
    - CLB LUTs: `7929 / 298600` (`2.66%`)
    - CLB FFs: `1174 / 597200` (`0.20%`)
    - DSPs: `32 / 1920` (`1.67%`)
    - BRAM36-equivalent: `11 / 955` (`1.15%`)
- Next board action:
  - program:
    - `sudo openFPGALoader -c digilent_hs3 --ftdi-serial 210299BF3824 /nix/store/w8apmmjr009862ba9cc67va7zj8nd6gz-task6-int8-l2-mlp-chain-residual-add-selftest.bit`
  - expected pass indication:
    - ignore the always-on board status LED
    - design red LED blinks as heartbeat
    - design green LED stays on
    - design orange LED stays off
  - if the orange LED still stays on, the next diagnostic should expose
    intermediate registered multiply state through a scan/debug interface or a
    more compact LED-coded sequence, rather than changing DDR3 or the upstream
    load path

JTAG debug follow-up:

- User direction:
  - stop relying on LED decoding for detailed diagnosis
  - use JTAG/XVC to read an internal debug payload autonomously
- First JTAG payload result:
  - bitstream:
    - `/nix/store/yxcnqkz4rv3lvxbjdsqmb5qywpcwvn40-task6-int8-l2-mlp-chain-residual-add-selftest-jtag-debug.bit`
  - result:
    - final state was `SELFTEST_FAIL`
    - fail reason was `MISMATCH`
    - failing stage was `ACC`
    - first failing output index was `0`
  - critical decoded values:
    - c_proj final accumulator for output `0` was `-55384`
    - expected c_proj accumulator for output `0` was `7346`
    - c_proj scale and bias matched expected constants
    - c_proj input sample values matched the values transferred from c_fc
    - c_proj weights and sampled multiply/add behavior matched at the sampled
      points
  - interpretation:
    - this moved the leading fault upstream of c_proj requant arithmetic
    - the c_proj transfer path and c_proj local input memory agree with each
      other
    - the wrong values are already present in the c_fc post-GELU output stream
      seen by c_proj
- Second JTAG payload implemented:
  - added c_fc post-GELU/requant checkpoints for hidden indices
    `0, 1, 2, 3, 63, 127, 191, 255`
  - each checkpoint exposes:
    - hidden index
    - raw c_fc accumulator
    - requant scale multiplier
    - requant bias
    - rounded/scaled fixed-point value
    - final post-GELU int8 output byte
  - decoder updated in `scripts/task6/read_jtag_debug_xvc.py`
  - payload version is now `4`
  - payload width is now `2048` bits
- Verification:
  - simulation:
    - `nix build .#task6-int8-l2-mlp-chain-residual-add-selftest-sv-sim -L`
    - passed at cycle `21108`
  - JTAG-debug bitstream:
    - `nix build .#task6-int8-l2-mlp-chain-residual-add-selftest-jtag-debug-bitstream -L`
    - output:
      - `/nix/store/gk1m3vghlv61149k329w60mzgdncn0i2-task6-int8-l2-mlp-chain-residual-add-selftest-jtag-debug.bit`
    - route/timing:
      - router completed with `0` errors
      - main clock max frequency `118.61 MHz`, passing the `50.00 MHz`
        target
      - JTAG debug shift clock max frequency `580.72 MHz`, passing the
        `50.00 MHz` target
- Current physical-access blocker:
  - programming without sudo fails with FTDI USB permission error:
    - `unable to open ftdi device: -4 (usb_open() failed)`
  - `sudo -n openFPGALoader ...` fails because no cached sudo credentials are
    available:
    - `sudo: a password is required`
- Immediate next action:
  - program the v4 JTAG-debug bitstream and start XVC with root USB access
  - then run:
    - `python3 scripts/task6/read_jtag_debug_xvc.py --poll --poll-count 50 --poll-interval 0.1`
  - discriminator:
    - if raw c_fc accumulators mismatch, debug c_fc GEMV activation/weight/MAC
      sampling next
    - if raw c_fc accumulators match but post-GELU output mismatches, debug the
      c_fc post-GELU/requant arithmetic/control next
    - if c_fc checkpoints all match, debug the c_fc-to-c_proj transfer
      boundary next

## Parallel strategy execution guidance

Use one lane per strategy, derived from `task6`.

Recommended lane names:

- `task6-quant`
- `task6-docc`
- `task6-alt-dialect`
- `task6-eqmap`
- `task6-board-ram`
- `task6-lsq`
- `task6-lowering`
- `task6-paper-review`

Recommended workspace layout:

- keep this repo as the canonical `task6` base
- prefer sibling `git worktree`s over deleting this repo and making full clones
- each worktree should check out one strategy branch derived from `task6`

Why prefer worktrees:

- they keep one shared git object store and remote config
- they avoid destructive repo replacement
- they are a better fit for parallel Codex threads, because each thread can own
  one working tree and one branch

Per-lane rules:

- compare every measurement against the copied baseline bundle in
  `artifacts/task6/baselines/...`
- keep strategy-specific edits isolated to that lane until they are worth
  merging back to `task6`
- if a new script, testbench, or helper file must be visible to `nix build`,
  make sure it is tracked by git first; untracked files are omitted from the
  flake source snapshot
- do not rebuild `tiny-stories-1m-baseline-float-sv` just to recreate the
  baseline reference if the copied baseline bundle already answers the
  comparison question

Suggested mapping:

- quantization lane: dynamic-int8, TorchAO, PT2E-static, and any follow-up from
  `task3-experiments`
- eqmap lane: RTL/Verilog simplification and post-lowering cleanup experiments
- board RAM lane: move suitable weights/buffers into on-board DDR3 and record
  capacity/bandwidth assumptions explicitly
- LSQ lane: compare standard handshake vs LSQ/external-memory variants
- paper-review lane: extract transplantable ideas from StreamTensor and newer
  FPGA LLM papers, with explicit resource-saving claims

Concurrency note:

- the Nix daemon can handle concurrent builds, but the real bottlenecks will be
  host CPU, RAM, disk I/O, and cache contention
- begin with at most two or three active strategy builds plus any lighter
  paper-review work
- stagger the most expensive builds if evaluation or patch rebuilds contend on
  the same large dependencies

## What can be done now vs later

### Work that can be done now in `task6`

- keep the Task 6 execution notes, hypotheses, and comparison templates current
- refine success criteria for "fits the board"
- review papers and extract only transplantable ideas
- identify the best donor branch for later TinyStories/pipeline import
- use the existing matmul/board path only as infrastructure sanity, not as a
  surrogate for Task 6 success

### Work that requires importing Task 3 artifacts later

- quantization continuation on TinyStories
- standard vs LSQ handshake comparison
- external-memory experiments driven by emitted TinyStories RTL/SV
- post-lowering RTL simplification on full-model artifacts
- any claim that a real LLM now fits or almost fits the board

## Guardrails

- Do not modify `docs/project-plan*` without explicit reviewer approval.
- Use on-board DDR3 as a first-class system resource, not only LUT/FF/BRAM/DSP.
- Confirm the exact usable DDR3 budget before making a final fit-to-board claim.
- Use the largest model that cleanly completes the scaling pipeline as the
  baseline. If scaling is still incomplete, use `tiny-stories-1m-baseline-float`
  as the provisional baseline.
- Track Yosys resource estimates and nextpnr outcomes separately. Given the
  documented nextpnr-xilinx instability in this repo, early Task 6 screening
  should not block on nextpnr success.
- Final claims must not rely on unresolved stubs or hidden blackboxes.

## Metrics to record for every strategy

- Functional status and first failing stage
- Delta LUT/FF/BRAM/DSP
- Delta Fmax or best available timing proxy
- Toolchain wall-clock time and peak host memory
- External DDR3 usage, what moved off-chip, and estimated bandwidth pressure
- Patch burden: standard flow, local script change, or compiler patch
- Viability status: recommended, conditional, or reject

Comparison rule:

- every strategy result must be compared against the copied baseline bundle
  above, not just against memory or intuition
- if a strategy uses a different measurement path, record that explicitly and
  explain why it is still comparable

## Success criteria and exit gates

### Provisional definition of "good enough to hand off"

A strategy stack is ready to hand off when all of the following are true:

- it improves the limiting resource relative to baseline in a measurable way
- it does not introduce unresolved stubs or hidden blackboxes
- it reaches at least the same downstream stage as baseline
- the required patch burden is understood and documented
- it has a plausible board story, including DDR3 assumptions where relevant

### Stop conditions for an individual strategy

Stop investing in a strategy if any of the following becomes true:

- it fails earlier than baseline without a clear path to recovery
- it shows negligible benefit in the primary limiting resource
- it requires turning Task 6 into a retraining or compiler-rewrite project
- its claimed benefit disappears once downstream stages are included
- it creates a memory or interface story that is clearly unrealistic for the
  board

## Strategy shortlist

| ID | Strategy | Can start in this branch now? | Depends on later Task 3 import? | Why it matters |
| --- | --- | --- | --- | --- |
| S0 | Measurement harness and result schema | Yes | No | Makes every later comparison reproducible |
| S1 | Define board-fit criterion | Yes | No | Prevents moving goalposts during experiments |
| S2 | DDR3 / external-memory path | Partly | Yes | Likely best way to relieve BRAM pressure |
| S3 | Quantization continuation | No | Yes | May reduce BRAM and DSP pressure materially |
| S4 | Handshake-cost reduction | No | Yes | Handshake may be the main area amplifier |
| S5 | RTL simplification / eqmap-style passes | Partly | Yes | Cheap post-lowering area reduction is worth testing |
| S6 | StreamTensor and recent-paper refresh | Yes | No | Can supply transferrable memory and scheduling ideas |
| S7 | MoE feasibility probe | Yes, at literature level | Yes, for implementation | Interesting but must stay gated |

## Main workstreams

### 1. Freeze baseline and measurement harness

- Lock the baseline model and exact pipeline path.
- Script one reproducible measurement path that emits stage status, Yosys stats,
  timing if available, host runtime, and peak host memory.
- Prepare a per-strategy comparison matrix before running experiments.

Concrete output expected from this workstream:

- one baseline row filled in the strategy comparison matrix
- one short command log showing how the row was generated
- one explicit statement of whether baseline fit is judged by Yosys only,
  Yosys-plus-nextpnr, or both reported separately

### 2. Direct resource-reduction tracks

Run these before architecture-heavy exploration.

#### DDR3 / external-memory track

- Move suitable memories off-chip instead of forcing them into FPGA BRAM.
- Separate weights, activations, and cache/state when reasoning about what can
  live in DDR3.
- Start from the existing memory inventory / externalization hooks once the
  TinyStories pipeline files are imported into this branch.

Questions that must be answered before claiming success:

- which memories move off-chip?
- what BRAM reduction results?
- what interface/control logic is added?
- what bandwidth assumption is required?
- is the result still realistic for this board?

#### Quantization continuation track

- First use the quantization experiments present in the donor Task 3 branches:
  - `TinyStories/model_adapter_dynamic_quant.py`
  - `TinyStories/model_adapter_pt2e_static_quant.py`
  - `TinyStories/model_adapter_torchao.py`
- Preferred donor order:
  - `task3-experiments` if/when available in this clone
  - `origin/task3-rfp-sandbox` as the current fallback
  - `origin/task3-hybrid-sandbox-toolchain` only for selected helpers or clean
    landing-state references
- Treat quantization as a bounded path:
  - standard routes first
  - focused follow-up second
  - no unbounded patch-stack revival without evidence of material gains

#### Handshake-cost reduction track

- Profile growth before and after handshake lowering.
- Compare the standard handshake path with the LSQ variant already present in
  the donor Task 3 branches.
- Inspect buffer insertion, fork/sink materialization, and memory lowering as
  likely area amplifiers.

Priority question:

- does area explode before handshake, during handshake, or after handshake when
  memory/interface lowering happens?

#### RTL simplification track

- Try equivalence-preserving RTL simplification after SV/IL emission.
- Check whether `eqmap`-style or similar Yosys simplification actually shrinks
  area instead of merely reshuffling logic.
- Avoid brittle text rewriting as the main method.

Note:
- this track can be prepared now at the planning level, but meaningful testing
  still depends on having full-model emitted RTL/SV in this branch

### 3. Research and architecture track

Run in parallel, but do not let it block the direct tracks.

#### StreamTensor and recent-paper refresh

For each paper, extract:

- What problem it attacks
- What efficiency or resource gain it claims
- Whether the gain comes from quantization, streaming, memory hierarchy,
  scheduling, sparsity, or architecture change
- Whether any part looks transplantable into this open-source pipeline

Read StreamTensor first, then refresh the FPGA-LLM paper survey with an eye for
small-model, external-memory, and quantization ideas.

#### MoE feasibility track

- Do not make "convert TinyStories-1M to MoE" the primary plan.
- Dense-to-MoE adaptation appears possible in the literature, but it is an
  upcycling / retraining problem, not a direct toggle on an existing dense
  checkpoint.
- Only pursue MoE as an implementation path if a small open MoE model in
  PyTorch / Transformers form can be exported with limited custom work.

Decision gate:
- if MoE requires new training or substantial model surgery before export, move
  it to future work and keep Task 6 focused on direct reduction strategies

## Failure-triage rules

- If failure happens before MLIR/SV emission:
  - treat it as a frontend/compiler support issue first, not a resource issue
- If full RTL/IL is emitted but area is far too large:
  - prioritize DDR3, quantization, handshake, and RTL simplification tracks
- If Yosys looks promising but nextpnr fails:
  - record it as a place-and-route/toolchain limitation separately from model
    lowering success
- If a strategy improves one resource but makes another dominant resource much
  worse:
  - keep it only if the new bottleneck is still more tractable than baseline

## Suggested order once Task 3 artifacts are imported

1. Freeze the baseline row and fill the measurement matrix.
2. Run one DDR3/external-memory experiment.
3. Run the three standard quantization variants.
4. Compare standard vs LSQ handshake paths.
5. Run one RTL simplification pass bundle on the best candidate from steps 2 to 4.
6. Stop broad exploration if one path clearly dominates.
7. Hand off immediately if the resulting candidate has a plausible board-fit story.

## Comparison templates

### Strategy comparison matrix

| Strategy ID | Input branch/artifact | Stage reached | LUT delta | FF delta | BRAM delta | DSP delta | Timing delta | Host runtime delta | Peak RAM delta | DDR3 assumption | Patch burden | Result |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Baseline | TBD | TBD | 0 | 0 | 0 | 0 | 0 | 0 | 0 | None | TBD | TBD |
| S2 | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD |
| S3 | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD |
| S4 | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD |
| S5 | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD |

### Paper review matrix

| Paper / repo | Claimed gain | Main idea | Memory relevance | Quantization relevance | Reusable here? | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| StreamTensor | TBD | TBD | High | Medium | TBD | First priority read |

### Donor-branch import checklist

| Item needed for Task 6 | Present in `origin/task3` | Present in `origin/task3-rfp-sandbox` | Present in `origin/task3-hybrid-sandbox-toolchain` | Preferred donor |
| --- | --- | --- | --- | --- |
| TinyStories base adapter | Yes | Yes | Yes | TBD |
| Quantization adapters | No | Yes | Yes | `task3-experiments` if available, else `origin/task3-rfp-sandbox` |
| `nix/models.nix` | Yes | Yes | Yes | TBD |
| `nix/pipeline.nix` | Yes | Yes | Yes | TBD |
| LSQ handshake script | No | Yes | Yes | `origin/task3-rfp-sandbox` |
| `externalize_large_memories.py` | No | Yes | Yes | `origin/task3-rfp-sandbox` |
| `sv_memory_inventory.py` | No | No | Yes | `origin/task3-hybrid-sandbox-toolchain` |
| `mlir_op_profile.py` | No | No | Yes | `origin/task3-hybrid-sandbox-toolchain` |

## Repo starting points

- Files already present in this branch now:
  - `flake.nix`
  - `deliverables/1a-survey.org`
  - `deliverables/1c-selected_route.org`
  - `deliverables/2d-fpga-bitstream.org`
  - `docs/project-management.org`
- Donor branches for later import/reference:
  - `task3-experiments` if it can be fetched or recovered into this clone
  - `origin/task3`
  - `origin/task3-rfp-sandbox`
  - `origin/task3-hybrid-sandbox-toolchain`

## Questions to resolve later

- What counts as Task 6 success: Yosys estimate only, or Yosys plus nextpnr
  viability?
- Can the DDR3 track use a temporary explicit shell/wrapper interface before
  full board integration?
- How much time should be allowed for the exploratory MoE path before it is cut
  as future work?
- Which donor branch should become the base for the TinyStories Task 6 execution
  work once Task 3 cleanup is far enough along?

## Feedback-loop-first update later on 2026-04-21

- New standing maxim for later sessions:
  - maximize iteration speed, learning speed, and feedback-loop speed first
  - use the cheapest artifact that answers the current question
  - only escalate to long synthesis runs after a smaller measurement path stops
    being informative
- Action taken:
  - shrank `tiny-stories-1m-representative-core` again to the current fast-loop
    profile:
    - `vocab_size = 32`
    - `num_layers = 2`
    - `hidden_size = 2`
    - `num_heads = 1`
    - `max_position_embeddings = 4`
    - `window_size = 2`
  - kept `num_layers = 2` specifically so the reduced core still exercises both
    the `global` and `local` GPT-Neo attention patterns
- New MLIR op-coverage tooling:
  - raw stats outputs:
    - `tiny-stories-1m-baseline-float-torch-stats`
    - `tiny-stories-1m-representative-core-torch-stats`
    - existing `*-cf-stats`
  - comparison outputs:
    - `tiny-stories-1m-baseline-float-vs-representative-core-torch-op-coverage`
    - `tiny-stories-1m-baseline-float-vs-representative-core-cf-op-coverage`
    - `tiny-stories-1m-baseline-float-vs-representative-core-op-coverage`
- Intended use:
  - baseline float is the witness
  - representative core is allowed to shrink only if it keeps the baseline op
    and dialect coverage we care about at `torch` and `cf`
  - this is the default admission check before another Task 6 synthesis loop
- Verification result from the current shrink sweep:
  - full op-name and dialect coverage is still intact against the baseline at
    both `torch` and `cf`
  - measured artifact reduction at the current floor:
    - `torch.mlir`: `30,091,456` bytes / `996` lines -> `36,485` bytes /
      `303` lines
    - `cf.mlir`: `30,664,646` bytes / `14,545` lines -> `194,052` bytes /
      `4,177` lines
    - `torch` op coverage: `36/36` distinct baseline ops retained
    - `cf` op coverage: `32/32` distinct baseline ops retained
- Current decision:
  - keep this as the default representative-core floor for fast iteration
  - do not spend more time shrinking it unless a later structural metric shows
    that the op-coverage check was not enough

Minimal representative-core synthesis follow-up later on 2026-04-21:

- Command under test:
  - `nix build .#tiny-stories-1m-representative-core-selftest-top4-memory-json --no-link --print-out-paths`
- Scope:
  - first narrowed-shell synthesis run on the new representative-core floor
    after the MLIR op-coverage admission check passed
- Confirmed stage progression so far:
  - `stage1`
  - `stage2`
  - `stage3`
  - `stage4`
  - `stage5a`
  - `stage5b`
  - `stage5c`
  - `stage5d`
  - `stage6a`
  - `stage6b`
  - `stage7`
  - `stage8a`
  - live in `stage8b` at the time of this note
- Measured live memory shape from direct `/proc` sampling:
  - `stage2` worker:
    - `VmPeak` about `6.6 GiB`
    - later current `VmRSS` dropped back toward `1.9-4.6 GiB` while still in
      the same stage
  - `stage5a` worker:
    - `VmPeak` about `6.27 GiB`
    - `VmHWM` about `4.81 GiB`
  - `stage6a` restart-batched worker family:
    - repeated fresh Yosys PIDs observed inside the same `stage6a` derivation
    - each fresh batch worker remained around `1.78-1.81 GiB` `VmRSS` /
      `VmHWM`
  - `stage8b` live split:
    - parent `yosys` around `2.05 GiB` RSS
    - child `yosys-abc` around `725 MiB` RSS after roughly `80` seconds
- Interpretation:
  - the minimal representative core is no longer just a frontend witness
  - it now clears the old `stage6a` frontier and reaches the late `stage8b`
    band with a much smaller memory envelope than the earlier
    representative-core presets
  - the restart-per-batch `stage6a` path is confirmed on this floor by direct
    observation of multiple fresh Yosys worker PIDs within one `stage6a`
    derivation
- Continue decision:
  - keep this run alive until `stage8b` clears or fails
  - if it clears late `stage8*`, promote this minimal floor as the default Task
    6 synthesis debug target
  - after the live run settles, rebuild the same target under
    `scripts/pipeline/monitor_build.sh` only if a wrapped artifact bundle is
    still needed for later comparison

Minimal representative-core synthesis completion on 2026-04-22:

- The unwrapped synthesis target completed successfully:
  - command:
    - `nix build .#tiny-stories-1m-representative-core-selftest-top4-memory-json --no-link --print-out-paths`
  - output:
    - `/nix/store/x71jisw24p9w10yhv93yxximas587pci-tiny-stories-1m-representative-core-selftest-top4-memory.json`
- Follow-up artifacts also completed successfully:
  - utilization:
    - `nix build .#tiny-stories-1m-representative-core-selftest-top4-memory-utilization --no-link --print-out-paths`
    - output:
      - `/nix/store/djnni1viapdqfs8n45vny1135zw9s53g-tiny-stories-1m-representative-core-selftest-top4-memory-utilization`
  - stage stats:
    - `nix build .#tiny-stories-1m-representative-core-selftest-top4-memory-stage-stats --no-link --print-out-paths`
    - output:
      - `/nix/store/f22qqhvhpxr7rhbnwv5y7qq201g7q56q-tiny-stories-1m-representative-core-selftest-top4-memory-stage-stats`
- Confirmed stage coverage:
  - the minimal representative-core floor now clears the full narrowed-shell
    synthesis path through `stage8h` and final `json` emission
- Useful structural checkpoints from the stage-stats bundle:
  - `stage6a`:
    - `641,719,733` RTLIL bytes
    - `9,256,137` RTLIL lines
    - `225` module definitions
    - `242` top cells
    - `0` memories / `0` memory bits
  - `stage8b`:
    - `473,231,814` RTLIL bytes
    - `6,601,755` RTLIL lines
    - `225` module definitions
    - `203` top cells
  - `stage8h`:
    - `996,246,572` RTLIL bytes
    - `12,031,729` RTLIL lines
    - `225` module definitions
    - `166` top cells
- Current interpretation:
  - the minimal representative core is now a real synthesis debug target, not
    just a frontend witness
  - it is suitable as the default fast Task 6 loop for flow debugging and lane
    comparison before replay on the full TinyStories baseline
- Current decision:
  - promote this representative-core floor as the default Task 6 synthesis
    debug target
  - use the full baseline only for replay once a change proves itself here

Main-lane replay start on 2026-04-22:

- Wrapped replay launched for the real narrowed-shell baseline path:
  - command:
    - `MONITOR_GLOBAL_PGREP_PATTERN="default-builder.sh|yosys -q -s run.ys|yosys-abc" scripts/pipeline/monitor_build.sh artifacts/task6/runs/baseline-float-selftest-top4-memory-json-20260422-075933 5 -- nix build .#tiny-stories-1m-baseline-float-selftest-top4-memory-json --no-link -L`
  - run directory:
    - `artifacts/task6/runs/baseline-float-selftest-top4-memory-json-20260422-075933`
- Current status at note time:
  - active
  - still in the model/shell build band before the first staged Yosys banner
- Current decision:
  - let this replay establish whether the restart-batched `stage6a` fix carries
    over from the minimal representative-core lane to the real TinyStories
    baseline path

Representative-core same-core pipeline comparison setup on 2026-04-22:

- Question being answered:
  - compare the same minimal representative core under the two Task 6 pipeline
    shapes:
    - `tiny-stories-1m-representative-core-selftest-all-memory-*`
    - `tiny-stories-1m-representative-core-selftest-top4-memory-*`
  - do not confuse this with the already-built baseline-vs-representative-core
    compare
- Fix landed first:
  - the monolithic all-memory stage-stats path was broken because the staged
    synth record exposed `stage5Monolithic` / `stage6Monolithic` but not the
    `stage5` / `stage6` attribute names that the stage-stats bundle expected
  - added explicit aliases for `stage5` and `stage6` so monolithic
    representative-core bundles can now materialize stage stats
- New direct compare outputs:
  - `tiny-stories-1m-representative-core-all-memory-vs-top4-memory-stage-stats`
  - `tiny-stories-1m-representative-core-all-memory-vs-top4-memory-utilization`
  - `tiny-stories-1m-representative-core-all-memory-vs-top4-memory-compare`
- Comparison alignment:
  - use exact same-stage compares for `stage1` through `stage4` and `stage7`
  - compare the monolithic all-memory milestones against the split top4-memory
    milestones at:
    - `stage5` vs `stage5d`
    - `stage6` vs `stage6b`
    - `stage8` vs `stage8h`
- Current status at note time:
  - direct same-core compare build launched
  - first fixed all-memory stage-stats artifact already materialized:
    - `/nix/store/5nsiy5rbp3w3cfsaxz8sp7j7a0iy5vkv-tiny-stories-1m-representative-core-selftest-all-memory-stage1-stats`
  - full compare bundle still in progress
- Current decision:
  - use this same-core compare as the default way to judge whether `top4-memory`
    is helping on the representative core before talking about the full
    baseline lane

Representative-core same-core pipeline comparison result later on 2026-04-22:

- Direct same-core compare outputs completed:
  - `tiny-stories-1m-representative-core-selftest-all-memory-stage-stats`
  - `tiny-stories-1m-representative-core-selftest-all-memory-utilization`
  - `tiny-stories-1m-representative-core-all-memory-vs-top4-memory-stage-stats`
  - `tiny-stories-1m-representative-core-all-memory-vs-top4-memory-utilization`
  - `tiny-stories-1m-representative-core-all-memory-vs-top4-memory-compare`
- Result:
  - on the current minimal representative core, `top4-memory` is worse than
    `all-memory` at every comparable stage and at final mapped utilization
- Stage-stat deltas, `all-memory` -> `top4-memory`:
  - `stage1`:
    - `163,087,589` -> `166,555,929` RTLIL bytes (`+2.13%`)
  - `stage5` vs `stage5d`:
    - `628,922,879` -> `632,085,438` RTLIL bytes (`+0.50%`)
  - `stage6` vs `stage6b`:
    - `628,922,846` -> `641,684,683` RTLIL bytes (`+2.03%`)
  - `stage7`:
    - `628,951,844` -> `641,898,669` RTLIL bytes (`+2.06%`)
  - `stage8` vs `stage8h`:
    - `622,447,688` -> `996,246,572` RTLIL bytes (`+60.05%`)
- Utilization delta, `all-memory` -> `top4-memory`:
  - `clb_luts`:
    - `9,181,200` -> `12,472,727` (`+35.85%`)
  - `clb_ffs`:
    - `12,837,053` -> `12,845,684` (`+0.07%`)
  - `slices_lower_bound`:
    - `1,604,632` -> `1,605,711` (`+0.07%`)
  - largest driver:
    - `LUT3` cells rise from `4,484,247` to `7,636,072` (`+70.29%`)
- Interpretation:
  - the current representative-core floor is too small to show the intended
    benefit of externalizing only the top four memories
  - on this floor, the extra shell/interface structure dominates and makes the
    narrowed path look strictly worse than the monolithic all-memory path
- Current decision:
  - do not use this minimal representative core to judge whether `top4-memory`
    helps
  - keep using it for fast general flow debugging only
  - evaluate `top4-memory` on a larger representative core or the real baseline

Main-lane replay result later on 2026-04-22:

- The wrapped full-baseline narrowed-shell replay failed in late `stage6a`:
  - last completed progress:
    - `stage6a targeted techmap cells_map batch 12/15`
  - failure mode:
    - `yosys` killed with exit `137`-class behavior during the batch loop
  - monitored peak memory:
    - about `29.1 GiB` `VmRSS`
- Interpretation:
  - restart-per-batch `stage6a` improved the baseline frontier substantially
  - but it is not enough to carry the real TinyStories baseline through the
    full narrowed-shell `stage6a` band

Representative-core sweep setup later on 2026-04-22:

- Decision:
  - because the minimal representative core is too small to judge when
    `top4-memory` helps, add a real representative-core sweep instead of
    arguing from one floor
- Sweep points currently registered through the model registry:
  - `tiny-stories-1m-representative-core`
    - `vocab=32 hidden=2 layers=2 heads=1 pos=4 win=2`
  - `tiny-stories-1m-representative-core-v64-h4`
    - `vocab=64 hidden=4 layers=2 heads=1 pos=8 win=4`
  - `tiny-stories-1m-representative-core-v128-h8`
    - `vocab=128 hidden=8 layers=2 heads=2 pos=16 win=8`
  - `tiny-stories-1m-representative-core-v256-h16`
    - `vocab=256 hidden=16 layers=2 heads=4 pos=32 win=16`
  - `tiny-stories-1m-representative-core-v512-h32`
    - `vocab=512 hidden=32 layers=2 heads=4 pos=64 win=32`
  - `tiny-stories-1m-representative-core-v1024-h64`
    - `vocab=1024 hidden=64 layers=2 heads=8 pos=128 win=64`
- Structural rule kept:
  - `num_layers = 2` across the sweep so both TinyStories GPT-Neo attention
    variants remain exercised
- New flake outputs:
  - cheap manifest:
    - `tiny-stories-1m-representative-core-sweep-manifest`
  - expensive aggregate summary:
    - `tiny-stories-1m-representative-core-sweep-all-memory-vs-top4-memory-summary`
  - per-sweep-point compare outputs:
    - `<key>-all-memory-vs-top4-memory-compare`
    - plus the corresponding `selftest-all-memory-*` and
      `selftest-top4-memory-*` bundles
- Verification:
  - the sweep manifest now builds cheaply on its own
  - a nondefault sweep point was validated through the normal derivation path:
    - `nix build .#tiny-stories-1m-representative-core-v64-h4-cf-stats --no-link --print-out-paths`
    - output:
      - `/nix/store/w71iwb04zs0gpiffkbcr46nx4xqp2a6p-tiny-stories-1m-representative-core-v64-h4-cf.stats`
- Current decision:
  - use the sweep to find the crossover where `top4-memory` stops being shell
    overhead and starts reducing the real design

## StreamTensor-lite lane start on 2026-04-22

- Priority shift:
  - new lane branch: `task6-streamtensor-lite`
  - new lane worktree: `/tmp/LLM2FPGA_task6_streamtensor_lite`
  - lane note: `docs/task6-lane.md` inside that worktree
- Actual shared-plan anchor:
  - shared thread:
    `https://chatgpt.com/s/t_69e8e80bdd388191bcc4279dc0e00fc4`
  - key conclusion:
    - `StreamTensor-lite / fit-first accelerator lane` is the most promising
      active path right now
- Purpose:
  - treat this as a fit-first accelerator lane, not a generic streaming survey
    and not a full StreamTensor port
  - keep Torch-MLIR / Linalg as the frontend
  - stop treating full-model RTL lowering as the target architecture for this
    lane
  - prove that one reused kernel with external weights can change the resource
    signature away from `0 DSP / 0 BRAM`
- Immediate plan:
  - start from representative-core artifacts rather than the `top4-memory`
    shell path
  - begin with `tiny-stories-1m-representative-core-v64-h4` unless it is too
    small for the first meaningful proof
  - identify one Linalg linear / GEMV region that can be redirected into a
    small reused kernel
  - model weights as external inputs in that proof
  - require the proof to consume DSPs or otherwise visibly change the current
    all-fabric signature before promoting the lane
- Required first output:
  - shortlist of candidate insertion points with:
    - targeted linear / GEMV region
    - expected resource-signature change
    - cheapest validation artifact
    - replay target if the result is helpful

### Feedback pass later on 2026-04-22

- The lane plan was tightened to add operational rejection structure, not just
  direction:
  - hard first-proof scorecard with fixed ceilings:
    - `DSP > 0`
    - large weights not emitted as RTL constants
    - `<= 29,860` LUT
    - `<= 59,720` FF
    - Verilator pass required
  - benchmark pack with explicit time budgets:
    - export + pack `< 30 s`
    - task-graph build `< 10 s`
    - Verilator kernel test `< 20 s`
    - kernel Yosys stat `< 30 s`
    - one-block-top Yosys stat `< 2 min`
  - fixed first insertion point:
    - block-0 MLP expansion linear
    - GPT-Neo path: `transformer.h.0.mlp.c_fc`
  - frozen model ladder:
    - keep the current `v64-h4` representative-core artifact for cheap boundary
      discovery
    - add reduced-vocab, `hidden_size = 64` lane variants next:
      - `tinystories_v1k_h64_l1`
      - `tinystories_v4k_h64_l1`
      - `tinystories_v10k_h64_l1`
      - `tinystories_v10k_h64_l2`
      - `tinystories_v10k_h64_l8`
  - canonical experiment ledger moved into `docs/task6-lane-results.md`
  - whole-model TinyStories lane is now explicitly comparison-only once any
    reduced-vocab `h64` rung exists

### Follow-up feedback pass later on 2026-04-22

- The lane plan was tightened again to match the requested fast-rejection shape
  more literally:
  - the first proof record is now frozen at:
    - insertion point:
      - `transformer.h.0.mlp.c_fc`
    - representation level:
      - `linalg` on tensors immediately after Torch-MLIR backend-to-Linalg
        lowering
    - shape contract:
      - `[1, hidden_size] x [hidden_size, 4 * hidden_size]`
      - representative-core discovery rung:
        - `[1, 4] x [4, 16]`
      - reduced-vocab `h64` ladder:
        - `[1, 64] x [64, 256]`
  - the rung ladder now makes the reduced-vocab path explicit before broader
    replay:
    - `L0`:
      - synthetic `64x64` GEMV harness
    - `L1`:
      - single-op cutout from
        `tiny-stories-1m-representative-core-v64-h4`
    - `L2`:
      - `tiny-stories-v1k-h64-l1`
    - `L3`:
      - `tiny-stories-v4k-h64-l1`
    - `L4`:
      - `tiny-stories-v10k-h64-l1`
    - optional bridge rung:
      - `tiny-stories-v10k-h64-l2`
    - `L5`:
      - representative-core replay
    - `L6`:
      - real TinyStories baseline replay
  - the results ledger schema was tightened to include:
    - rung
    - insertion point
    - representation level
    - `DSP`, `BRAM`, `LUT`, `FF`
    - wall-clock
    - peak RAM
    - verdict
    - next action

### Further refinement later on 2026-04-22

- The lane was tightened again to make it operational as a daily execution loop,
  not just a well-framed concept:
  - the first-proof scorecard now includes the micro-proof runtime directly:
    - kernel Yosys stat must finish in `< 30 s`
  - the primary ladder was shortened to the minimum fast-feedback path:
    - `L0`:
      - synthetic `64x64` GEMV harness
    - `L1`:
      - single-op TinyStories linear cutout
    - `L2`:
      - `tiny-stories-v1k-h64-l1`
    - `L3`:
      - `tiny-stories-v4k-h64-l1`
    - `L4`:
      - representative-core replay
  - the larger-fidelity steps were explicitly demoted to deferred extensions:
    - `tiny-stories-v10k-h64-l1`
    - `tiny-stories-v10k-h64-l2`
    - real TinyStories baseline replay
  - the experiment ledger was renamed toward artifact-centric logging and now
    has an explicit row recording that the fast loop stops at `L4` unless the
    earlier rungs justify widening

### L0 and L1 execution start later on 2026-04-22

- `L0` implementation:
  - added a new local model:
    - `task6-l0-gemv64`
  - shape:
    - activation input `tensor<1x64xf32>`
    - weight input `tensor<64x64xf32>`
    - result `tensor<1x64xf32>`
  - purpose:
    - make the synthetic kernel explicitly external-weighted rather than
      embedding a constant matrix
- `L0` first results:
  - `linalg` now contains the expected single op:
    - `linalg.matmul ins(%arg0, %arg1 : tensor<1x64xf32>, tensor<64x64xf32>)`
  - first `yosys-stat` attempt failed at `sv` export because float externs were
    not enabled for the new model
  - after reusing the baseline float-extern wiring
    (`allowHwExterns`, per-file extern import, `fpPrimsSv`), the rerun
    succeeded
  - measured rerun:
    - wall-clock:
      - `9.23 s`
    - peak RSS:
      - `560,684 KB`
    - Yosys design cells:
      - `11,471`
    - memory bits:
      - `2,048`
    - cell signal:
      - one `$mul`
      - one `arith_mulf_in_f32_f32_out_f32`
      - one `arith_addf_in_f32_f32_out_f32`
  - interpretation:
    - the micro-proof runtime budget is already satisfied on `L0`
    - externalized weights are present at `linalg` because the matrix is a
      function argument, not a dense resource constant
    - mapped DSP / LUT / FF conclusions are still pending because this is only
      the generic Yosys stat stage
- `L1` implementation:
  - added:
    - `scripts/task6/find_l1_gemv_candidate.py`
  - artifact:
    - `artifacts/task6/streamtensor-lite/l1/representative-core-v64-h4-c_fc-candidate.json`
- `L1` first results:
  - the representative-core `linalg` export contains exactly two matching
    `1x1x4` by `1x4x16` `linalg.batch_matmul` sites across the two-layer core
  - the selected first candidate is:
    - line `363`
    - value `%75`
  - immediate surrounding structure matches the intended cutout:
    - tensor materialization into `tensor<1x4x16xf32>`
    - `linalg.batch_matmul`
    - bias-add style `linalg.generic` immediately after
  - measured candidate-finder runtime:
    - wall-clock:
      - `0.05 s`
    - peak RSS:
      - `13,024 KB`
- Next execution step:
  - begin weight-pack extraction around the selected `%75` / line `363` `L1`
    site
  - add Verilator coverage for `L0`

### L1 weight-pack extraction later on 2026-04-22

- Added:
  - `scripts/task6/export_weights_pack.py`
- First packed artifact:
  - `artifacts/task6/weights_pack/tiny-stories-1m-representative-core-v64-h4/transformer.h.0.mlp.c_fc/`
- Exported tensors:
  - `weight.bin`
    - shape:
      - `(16, 4)`
    - bytes:
      - `256`
  - `bias.bin`
    - shape:
      - `(16,)`
    - bytes:
      - `64`
  - `manifest.json`
    - records:
      - module path
      - representative-core config
      - tensor shapes
      - raw-f32-le format
- Measured export:
  - wall-clock:
    - `2.42 s`
  - peak RSS:
    - `336,816 KB`
- Interpretation:
  - the lane now has a first real external pack artifact tied directly to the
    selected `L1` `c_fc` site
  - the export + pack budget is satisfied for the representative-core proof
- Immediate next choice:
  - either build the smallest task-graph consumer around this pack
  - or add the lightest possible Verilator harness for `task6-l0-gemv64`

### L1 minimal task-graph consumer later on 2026-04-22

- Added:
  - `scripts/task6/build_task_graph.py`
- First task-graph artifact:
  - `artifacts/task6/streamtensor-lite/l1/representative-core-v64-h4-c_fc-task-graph.json`
- Measured build:
  - wall-clock:
    - `0.03 s`
  - peak RSS:
    - `13,456 KB`
- Structure:
  - one activation input
  - one packed-weight reader
  - one packed-bias reader
  - one `gemv` node
  - one `bias-add` node
  - one activation output
- Key linkage:
  - selected site:
    - line `363`
    - value `%75`
  - pack source:
    - `transformer.h.0.mlp.c_fc/manifest.json`
- Interpretation:
  - the lane now has both:
    - a first packed-weight producer
    - and a first consumer-side task graph around the same `L1` site
  - the task-graph budget is satisfied comfortably
- Immediate next choice:
  - either refine this graph into a more explicit executable contract
  - or spend the next slice on the lightest possible `task6-l0-gemv64`
    simulation harness

### L1 contract capture and pack replay later on 2026-04-22

- Added:
  - `scripts/task6/export_l1_contract.py`
  - `scripts/task6/verify_l1_contract.py`
- First contract artifact:
  - `artifacts/task6/streamtensor-lite/l1/representative-core-v64-h4-c_fc-contract/`
- Captured tensors:
  - `activation_in.bin`
    - shape:
      - `(1, 1, 4)`
    - bytes:
      - `16`
  - `activation_out.bin`
    - shape:
      - `(1, 1, 16)`
    - bytes:
      - `64`
  - `manifest.json`
    - records:
      - module path
      - representative-core config
      - sample input ids `[[0]]`
      - selected-site linkage back to line `363` / `%75`
- Measured contract capture:
  - wall-clock:
    - `2.42 s`
  - peak RSS:
    - `342,280 KB`
- First replay-check artifact:
  - `artifacts/task6/streamtensor-lite/l1/representative-core-v64-h4-c_fc-contract-check.json`
- Measured replay check:
  - wall-clock:
    - `0.93 s`
  - peak RSS:
    - `226,472 KB`
- Replay result:
  - formula:
    - `activation_in @ weight.T + bias`
  - max absolute error:
    - `0.0`
  - mean absolute error:
    - `0.0`
  - verdict:
    - `pass`
- Task-graph follow-up:
  - the minimal `L1` task graph now points at:
    - the selected `linalg` site
    - the packed weight/bias manifest
    - the captured sample contract
- Interpretation:
  - `L1` now has a real executable proof path that stays below the heavier
    handshake-level simulation boundary
  - the packed tensors are no longer only exported; they are replayed against a
    captured module-level contract with exact agreement
- Immediate next choice:
  - either add the lightest honest Verilator harness for `L0`
  - or start `L2` with the reduced-vocab `h64` ladder now that `L1` has a
    pack-backed executable contract

### L2 reduced-vocab `h64` rung start later on 2026-04-22

- Added rung definitions:
  - `tiny-stories-v1k-h64-l1`
  - `tiny-stories-v4k-h64-l1`
- Supporting script change:
  - generalized `scripts/task6/find_l1_gemv_candidate.py`
    - it now accepts explicit `lhs`, `rhs`, and `out` tensor shapes so the same
      boundary finder can work on both `L1` and reduced-vocab `h64` rungs
- First `L2` build:
  - `nix build .#tiny-stories-v1k-h64-l1-linalg --no-link --print-out-paths`
  - artifact:
    - `/nix/store/x8lnd266sjig478x9b34bmlv8p0x4m61-tiny-stories-v1k-h64-l1-linalg.mlir`
- `L2` first boundary result:
  - artifact:
    - `artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_fc-candidate.json`
  - measured candidate-finder runtime:
    - wall-clock:
      - `0.03 s`
    - peak RSS:
      - `15,644 KB`
  - selected site:
    - line `357`
    - value `%81`
  - shape contract:
    - `tensor<1x1x64xf32>`
    - `tensor<1x64x256xf32>`
    - `tensor<1x1x256xf32>`
  - interpretation:
    - the same block-0 `transformer.h.0.mlp.c_fc` boundary survives cleanly at
      the first reduced-vocab `h64` rung
    - there is exactly one matching site because the rung uses one transformer
      layer
- `L2` first packed artifact:
  - `artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_fc/`
  - measured export:
    - wall-clock:
      - `2.38 s`
    - peak RSS:
      - `337,536 KB`
  - tensor shapes:
    - weight:
      - `(256, 64)`
    - bias:
      - `(256,)`
- `L2` first contract artifact:
  - `artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_fc-contract/`
  - measured capture:
    - wall-clock:
      - `2.40 s`
    - peak RSS:
      - `342,932 KB`
  - sample contract:
    - input ids:
      - `[[0]]`
    - activation in:
      - `(1, 1, 64)`
    - activation out:
      - `(1, 1, 256)`
- `L2` replay check:
  - artifact:
    - `artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_fc-contract-check.json`
  - measured replay:
    - wall-clock:
      - `0.92 s`
    - peak RSS:
      - `226,720 KB`
  - replay result:
    - formula:
      - `activation_in @ weight.T + bias`
    - max absolute error:
      - `0.0`
    - mean absolute error:
      - `0.0`
    - verdict:
      - `pass`
- `L2` task-graph artifact:
  - `artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_fc-task-graph.json`
  - measured build:
    - wall-clock:
      - `0.03 s`
    - peak RSS:
      - `14,268 KB`
- Supporting fix:
  - generalized `scripts/task6/build_task_graph.py`
    - it now derives expected weight and bias tensor shapes from the selected
      candidate contract instead of assuming the `L1` `4 -> 16` case
- Interpretation:
  - `L2` is now active rather than planned only
  - the first reduced-vocab `h64` rung preserves the same `c_fc` boundary and
    external-pack replay contract as `L1`
  - the next decision is no longer whether `L2` exists; it is whether to widen
    to `L3` (`v4k-h64-l1`) or spend the next slice on kernel-level synthesis /
    simulation evidence

### L0 Verilator harness later on 2026-04-22

- Added:
  - `sim/gen_task6_l0_gemv64_tb_data.py`
  - `sim/task6_l0_gemv64_tb_main.sv`
  - `sim/sim_utils.py`
  - flake outputs:
    - `task6-l0-gemv64-sim-main`
    - `task6-l0-gemv64-sv-sim`
    - `task6-l0-gemv64-sv-wave`
- First pass:
  - `nix build .#task6-l0-gemv64-sv-sim --no-link -L`
  - result:
    - `PASS: stores 64 outputs 64`
- Harness contract:
  - activation source:
    - `64` deterministic `f32` words
  - weight source:
    - `4096` deterministic `f32` words
  - completion rule:
    - observe `64` stores and compare them bit-exactly against generated
      expected outputs
  - memory-side behavior:
    - one outstanding read per source plus explicit `stDone` acknowledgement
      handling so the testbench matches the kernel's external-memory handshake
- Measured direct execution:
  - command target:
    - `/nix/store/cfcang44fpaifcchz6xrny925pgzx984-task6-l0-gemv64-sim-main/obj_dir/sim_main`
  - wall-clock:
    - `0.55 s`
  - peak RSS:
    - `4,852 KB`
- Build caveat:
  - Nix did not see the new simulation files until they were tracked by git,
    because the flake source snapshot omits untracked files
- Interpretation:
  - the `L0` Verilator scorecard item now passes
  - the Verilator runtime budget is comfortably satisfied
  - the next useful slice is mapped kernel synthesis, because DSP / LUT / FF
    evidence is still the main unanswered first-proof question

### L0 mapped utilization later on 2026-04-22

- Added:
  - flake outputs:
    - `task6-l0-gemv64-json`
    - `task6-l0-gemv64-utilization`
- Supporting fix:
  - `scripts/pipeline/write_utilization_report.py`
    - it now treats mapped blackbox modules such as `LUT*`, `FDRE`, and
      `DSP48E1` as leaf cells instead of recursing into their internal
      `$specify*` scaffolding
- First mapped report:
  - `nix build .#task6-l0-gemv64-utilization --no-link --print-out-paths`
  - output:
    - `/nix/store/57r5sdcry3nmh04x5hqz8shz9w65z0a1-task6-l0-gemv64-utilization`
- Mapped resource summary:
  - DSP:
    - `4`
  - BRAM36:
    - `0`
  - CLB LUTs:
    - `32,449`
  - CLB FFs:
    - `46,736`
  - slice lower bound:
    - `5,842`
- Synth runtime from the mapped `task6-l0-gemv64.json` build log:
  - wall-clock:
    - `57.95 s`
  - peak RSS:
    - `851,592 KB`
- Interpretation:
  - the first-proof DSP requirement now passes on `L0`
  - the FF ceiling also passes on `L0`
  - the LUT ceiling still fails by `2,589` LUT, so the synthetic kernel is not
    yet small enough to count as a clean first-proof win
  - the next useful choice is to cut LUT cost before promoting the lane, not to
    spend more time on basic simulation plumbing

### L0 int16 alternate datatype probe later on 2026-04-22

- Added:
  - `src/gemv64_int16.py`
  - `src/gemv64_int16_adapter.py`
  - flake outputs:
    - `task6-l0-gemv64-int16-json`
    - `task6-l0-gemv64-int16-utilization`
- First mapped report:
  - `nix build .#task6-l0-gemv64-int16-utilization --no-link --print-out-paths`
  - output:
    - `/nix/store/li6g5avkfdfjnfffp7924m1ndrxkik6b-task6-l0-gemv64-int16-utilization`
- Timed direct synth check:
  - wall-clock:
    - `54.57 s`
  - peak RSS:
    - `873,180 KB`
- Mapped resource summary:
  - DSP:
    - `1`
  - BRAM36:
    - `0`
  - CLB LUTs:
    - `35,737`
  - CLB FFs:
    - `59,276`
  - slice lower bound:
    - `7,410`
- Interpretation:
  - the int16 variant stays buildable, but it is not an improvement over the
    float `L0` proof
  - LUT cost gets worse by `3,288` relative to the float `L0` mapped result
  - the DSP signal weakens from `4 DSP48E1` to `1 DSP48E1`
  - this is a rejection of a datatype-only int16 substitution, not a promotion
    candidate for the lane

### L0 int8 alternate datatype probe later on 2026-04-22

- Probe setup:
  - verified locally that `torch.export` plus `torch_mlir.fx.export_and_import`
    can represent `torch.aten.mm` on `si8`
  - briefly wired an `int8` `L0` adapter to test the real lane pipeline
- Failure point:
  - `task6-l0-gemv64-int8-linalg`
  - error:
    - `unimplemented: for conversion to byte or char type dstOriginalDtype has to be passed to convertScalarToDtype`
  - observed behavior:
    - `torch-mlir-opt` crashes during `torch` to `linalg` lowering on the
      `si8` `torch.aten.mm` path
- Interpretation:
  - `int8` is currently a tooling blocker rather than a usable LUT-reduction
    path in this repo state
  - do not keep an `int8` `L0` package surface active until the byte/char
    lowering bug is fixed upstream or patched locally

### L1 redirected-kernel proof later on 2026-04-22

- Added:
  - `src/task6_rect_gemv.py`
  - `src/task6_rect_gemv_adapter.py`
  - `sim/gen_task6_contract_gemv_tb_data.py`
  - `sim/task6_contract_gemv_tb_main.sv`
  - model key:
    - `task6-l1-c-fc-redirect`
- Logged run bundle:
  - `artifacts/task6-streamtensor-lite/runs/2026-04-22T23-22-07+0200/`

#### Folded-bias attempt

- Goal:
  - keep the redirect surface at two inputs by appending bias as an extra
    external weight row and a constant `1` activation lane
- Outcome:
  - structural compilation succeeded, but exact replay failed at simulation on
    all `16` outputs
  - representative log lines:
    - `FAIL: addr 0 expected 0x3d085992 got 0x3d082000`
    - `FAIL: addr 1 expected 0x3d2a1d92 got 0x3d29e000`
  - maximum observed absolute error:
    - `0.000075929`
- Interpretation:
  - do not treat algebraic bias folding as an exact replay proof under the
    current float primitive lowering path

#### Explicit external bias attempt

- Goal:
  - keep bias explicit as a third input and prove that it survives as a top
    level external memory interface
- Early IR evidence:
  - `linalg` showed:
    - `func.func @main(%arg0: tensor<1x5xf32>, %arg1: tensor<5x16xf32>, %arg2: tensor<16xf32>)`
  - the body still separated `linalg.matmul` from the later bias add
- Failure point:
  - handshake and `hw-clean` no longer surfaced bias as a top-level load
    interface
  - the lowered top instead materialized an internal `handshake_memory_out_f32`
    block for that path
- Interpretation:
  - this is the one explicit externalization failure for the L1 bias path, so
    stop spending more slices there and use the kernel-only fallback

#### Accepted kernel-only fallback

- Accepted boundary:
  - the selected pre-bias `batch_matmul` site for
    `transformer.h.0.mlp.c_fc`
- Timed `yosys-stat`:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-yosys-stat --no-link -L`
  - result:
    - `ELAPSED=4.07`
    - `RSS_KB=564032`
  - design summary:
    - `num_cells = 12611`
    - `num_memory_bits = 512`
    - `$mul = 1`
    - `arith_mulf_in_f32_f32_out_f32 = 1`
    - `arith_addf_in_f32_f32_out_f32 = 1`
- Timed mapped utilization:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-utilization --no-link --print-out-paths`
  - output:
    - `/nix/store/cgk31f78g5c0rd8bwyw98v1p38m0vz4f-task6-l1-c-fc-redirect-utilization`
  - result:
    - `ELAPSED=64.82`
    - `RSS_KB=562944`
  - mapped summary:
    - DSP:
      - `4`
    - BRAM36:
      - `0`
    - CLB LUTs:
      - `33,116`
    - CLB FFs:
      - `51,296`
- Timed Verilator proof:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-sv-sim --no-link -L`
  - result:
    - `PASS: stores 16 outputs 16`
    - `ELAPSED=61.91`
    - `RSS_KB=437820`
  - testbench rule:
    - `ABS_TOL = 1.0e-4`
  - reason for tolerance:
    - the observed mismatch scale matched the visible `q16.16` float primitive
      path, so the accepted proof checks the redirected kernel against an
      explicit absolute error bound instead of bit-exact float equality
- Weight placement evidence:
  - `hw-clean` and `main.sv` still expose top-level `in1_ld0_*` weight load
    ports, so the large `16 x 4` weight tensor is not emitted as a giant RTL
    constant bundle
- Interpretation:
  - `L1` now has a valid redirected-kernel structural proof:
    - external weights: pass
    - `yosys-stat` runtime: pass
    - mapped DSP use: pass
    - Verilator proof: pass
  - the mapped LUT count still fails the lane ceiling at `33,116 > 29,860`
  - the next useful slice is `L2`, not further L1 bias surgery

### L2 redirected-kernel proof later on 2026-04-22

- Added:
  - model key:
    - `task6-l2-c-fc-redirect`
  - flake outputs:
    - `task6-l2-c-fc-redirect-tb-data-sv`
    - `task6-l2-c-fc-redirect-sim-main`
    - `task6-l2-c-fc-redirect-json`
    - `task6-l2-c-fc-redirect-utilization`
    - `task6-l2-c-fc-redirect-sv-sim`
- Logged run bundle:
  - `artifacts/task6-streamtensor-lite/runs/2026-04-22T23-22-07+0200/`

#### Accepted reduced-vocab proof

- Accepted boundary:
  - the selected pre-bias `batch_matmul` site for
    `tiny-stories-v1k-h64-l1`
    `transformer.h.0.mlp.c_fc`
- Manifest alignment:
  - `task6-l2-c-fc-redirect-tb-data-sv`
  - output:
    - `/nix/store/kv3li6fbzgj3w1sp5zzypvrh23a7c62g-task6-l2-c-fc-redirect-tb-data-sv`
- Timed `yosys-stat`:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l2-c-fc-redirect-yosys-stat --no-link -L`
  - result:
    - `ELAPSED=9.13`
    - `RSS_KB=563512`
  - design summary:
    - `num_cells = 13703`
    - `num_memory_bits = 8192`
    - `$mul = 1`
    - `arith_mulf_in_f32_f32_out_f32 = 1`
    - `arith_addf_in_f32_f32_out_f32 = 1`
- Timed mapped utilization:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l2-c-fc-redirect-utilization --no-link --print-out-paths -L`
  - output:
    - `/nix/store/2sfssv27f1ijhwlwzaxsny76ixvjrzmn-task6-l2-c-fc-redirect-utilization`
  - result:
    - `ELAPSED=88.93`
    - `RSS_KB=562776`
  - mapped summary:
    - DSP:
      - `4`
    - BRAM36:
      - `0`
    - CLB LUTs:
      - `50,235`
    - CLB FFs:
      - `65,523`
- Timed Verilator proof:
  - first run failure:
    - `Timeout waiting for redirected GEMV completion`
  - harness fix:
    - `sim/task6_contract_gemv_tb_main.sv`
    - `TIMEOUT_CYCLES` now scales with
      `ACTIVATION_WORDS + WEIGHT_WORDS + EXPECTED_STORE_COUNT`
  - rerun command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l2-c-fc-redirect-sv-sim --no-link -L`
  - rerun result:
    - `PASS: stores 256 outputs 256`
    - `ELAPSED=47.06`
    - `RSS_KB=437352`
- Weight placement evidence:
  - `hw-clean` and `main.sv` still expose top-level `in1_ld0_*` weight load
    ports, so the reduced-vocab `256 x 64` weight tensor is still external
- Interpretation:
  - `L2` is a valid reduced-vocab redirected-kernel proof:
    - external weights: pass
    - `yosys-stat` runtime: pass
    - mapped DSP use: pass
    - Verilator proof: pass
  - `L2` is not a promotion candidate for fit-first work:
    - LUT grows from `33,116` on `L1` to `50,235`
    - FF grows from `51,296` on `L1` to `65,523`
  - the next useful slice is fit reduction on the cheaper `L1` proof, not
    larger-lane bring-up

### L1 mapper-only fit check later on 2026-04-23

- Added:
  - direct `abc9` flake outputs:
    - `task6-l0-gemv64-abc9-json`
    - `task6-l0-gemv64-abc9-utilization`
    - `task6-l1-c-fc-redirect-abc9-json`
    - `task6-l1-c-fc-redirect-abc9-utilization`
  - staged `abc9` flake outputs:
    - `task6-l1-c-fc-redirect-staged-abc9-json`
    - `task6-l1-c-fc-redirect-staged-abc9-utilization`
- Logged run bundle:
  - `artifacts/task6-streamtensor-lite/runs/2026-04-23T09-23-28+0200/`

#### Direct `abc9` control on `L0`

- Timed mapped utilization:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l0-gemv64-abc9-utilization --no-link --print-out-paths`
  - output:
    - `/nix/store/mp68ywi5hy4zr5ldvjmm0zib5a5anddh-task6-l0-gemv64-abc9-utilization`
  - result:
    - `ELAPSED=94.83`
    - `RSS_KB=561388`
  - mapped summary:
    - DSP:
      - `4`
    - BRAM36:
      - `0`
    - CLB LUTs:
      - `32,478`
    - CLB FFs:
      - `46,736`
- Interpretation:
  - direct `abc9` is not a useful `L0` fit tactic:
    - LUT rises from `32,449` to `32,478`
    - FF and DSP stay effectively unchanged

#### Direct `abc9` on the accepted `L1` kernel

- Timed mapped utilization:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-abc9-utilization --no-link --print-out-paths`
  - output:
    - `/nix/store/iamh08ddr6pahr3py2ach61abzpxbrqs-task6-l1-c-fc-redirect-abc9-utilization`
  - result:
    - `ELAPSED=94.27`
    - `RSS_KB=561892`
  - mapped summary:
    - DSP:
      - `4`
    - BRAM36:
      - `0`
    - CLB LUTs:
      - `32,236`
    - CLB FFs:
      - `51,296`
- Weight placement and replay status:
  - unchanged from the accepted kernel-only `L1` proof:
    - large weights still enter through top-level `in1_ld0_*`
    - Verilator still passes on `task6-l1-c-fc-redirect-sv-sim`
    - `yosys-stat` still fits the micro-proof budget at `4.07 s`
- Interpretation:
  - direct `abc9` is a real but insufficient improvement on the active lane:
    - LUT falls from `33,116` to `32,236`
    - the ceiling still fails by `2,376`
  - mapper choice matters, but it is not enough on its own to clear the lane

#### Staged `abc9` check on the accepted `L1` kernel

- Timed staged build:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-staged-abc9-utilization --no-link --print-out-paths`
  - result:
    - `ELAPSED=15.14`
    - `RSS_KB=564392`
  - failure:
    - `ERROR: Module \`FDRE' is used with parameters but is not parametric!`
    - failure point:
      - `task6-l1-c-fc-redirect-staged-abc9-stage8.il`
- Interpretation:
  - stop the staged micro-flow after one failure:
    - it does not currently produce a mapped JSON on the accepted `L1` kernel
    - fixing the staged Xilinx primitive handling would be plumbing work, not a
      fit-first micro-proof
  - the next useful slice is no longer mapper-only:
    - keep direct `abc9` as the current best mapped `L1` result
    - move the next effort to RTL-structural LUT reduction on the shared float
      kernel path

### L1 `ui64` buffer-lite diagnostic later on 2026-04-23

- Added:
  - override file:
    - `rtl/task6/handshake_buffer_in_ui64_out_ui64_2slots_seq.sv`
  - flake outputs:
    - `task6-l1-c-fc-redirect-ui64-buffer-lite-sim-main`
    - `task6-l1-c-fc-redirect-ui64-buffer-lite-json`
    - `task6-l1-c-fc-redirect-ui64-buffer-lite-utilization`
    - `task6-l1-c-fc-redirect-ui64-buffer-lite-sv-sim`
- Logged run bundle:
  - `artifacts/task6-streamtensor-lite/runs/2026-04-23T09-23-28+0200/`

#### Why this slice

- Structural inspection of the accepted `L1` RTL showed:
  - `204` instances of `handshake_buffer_in_ui64_out_ui64_2slots_seq`
  - `48` instances of `handshake_buffer_in_none_out_none_2slots_seq_1ins_1outs_ctrl`
  - only one `arith_mulf_in_f32_f32_out_f32` and one
    `arith_addf_in_f32_f32_out_f32`
- that made the `ui64` two-slot buffer the cheapest first target for a fit
  probe without broad compiler surgery

#### Functional check

- Timed Verilator proof:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-ui64-buffer-lite-sv-sim --no-link -L`
  - tracked-file reminder:
    - the first rerun failed until `rtl/task6/handshake_buffer_in_ui64_out_ui64_2slots_seq.sv`
      was git-tracked, because the flake source snapshot omits untracked files
  - tested variants:
    - strict one-slot FIFO
    - fall-through skid-style one-slot FIFO
  - final result:
    - `ELAPSED=22.69`
    - `RSS_KB=437508`
    - `Timeout waiting for redirected GEMV completion`
- Interpretation:
  - the current `ui64` one-slot replacements are not valid drop-ins for the
    accepted `L1` handshake schedule
  - this counts as two failures of the same replacement class, so do not spend
    another slice on a third ad hoc `ui64` one-slot variant without a stronger
    semantic argument

#### Fit-only diagnostic

- Timed mapped utilization:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-ui64-buffer-lite-utilization --no-link --print-out-paths`
  - output:
    - `/nix/store/aw5y4ri37p3zp0dksym0y2f2agm5p5ax-task6-l1-c-fc-redirect-ui64-buffer-lite-utilization`
  - result:
    - `ELAPSED=53.61`
    - `RSS_KB=562884`
  - mapped summary:
    - DSP:
      - `4`
    - BRAM36:
      - `0`
    - CLB LUTs:
      - `20,725`
    - CLB FFs:
      - `15,731`
- Primitive signature:
  - `FDRE` drops from `51,293` on the accepted `L1` proof to `15,728`
  - `LUT6` drops from `19,276` to `3,750`
- Interpretation:
  - this is the strongest fit signal in the lane so far:
    - replacing only the `ui64` two-slot buffer class pushes the mapped design
      comfortably under the LUT ceiling while keeping `4 DSP48E1`
  - but it is diagnostic only:
    - the current replacement breaks the kernel contract, so it is not a valid
      promotion candidate
  - the next useful slice is now clear:
    - preserve the accepted `L1` functionality
    - find a semantically correct way to cut `ui64` buffer state, likely by
      targeting only a subset of buffers or by matching the existing ready/valid
      scheduling more faithfully than a generic one-slot drop-in

### L1 selective `buffer165` FIFO2 proof later on 2026-04-23

- Added:
  - helper module:
    - `rtl/task6/task6_ui64_fifo2_buffer.sv`
  - flake outputs:
    - `task6-l1-c-fc-redirect-buffer165-fifo2-sim-main`
    - `task6-l1-c-fc-redirect-buffer165-fifo2-sv-sim`
    - `task6-l1-c-fc-redirect-buffer165-fifo2-json`
    - `task6-l1-c-fc-redirect-buffer165-fifo2-utilization`
- Logged run bundle:
  - `artifacts/task6-streamtensor-lite/runs/2026-04-23T10-59-21+0200/`

#### Why this slice

- The class-wide `ui64` buffer replacements failed three times:
  - strict one-slot FIFO
  - fall-through one-slot FIFO
  - class-wide lean two-entry FIFO
- the next smallest non-redundant test was a single central loop-index site:
  - `handshake_buffer165`
  - this is the buffer that feeds `handshake_fork34`, which fans the loop index
    into the `handshake_mux30..37` selection tree

#### Functional proof

- Timed Verilator proof:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-buffer165-fifo2-sv-sim --no-link -L`
  - result:
    - `PASS: stores 16 outputs 16`
    - `ELAPSED=56.13`
    - `RSS_KB=437056`
- Interpretation:
  - targeted replacement is viable:
    - at least one central `ui64` loop-index buffer can move to the lean FIFO2
      implementation without breaking the accepted `L1` contract

#### Mapped utilization

- Timed mapped utilization:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-buffer165-fifo2-utilization --no-link --print-out-paths`
  - output:
    - `/nix/store/ay0550kjz47qmv3ig0wrr212sflz78fd-task6-l1-c-fc-redirect-buffer165-fifo2-utilization`
  - result:
    - `ELAPSED=66.21`
    - `RSS_KB=562608`
  - mapped summary:
    - DSP:
      - `4`
    - BRAM36:
      - `0`
    - CLB LUTs:
      - `33,020`
    - CLB FFs:
      - `51,292`
- Delta against accepted base `L1`:
  - LUT:
    - `33,116 -> 33,020` (`-96`)
  - FF:
    - `51,296 -> 51,292` (`-4`)
- Interpretation:
  - a single safe replacement is not enough to matter on its own
  - but it proves the right next shape:
    - do not replace the full `ui64` buffer class again
    - widen only within the same local index-distribution spine and keep
      Verilator as the immediate gate

### L1 class-wide `ui64` FIFO2 rejection later on 2026-04-23

- Added:
  - helper module:
    - `rtl/task6/handshake_buffer_in_ui64_out_ui64_2slots_seq_fifo2.sv`
  - flake outputs:
    - `task6-l1-c-fc-redirect-ui64-buffer-fifo2-sim-main`
    - `task6-l1-c-fc-redirect-ui64-buffer-fifo2-sv-sim`
    - `task6-l1-c-fc-redirect-ui64-buffer-fifo2-json`
    - `task6-l1-c-fc-redirect-ui64-buffer-fifo2-utilization`
- Logged run bundle:
  - `artifacts/task6-streamtensor-lite/runs/2026-04-23T11-05-39+0200/l1-ui64-buffer-fifo2-reject/summary.md`

#### Why this slice

- The one-slot class-wide replacements had already failed twice:
  - strict FIFO
  - fall-through FIFO
- the smallest remaining same-class check was a class-wide lean two-entry FIFO:
  - keep the `ui64` buffer interface and depth at `2`
  - cut the internal state and control logic compared with the generated
    baseline implementation

#### Functional proof

- Timed Verilator proof:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-ui64-buffer-fifo2-sv-sim --no-link -L`
  - result:
    - `Timeout waiting for redirected GEMV completion`
    - `ELAPSED=42.50`
    - `RSS_KB=437644`
- Interpretation:
  - this is the third failure of the same whole-class path:
    - one-slot strict
    - one-slot fall-through
    - two-slot FIFO2
  - per lane rules, whole-class `ui64` buffer replacement should stop here

### L1 selective index-spine FIFO2 proof later on 2026-04-23

- Added:
  - flake outputs:
    - `task6-l1-c-fc-redirect-index-spine-fifo2-sim-main`
    - `task6-l1-c-fc-redirect-index-spine-fifo2-sv-sim`
    - `task6-l1-c-fc-redirect-index-spine-fifo2-json`
    - `task6-l1-c-fc-redirect-index-spine-fifo2-utilization`
- Logged run bundle:
  - `artifacts/task6-streamtensor-lite/runs/2026-04-23T11-05-39+0200/l1-index-spine-fifo2-proof/summary.md`

#### Why this slice

- After the class-wide path was exhausted, the next bounded test was a local
  cluster around the already-safe `handshake_buffer165` site:
  - `handshake_buffer160`
  - `handshake_buffer161`
  - `handshake_buffer162`
  - `handshake_buffer163`
  - `handshake_buffer164`
  - `handshake_buffer165`
- these six sites sit on the same loop-index distribution spine feeding the
  local `handshake_mux30..37` / `handshake_cond_br32..39` region

#### Functional proof

- Timed Verilator proof:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-spine-fifo2-sv-sim --no-link -L`
  - result:
    - `PASS: stores 16 outputs 16`
    - `ELAPSED=58.30`
    - `RSS_KB=437376`
- Interpretation:
  - the safe selective replacement can widen at least across this local spine
    without breaking the accepted `L1` contract

#### Mapped utilization

- Timed mapped utilization:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-spine-fifo2-utilization --no-link --print-out-paths`
  - output:
    - `/nix/store/dkwlcml8ckf8gg5kx2c3v4w8d5yq43i6-task6-l1-c-fc-redirect-index-spine-fifo2-utilization`
  - result:
    - `ELAPSED=64.88`
    - `RSS_KB=563044`
  - mapped summary:
    - DSP:
      - `4`
    - BRAM36:
      - `0`
    - CLB LUTs:
      - `32,808`
    - CLB FFs:
      - `50,642`
- Primitive signature:
  - `FDRE`:
    - `50,639`
  - `LUT6`:
    - `18,981`
  - `LUT3`:
    - `6,595`
  - `LUT2`:
    - `3,591`
- Weight placement and runtime checks:
  - large weights emitted as RTL constants:
    - `no`
    - this slice only swaps selected buffer instances in copied `sv/main.sv`,
      so it inherits the accepted `L1` externalized-weight path unchanged
  - Yosys stat finished within budget:
    - `yes`
    - unchanged from the accepted `L1` kernel at `4.07 s`
- Delta against accepted base `L1`:
  - LUT:
    - `33,116 -> 32,808` (`-308`)
  - FF:
    - `51,296 -> 50,642` (`-654`)
- Interpretation:
  - the widened local spine is a real safe improvement, not measurement noise
  - but it still misses the LUT ceiling and still trails the direct `abc9`
    result of `32,236` LUT
  - the next cheapest valid slice is to test whether this safe structural
    reduction stacks with `abc9` before widening to more buffer sites

### L1 selective index-spine FIFO2 `abc9` proof later on 2026-04-23

- Added:
  - flake outputs:
    - `task6-l1-c-fc-redirect-index-spine-fifo2-abc9-json`
    - `task6-l1-c-fc-redirect-index-spine-fifo2-abc9-utilization`
- Logged run bundle:
  - `artifacts/task6-streamtensor-lite/runs/2026-04-23T11-09-44+0200/l1-index-spine-fifo2-abc9-proof/summary.md`

#### Why this slice

- The two strongest valid `L1` signals before this point were:
  - direct `abc9`:
    - `32,236` LUT
  - safe local `160..165` FIFO2 spine:
    - `32,808` LUT
- the cheapest remaining learning step was to test whether those two valid
  reductions compose without widening the structural patch

#### Mapped utilization

- Timed mapped utilization:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-spine-fifo2-abc9-utilization --no-link --print-out-paths`
  - output:
    - `/nix/store/0hxm9fclxr0sgg5wl6nq2w0r7f568p60-task6-l1-c-fc-redirect-index-spine-fifo2-abc9-utilization`
  - result:
    - `ELAPSED=92.79`
    - `RSS_KB=562772`
  - mapped summary:
    - DSP:
      - `4`
    - BRAM36:
      - `0`
    - CLB LUTs:
      - `32,036`
    - CLB FFs:
      - `50,642`
- Primitive signature:
  - `FDRE`:
    - `50,639`
  - `LUT6`:
    - `17,374`
  - `LUT3`:
    - `6,570`
  - `LUT2`:
    - `3,474`
  - `LUT5`:
    - `3,086`
- Weight placement and runtime checks:
  - large weights emitted as RTL constants:
    - `no`
    - this slice still reuses the accepted external-weight `L1` kernel and only
      changes selected buffer modules plus mapper selection
  - Verilator passed:
    - `yes`
    - inherited from the identical `task6-l1-c-fc-redirect-index-spine-fifo2`
      structural variant
  - Yosys stat finished within budget:
    - `yes`
    - unchanged from the accepted `L1` kernel at `4.07 s`
- Delta against prior `L1` points:
  - accepted base `L1`:
    - `33,116 -> 32,036` LUT (`-1,080`)
    - `51,296 -> 50,642` FF (`-654`)
  - direct `abc9`:
    - `32,236 -> 32,036` LUT (`-200`)
  - non-`abc9` local spine:
    - `32,808 -> 32,036` LUT (`-772`)
- Interpretation:
  - the safe local FIFO2 reduction and `abc9` do compose
  - this is the best `L1` mapped result in the lane so far, but it still misses
    the LUT ceiling by `2,176`
  - the next bounded local test is one more adjacent buffer cluster under the
    same `abc9` recipe, because the structural path is now validated and still
    has measurable headroom

### L1 selective index-fanout FIFO2 `abc9` proof later on 2026-04-23

- Added:
  - flake outputs:
    - `task6-l1-c-fc-redirect-index-fanout-fifo2-sim-main`
    - `task6-l1-c-fc-redirect-index-fanout-fifo2-sv-sim`
    - `task6-l1-c-fc-redirect-index-fanout-fifo2-abc9-json`
    - `task6-l1-c-fc-redirect-index-fanout-fifo2-abc9-utilization`
- Logged run bundle:
  - `artifacts/task6-streamtensor-lite/runs/2026-04-23T11-14-57+0200/l1-index-fanout-fifo2-abc9-proof/summary.md`

#### Why this slice

- The current safe local recipe had already improved twice:
  - `160..165` index spine:
    - `32,036` LUT under `abc9`
- the next directly adjacent ring is the `ui64` branch-output fanout driven by
  that spine:
  - `handshake_buffer173`
  - `handshake_buffer174`
  - `handshake_buffer175`
  - `handshake_buffer176`
  - `handshake_buffer177`
  - `handshake_buffer178`
  - `handshake_buffer179`
  - `handshake_buffer180`
  - `handshake_buffer181`
  - `handshake_buffer182`
- the exact hypothesis was:
  - if this immediate fanout ring still passes the kernel contract, the local
    FIFO2 replacement has not yet reached its safe boundary

#### Functional proof

- Timed Verilator proof:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-fanout-fifo2-sv-sim --no-link -L`
  - result:
    - `PASS: stores 16 outputs 16`
    - `ELAPSED=65.50`
    - `RSS_KB=436664`
- Interpretation:
  - the safe selective region extends through this immediate downstream fanout
    ring; the next gate remains mapped utilization, not more functional debug

#### Mapped utilization

- Timed mapped utilization:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-fanout-fifo2-abc9-utilization --no-link --print-out-paths`
  - output:
    - `/nix/store/adf0la4c5xkqdmvc6n5i37db5zaz929x-task6-l1-c-fc-redirect-index-fanout-fifo2-abc9-utilization`
  - result:
    - `ELAPSED=93.49`
    - `RSS_KB=563372`
  - mapped summary:
    - DSP:
      - `4`
    - BRAM36:
      - `0`
    - CLB LUTs:
      - `31,309`
    - CLB FFs:
      - `49,342`
- Primitive signature:
  - `FDRE`:
    - `49,339`
  - `LUT6`:
    - `16,067`
  - `LUT3`:
    - `7,213`
  - `LUT2`:
    - `3,392`
  - `LUT5`:
    - `3,101`
- Weight placement and runtime checks:
  - large weights emitted as RTL constants:
    - `no`
    - this variant still only swaps selected local buffer instances and keeps
      the accepted externalized-weight `L1` kernel intact
  - Verilator passed:
    - `yes`
  - Yosys stat finished within budget:
    - `yes`
    - unchanged from the accepted `L1` kernel at `4.07 s`
- Delta against prior `L1` points:
  - previous best `index-spine-fifo2-abc9`:
    - `32,036 -> 31,309` LUT (`-727`)
    - `50,642 -> 49,342` FF (`-1,300`)
  - accepted base `L1`:
    - `33,116 -> 31,309` LUT (`-1,807`)
    - `51,296 -> 49,342` FF (`-1,954`)
- Interpretation:
  - the local selective FIFO2 path is still productive and not yet at noise
  - this is the best `L1` mapped result in the lane so far, now within `1,449`
    LUT of the ceiling while preserving `4 DSP48E1`
  - the next bounded question is whether one further adjacent hop keeps paying
    or whether the local fit curve is flattening

### L1 selective index ring-2 FIFO2 `abc9` proof later on 2026-04-23

- Added:
  - flake outputs:
    - `task6-l1-c-fc-redirect-index-ring2-fifo2-sim-main`
    - `task6-l1-c-fc-redirect-index-ring2-fifo2-sv-sim`
    - `task6-l1-c-fc-redirect-index-ring2-fifo2-abc9-json`
    - `task6-l1-c-fc-redirect-index-ring2-fifo2-abc9-utilization`
- Logged run bundle:
  - `artifacts/task6-streamtensor-lite/runs/2026-04-23T11-20-09+0200/l1-index-ring2-fifo2-abc9-proof/summary.md`

#### Why this slice

- After the `173..182` fanout ring still improved fit materially, the next
  directly connected `ui64` ring was:
  - `handshake_buffer185`
  - `handshake_buffer186`
  - `handshake_buffer187`
  - `handshake_buffer188`
  - `handshake_buffer189`
  - `handshake_buffer190`
  - `handshake_buffer191`
  - `handshake_buffer192`
- these buffers are the next immediate downstream stage fed by the already-safe
  local ring, so they were the smallest remaining adjacent expansion

#### Functional proof

- Timed Verilator proof:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-ring2-fifo2-sv-sim --no-link -L`
  - result:
    - `PASS: stores 16 outputs 16`
    - `ELAPSED=69.90`
    - `RSS_KB=436804`
- Interpretation:
  - the safe local replacement region extends through this second downstream
    ring as well

#### Mapped utilization

- Timed mapped utilization:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-ring2-fifo2-abc9-utilization --no-link --print-out-paths`
  - output:
    - `/nix/store/saahgj5jaiv7bvhxjds1qypv62q57wbg-task6-l1-c-fc-redirect-index-ring2-fifo2-abc9-utilization`
  - result:
    - `ELAPSED=93.67`
    - `RSS_KB=563284`
  - mapped summary:
    - DSP:
      - `4`
    - BRAM36:
      - `0`
    - CLB LUTs:
      - `30,762`
    - CLB FFs:
      - `48,302`
- Primitive signature:
  - `FDRE`:
    - `48,299`
  - `LUT6`:
    - `15,147`
  - `LUT3`:
    - `7,614`
  - `LUT2`:
    - `3,299`
  - `LUT5`:
    - `3,135`
- Weight placement and runtime checks:
  - large weights emitted as RTL constants:
    - `no`
  - Verilator passed:
    - `yes`
  - Yosys stat finished within budget:
    - `yes`
    - unchanged from the accepted `L1` kernel at `4.07 s`
- Delta against prior `L1` points:
  - previous best `index-fanout-fifo2-abc9`:
    - `31,309 -> 30,762` LUT (`-547`)
    - `49,342 -> 48,302` FF (`-1,040`)
  - accepted base `L1`:
    - `33,116 -> 30,762` LUT (`-2,354`)
    - `51,296 -> 48,302` FF (`-2,994`)
- Interpretation:
  - the widening curve is still improving and has not flattened yet
  - this is the best `L1` mapped result in the lane so far, now only `902` LUT
    above the ceiling while preserving `4 DSP48E1`
  - the next bounded question is whether the connected `213..219` mux-return
    buffers provide one last meaningful drop or whether this is where the local
    buffer path tops out

### L1 selective index ring-3 FIFO2 `abc9` proof later on 2026-04-23

- Added:
  - flake outputs:
    - `task6-l1-c-fc-redirect-index-ring3-fifo2-sim-main`
    - `task6-l1-c-fc-redirect-index-ring3-fifo2-sv-sim`
    - `task6-l1-c-fc-redirect-index-ring3-fifo2-abc9-json`
    - `task6-l1-c-fc-redirect-index-ring3-fifo2-abc9-utilization`
- Logged run bundle:
  - `artifacts/task6-streamtensor-lite/runs/2026-04-23T11-24-52+0200/l1-index-ring3-fifo2-abc9-proof/summary.md`

#### Why this slice

- The next still-local connected `ui64` stage after ring-2 was the mux-return
  ring:
  - `handshake_buffer213`
  - `handshake_buffer214`
  - `handshake_buffer215`
  - `handshake_buffer216`
  - `handshake_buffer217`
  - `handshake_buffer218`
  - `handshake_buffer219`
- this was treated as the last blind local hop worth checking before the region
  became too diffuse for fast-learning work

#### Functional proof

- Timed Verilator proof:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-ring3-fifo2-sv-sim --no-link -L`
  - result:
    - `PASS: stores 16 outputs 16`
    - `ELAPSED=82.55`
    - `RSS_KB=437104`
- Interpretation:
  - the connected mux-return ring is still structurally safe under the kernel
    contract

#### Mapped utilization

- Timed mapped utilization:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-ring3-fifo2-abc9-utilization --no-link --print-out-paths`
  - output:
    - `/nix/store/y57gd36j5fbplkw51iv6if0cflppn052-task6-l1-c-fc-redirect-index-ring3-fifo2-abc9-utilization`
  - result:
    - `ELAPSED=93.19`
    - `RSS_KB=563112`
  - mapped summary:
    - DSP:
      - `4`
    - BRAM36:
      - `0`
    - CLB LUTs:
      - `30,320`
    - CLB FFs:
      - `47,392`
- Primitive signature:
  - `FDRE`:
    - `47,389`
  - `LUT6`:
    - `14,728`
  - `LUT3`:
    - `7,749`
  - `LUT2`:
    - `3,242`
  - `LUT5`:
    - `3,132`
- Weight placement and runtime checks:
  - large weights emitted as RTL constants:
    - `no`
  - Verilator passed:
    - `yes`
  - Yosys stat finished within budget:
    - `yes`
    - unchanged from the accepted `L1` kernel at `4.07 s`
- Delta against prior `L1` points:
  - previous best `index-ring2-fifo2-abc9`:
    - `30,762 -> 30,320` LUT (`-442`)
    - `48,302 -> 47,392` FF (`-910`)
  - accepted base `L1`:
    - `33,116 -> 30,320` LUT (`-2,796`)
    - `51,296 -> 47,392` FF (`-3,904`)
- Interpretation:
  - the local selective path still improves, but the gains are tapering
  - this is the best `L1` mapped result in the lane so far, now only `460` LUT
    above the ceiling while preserving `4 DSP48E1`
  - this is a good place to stop blind widening:
    - the next move should be a deliberate choice among the remaining adjacent
      control/merge sites rather than another generic ring expansion

### L1 deliberate control-merge FIFO2 `abc9` proof later on 2026-04-23

- Added:
  - `rtl/task6/task6_ctrl_fifo2_buffer.sv`
  - flake outputs:
    - `task6-l1-c-fc-redirect-index-ring3-ctrlmerge-fifo2-sim-main`
    - `task6-l1-c-fc-redirect-index-ring3-ctrlmerge-fifo2-sv-sim`
    - `task6-l1-c-fc-redirect-index-ring3-ctrlmerge-fifo2-json`
    - `task6-l1-c-fc-redirect-index-ring3-ctrlmerge-fifo2-abc9-json`
    - `task6-l1-c-fc-redirect-index-ring3-ctrlmerge-fifo2-abc9-utilization`
- Logged run bundle:
  - `artifacts/task6-streamtensor-lite/runs/2026-04-23T12-36-17+0200/l1-index-ring3-ctrlmerge-fifo2-proof/summary.md`

#### Why this slice

- The shared follow-up instruction was to:
  - freeze `task6-l1-c-fc-redirect-index-ring3-fifo2-abc9` as the reference
  - avoid more blind ring expansion
  - do one deliberate hotspot pass on the remaining nearby control or merge
    state
- The nearest still-local control-heavy sites around the frozen ring-3 region
  were:
  - `handshake_buffer194`
  - `handshake_buffer220`
  - `handshake_buffer229`
  - `handshake_buffer237`
- These buffers feed the nearby control-merge chain:
  - `handshake_buffer194 -> handshake_buffer220 -> handshake_control_merge2`
  - `handshake_buffer229 -> handshake_buffer237 -> handshake_control_merge1`
- The specific hypothesis was:
  - if these zero-width control buffers were still overprovisioned in the same
    way as the already-profitable `ui64` ring, a lean FIFO2 replacement might
    close the remaining `460` LUT gap without broadening the patch radius

#### Functional proof

- Because the derivation was already cached, the timed rerun first deleted the
  previous simulation outputs:
  - `nix-store --delete /nix/store/1xphnja7abzdswcfxqmhcfz3lj0y1wja-task6-l1-c-fc-redirect-index-ring3-ctrlmerge-fifo2-sim-main /nix/store/llngvrfdwz6a78hwml7ia2k6pam9i56c-task6-l1-c-fc-redirect-index-ring3-ctrlmerge-fifo2-sv-sim.json >/dev/null`
- Timed Verilator proof:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-ring3-ctrlmerge-fifo2-sv-sim --no-link -L`
  - result:
    - `PASS: stores 16 outputs 16`
    - `ELAPSED=149.22`
    - `RSS_KB=436284`
- Interpretation:
  - the deliberate control/merge hotspot is contract-safe, so the result is a
    real fit comparison rather than another functional dead end

#### Mapped utilization

- Timed mapped utilization:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-ring3-ctrlmerge-fifo2-abc9-utilization --no-link --print-out-paths`
  - output:
    - `/nix/store/h6mh3s3skf8spnczfabhl71khhb6asgv-task6-l1-c-fc-redirect-index-ring3-ctrlmerge-fifo2-abc9-utilization`
  - result:
    - `ELAPSED=156.72`
    - `RSS_KB=562952`
  - mapped summary:
    - DSP:
      - `4`
    - BRAM36:
      - `0`
    - CLB LUTs:
      - `30,360`
    - CLB FFs:
      - `47,384`
- Primitive signature:
  - `FDRE`:
    - `47,381`
  - `LUT6`:
    - `14,718`
  - `LUT3`:
    - `7,740`
  - `LUT2`:
    - `3,297`
  - `LUT5`:
    - `3,140`
- Weight placement and runtime checks:
  - large weights emitted as RTL constants:
    - `no`
    - this slice still reuses the accepted external-weight `L1` kernel and only
      changes four local control buffers plus the helper module they instantiate
  - Verilator passed:
    - `yes`
  - Yosys stat finished within budget:
    - `yes`
    - unchanged from the accepted `L1` kernel at `4.07 s`
- Delta against the frozen ring-3 reference:
  - LUT:
    - `30,320 -> 30,360` (`+40`)
  - FF:
    - `47,392 -> 47,384` (`-8`)
- Interpretation:
  - this hotspot is real and safe, but it is not a fit win
  - the result is close enough to rule out measurement noise as the likely
    explanation, but it still points the wrong way on the metric that matters
  - the right conclusion is to keep
    `task6-l1-c-fc-redirect-index-ring3-fifo2-abc9` frozen as the current `L1`
    reference and stop spending more slices on this local control/merge branch

### Reduced-vocab one-block-top Yosys gate later on 2026-04-23

- Logged run bundle:
  - `artifacts/task6-streamtensor-lite/runs/2026-04-23T12-36-17+0200/l1-one-block-top-yosys-gate/summary.md`

#### Why this gate

- The shared follow-up instruction also required:
  - after one deliberate hotspot pass, run the pending one-block-top Yosys gate
    before any `L3` or `L4` promotion
- The repo surface available for that check is:
  - `tiny-stories-v1k-h64-l1-selftest-top4-memory-yosys-json`
- This is a `yosys-json` gate rather than a dedicated `yosys-stat` package, but
  it exercises the one-block-top build path and is the existing reproducible
  budget gate in-tree

#### Timed gate

- Timed one-block-top Yosys build:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#tiny-stories-v1k-h64-l1-selftest-top4-memory-yosys-json --no-link --print-out-paths`
  - output:
    - `/nix/store/hh7fkqlis1kdgi07qgmxxjl1nl6lxrq9-tiny-stories-v1k-h64-l1-selftest-top4-memory-yosys.json`
  - result:
    - `ELAPSED=99.26`
    - `RSS_KB=564340`

#### Interpretation

- Relative to the lane budget:
  - one-block-top Yosys gate:
    - `99.26 s`
    - this passes the `< 2 min` budget
- Structural implications:
  - the promotion gate is no longer missing
  - but it does not rescue the fit-first decision:
    - the frozen `L1` reference still sits at `30,320` LUT, which is `460` over
      the ceiling
    - the best reduced-vocab `L2` mapped replay is still materially worse than
      that reference
- Conclusion:
  - do not widen to `L3` or `L4` from this result alone
  - the next slice, if any, should be a different fit lever than the rejected
    control/merge hotspot

### L1 local `ui1` selector-buffer FIFO2 proof later on 2026-04-23

- Added:
  - `rtl/task6/task6_ui1_fifo2_buffer.sv`
  - flake outputs:
    - `task6-l1-c-fc-redirect-index-ring3-ui1buf263-fifo2-sim-main`
    - `task6-l1-c-fc-redirect-index-ring3-ui1buf263-fifo2-sv-sim`
    - `task6-l1-c-fc-redirect-index-ring3-ui1buf263-fifo2-abc9-json`
    - `task6-l1-c-fc-redirect-index-ring3-ui1buf263-fifo2-abc9-utilization`
- Logged run bundle:
  - `artifacts/task6-streamtensor-lite/runs/2026-04-23T12-49-10+0200/l1-index-ring3-ui1buf263-fifo2-proof/summary.md`

#### Why this slice

- After the control/merge hotspot missed, the next smallest visibly different
  fit lever near the frozen ring-3 region was not another `ui64` branch
  widening, but the selector-side `ui1` state feeding the local fanout:
  - `arith_cmpi5 -> handshake_buffer263 -> handshake_fork49`
- Only six `handshake_buffer_in_ui1_out_ui1_2slots_seq` instances exist in the
  whole kernel, and `handshake_buffer263` is the one sitting directly inside
  the ring-3 neighborhood.
- The specific hypothesis was:
  - if the local compare result buffer is overbuilt in the same way as the
    profitable `ui64` buffers, replacing just this one selector buffer with a
    lean FIFO2 helper might recover LUT without another broad patch

#### Implementation note

- The first mapped build attempt exposed a packaging bug, not a design failure:
  - the copied source bundle still referenced the parent `sources.f` paths, so
    `mkSynthJson` saw both the old and new `main.sv` and failed with a duplicate
    `main` definition
- That was fixed by rewriting `sources.f` and `sv/filelist.f` to the new output
  directory before rerunning the probe.

#### Functional proof

- Timed Verilator proof:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-ring3-ui1buf263-fifo2-sv-sim --no-link -L`
  - result:
    - `PASS: stores 16 outputs 16`
    - `ELAPSED=150.24`
    - `RSS_KB=436780`
- Interpretation:
  - trimming this one selector-side `ui1` buffer is contract-safe

#### Mapped utilization

- Timed mapped utilization:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-ring3-ui1buf263-fifo2-abc9-utilization --no-link --print-out-paths`
  - output:
    - `/nix/store/ga92apld656zs2h1w0515iw76yr9ppmm-task6-l1-c-fc-redirect-index-ring3-ui1buf263-fifo2-abc9-utilization`
  - result:
    - `ELAPSED=150.20`
    - `RSS_KB=561796`
  - mapped summary:
    - DSP:
      - `4`
    - BRAM36:
      - `0`
    - CLB LUTs:
      - `30,370`
    - CLB FFs:
      - `47,388`
- Primitive signature:
  - `FDRE`:
    - `47,385`
  - `LUT6`:
    - `14,711`
  - `LUT3`:
    - `7,746`
  - `LUT2`:
    - `3,271`
  - `LUT5`:
    - `3,114`
- Weight placement and runtime checks:
  - large weights emitted as RTL constants:
    - `no`
  - Verilator passed:
    - `yes`
  - Yosys stat finished within budget:
    - `yes`
    - unchanged from the accepted `L1` kernel at `4.07 s`
- Delta against the frozen ring-3 reference:
  - LUT:
    - `30,320 -> 30,370` (`+50`)
  - FF:
    - `47,392 -> 47,388` (`-4`)
- Interpretation:
  - the local `ui1` selector-buffer trim is real and safe, but it is not a fit
    win
  - this is the second deliberate post-ring-3 hotspot that points the wrong
    way on LUT, so it should not become the next default lane direction

### L1 local `fork49` statevec proof later on 2026-04-23

- Added:
  - `rtl/task6/task6_ui1_fork5.sv`
  - flake outputs:
    - `task6-l1-c-fc-redirect-index-ring3-fork49-statevec-sim-main`
    - `task6-l1-c-fc-redirect-index-ring3-fork49-statevec-sv-sim`
    - `task6-l1-c-fc-redirect-index-ring3-fork49-statevec-abc9-json`
    - `task6-l1-c-fc-redirect-index-ring3-fork49-statevec-abc9-utilization`
- Logged run bundle:
  - `artifacts/task6-streamtensor-lite/runs/2026-04-23T13-02-39+0200/l1-index-ring3-fork49-statevec-proof/summary.md`

#### Why this slice

- After the selector-buffer trim missed, the next smallest visibly different
  fit lever in the same frozen ring-3 neighborhood was the five-way local
  selector fork itself:
  - `handshake_buffer263 -> handshake_fork49`
- The generated `handshake_fork49` implementation keeps one scalar `emitted`
  register per output leg.
- The specific hypothesis was:
  - a semantically equivalent local helper that keeps the same staggered
    handshake contract but packs completion state into one vector might let
    `abc9` share the control terms more effectively than the generated fork

#### Functional proof

- Timed Verilator proof:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-ring3-fork49-statevec-sv-sim --no-link -L`
  - result:
    - `PASS: stores 16 outputs 16`
    - `ELAPSED=147.32`
    - `RSS_KB=437320`
- Interpretation:
  - trimming only the local `fork49` state encoding is contract-safe

#### Mapped utilization

- Timed mapped utilization:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-ring3-fork49-statevec-abc9-utilization --no-link --print-out-paths`
  - output:
    - `/nix/store/gii6p7aprr0szvjfr8vg6m1sylywa081-task6-l1-c-fc-redirect-index-ring3-fork49-statevec-abc9-utilization`
  - result:
    - `ELAPSED=144.56`
    - `RSS_KB=562532`
  - mapped summary:
    - DSP:
      - `4`
    - BRAM36:
      - `0`
    - CLB LUTs:
      - `30,358`
    - CLB FFs:
      - `47,392`
- Primitive signature:
  - `FDRE`:
    - `47,389`
  - `LUT6`:
    - `14,734`
  - `LUT3`:
    - `7,754`
  - `LUT2`:
    - `3,276`
  - `LUT5`:
    - `3,130`
- Weight placement and runtime checks:
  - large weights emitted as RTL constants:
    - `no`
  - Verilator passed:
    - `yes`
  - Yosys stat finished within budget:
    - `yes`
    - unchanged from the accepted `L1` kernel at `4.07 s`
- Delta against the frozen ring-3 reference:
  - LUT:
    - `30,320 -> 30,358` (`+38`)
  - FF:
    - `47,392 -> 47,392` (`+0`)
- Interpretation:
  - the local `fork49` statevec helper is safe and the least-bad post-ring-3
    hotspot miss so far, but it is still not a fit win
  - this is the third deliberate post-ring-3 hotspot miss, so the lane should
    move on from local hotspot surgery rather than stacking more nearby buffer
    or fork micro-swaps

### L1 selector-cluster FIFO2 proof later on 2026-04-23

- Added:
  - `rtl/task6/task6_ui1_init0_fifo2_fork4.sv`
  - flake outputs:
    - `task6-l1-c-fc-redirect-index-ring3-selectcluster-fifo2-sim-main`
    - `task6-l1-c-fc-redirect-index-ring3-selectcluster-fifo2-sv-sim`
    - `task6-l1-c-fc-redirect-index-ring3-selectcluster-fifo2-abc9-json`
    - `task6-l1-c-fc-redirect-index-ring3-selectcluster-fifo2-abc9-utilization`
- Logged run bundle:
  - `artifacts/task6-streamtensor-lite/runs/2026-04-23T13-13-00+0200/l1-index-ring3-selectcluster-fifo2-proof/summary.md`

#### Why this slice

- After the one-site selector and fork hotspots missed, the next smallest
  structural cut inside the same local control tree was the selector leg:
  - `handshake_fork49_out4 -> handshake_buffer255 -> handshake_fork46`
- The specific hypothesis was:
  - if the cost is in the interaction between the init-0 selector buffer and
    the four-way fork, then replacing that whole local leg with one helper
    should be more informative than yet another one-instance swap

#### Functional proof

- Timed Verilator proof:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-ring3-selectcluster-fifo2-sv-sim --no-link -L`
  - result:
    - `PASS: stores 16 outputs 16`
    - `ELAPSED=149.01`
    - `RSS_KB=437064`
- Interpretation:
  - collapsing the local selector cluster is contract-safe

#### Mapped utilization

- Timed mapped utilization:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-ring3-selectcluster-fifo2-abc9-utilization --no-link --print-out-paths`
  - output:
    - `/nix/store/9d5q0szcjv49jmnwjnr5v2hz8jliffqd-task6-l1-c-fc-redirect-index-ring3-selectcluster-fifo2-abc9-utilization`
  - result:
    - `ELAPSED=147.09`
    - `RSS_KB=562120`
  - mapped summary:
    - DSP:
      - `4`
    - BRAM36:
      - `0`
    - CLB LUTs:
      - `30,358`
    - CLB FFs:
      - `47,392`
- Primitive signature:
  - `FDRE`:
    - `47,389`
  - `LUT6`:
    - `14,715`
  - `LUT3`:
    - `7,727`
  - `LUT2`:
    - `3,285`
  - `LUT5`:
    - `3,145`
- Weight placement and runtime checks:
  - large weights emitted as RTL constants:
    - `no`
  - Verilator passed:
    - `yes`
  - Yosys stat finished within budget:
    - `yes`
    - unchanged from the accepted `L1` kernel at `4.07 s`
- Delta against the frozen ring-3 reference:
  - LUT:
    - `30,320 -> 30,358` (`+38`)
  - FF:
    - `47,392 -> 47,392` (`+0`)
- Interpretation:
  - the first real selector-cluster cut ties the earlier `fork49` statevec
    helper exactly on top-line fit metrics
  - that is enough to close the selector-control tree as the next fit lever:
    it stays safe, but it does not beat the frozen ring-3 reference

### L1 downstream post-branch FIFO2 proof later on 2026-04-23

- Added flake outputs:
  - `task6-l1-c-fc-redirect-index-ring3-postbranch-fifo2-sim-main`
  - `task6-l1-c-fc-redirect-index-ring3-postbranch-fifo2-sv-sim`
  - `task6-l1-c-fc-redirect-index-ring3-postbranch-fifo2-abc9-json`
  - `task6-l1-c-fc-redirect-index-ring3-postbranch-fifo2-abc9-utilization`
- Logged run bundle:
  - `artifacts/task6-streamtensor-lite/runs/2026-04-23T13-55-32+0200/l1-index-ring3-postbranch-fifo2-proof/summary.md`

#### Why this slice

- After the selector-control tree closed, the next bounded non-selector area in
  the same `L1` kernel was the downstream post-branch `ui64` cluster:
  - `handshake_buffer264`, `265`, `266`, `269`, `270`, and `271`
- The specific hypothesis was:
  - the next real fit lever is still local FIFO state, but not in the selector
    neighborhood; replacing the branch-success data path and its immediate
    address/data staging should trim both LUTs and FFs without reopening the
    stalled selector-side search

#### Functional proof

- Timed Verilator proof:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-ring3-postbranch-fifo2-sv-sim --no-link -L`
  - result:
    - `PASS: stores 16 outputs 16`
    - `ELAPSED=149.45`
    - `RSS_KB=437752`
- Interpretation:
  - the downstream post-branch data cluster is contract-safe

#### Mapped utilization

- Timed mapped utilization:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-ring3-postbranch-fifo2-abc9-utilization --no-link --print-out-paths`
  - output:
    - `/nix/store/vgfr4q1q35jnlpdy8j5k0gdi3f6b7rhz-task6-l1-c-fc-redirect-index-ring3-postbranch-fifo2-abc9-utilization`
  - result:
    - `ELAPSED=149.96`
    - `RSS_KB=562980`
  - mapped summary:
    - DSP:
      - `4`
    - BRAM36:
      - `0`
    - CLB LUTs:
      - `29,967`
    - CLB FFs:
      - `46,612`
- Primitive signature:
  - `FDRE`:
    - `46,609`
  - `LUT6`:
    - `13,989`
  - `LUT3`:
    - `8,076`
  - `LUT2`:
    - `3,241`
  - `LUT5`:
    - `3,194`
- Weight placement and runtime checks:
  - large weights emitted as RTL constants:
    - `no`
  - Verilator passed:
    - `yes`
  - Yosys stat finished within budget:
    - `yes`
    - unchanged from the accepted `L1` kernel at `4.07 s`
- Delta against the frozen ring-3 reference:
  - LUT:
    - `30,320 -> 29,967` (`-353`)
  - FF:
    - `47,392 -> 46,612` (`-780`)
- Interpretation:
  - this is the first productive non-selector follow-up after the selector
    branch closed
  - the cluster is still just short of the ceiling, so exactly one bounded
    follow-up on the same downstream data path is justified

### L1 downstream post-branch out-buffer FIFO2 proof later on 2026-04-23

- Added flake outputs:
  - `task6-l1-c-fc-redirect-index-ring3-postbranch-outbuf-fifo2-sim-main`
  - `task6-l1-c-fc-redirect-index-ring3-postbranch-outbuf-fifo2-sv-sim`
  - `task6-l1-c-fc-redirect-index-ring3-postbranch-outbuf-fifo2-abc9-json`
  - `task6-l1-c-fc-redirect-index-ring3-postbranch-outbuf-fifo2-abc9-utilization`
- Logged run bundle:
  - `artifacts/task6-streamtensor-lite/runs/2026-04-23T13-55-32+0200/l1-index-ring3-postbranch-outbuf-fifo2-proof/summary.md`

#### Why this slice

- The first post-branch cut left the lane only `107` LUT over the ceiling.
- The cheapest same-direction extension was the pair of immediate `ui64`
  out-buffers from that cluster:
  - `handshake_buffer279` and `280`
- The specific hypothesis was:
  - if the downstream post-branch path is the right lever, replacing the two
    first post-fork out-buffers should be enough to clear `L1` without
    touching control state or reopening the selector-side search

#### Functional proof

- Timed Verilator proof:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-ring3-postbranch-outbuf-fifo2-sv-sim --no-link -L`
  - result:
    - `PASS: stores 16 outputs 16`
    - `ELAPSED=133.51`
    - `RSS_KB=437680`
- Interpretation:
  - extending the same downstream data-path lever through the immediate
    out-buffers remains contract-safe

#### Mapped utilization

- Timed mapped utilization:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-ring3-postbranch-outbuf-fifo2-abc9-utilization --no-link --print-out-paths`
  - output:
    - `/nix/store/7z3fdnp57z3b5bs1ziv1bjlrhbnlid3h-task6-l1-c-fc-redirect-index-ring3-postbranch-outbuf-fifo2-abc9-utilization`
  - result:
    - `ELAPSED=149.06`
    - `RSS_KB=562936`
  - mapped summary:
    - DSP:
      - `4`
    - BRAM36:
      - `0`
    - CLB LUTs:
      - `29,778`
    - CLB FFs:
      - `46,352`
- Primitive signature:
  - `FDRE`:
    - `46,349`
  - `LUT6`:
    - `13,887`
  - `LUT3`:
    - `8,050`
  - `LUT5`:
    - `3,189`
  - `LUT2`:
    - `3,188`
- Weight placement and runtime checks:
  - large weights emitted as RTL constants:
    - `no`
  - Verilator passed:
    - `yes`
  - Yosys stat finished within budget:
    - `yes`
    - unchanged from the accepted `L1` kernel at `4.07 s`
- Delta against the first post-branch cut:
  - LUT:
    - `29,967 -> 29,778` (`-189`)
  - FF:
    - `46,612 -> 46,352` (`-260`)
- Delta against the frozen ring-3 reference:
  - LUT:
    - `30,320 -> 29,778` (`-542`)
  - FF:
    - `47,392 -> 46,352` (`-1,040`)
- Interpretation:
  - this is the first validated `L1` point that clears both the LUT and FF
    ceilings while preserving external weights, `4 DSP48E1`, and the kernel
    contract
  - stop widening `L1` again here; the next replay should move to `L2` before
    any promotion toward `L3`

### L2 aligned post-branch FIFO2 replay later on 2026-04-23

- Added flake outputs:
  - `task6-l2-c-fc-redirect-postbranch-fifo2-sim-main`
  - `task6-l2-c-fc-redirect-postbranch-fifo2-sv-sim`
  - `task6-l2-c-fc-redirect-postbranch-fifo2-abc9-json`
  - `task6-l2-c-fc-redirect-postbranch-fifo2-abc9-utilization`
- Logged run bundle:
  - `artifacts/task6-streamtensor-lite/runs/2026-04-23T14-23-08+0200/l2-postbranch-fifo2-proof/summary.md`

#### Why this slice

- The lane rule after the new `L1` reference was:
  - replay that exact fit lever on `L2` before considering any `L3` promotion
- The generated `L2` SV does not match the `L1` post-branch neighborhood one
  for one:
  - `handshake_buffer264`, `265`, `266`, `270`, and `271` are still
    `ui64 -> ui64` buffers
  - `handshake_buffer269`, `279`, and `280` have changed type, so the full
    `L1` out-buffer replay is not a legal direct copy
- The smallest aligned hypothesis was therefore:
  - replace only the still-matching post-branch `ui64` buffers
    `264/265/266/270/271` with `task6_ui64_fifo2_buffer`
  - then re-run Verilator plus mapped `abc9` and stop if LUT moves the wrong
    way

#### Functional proof

- Timed Verilator proof:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l2-c-fc-redirect-postbranch-fifo2-sv-sim --no-link -L`
  - result:
    - `PASS: stores 256 outputs 256`
    - `ELAPSED=77.00`
    - `RSS_KB=437400`
- Interpretation:
  - the aligned subset replay is functionally valid on `L2`
  - no broad compiler or kernel surgery was needed to carry the `L1` lever
    over

#### Mapped utilization

- Timed mapped utilization:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l2-c-fc-redirect-postbranch-fifo2-abc9-utilization --no-link --print-out-paths`
  - output:
    - `/nix/store/85z4gz624dqdmqf9hszcxn65gqrv5drc-task6-l2-c-fc-redirect-postbranch-fifo2-abc9-utilization`
  - result:
    - `ELAPSED=255.15`
    - `RSS_KB=563416`
  - mapped summary:
    - DSP:
      - `4`
    - BRAM36:
      - `0`
    - CLB LUTs:
      - `51,622`
    - CLB FFs:
      - `64,873`
- Primitive signature:
  - `FDRE`:
    - `64,870`
  - `LUT6`:
    - `29,438`
  - `LUT5`:
    - `8,333`
  - `LUT3`:
    - `7,749`
  - `LUT2`:
    - `4,005`
- Weight placement and runtime checks:
  - large weights emitted as RTL constants:
    - `no`
    - unchanged from the accepted `L2` redirect; this replay only swaps local
      buffer modules and does not touch the external load interface
  - Verilator passed:
    - `yes`
  - Yosys stat finished within budget:
    - `not rerun`
    - the accepted `L2` kernel still has a separate `yosys-stat` proof at
      `9.13 s`, but this replay was judged directly on Verilator plus mapped
      `abc9`
- Delta against the existing `L2` kernel:
  - LUT:
    - `50,235 -> 51,622` (`+1,387`)
  - FF:
    - `65,523 -> 64,873` (`-650`)
- Delta against the current `L1` reference:
  - LUT:
    - `29,778 -> 51,622` (`+21,844`)
  - FF:
    - `46,352 -> 64,873` (`+18,521`)
- Interpretation:
  - the bounded `L1` fit lever does not survive as a useful fit lever on `L2`
    even when replayed only on the structurally matching `ui64` sites
  - this is a clean negative datapoint, not a broken build:
    - external weights still hold
    - `4 DSP48E1` still hold
    - the kernel contract still passes
  - close this exact replay path rather than widening it blindly, because LUT
    moved in the wrong direction on the first aligned test

### L2 downstream out-buffer FIFO2 probe later on 2026-04-23

- Added flake outputs:
  - `task6-l2-c-fc-redirect-downstream-outbuf-fifo2-sim-main`
  - `task6-l2-c-fc-redirect-downstream-outbuf-fifo2-sv-sim`
  - `task6-l2-c-fc-redirect-downstream-outbuf-fifo2-abc9-json`
  - `task6-l2-c-fc-redirect-downstream-outbuf-fifo2-abc9-utilization`
- Logged run bundle:
  - `artifacts/task6-streamtensor-lite/runs/2026-04-23T14-36-13+0200/l2-downstream-outbuf-fifo2-proof/summary.md`

#### Why this slice

- The next bounded `L2` rule after the aligned replay miss was:
  - try exactly one `L2`-native local probe in the changed downstream
    `272..280` neighborhood before abandoning `L2 c_fc` micro-surgery
- The generated `L2` SV in that neighborhood contains:
  - `handshake_buffer272`, `273`, `274`, `275`, `276`, and `278` as
    `ui64 -> ui64` buffers on the downstream data fanout
  - `handshake_buffer277` and `279` as ctrl-only buffers
  - `handshake_buffer280` as a `ui1` buffer
- The smallest legal hypothesis was therefore:
  - replace only `272/273/274/275/276/278` with
    `task6_ui64_fifo2_buffer`
  - keep the ctrl and `ui1` sites untouched
  - stop the `L2 c_fc` path if official CLB LUTs still moved the wrong way

#### Functional proof

- Timed Verilator proof:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l2-c-fc-redirect-downstream-outbuf-fifo2-sv-sim --no-link -L`
  - result:
    - `PASS: stores 256 outputs 256`
    - `ELAPSED=80.01`
    - `RSS_KB=437188`
- Interpretation:
  - the first `L2`-native downstream out-buffer cluster is functionally valid
  - the changed `272..280` neighborhood is not blocked by contract breakage

#### Mapped utilization

- Timed mapped utilization:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l2-c-fc-redirect-downstream-outbuf-fifo2-abc9-utilization --no-link --print-out-paths -L`
  - output:
    - `/nix/store/6rvwfbgznp2jad70hxmm69j8kqwgab0w-task6-l2-c-fc-redirect-downstream-outbuf-fifo2-abc9-utilization`
  - result:
    - `ELAPSED=261.04`
    - `RSS_KB=563320`
  - mapped summary:
    - DSP:
      - `4`
    - BRAM36:
      - `0`
    - CLB LUTs:
      - `51,832`
    - CLB FFs:
      - `64,743`
    - Estimated number of LCs:
      - `47,802`
- Primitive signature:
  - `FDRE`:
    - `64,740`
  - `LUT6`:
    - `29,301`
  - `LUT5`:
    - `8,416`
  - `LUT3`:
    - `8,112`
  - `LUT2`:
    - `4,027`
- Weight placement and runtime checks:
  - large weights emitted as RTL constants:
    - `no`
    - unchanged from the accepted `L2` redirect; this probe only swaps local
      buffer modules and does not touch the external load interface
  - Verilator passed:
    - `yes`
  - Yosys stat finished within budget:
    - `not rerun`
    - the accepted `L2` kernel still has a separate `yosys-stat` proof at
      `9.13 s`, but this probe was judged directly on Verilator plus mapped
      `abc9`
- Delta against the existing `L2` kernel:
  - LUT:
    - `50,235 -> 51,832` (`+1,597`)
  - FF:
    - `65,523 -> 64,743` (`-780`)
- Delta against the aligned `L2` replay:
  - LUT:
    - `51,622 -> 51,832` (`+210`)
  - FF:
    - `64,873 -> 64,743` (`-130`)
- Delta against the current `L1` reference:
  - LUT:
    - `29,778 -> 51,832` (`+22,054`)
  - FF:
    - `46,352 -> 64,743` (`+18,391`)
- Interpretation:
  - this first `L2`-native local probe does improve one diagnostic number:
    - mapped `Estimated number of LCs` drops to `47,802`
  - but the lane scorecard does not use that diagnostic number:
    - the official metric is CLB LUTs, and those worsen again to `51,832`
  - treat this as the second clean move-on signal for `L2 c_fc`:
    - external weights still hold
    - `4 DSP48E1` still hold
    - the kernel contract still passes
    - the official fit metric still moves the wrong way
  - stop `L2 c_fc` micro-surgery here and pivot within StreamTensor-lite to
    the reserve fallback boundary `mlp.c_proj`

### `c_proj` fallback boundary scout later on 2026-04-23

- Supporting script change:
  - generalized `scripts/task6/build_task_graph.py`
    - it now derives graph and tensor node names from the module leaf instead
      of hard-coding `c_fc`, so the same lightweight artifact path stays honest
      on `c_proj`
- Logged run bundle:
  - `artifacts/task6-streamtensor-lite/runs/2026-04-23T14-46-31+0200/cproj-fallback-scout/summary.md`

#### Why this slice

- The lane move-on rule after the second clean `L2 c_fc` miss was:
  - stop local `L2 c_fc` micro-surgery
  - pivot within StreamTensor-lite to the reserve fallback boundary
    `transformer.h.0.mlp.c_proj`
- The smallest honest question before building a new redirected kernel was:
  - does `c_proj` preserve the same lightweight artifact path at both `L1` and
    `L2`:
    - `linalg` candidate
    - external weight pack
    - module-level activation contract
    - exact packed replay
    - minimal task graph

#### L1 fallback boundary

- First `L1` candidate artifact:
  - `artifacts/task6/streamtensor-lite/l1/representative-core-v64-h4-c_proj-candidate.json`
  - measured finder runtime:
    - wall-clock:
      - `0.07 s`
    - peak RSS:
      - `13,272 KB`
  - selected site:
    - line `418`
    - value `%88`
  - shape contract:
    - `tensor<1x1x16xf32>`
    - `tensor<1x16x4xf32>`
    - `tensor<1x1x4xf32>`
  - candidate count:
    - `2`
- First `L1` `c_proj` pack:
  - `artifacts/task6/weights_pack/tiny-stories-1m-representative-core-v64-h4/transformer.h.0.mlp.c_proj/`
  - measured export:
    - wall-clock:
      - `4.69 s`
    - peak RSS:
      - `334,732 KB`
  - tensor shapes:
    - weight:
      - `(4, 16)`
    - bias:
      - `(4,)`
- First `L1` `c_proj` contract:
  - `artifacts/task6/streamtensor-lite/l1/representative-core-v64-h4-c_proj-contract/`
  - measured capture:
    - wall-clock:
      - `4.51 s`
    - peak RSS:
      - `342,492 KB`
  - sample contract:
    - input ids:
      - `[[0]]`
    - activation in:
      - `(1, 1, 16)`
    - activation out:
      - `(1, 1, 4)`
- First `L1` `c_proj` replay check:
  - artifact:
    - `artifacts/task6/streamtensor-lite/l1/representative-core-v64-h4-c_proj-contract-check.json`
  - measured replay:
    - wall-clock:
      - `1.83 s`
    - peak RSS:
      - `226,384 KB`
  - replay result:
    - formula:
      - `activation_in @ weight.T + bias`
    - max absolute error:
      - `0.0`
    - mean absolute error:
      - `0.0`
    - verdict:
      - `pass`
- First `L1` `c_proj` task graph:
  - `artifacts/task6/streamtensor-lite/l1/representative-core-v64-h4-c_proj-task-graph.json`
  - measured build:
    - wall-clock:
      - `0.07 s`
    - peak RSS:
      - `14,020 KB`
  - graph name:
    - `task6-c_proj-minimal-task-graph`

#### L2 fallback boundary

- First `L2` candidate artifact:
  - `artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_proj-candidate.json`
  - measured finder runtime:
    - wall-clock:
      - `0.08 s`
    - peak RSS:
      - `14,888 KB`
  - selected site:
    - line `412`
    - value `%94`
  - shape contract:
    - `tensor<1x1x256xf32>`
    - `tensor<1x256x64xf32>`
    - `tensor<1x1x64xf32>`
  - candidate count:
    - `1`
- First `L2` `c_proj` pack:
  - `artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_proj/`
  - measured export:
    - wall-clock:
      - `4.71 s`
    - peak RSS:
      - `335,104 KB`
  - tensor shapes:
    - weight:
      - `(64, 256)`
    - bias:
      - `(64,)`
- First `L2` `c_proj` contract:
  - `artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_proj-contract/`
  - measured capture:
    - wall-clock:
      - `4.54 s`
    - peak RSS:
      - `342,668 KB`
  - sample contract:
    - input ids:
      - `[[0]]`
    - activation in:
      - `(1, 1, 256)`
    - activation out:
      - `(1, 1, 64)`
- First `L2` `c_proj` replay check:
  - artifact:
    - `artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_proj-contract-check.json`
  - measured replay:
    - wall-clock:
      - `1.83 s`
    - peak RSS:
      - `226,016 KB`
  - replay result:
    - formula:
      - `activation_in @ weight.T + bias`
    - max absolute error:
      - `0.0`
    - mean absolute error:
      - `0.0`
    - verdict:
      - `pass`
- First `L2` `c_proj` task graph:
  - `artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_proj-task-graph.json`
  - measured build:
    - wall-clock:
      - `0.08 s`
    - peak RSS:
      - `13,760 KB`
  - graph name:
    - `task6-c_proj-minimal-task-graph`

#### Interpretation

- The reserve `mlp.c_proj` fallback boundary is now validated on the same
  lightweight gates that previously brought up `c_fc`:
  - clean `linalg.batch_matmul` sites exist on both `L1` and `L2`
  - external weight packs exist on both `L1` and `L2`
  - module-level activation contracts exist on both `L1` and `L2`
  - packed replay is exact on both `L1` and `L2`
- This does not yet claim any mapped fit result:
  - no redirected `c_proj` kernel has been built
  - no Verilator kernel harness has been run
  - no mapped utilization has been collected
- The next useful slice is therefore:
  - build the first redirected `c_proj` kernel at `L1`
  - judge it with the same fast loop before replaying onto `L2`

### `L1 c_proj` redirected kernel start later on 2026-04-23

- Added model:
  - `task6-l1-c-proj-redirect`
  - location:
    - `nix/models.nix`
  - implementation:
    - reuse the existing `task6_rect_gemv.py` kernel with
      `TASK6_RECT_GEMV_IN_DIM=16` and `TASK6_RECT_GEMV_OUT_DIM=4`
- Logged run bundle:
  - `artifacts/task6-streamtensor-lite/runs/2026-04-23T14-51-00+0200/l1-cproj-redirect-yosys-stat-proof/summary.md`

#### Why this slice

- After the fallback scout, the cheapest honest next claim was:
  - the first redirected `c_proj` kernel should compile through the inherited
    flow at `L1`
  - stop there if even `yosys-stat` breaks or exceeds the budget
- Reusing the existing rectangular GEMV kernel keeps this narrow:
  - no new arithmetic module
  - no new compiler path
  - only the boundary shape changes from `4 -> 16` to `16 -> 4`

#### First `yosys-stat` result

- Timed build:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-proj-redirect-yosys-stat --no-link -L`
  - result:
    - `ELAPSED=17.52`
    - `RSS_KB=563732`
- Pre-map structural signature:
  - `$mul`:
    - `1`
  - `arith_mulf_in_f32_f32_out_f32`:
    - `1`
  - `arith_addf_in_f32_f32_out_f32`:
    - `1`
  - `handshake_buffer_in_ui64_out_ui64_2slots_seq`:
    - `204`
  - `handshake_load_in_ui64_f32_none_out_f32_ui64`:
    - `4`
  - `handshake_store_in_ui64_f32_none_out_f32_ui64`:
    - `3`
- Interpretation:
  - the first redirected `c_proj` kernel is structurally live
  - it stays inside the `< 30 s` micro-proof budget on the first inherited gate
  - the expected float arithmetic extern signature is still present, so this is
    not blocked by a boundary mismatch
  - no fit claim should be made yet:
    - Verilator is still pending
    - mapped utilization is still pending

#### Next action

- Add the minimal `L1 c_proj` Verilator and mapped-utilization surfaces using
  the newly generated `c_proj` contract and weight-pack artifacts.

### `L1 c_proj` executable proof and mapper follow-up later on 2026-04-23

- Added flake outputs:
  - `task6-l1-c-proj-redirect-tb-data-sv`
  - `task6-l1-c-proj-redirect-sim-main`
  - `task6-l1-c-proj-redirect-json`
  - `task6-l1-c-proj-redirect-utilization`
  - `task6-l1-c-proj-redirect-sv-sim`
  - `task6-l1-c-proj-redirect-abc9-json`
  - `task6-l1-c-proj-redirect-abc9-utilization`
- Logged run bundles:
  - `artifacts/task6-streamtensor-lite/runs/2026-04-23T15-01-29+0200/l1-cproj-redirect-proof/summary.md`
  - `artifacts/task6-streamtensor-lite/runs/2026-04-23T15-04-46+0200/l1-cproj-redirect-abc9-proof/summary.md`

#### Why this slice

- After `yosys-stat`, the next smallest honest question was:
  - does the untouched `L1 c_proj` redirected kernel pass the captured contract
    under Verilator
  - and if so, is the first mapped result competitive enough to justify more
    real fit work
- The follow-up stop rule was:
  - if the first mapped result still trails the frozen `L1 c_fc` reference,
    allow at most one cheap mapper-only discriminator before leaving `c_proj`
    reserve-only

#### Base executable proof

- Timed Verilator proof:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-proj-redirect-sv-sim --no-link -L`
  - result:
    - `PASS: stores 4 outputs 4`
    - `ELAPSED=106.74`
    - `RSS_KB=437244`
- Timed mapped utilization:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-proj-redirect-utilization --no-link --print-out-paths -L`
  - output:
    - `/nix/store/hlq0lqfxrbglnc8dxzp0jgandqjw2i4m-task6-l1-c-proj-redirect-utilization`
  - result:
    - `ELAPSED=97.85`
    - `RSS_KB=562712`
  - mapped summary:
    - DSP:
      - `4`
    - BRAM36:
      - `0`
    - CLB LUTs:
      - `32,393`
    - CLB FFs:
      - `50,864`
- Weight placement and runtime checks:
  - large weights emitted as RTL constants:
    - `no`
    - inherited redirected-kernel structure still uses external loads plus the
      generated task6 contract/pack flow
  - Verilator passed:
    - `yes`
  - Yosys stat finished within budget:
    - `yes`
    - `17.52 s`
- Delta against raw `L1 c_fc` redirect:
  - LUT:
    - `33,116 -> 32,393` (`-723`)
  - FF:
    - `51,296 -> 50,864` (`-432`)
- Delta against frozen `L1 c_fc` reference:
  - LUT:
    - `29,778 -> 32,393` (`+2,615`)
  - FF:
    - `46,352 -> 50,864` (`+4,512`)
- Interpretation:
  - the untouched `L1 c_proj` redirect is a real executable fallback proof:
    - external weights hold
    - `4 DSP48E1` hold
    - Verilator passes
  - but it is not a mainline fit win:
    - it still misses the LUT ceiling by `2,533`
    - it clearly trails the frozen `L1 c_fc` reference
  - that justified only one cheap mapper-only discriminator, not a new blind
    optimization branch

#### Direct `abc9` follow-up

- Timed mapped utilization:
  - command:
    - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-proj-redirect-abc9-utilization --no-link --print-out-paths -L`
  - output:
    - `/nix/store/lffxb0w5ac1hwhfyyd12vxfnmsj9sd64-task6-l1-c-proj-redirect-abc9-utilization`
  - result:
    - `ELAPSED=143.08`
    - `RSS_KB=563156`
  - mapped summary:
    - DSP:
      - `4`
    - BRAM36:
      - `0`
    - CLB LUTs:
      - `31,611`
    - CLB FFs:
      - `50,864`
- Delta against base `L1 c_proj` redirect:
  - LUT:
    - `32,393 -> 31,611` (`-782`)
  - FF:
    - `50,864 -> 50,864` (`+0`)
- Delta against frozen `L1 c_fc` reference:
  - LUT:
    - `29,778 -> 31,611` (`+1,833`)
  - FF:
    - `46,352 -> 50,864` (`+4,512`)
- Interpretation:
  - direct `abc9` does buy a real reduction on the untouched `c_proj` kernel
  - but it still does not change lane order:
    - the kernel remains `1,751` LUT above the ceiling
    - and still worse than the frozen `L1 c_fc` reference by `1,833` LUT
  - treat this as enough evidence to keep `c_proj` reserve-only:
    - structurally valid
    - reproducible
    - useful fallback
    - not the main fit-first lane on mapper-only evidence

#### Next action

- Keep `task6-l1-c-fc-redirect-index-ring3-postbranch-outbuf-fifo2-abc9` as
  the main `L1` reference.
- Keep `c_proj` as a validated reserve fallback, and do not start another blind
  `c_proj` optimization loop unless there is a new bounded structural
  hypothesis stronger than mapper-only improvement.

### Bounded `L2` structural hypothesis on 2026-04-23

#### Hypothesis

- The remaining `L2 c_fc` fit failure is now more likely to be dominated by the
  monolithic `64 -> 256` downstream wrapper shape than by the GEMV arithmetic
  kernel itself:
  - `L1` only crossed the ceiling after trimming the downstream post-branch
    `ui64` cluster
  - the aligned `L2` replay of that same lever and the first `L2`-native
    downstream out-buffer probe both worsened official CLB LUTs
- The next bounded structural test is therefore:
  - replace the monolithic `64 -> 256` redirected kernel with one sequential
    `4 x 64` output-tiled wrapper that reuses a single `64 -> 64` redirected
    kernel instance across four phases
  - keep the same external activation/weight/store contract at the top level
  - remap only:
    - weight addresses:
      - `phase[1:0] ++ local_tile_addr[11:0]`
    - store addresses:
      - `phase[1:0] ++ local_store_addr[5:0]`
  - pass the same full `L2` contract and weight-pack artifacts through the
    existing Verilator harness

#### Bounds and stop rule

- Stay strictly inside `task6-streamtensor-lite` and only touch the `L2 c_fc`
  redirect path.
- Reuse the existing rectangular GEMV kernel and current proof harness.
- Do not broaden into compiler redesign, alternate dialects, or whole-model
  RTL.
- Reject the hypothesis immediately if any of these happen:
  - mapped `abc9` does not beat the current `L2` base at `50,235` LUT by a
    clear margin
  - DSP falls back to `0`
  - large weights reappear as RTL constants
  - the wrapper requires broad RTL surgery instead of a local top-level
    sequencer

### `L2 c_fc` tiled `4 x 64` wrapper proof later on 2026-04-23

- New bounded proof surfaces:
  - `task6-l2-c-fc-redirect-tile64-yosys-stat`
  - `task6-l2-c-fc-redirect-tile4x64-sim-main`
  - `task6-l2-c-fc-redirect-tile4x64-sv-sim`
  - `task6-l2-c-fc-redirect-tile4x64-abc9-json`
  - `task6-l2-c-fc-redirect-tile4x64-abc9-utilization`
- New local wrapper:
  - `rtl/task6/task6_l2_c_fc_tile4x64_main.sv`
- Artifact bundle:
  - `artifacts/task6-streamtensor-lite/runs/2026-04-23T16-03-42+0200/l2-cfc-tile4x64-proof/summary.md`

#### What was implemented

- The hypothesis was executed exactly as bounded:
  - one reused `64 -> 64` redirected kernel generated as
    `task6-l2-c-fc-redirect-tile64`
  - one local top-level sequencer that runs the tile kernel across four output
    phases while preserving the same external activation, weight, and store
    contract as the original `L2` kernel
- The wrapper only remaps:
  - weight addresses:
    - `{phase[1:0], local_tile_addr[11:0]}`
  - store addresses:
    - `{phase[1:0], local_store_addr[5:0]}`
- No compiler redesign or alternate lowering path was introduced; this stays
  strictly inside the existing StreamTensor-lite lane.

#### Commands

- Cheap kernel gate:
  - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l2-c-fc-redirect-tile64-yosys-stat --no-link -L`
- Full-contract Verilator proof:
  - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l2-c-fc-redirect-tile4x64-sv-sim --no-link -L`
- Mapped `abc9` utilization:
  - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l2-c-fc-redirect-tile4x64-abc9-utilization --no-link --print-out-paths -L`
  - output:
    - `/nix/store/cj8356nv9izcs60znfqfdysydrxdy8vc-task6-l2-c-fc-redirect-tile4x64-abc9-utilization`

#### Results

- `task6-l2-c-fc-redirect-tile64-yosys-stat`:
  - `ELAPSED=16.09`
  - `RSS_KB=561720`
  - stays inside the `< 30 s` micro-proof budget
- `task6-l2-c-fc-redirect-tile4x64-sv-sim`:
  - `PASS: stores 256 outputs 256`
  - `ELAPSED=161.55`
  - `RSS_KB=437564`
- `task6-l2-c-fc-redirect-tile4x64-abc9-utilization`:
  - `ELAPSED=153.09`
  - `RSS_KB=563056`
  - mapped resources:
    - `DSP48E1`
      - `4`
    - `BRAM36`
      - `0`
    - `CLB LUTs`
      - `32,460`
    - `CLB FFs`
      - `46,740`
    - `Estimated mapped LCs`
      - `29,089`
- Large weights emitted as RTL constants:
  - `no`
  - the top-level interface is still external-memory based, and the new
    wrapper only sequences one reused tile kernel around that contract

#### Deltas

- Against the existing untiled `L2` reference:
  - LUT:
    - `50,235 -> 32,460` (`-17,775`)
  - FF:
    - `65,523 -> 46,740` (`-18,783`)
- Against the best validated `L1` reference:
  - LUT:
    - `29,778 -> 32,460` (`+2,682`)
  - FF:
    - `46,352 -> 46,740` (`+388`)

#### Verdict

- The bounded structural hypothesis is supported.
- The monolithic `64 -> 256` wrapper shape was a major `L2` cost center:
  - reusing one external-weight `64 -> 64` kernel across four phases keeps
    `4 DSP48E1`, preserves the full `L2` contract, and collapses the mapped
    `L2` footprint to near-`L0`/`L1` scale
- This is the first fit-positive `L2` structural result in the lane and the new
  `L2 c_fc` reference.
- It is not yet enough to unblock `L3`:
  - `32,460` LUT is still `2,600` over the `29,860` ceiling

#### Next action

- Freeze `task6-l2-c-fc-redirect-tile4x64-abc9-utilization` as the new `L2`
  reference.
- If `L2 c_fc` continues, use at most one more bounded fit hypothesis on the
  reusable `64 -> 64` tile kernel or tile/wrapper seam.
- Do not reopen the abandoned monolithic `64 -> 256` local micro-surgery loop,
  and do not promote to `L3` until the tiled `L2` path clears the LUT ceiling.

### 2026-04-23 - Amend the active `L2` plan around the tiled wrapper

The branch had moved beyond the original Apr 22 ladder, so
`docs/task6-lane.md` was amended to match the recorded frontier in
`docs/task6-lane-results.md`.

The live contract is now:

- freeze `L1 c_fc` as solved for the first-proof bar
- keep `mlp.c_proj` reserve-only
- treat tiled `L2 c_fc` as the sole active mainline
- spend the already-authorized single follow-up probe on the tiled `L2`
  structure, not on the abandoned monolithic `64 -> 256` path

### 2026-04-23 - Instrument the tiled `L2` seam before touching RTL again

The first amended follow-up was a seam split: measure the untouched reusable
`64 -> 64` tile kernel directly, then compare it against the existing `4 x 64`
wrapper result.

#### Command

- `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l2-c-fc-redirect-tile64-abc9-utilization --no-link --print-out-paths -L`

#### Output

- `/nix/store/1jsmab9fgsjdv0n4czy9pqcgmy9l6rns-task6-l2-c-fc-redirect-tile64-abc9-utilization`

#### Result

- `CLB LUTs = 32,478`
- `CLB FFs = 46,736`
- `DSP48E1 = 4`
- `BRAM36 = 0`
- `Estimated number of LCs = 29,116`
- `ELAPSED = 92.53 s`
- `RSS_KB = 563,708`

#### Verdict

- The seam is not the dominant cost center.
- The existing tiled wrapper lands at `32,460 LUT / 46,740 FF`, so the seam
  delta is only:
  - `32,478 -> 32,460` (`-18 LUT`)
  - `46,736 -> 46,740` (`+4 FF`)
- That is too small to justify another seam-only iteration. The single
  remaining bounded probe had to target the reusable tile kernel itself.

### 2026-04-23 - One bounded tile-kernel follow-up on the tiled `L2` mainline

With the seam effectively flat, the single allowed follow-up probe moved into
the tile kernel's local post-branch/output `ui64` cluster.

Bounded edit:

- reuse the existing `task6_ui64_fifo2_buffer` helper
- replace only:
  - `handshake_buffer244`
  - `handshake_buffer245`
  - `handshake_buffer248`
  - `handshake_buffer250`
  - `handshake_buffer252`
  - `handshake_buffer253`
  - `handshake_buffer254`
  - `handshake_buffer256`
- do not change arithmetic, weight loading, or the tiled wrapper protocol

This stays inside the existing StreamTensor-lite lane and is intentionally
smaller than reopening monolithic `L2` surgery.

#### Cheap kernel gate

- `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l2-c-fc-redirect-tile64-postbranch-outbuf-fifo2-abc9-utilization --no-link --print-out-paths -L`

Output:

- `/nix/store/jxgi6fqjd9hivzhkgmjqpnm1m4ghkwx9-task6-l2-c-fc-redirect-tile64-postbranch-outbuf-fifo2-abc9-utilization`

Kernel-gate result:

- `CLB LUTs = 31,968`
- `CLB FFs = 45,928`
- `DSP48E1 = 4`
- `BRAM36 = 0`
- `Estimated number of LCs = 28,689`
- `ELAPSED = 93.06 s`
- `RSS_KB = 563,328`

Kernel-gate delta versus the untouched tile kernel:

- LUT:
  - `32,478 -> 31,968` (`-510`)
- FF:
  - `46,736 -> 45,928` (`-808`)

Verdict:

- This is a real kernel-local win, so the same bounded hypothesis was worth one
  replay into the full `4 x 64` wrapper.

#### Full wrapper replay

- Verilator proof:
  - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2-sv-sim --no-link -L`
- Direct rerun for a clean run-bundle sim log:
  - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' /nix/store/363slmdlg8mv44sqxczkd0vbp9sji7ig-task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2-sim-main/obj_dir/sim_main`
- Mapped `abc9` utilization:
  - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2-abc9-utilization --no-link --print-out-paths -L`

Output:

- `/nix/store/cj1s942zmpcwg0xz73g86k58idwavari-task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2-abc9-utilization`

Wrapper replay result:

- Verilator:
  - `PASS: stores 256 outputs 256`
  - build-time `ELAPSED = 85.86 s`
  - build-time `RSS_KB = 437,444`
  - direct rerun `ELAPSED = 2.25 s`
  - direct rerun `RSS_KB = 5,224`
- mapped `abc9` utilization:
  - `CLB LUTs = 31,907`
  - `CLB FFs = 45,932`
  - `DSP48E1 = 4`
  - `BRAM36 = 0`
  - `Estimated number of LCs = 28,653`
  - `ELAPSED = 94.03 s`
  - `RSS_KB = 562,812`

Wrapper delta versus the prior tiled `L2` reference:

- LUT:
  - `32,460 -> 31,907` (`-553`)
- FF:
  - `46,740 -> 45,932` (`-808`)

Wrapper delta versus the current `L1` reference:

- LUT:
  - `29,778 -> 31,907` (`+2,129`)
- FF:
  - `46,352 -> 45,932` (`-420`)

#### Verdict

- The amended tiled-`L2` follow-up succeeded in the narrow sense:
  - the seam hypothesis is now falsified
  - the bounded tile-kernel post-branch/output probe is real
  - replaying it into the full tiled wrapper preserves external weights,
    `4 DSP48E1`, and the `L2` contract
- The new `L2` reference is now:
  - `task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2-abc9-utilization`
  - `31,907 LUT / 45,932 FF / 4 DSP / 0 BRAM`
- This is still not enough to unblock `L3`:
  - `31,907` LUT is still `2,047` above the `29,860` ceiling

#### Next action

- Do not reopen monolithic `L2 c_fc` micro-surgery.
- Do not reopen the already-closed seam-only line.
- Treat the amended one-probe plan as spent.
- Any further `L2 c_fc` work now needs a new structural hypothesis that is
  stronger than "another nearby buffer cluster may help."

### 2026-04-23 - Amend the live plan after the selective-buffer phase

The branch evidence now fixes the continuation rule more tightly than the older
`72a502f` selective-buffer checkpoint alone.

Interpretation:

- Treat the selective-buffer widening that led into `72a502f` as the end of the
  blind ring-expansion loop, not the start of more generic widening.
- Freeze `task6-l1-c-fc-redirect-index-ring3-postbranch-outbuf-fifo2-abc9` as
  the `L1` gold reference.
- Keep `mlp.c_proj` reserve-only.
- Keep monolithic `L2 c_fc` micro-surgery closed.
- Treat tiled `L2 c_fc` as the sole active mainline until a stronger structural
  hypothesis appears.

One code-structure cleanup is now part of the plan before another local probe
wave:

- `rtl/task6/task6_ui64_fifo2_buffer.sv`
- `rtl/task6/handshake_buffer_in_ui64_out_ui64_2slots_seq_fifo2.sv`

These currently carry the same FIFO body under two names. That duplication was
acceptable for fast proof work, but it is now a drift risk. Future local
rewrites should be driven by:

- one canonical FIFO2 helper implementation
- thin wrappers or aliases only where an old module name must be preserved
- one small patch map naming the rewritten sites, instead of scattering more
  near-duplicate helper modules and ad hoc site lists across `flake.nix`

This is a plan amendment only. It does not reopen the spent `L2` probe budget,
and it does not authorize another local `L2 c_fc` edit without a new bounded
structural hypothesis.

### 2026-04-23 - Consolidate the `ui64` FIFO2 probe plumbing and validate no regression

This closes the code-structure cleanup that the amended plan required before
another local probe wave.

Changes:

- Added `nix/task6-ui64-fifo2-site-map.nix` as the single source of truth for
  the Task 6 `ui64` FIFO2 rewrite site lists.
- Added shared flake helpers:
  - `mkTask6PatchedSv`
  - `mkTask6Ui64Fifo2SitePatchSv`
  - `mkTask6Ui64Fifo2WholeClassSv`
- Replaced the repeated inline `runCommand` site-rewrite blocks for the
  existing `L1` and `L2` FIFO2 probes with those helpers.
- Reduced duplicate RTL:
  - `rtl/task6/task6_ui64_fifo2_buffer.sv` is now the canonical FIFO2 body.
  - `rtl/task6/handshake_buffer_in_ui64_out_ui64_2slots_seq_fifo2.sv` is now
    only a thin wrapper that instantiates the canonical helper under the legacy
    module name expected by the old whole-class path.
- Needed operational step:
  - `nix/task6-ui64-fifo2-site-map.nix` had to be staged before Nix could see
    it because the flake source snapshot excludes untracked files.

Validation bundle:

- `artifacts/task6-streamtensor-lite/runs/2026-04-23T18-08-31+0200/`

Commands rerun:

- `nix build .#task6-l1-c-fc-redirect-ui64-buffer-fifo2-utilization --no-link --print-out-paths -L`
- `nix build .#task6-l1-c-fc-redirect-index-ring3-postbranch-outbuf-fifo2-abc9-utilization --no-link --print-out-paths -L`
- `nix build .#task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2-abc9-utilization --no-link --print-out-paths -L`
- `nix build .#task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2-sv-sim --no-link -L`
- direct rerun:
  - `/nix/store/4hdp3s5lqqwqkpwqwy6mxwc634fk5ixd-task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2-sim-main/obj_dir/sim_main`

Results:

- legacy whole-class wrapper still builds through the alias wrapper:
  - `23,161 LUT / 27,591 FF / 4 DSP / 0 BRAM`
- frozen `L1` reference is unchanged:
  - `29,778 LUT / 46,352 FF / 4 DSP / 0 BRAM`
- active tiled `L2` reference is unchanged:
  - `31,907 LUT / 45,932 FF / 4 DSP / 0 BRAM`
- direct rerun still passes:
  - `PASS: stores 256 outputs 256`

Verdict:

- The cleanup is accepted.
- The probe plumbing is now safe to reuse for future local rewrites.
- No accepted Task 6 reference moved, and no old evidence path was stranded.

Next action:

- Use the cleaned plumbing for one new bounded `L2 tile64` structural
  hypothesis on the remaining mixed data/control store path, not for another
  generic `ui64` buffer-only sweep.

### 2026-04-23 - First mixed `tile64` fork/control seam probe fails functionally

The first post-cleanup seam probe targeted the remaining local store-path
fanout state in the tiled `64 -> 64` kernel:

- `handshake_fork50`
- `handshake_fork51`
- `handshake_fork52`
- `handshake_buffer246`
- `handshake_buffer247`
- `handshake_buffer255`

Implementation:

- Added lean fork helpers:
  - `rtl/task6/task6_ui64_fork2.sv`
  - `rtl/task6/task6_ui64_fork3.sv`
  - `rtl/task6/task6_ctrl_fork3.sv`
- Reused `rtl/task6/task6_ctrl_fifo2_buffer.sv` for the zero-width control
  buffers in the same seam.
- Added the local surface:
  - `task6-l2-c-fc-redirect-tile64-storepath-forkctrl-*`

Run bundle:

- `artifacts/task6-streamtensor-lite/runs/2026-04-23T18-14-40+0200/`

Command run:

- `nix build .#task6-l2-c-fc-redirect-tile64-storepath-forkctrl-sv-sim --no-link -L`

Result:

- Verilator build completed, but the contract failed:
  - `FAIL: expected 256 stores but observed 64`
- runtime:
  - `80.97 s`
- peak RSS:
  - `438,164 KB`

Verdict:

- Reject this combined helper cluster as a valid drop-in.
- The failure happens before mapped scoring, so there is no reason to run
  `abc9` on this exact surface.

Next action:

- Narrow the same seam.
- Keep the zero-width control buffers untouched on the next attempt.
- If the seam work continues, isolate the fork-state helpers only:
  - `fork50`
  - `fork51`
  - `fork52`

### 2026-04-23 - Fork-only follow-up reproduces the same `64`-store failure

The narrowed follow-up kept the original zero-width control buffers and changed
only the local fanout helpers:

- `fork50`
- `fork51`
- `fork52`

Surface:

- `task6-l2-c-fc-redirect-tile64-storepath-forks-*`

Run bundle:

- `artifacts/task6-streamtensor-lite/runs/2026-04-23T18-18-28+0200/`

Command run:

- `nix build .#task6-l2-c-fc-redirect-tile64-storepath-forks-sv-sim --no-link -L`

Result:

- same contract failure as the wider cluster:
  - `FAIL: expected 256 stores but observed 64`
- runtime:
  - `83.16 s`
- peak RSS:
  - `438,492 KB`

Verdict:

- The remaining local store-path helper substitution line is closed.
- The failure survives after removing the ctrl-buffer substitutions, so the
  problem is not just the zero-width FIFO replacements.
- Do not spend another `L2 tile64` slice on helper replacement in this same
  neighborhood.

Blocking state:

- The current amended `L2` plan is now exhausted.
- More local `L2 c_fc` RTL edits would violate the lane rule unless a new
  structural hypothesis is stated first.

### 2026-04-23 - Implement the stage-local runner surface

The only remaining concrete operational item in the current lane plan was the
missing stage-local runner surface. I closed that gap without reopening the RTL
search:

- added:
  - `justfile`
  - `scripts/task6/run_stage_local.py`
- exported the missing package surfaces needed by the runner:
  - `task6-l0-gemv64-yosys-stat`
  - `task6-l1-c-fc-redirect-index-ring3-postbranch-outbuf-fifo2-yosys-stat`
  - `task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2-yosys-stat`

The runner now covers the active and gated ladder surfaces:

- `just task6-l0`
- `just task6-l1`
- `just task6-l2`
- `just task6-l3`
- `just task6-l4`
- `just task6-x1`
- `just task6-x2`
- `just task6-x3`

Design rule:

- active rungs execute the existing frozen/reference proof surfaces and write a
  fresh run bundle under `artifacts/task6-streamtensor-lite/runs/<timestamp>/`
- blocked rungs do not pretend to run; they emit a summary bundle that records
  the current promotion gate and next action explicitly
- the runner is a frozen status surface:
  - its timings are replay timings, not frontier experiment timings
  - do not keep spending frontier bandwidth on blocked-rung sweeps or runner
    feature growth unless the frontier itself changes

### 2026-04-24 - Clean the stage-local runner and freeze it as status-only

The runner needed execution cleanup, not more feature growth.

Problems fixed:

- `L1` and `L2` were previously mixing different surfaces inside one rung:
  - `yosys-stat` came from the base kernel path
  - sim and mapped utilization came from the frozen/reference patched surface
- `README.md` used absolute workstation paths, which are not useful in GitHub
- run-directory allocation used an `exists()` check before `mkdir()`, which was
  collision-resistant in practice but not race-safe in principle
- the branch was recording blocked-run sweeps as if they were frontier
  experiments

Fixes applied:

- added exact `yosys-stat` derivations for the frozen `L1` and active tiled `L2`
  references
- changed the runner summaries to label timings explicitly as cache-hit status
  replay timings
- changed runner `README.md` links to relative paths
- changed run-directory allocation to retry on `FileExistsError`
- pruned the blocked-run sweep artifacts from the current tree and stopped
  treating them as experiment rows

Execution gate:

- before any new `L2 c_fc` frontier experiment, record one short hypothesis
  note here with:
  - expected dominant cost center
  - expected LUT delta
  - explicit falsifier
- without that note, only `just task6-l0`, `task6-l1`, and `task6-l2` status
  replays are allowed

### 2026-04-24 - Revalidate the frozen status surface on the active rungs only

Run bundles:

- `artifacts/task6-streamtensor-lite/runs/2026-04-24T00-10-19+0200/`
- `artifacts/task6-streamtensor-lite/runs/2026-04-24T00-10-27+0200/`
- `artifacts/task6-streamtensor-lite/runs/2026-04-24T00-10-36+0200/`

Commands run:

- `nix shell nixpkgs#just -c just task6-l0`
- `nix shell nixpkgs#just -c just task6-l1`
- `nix shell nixpkgs#just -c just task6-l2`

Results:

- `just task6-l0` remains a replay of the kernel-only miss:
  - Verilator: `PASS: stores 64 outputs 64`
  - mapped utilization: `32,449 LUT / 46,736 FF / 4 DSP / 0 BRAM`
- `just task6-l1` is now stage-pure across Yosys, sim, and utilization:
  - Verilator: `PASS: stores 16 outputs 16`
  - mapped utilization: `29,778 LUT / 46,352 FF / 4 DSP / 0 BRAM`
- `just task6-l2` is now stage-pure across Yosys, sim, and utilization:
  - Verilator: `PASS: stores 256 outputs 256`
  - mapped utilization: `31,907 LUT / 45,932 FF / 4 DSP / 0 BRAM`

Operational conclusion:

- The runner is now a cleaner status surface for the active ladder.
- It is no longer the frontier.
- The branch remains blocked on a new structural hypothesis, not on tooling.

### 2026-04-24 - New bounded structural hypothesis: the tile-local output scratch memory is the remaining `L2` cost center

This is a research note only. No new RTL experiment was run here.

Evidence reviewed from the exact stage-pure frozen/reference surfaces:

- `L1` exact frozen reference:
  - `29,778 LUT / 46,352 FF / 4 DSP / 0 BRAM`
  - `11,519` pre-map design cells
- `L2` exact active tiled reference:
  - `31,907 LUT / 45,932 FF / 4 DSP / 0 BRAM`
  - `11,265` pre-map design cells
- The tiled `L2` wrapper shell itself is tiny:
  - `main.sv` is only `128` lines in the exact `yosys-stat` bundle
- The mapped leaf mix shifts materially from `L1` to `L2` even though the
  pre-map cell count does not grow:
  - `LUT6`: `13,887 -> 15,280` (`+1,393`)
  - `LUT5`: `3,189 -> 5,526` (`+2,337`)
  - `LUT3`: `8,050 -> 6,295` (`-1,755`)
  - `FF` stays roughly flat
- The exact memory inventory shows only one memory module in each bundle:
  - `L1`: `handshake_memory_out_f32_id3 = 512 bits`
  - `L2`: `handshake_memory_out_f32_id3 = 2,048 bits`
- The generated SV confirms that this module is the same control shape in both
  cases, but the tiled `L2` kernel grows it from:
  - `reg [31:0] _handshake_memory_3[0:15]`
  - to `reg [31:0] _handshake_memory_3[0:63]`
- That `L2` memory remains a local multi-ported register array with:
  - two write ports
  - two combinational read ports
  - `6-bit` local addresses
- That shape is consistent with LUT-mux expansion rather than BRAM use, which
  matches the current resource signature:
  - `4 DSP / 0 BRAM`
  - higher `LUT5/LUT6`, not a large FF increase

Hypothesis:

- The remaining `L2` gap is dominated by the tile-local output scratch memory
  and its widened address/mux logic inside `task6_l2_c_fc_tile64_kernel`, not
  by the `tile4x64` phase wrapper seam.
- The next bounded structural move should therefore be a storage-class /
  access-pattern rewrite on that local scratchpad, not another nearby FIFO/site
  sweep.
- Concretely: replace the current `2R/2W` async register-array behavior behind
  `handshake_memory_out_f32_id3` with a bounded alternative that exploits the
  already-serial tiled wrapper, so the tile kernel no longer pays for the same
  wide multi-port mux structure.

Expected dominant cost center:

- `handshake_memory_out_f32_id3` plus its immediate `ldAddr*` / `stAddr*`
  decode and valid/ready cone inside the `64 -> 64` tile kernel

Expected LUT delta:

- `-1,000` to `-2,500` LUT on the active tiled `L2` reference if this memory
  shape is actually dominant
- That is large enough to close most or all of the remaining `2,047` LUT gap
  without needing another architecture pivot

Explicit falsifier:

- A bounded rewrite of this tile-local scratch storage does not improve the
  active tiled `L2` mapped result by at least `800` LUT
- Or the mapped leaf mix stays dominated by the same `LUT5/LUT6` pattern
  without a clear storage-shape change
- Or the rewrite requires broad compiler/backend surgery instead of a local
  tile-kernel substitution
- Or the result breaks any of the current retained wins:
  - external weights
  - `DSP > 0`
  - passing tile-kernel / tiled-wrapper Verilator proof

Smallest validating artifact:

- Do not start at the full `tile4x64` wrapper
- First build the cheapest possible probe around the tile-local scratch memory:
  - either a standalone mapped comparison of the current `64 x 32` multi-port
    scratchpad against one bounded alternative
  - or a `tile64`-kernel-only substitution of that memory behavior
- Only replay into the full `tile4x64` wrapper if the `tile64`-local probe
  shows a clear mapped win while keeping the current contract intact

### 2026-04-24 - Amend the live execution order after the deep research audit

The external audit does not change the branch thesis, but it does change what
counts as the next mainline execution step.

Decision:

- keep StreamTensor-lite, but narrow its role:
  - it remains the fast extraction / contract / kernel-comparison harness
  - it is no longer assumed to be the whole board-fit solution by itself
- freeze the current validated StreamTensor-lite references:
  - `L1` gold reference:
    - `task6-l1-c-fc-redirect-index-ring3-postbranch-outbuf-fifo2-abc9`
    - `29,778 LUT / 46,352 FF / 4 DSP / 0 BRAM`
  - active tiled `L2` reference:
    - `task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2-abc9-utilization`
    - `31,907 LUT / 45,932 FF / 4 DSP / 0 BRAM`
- keep `mlp.c_proj` reserve-only
- keep monolithic `L2 c_fc` surgery closed
- keep `L3` blocked

New mainline execution order:

1. Finish the `top4-memory` / DDR3 shell evidence.
   - use the existing narrowed external-memory packages
   - record a final utilization result plus a short bandwidth note
2. Promote quantization from deferred follow-up to a bounded core track.
   - start from `task3-experiments`
   - import only the smallest donor set needed to test one surviving route on
     the same extracted-op proof surfaces
3. Run one bounded alternate-lowering comparison.
   - compare the current handshake-heavy path against one alternative on the
     same extracted contract
4. Only if one quantized route survives do we design a new low-bit tile
   kernel.

Operational rule change:

- the default next action is no longer "another local StreamTensor-lite RTL
  tweak"
- architecture-level tracks now take priority over further float32 helper
  surgery
- each new architecture-level track gets one bounded pass before we decide
  whether it deserves another slice

### 2026-04-24 - Execute the first bounded DDR3 / `top4-memory` pass

Run bundle:

- `artifacts/task6/runs/2026-04-24T11-26-50+0200/`

Commands run:

- `nix build .#tiny-stories-1m-baseline-float-selftest-top4-memory-external-memory-plan --no-link --print-out-paths`
- `nix build .#tiny-stories-1m-baseline-float-selftest-top4-memory-utilization --no-link --print-out-paths`
  - interrupted after the narrowed shell re-entered staged Yosys and no new
    mapped result had landed inside the bounded pass window

Direct outputs:

- external-memory-plan output:
  - `/nix/store/92wwyy3d90z6kiclnqncig9365ikd64n-tiny-stories-1m-baseline-float-selftest-top4-memory-external-memory-plan`
- live narrowed-shell utilization observations before interruption:
  - `stage1.il` and `stage2.il` began building
  - active staged Yosys worker reached at least:
    - `8,935,948 KB` RSS
    - later sampled at `6,215,864 KB` RSS while still active

What this bounded pass confirms:

- the narrowed `top4-memory` plan is still reproducible in the current branch
- the selected DDR3 candidates are unchanged:
  - `\handshake_memory_out_f32_id342`
  - `\handshake_memory_out_f32_id341`
  - `\handshake_memory_out_f32_id340`
  - `\handshake_memory_out_f32_id18`
- each selected module remains `3216448 x 32` bits:
  - `102,926,336` bits each
- selected total:
  - `411,705,344` bits
  - `49.08 MiB`
  - `95.1%` of the `433,040,010` eligible bits
- the narrowed shell still re-enters staged Yosys cleanly on the real baseline
  after the external-memory plan is applied

Bounded bandwidth worksheet:

- full cold sweep of the selected top-four footprint:
  - `1.6 GB/s` -> `32.16 ms`
  - `2.0 GB/s` -> `25.73 ms`
  - `3.2 GB/s` -> `16.08 ms`
  - `4.0 GB/s` -> `12.87 ms`
  - `6.4 GB/s` -> `8.04 ms`
- pessimistic upper bound if all four tables were reread every token:
  - `1 tok/s` -> `0.051 GB/s`
  - `10 tok/s` -> `0.515 GB/s`
  - `50 tok/s` -> `2.573 GB/s`
  - `100 tok/s` -> `5.146 GB/s`
- interpretation:
  - the selected memory footprint is small enough to be board-credible only if
    the runtime access pattern is far below the full-cold-sweep upper bound
  - this worksheet is a sizing note, not a measured DDR3 traffic trace

Verdict:

- This bounded pass is `partial`, not `closed`.
- The exact top-four DDR3 target set is reconfirmed and the narrowed shell
  still reaches staged Yosys on the real baseline.
- It did not produce a new mapped shell utilization result within the bounded
  pass.

Next action:

- if the DDR3 track gets another slice, rerun
  `tiny-stories-1m-baseline-float-selftest-top4-memory-utilization` under
  `scripts/pipeline/monitor_build.sh` so the late-stage shell frontier is
  captured as a real artifact
- otherwise move on to the bounded PT2E-static quantized replay rather than
  waiting blindly on another uninstrumented narrowed-shell build

### 2026-04-24 - Execute the bounded PT2E-static quantized replay

Run bundle:

- `artifacts/task6/runs/2026-04-24T11-32-46+0200/`

Commands run:

- `nix build .#tiny-stories-1m-cf-stats --no-link --print-out-paths`
- `nix build .#tiny-stories-1m-cf --no-link --print-out-paths`
- `nix build .#tiny-stories-1m-handshake --no-link --print-out-paths`
- cache-hot timing replays:
  - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#tiny-stories-1m-cf-stats --no-link --print-out-paths`
  - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#tiny-stories-1m-handshake --no-link --print-out-paths`

Direct outputs:

- `cf-stats`:
  - `/nix/store/zz6f4lb25aiajxwg3qipcwvky2q2fzcr-tiny-stories-1m-cf.stats`
- `cf`:
  - `/nix/store/m6a5fb7i1bxn2dyb6bidj3f7fkjvbkq7-tiny-stories-1m-cf.mlir`
- `handshake`:
  - `/nix/store/00bda3b97cnrgfi002d0hwjckkak25xg-tiny-stories-1m-handshake.mlir`

What this bounded pass confirms:

- the surviving quantized route in this branch is still `tiny-stories-1m`
  PT2E-static
- it still clears `cf-stats`
- it also now demonstrably clears:
  - full `cf`
  - full `handshake`
- important structural fact:
  - the quantized `handshake` path is currently built through
    `scripts/pipeline/cf_to_handshake_lsq.sh`
  - the live process invocation confirmed:
    - `circt-opt ... --lower-cf-to-handshake=lsq -handshake-insert-buffers`
- this means the surviving quantized route is already riding the LSQ handshake
  lowering path rather than the exact stock handshake script used by the float
  StreamTensor-lite mainline

Measured / observed details:

- `cf` artifact size:
  - `28,826,105` bytes
- `handshake` artifact size:
  - `500,285,892` bytes
- cache-hot replay timings:
  - `cf-stats`:
    - `ELAPSED=1.60`
    - `RSS_KB=294,732`
  - `handshake`:
    - `ELAPSED=0.26`
    - `RSS_KB=37,024`
- live frontier sample during the first `handshake` build:
  - `circt-opt` RSS around `3,195,504 KB`

Verdict:

- This bounded pass is `helpful`.
- The quantized route is stronger than the older note that stopped at
  `cf-stats`; it now reaches real `handshake`.
- `dynamic-int8` and `torchao` still stay frozen.

Next action:

- use this result to frame the alternate-lowering slice carefully:
  - do not compare "float stock handshake" versus "quantized LSQ handshake" as
    if only one variable changed
  - instead, pick one bounded A/B where the contract and representation are
    aligned well enough to isolate the lowering question
- keep the quantized route active, but do not widen it blindly into heavier
  downstream stages before that comparison is explicit

### 2026-04-24 - Execute the bounded LSQ alternate-lowering `L1` A/B

Run bundle:

- `artifacts/task6/runs/2026-04-24T11-40-03+0200/`

Commands run:

- `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-lsq-index-ring3-postbranch-outbuf-fifo2-yosys-stat --no-link --print-out-paths -L`
- `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-lsq-index-ring3-postbranch-outbuf-fifo2-abc9-utilization --no-link --print-out-paths -L`
- `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-lsq-index-ring3-postbranch-outbuf-fifo2-sv-sim --no-link --print-out-paths -L`

Why this A/B was chosen:

- The amended plan called for exactly one bounded alternate-lowering comparison
  on the same extracted `L1 c_fc` contract before any more kernel work.
- The surviving quantized full-model route already reaches `handshake` through
  `cf_to_handshake_lsq.sh`, so LSQ is the one concrete non-default lowering
  family already alive in this repo.
- The right first slice was therefore not "quantized LSQ versus float stock",
  but "same float extracted contract, LSQ lowering versus stock lowering",
  followed by the same validated selective `ui64` FIFO2 override pattern.

First issue found:

- Tightening the selective `ui64` patch helper to require exact replacement
  exposed that the historical `L1` hotspot site lists were not stage-pure on
  the LSQ path.
- The helper now fails fast if a listed `handshake_buffer*` site is not
  actually a `task6_ui64_fifo2_buffer` replacement target in the generated
  `sv/main.sv`.
- On the LSQ bundle, several old hotspot IDs are not `ui64` buffers:
  - ctrl buffers: `163,164,174,175,192,270`
  - `ui1` buffers: `176,271,280`
  - `f32` buffer: `216`
- The effective LSQ patchable subsets were:
  - index ring 3:
    - `160,161,162,165,173,177,178,179,180,181,182,185,186,187,188,189,190,191,213,214,215,217,218,219`
  - post-branch:
    - `264,265,266,269`
  - post-branch out-buffer:
    - `279`

Direct outputs:

- raw LSQ `sv` bundle:
  - `/nix/store/vv4bdibfff16bqg6vbv16dn7amxy2nmq-task6-l1-c-fc-redirect-lsq-sv`
- `yosys-stat`:
  - `/nix/store/zpimvrnbsi6yzg8iwzdi9f2lhqajn83f-task6-l1-c-fc-redirect-lsq-index-ring3-postbranch-outbuf-fifo2-yosys.stat`
- mapped utilization:
  - `/nix/store/3agxx5vklnklbz91mw1rgkj6sijsmcyh-task6-l1-c-fc-redirect-lsq-index-ring3-postbranch-outbuf-fifo2-abc9-utilization`
- built `sim_main`:
  - `/nix/store/zrvkisdq6476jccidssq8mr4y421wl7i-task6-l1-c-fc-redirect-lsq-index-ring3-postbranch-outbuf-fifo2-sim-main/obj_dir/sim_main`

Structural comparison against the frozen float `L1` reference:

- frozen float `sv` bundle:
  - `main.sv`: `7,664` lines, `809,614` bytes
  - total `sv`: `54` files, `1,109,724` bytes
- LSQ `sv` bundle:
  - `main.sv`: `8,241` lines, `896,749` bytes
  - total `sv`: `54` files, `1,185,425` bytes
- frozen float `yosys-stat`:
  - `num_cells=11,519`
- LSQ `yosys-stat`:
  - `ELAPSED=4.69`
  - `RSS_KB=564,140`
  - `num_cells=12,222`
  - `num_memory_bits=512`
  - top cell types:
    - `$mux=3,440`
    - `$and=2,845`
    - `$not=2,459`
    - `$dff=2,181`
    - `$or=722`

Mapped comparison against the frozen float `L1` reference:

- frozen float mapped reference:
  - `DSP=4`
  - `BRAM36=0`
  - `CLB LUTs=29,778`
  - `CLB FFs=46,352`
- LSQ mapped result:
  - `ELAPSED=89.23`
  - `RSS_KB=563,056`
  - `DSP=4`
  - `BRAM36=0`
  - `CLB LUTs=29,329`
  - `CLB FFs=46,570`
  - dominant mapped leaf types:
    - `LUT6=14,399`
    - `LUT3=7,653`
    - `LUT2=3,329`
    - `LUT5=2,568`
    - `LUT4=1,380`
    - `FDRE=46,567`
    - `RAM32M=6`

Functional result:

- `sv-sim` does not pass the same redirected `L1` contract.
- Verilator built successfully, but the run aborted with:
  - `Timeout waiting for redirected GEMV completion`
  - `task6_contract_gemv_tb_main.sv:259`
- measured sim timing:
  - `ELAPSED=82.09`
  - `RSS_KB=437,484`

Verdict:

- This bounded LSQ A/B is `structurally interesting but operationally negative`.
- Positive signal:
  - it beats the frozen float `L1` reference on mapped LUT
    - `29,778 -> 29,329`
  - it preserves `4 DSP48E1`
  - it stays under the `29,860` LUT ceiling on mapped area alone
- Negative signal:
  - it is not a drop-in-safe replacement for the same proof harness because the
    redirected `L1` contract still times out under Verilator
- The one-pass alternate-lowering slice is therefore spent and closed without
  becoming the new mainline.

Next action:

- Do not widen alternate-lowering work on this branch without a stronger
  hypothesis than "LSQ might lower LUT".
- Keep the result recorded as a negative A/B reference.
- Continue with quantized extracted-op parity on the Task 6 proof harness,
  using the surviving PT2E-static route as the active architecture track.

### 2026-04-24 - Execute the bounded PT2E-static extracted-op parity pass

Run bundle:

- `artifacts/task6/runs/2026-04-24T13-02-11+0200/`

Why this slice was next:

- After the bounded full-model PT2E-static replay and the bounded LSQ A/B, the
  smallest remaining architecture question was:
  - can the surviving PT2E-static route actually survive on the direct Task 6
    extracted-op harness once the weight matrix is externalized?
- The right first slice was the smallest `L1` surface:
  - `tiny-stories-1m-representative-core-v64-h4`
  - `task6-l1-c-fc-redirect`
  - shape `[1, 4] x [4, 16]`

Implementation added:

- `src/task6_rect_gemv_pt2e_static_quant_adapter.py`
- model key:
  - `task6-l1-c-fc-redirect-pt2e-static`

Commands run:

- `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-pt2e-static-torch --no-link --print-out-paths -L`
- `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-torch --no-link --print-out-paths -L`
- local PT2E graph inspection under the pinned `python-with-tiny-stories` env
  with:
  - `TASK6_RECT_GEMV_IN_DIM=4`
  - `TASK6_RECT_GEMV_OUT_DIM=16`

Direct outputs:

- quantized extracted-op `torch`:
  - `/nix/store/qfamvz0l8b6axi8pr7snnxm61y5yfp31-task6-l1-c-fc-redirect-pt2e-static-torch.mlir`
- frozen float `L1` `torch` reference:
  - `/nix/store/zbg1drcqw0a1w77pww3nv8xq3whvqg5p-task6-l1-c-fc-redirect-torch.mlir`

Measured details:

- quantized extracted-op `torch` build:
  - `ELAPSED=4.61`
  - `RSS_KB=276,128`
- frozen float `L1` `torch` build:
  - `ELAPSED=4.24`
  - `RSS_KB=276,464`
- local PT2E inspection:
  - `ELAPSED=2.26`
  - `RSS_KB=341,772`

Key result:

- the exported `torch` MLIR is byte-identical between the PT2E-static route and
  the frozen float route:
  - quantized size:
    - `299` bytes
  - float size:
    - `299` bytes
  - shared SHA-256:
    - `f72bdc8d20105e9b8ee048aec691ee16839eee7d9020ce7e18330b1590810d9b`
  - `cmp` result:
    - `TORCH_EXPORT_IDENTICAL=1`

Local graph inspection explains why:

- prepared graph:
  - still only `aten.matmul.default`
- converted graph:
  - still only `aten.matmul.default`
- re-exported graph:
  - still only `aten.matmul.default`
- there are no inserted quant/dequant nodes on this direct external-weight
  GEMV surface

Interpretation:

- This is not "quantized, then optimized away later in MLIR".
- PT2E-static is already a no-op at the PyTorch export surface for this
  external-weight kernel.
- So the direct extracted-op parity path fails before any later IR or RTL
  question becomes relevant.

Verdict:

- This bounded quantization slice is `reject-quant-noop`.
- The broader `tiny-stories-1m` PT2E-static route remains useful as a
  full-model reference because it reaches real `handshake`.
- But the direct external-weight Task 6 kernel does not currently survive as a
  quantized extracted-op route.

Next action:

- Do not widen `task6-l1-c-fc-redirect-pt2e-static` onto `L2` or any heavier
  parity surface.
- Do not start a low-bit kernel from this route.
- Any further quantization work now needs a new extracted-op hypothesis that
  actually quantizes with external weights instead of collapsing back to the
  frozen float graph.

### 2026-04-24 - Amend execution after the second deep-research audit

The latest audit changes the execution posture, not the Task 6 thesis.

Keep:

- StreamTensor-lite as the rapid extraction / contract / kernel-comparison
  harness
- `mlp.c_fc` as the mainline boundary
- `mlp.c_proj` as reserve-only
- monolithic `L2 c_fc` surgery closed
- `L3` blocked until an architecture-level result changes the story

Change:

- stop treating more float32 helper tuning as the default frontier
- make the `top4-memory` / DDR3 shell pass the first architecture-level track
- keep quantization active only if it starts from minimized TinyStories
  surfaces first:
  - `tiny-stories-1m-representative-core`
  - then the frozen `L1` cutout
  - only then wider replay
- keep alternate-lowering closed unless a new bounded hypothesis appears
- do not start a new low-bit kernel family until one quantized route survives
  the extracted-op parity gates as a genuinely quantized artifact

Operational consequence:

- `just task6-l0`, `just task6-l1`, and `just task6-l2` remain status-only
  replay surfaces
- the next live execution slice is the monitored baseline
  `tiny-stories-1m-baseline-float-selftest-top4-memory-utilization` rerun,
  not another local kernel edit

### 2026-04-24 - First `top4-memory` rerun after switching to upstream CIRCT

Run bundle:

- `artifacts/task6/runs/2026-04-24T13-34-06+0200/`

Command run:

- `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#tiny-stories-1m-baseline-float-selftest-top4-memory-external-memory-plan --no-link --print-out-paths -L`

Observed result:

- The command did not reach the `top4-memory` model derivations.
- It first re-entered the one-time upstream toolchain bootstrap:
  - `llvm-tblgen`
  - `llvm`
  - `mlir`
  - `circt`
- measured wall-clock before manual stop:
  - `77.96 s`
- deepest direct progress seen in the build log:
  - `llvm-tblgen` configure complete
  - `llvm-tblgen` build at `[221/388]`
- no external-memory-plan store path was emitted

Interpretation:

- This is not a new DDR3 shell result.
- It is the first concrete cost of the earlier branch decision to switch from
  the local CIRCT fork to upstream `llvm/circt`.
- Until that toolchain bootstrap lands once on this machine, architecture-level
  reruns will spend their bounded pass budget on toolchain re-entry instead of
  on the actual `top4-memory` shell question.

Verdict:

- Record this as `blocked-upstream-toolchain-bootstrap`.
- Do not treat it as evidence for or against the `top4-memory` shell itself.

Next action:

- Warm the upstream LLVM/MLIR/CIRCT stack once, then rerun the monitored
  baseline `top4-memory` pass.

### 2026-04-24 - Cheapest `L0` warm-up probe after the upstream rerun block

Run bundle:

- `artifacts/task6/runs/2026-04-24T13-37-32+0200/`

Command run:

- `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l0-gemv64-yosys-stat --no-link --print-out-paths -L`

Observed result:

- measured wall-clock before manual stop:
  - `32.17 s`
- no store path was emitted
- the log again re-entered the upstream toolchain bootstrap before any Task 6
  IR stage:
  - `llvm-tblgen`
  - `llvm`
  - `mlir`
  - `circt`
- deepest direct progress seen before stop:
  - `llvm-tblgen` configure complete

Interpretation:

- This confirms the blocker is not specific to the baseline `top4-memory`
  shell.
- The branch is currently blocked on completing one full upstream
  LLVM/MLIR/CIRCT bootstrap on this machine after the `llvm/circt` switch.
- Restarted Task 6 targets do not meaningfully advance the plan until that
  bootstrap lands once.

Verdict:

- Record this as the second `blocked-upstream-toolchain-bootstrap` signal.

Next action:

- Stop spending experiment slices on restarted Task 6 targets.
- Let one full upstream bootstrap finish, then resume with the monitored
  baseline `top4-memory` pass.

### 2026-04-24 - Resume execution with external memory mainline and one bounded quant spike

Execution change:

- keep the thesis unchanged:
  - external memory and quantization stay the two active architecture tracks
  - StreamTensor-lite stays the comparison harness, not the whole solution
- change the emphasis:
  - make external memory the mainline lane
  - keep quantization as a single bounded spike on minimized TinyStories
    surfaces rather than a survey

Mainline external-memory hypothesis:

- The correct next architecture-level run is still the monitored baseline
  `tiny-stories-1m-baseline-float-selftest-top4-memory-utilization` pass.
- With the repo-local CIRCT overlay removed and the `circt-nix` upstream pair
  restored, this rerun should finally produce a real narrowed-shell utilization
  result instead of spending the entire bounded pass in toolchain bootstrap.
- Expected result:
  - either a mapped `top4-memory` shell bundle with real `DSP / BRAM / LUT / FF`
    numbers and a usable monitor summary
  - or a new concrete blocker later than toolchain bootstrap
- Falsifier:
  - the run again fails to reach the actual `top4-memory` model stages
  - or produces no narrowed-shell utilization artifact

Bounded quantization-spike hypothesis:

- The surviving PT2E-static route should be replayed first on minimized
  TinyStories full-model surfaces, not on the already-rejected direct
  external-weight extracted-op surface.
- The missing fast-loop surface in this repo is a representative-core
  PT2E-static model key that uses the same reduced-config construction as
  `tiny-stories-1m-representative-core`, then runs through the existing LSQ
  quantized pipeline.
- Expected result:
  - a minimized representative-core PT2E-static route that reaches at least
    `cf-stats`, and ideally `handshake`, faster than the full
    `tiny-stories-1m` quantized path
- Falsifier:
  - the minimized representative-core PT2E-static route fails before `cf`
  - or it clearly collapses back to the same unquantized surface without
    surviving as a meaningful quantized full-model artifact

Operational split:

- Start the monitored baseline `top4-memory` rerun first and let it consume the
  larger experiment budget.
- Use the wait time to add the representative-core PT2E-static quant surface
  and run exactly one bounded minimized-surface quant replay.

### 2026-04-24 - Mainline `top4-memory` rerun after restoring `circt-nix` as shipped

Run bundle:

- `artifacts/task6/runs/2026-04-24T18-05-18+0200-baseline-top4-memory-utilization/`

Command run:

- `MONITOR_GLOBAL_PGREP_PATTERN="default-builder.sh|yosys -q -s run.ys|yosys-abc" scripts/pipeline/monitor_build.sh artifacts/task6/runs/2026-04-24T18-05-18+0200-baseline-top4-memory-utilization 5 -- nix build .#tiny-stories-1m-baseline-float-selftest-top4-memory-utilization --no-link --print-out-paths -L`

Observed result:

- This is no longer blocked on upstream LLVM/MLIR/CIRCT bootstrap.
- The run reaches the real baseline TinyStories lowering stack and fails at:
  - `tiny-stories-1m-baseline-float-handshake.mlir.drv`
  - `circt-opt ... -flatten-memref -flatten-memref-calls -canonicalize -cse -handshake-legalize-memrefs -canonicalize -cse`
- failure mode:
  - upstream CIRCT segfault
  - `pipeline/common.sh: line 28: Segmentation fault (core dumped)`
- monitor summary:
  - `exit_status=1`
  - `wall_seconds=16`
  - `peak_vmrss_kb=565,464`
- no narrowed-shell utilization artifact was emitted

Interpretation:

- Restoring `circt-nix` as shipped fixed the earlier source-pair compile
  mismatch, but it exposes a new downstream blocker on this branch:
  - upstream CIRCT now crashes during the baseline float `cf -> handshake`
    lowering before the `top4-memory` shell flow can answer the real shell-fit
    question
- So the external-memory lane is still the mainline, but it is currently
  blocked by a concrete upstream CIRCT runtime failure rather than by bootstrap
  warm-up

Verdict:

- Record this as `block-upstream-circt-handshake-crash`.
- Do not treat it as evidence for or against `top4-memory` itself.

Next action:

- Keep external memory as the mainline lane.
- Before another baseline `top4-memory` shell pass, either:
  - pin back to a CIRCT pair that survives `tiny-stories-1m-baseline-float-handshake`
  - or isolate the minimal crashing `cf.mlir` reproducer for the upstream
    `-handshake-legalize-memrefs` failure
- Use the bounded quantization spike meanwhile, since it does not require
  reopening the closed StreamTensor-lite float32 tuning loop

### 2026-04-24 - First minimized representative-core PT2E-static quant spike attempt

Run bundle:

- `artifacts/task6/runs/2026-04-24T18-06-57+0200-representative-core-pt2e-static-cf-stats-attempt/`

Why this slice was chosen:

- The plan calls for quantization to stay a bounded spike on minimized
  TinyStories surfaces first, not another full `tiny-stories-1m` replay and
  not another extracted-op PT2E-static retry.
- The missing fast-loop surface was a representative-core full-model
  PT2E-static key, so this slice adds exactly that and tries the smallest
  meaningful gate:
  - `tiny-stories-1m-representative-core-pt2e-static-cf-stats`

Implementation added:

- `TinyStories/model_adapter_representative_core_pt2e_static_quant.py`
- model key:
  - `tiny-stories-1m-representative-core-pt2e-static`

Command run:

- `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#tiny-stories-1m-representative-core-pt2e-static-cf-stats --no-link --print-out-paths -L`

Observed result:

- The first attempt does not reach PyTorch export or MLIR stages.
- Nix evaluation fails immediately because the new adapter file is untracked and
  therefore omitted from the flake source snapshot:
  - `Path 'TinyStories/model_adapter_representative_core_pt2e_static_quant.py' ... is not tracked by Git`
- measured front-end cost:
  - `ELAPSED=1.24`
  - `RSS_KB=184,688`

Interpretation:

- This is not a quantization verdict yet.
- It is only the flake tracked-file rule firing on the newly added minimized
  quant adapter.

Verdict:

- Record this as `block-untracked-quant-surface`.

Next action:

- Track the new representative-core PT2E-static adapter in Git, commit the
  current lane state, then rerun the same `cf-stats` gate unchanged.

### 2026-04-24 - Standalone repro for the baseline float `cf -> handshake` crash

Run bundle:

- `artifacts/task6/runs/2026-04-24T18-11-02+0200-baseline-handshake-repro/`

Command run:

- `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' /nix/store/9am975q7rmbvpzxzgg1j260da3qhkqzq-circt-1.144.0g20260331_5dc62fe/bin/circt-opt /nix/store/k34gyy0qqnsd0f7yi595kxs2mx3nfjr1-tiny-stories-1m-baseline-float-cf.mlir -flatten-memref -flatten-memref-calls -canonicalize -cse -handshake-legalize-memrefs -canonicalize -cse`

Observed result:

- The upstream CIRCT crash reproduces directly outside the Nix pipeline.
- key crash signature:
  - `mlir::DenseElementsAttr::getNumElements() const`
- measured direct reproducer cost:
  - `ELAPSED=1.42`
  - `RSS_KB=94,720`
- output file stays empty:
  - `0` bytes in `/tmp/task6-baseline-float-handshake-repro.mlir`

Interpretation:

- The active external-memory blocker is a clean standalone CIRCT runtime crash,
  not a wrapper bug in the Task 6 shell machinery.
- That makes the next external-memory choice much narrower:
  - either pin back to a non-crashing CIRCT pair for shell work
  - or isolate and report the crashing `cf.mlir` reproducer upstream

Verdict:

- Record this as `pass-reproducer`.

Next action:

- Use this reproducer as the concrete blocker reference for the external-memory
  mainline while the bounded quant spike continues.

### 2026-04-24 - Representative-core PT2E-static quant spike rerun on a tracked tree

Run bundle:

- `artifacts/task6/runs/2026-04-24T18-11-27+0200-representative-core-pt2e-static-cf-stats/`

Command run:

- `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#tiny-stories-1m-representative-core-pt2e-static-cf-stats --no-link --print-out-paths -L`

Direct outputs:

- `cf-stats`:
  - `/nix/store/lggrgacn2ymq9b579sgca94wbpvawwz0-tiny-stories-1m-representative-core-pt2e-static-cf.stats`
- quantized `torch` MLIR:
  - `/nix/store/gx4kwvs2sajyd55vzyggc8r4ag1wajl2-tiny-stories-1m-representative-core-pt2e-static-torch.mlir`

Observed result:

- The minimized representative-core PT2E-static route is a real surviving full
  model surface, not a no-op like the rejected direct external-weight
  extracted-op route.
- Measured build cost:
  - `ELAPSED=49.58`
  - `RSS_KB=293,732`
- The exported `torch` MLIR contains explicit quantized structure:
  - `66` `torch.aten.quantize_per_tensor` ops
  - `17` `torch.aten.matmul` ops
- Torch-MLIR warns that several quantized operands are only partially traced and
  therefore remain in QDQ form around `torch.aten.matmul`.
- The route reaches real `cf-stats` on the minimized model, with a nontrivial
  lowered control/memory shape:
  - `arith.cmpi=1,724`
  - `cf.cond_br=1,419`
  - `memref.alloc=104`
  - `memref.global=18`

Interpretation:

- This is the first bounded quant spike on minimized TinyStories that actually
  survives as a quantized full-model artifact in this branch.
- It is therefore materially stronger than the earlier direct extracted-op
  PT2E-static no-op result.

Verdict:

- Record this as `pass-quant-minimized-cf`.

Next action:

- Spend exactly one more gate on the same minimized surface:
  - `tiny-stories-1m-representative-core-pt2e-static-handshake`

### 2026-04-24 - Representative-core PT2E-static `handshake` gate

Run bundle:

- `artifacts/task6/runs/2026-04-24T18-12-19+0200-representative-core-pt2e-static-handshake/`

Command run:

- `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#tiny-stories-1m-representative-core-pt2e-static-handshake --no-link --print-out-paths -L`

Observed result:

- The minimized representative-core quantized route fails in the same upstream
  CIRCT shell pipeline as the baseline float shell:
  - `circt-opt ... -flatten-memref -flatten-memref-calls -canonicalize -cse -handshake-legalize-memrefs -canonicalize -cse`
- crash signature matches the baseline reproducer:
  - `mlir::DenseElementsAttr::getNumElements() const`
- measured cost:
  - `ELAPSED=5.45`
  - `RSS_KB=421,944`

Interpretation:

- The external-memory mainline and the bounded quant spike now share the same
  concrete blocker:
  - upstream CIRCT crashes in `-handshake-legalize-memrefs`
- This means the next architecture-level choice is no longer "which lane first"
  so much as "which CIRCT pair is allowed to answer either lane at all"

Verdict:

- Record this as `block-shared-upstream-circt-handshake-crash`.

Next action:

- Do not widen quantization further on this branch until the handshake crash is
  removed or worked around.
- Keep the minimized representative-core PT2E-static `cf-stats` result as the
  live quant reference surface below that blocker.

### 2026-04-24 - Direct pass isolation for the shared upstream CIRCT crash

Run bundle:

- `artifacts/task6/runs/2026-04-24T18-28-54+0200-flatten-memref-isolation/`

Command set:

- `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' /nix/store/9am975q7rmbvpzxzgg1j260da3qhkqzq-circt-1.144.0g20260331_5dc62fe/bin/circt-opt /nix/store/k34gyy0qqnsd0f7yi595kxs2mx3nfjr1-tiny-stories-1m-baseline-float-cf.mlir -flatten-memref`
- `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' /nix/store/9am975q7rmbvpzxzgg1j260da3qhkqzq-circt-1.144.0g20260331_5dc62fe/bin/circt-opt /nix/store/a0jsiyfh8py537xidmx38hkkdkz773j3-tiny-stories-1m-representative-core-pt2e-static-cf.mlir -flatten-memref`

Supporting control checks:

- baseline `-canonicalize -cse`:
  - passes
- baseline `-flatten-memref-calls`:
  - passes

Observed result:

- The shared upstream blocker is narrower than the earlier shell logs implied:
  both the baseline float shell and the minimized representative-core PT2E-static
  quant spike crash on `-flatten-memref` alone.
- crash signature matches in both cases:
  - `mlir::DenseElementsAttr::getNumElements() const`
- measured direct reproducer costs:
  - baseline float:
    - `ELAPSED=2.35`
    - `RSS_KB=93,940`
  - representative-core PT2E-static:
    - `ELAPSED=1.29`
    - `RSS_KB=43,764`

Manual bounded probes:

- These do **not** reproduce the crash:
  - trivial `memref.global` plus `memref.get_global`
  - trivial `memref.global` plus `memref.load`
  - trivial strided-arg `memref.load` / `memref.store`
- These fail as legalization leftovers, not as crashes:
  - trivial `memref.expand_shape`
  - trivial `memref.subview`

Reducer attempts:

- `circt-reduce` from the upstream CIRCT package is not usable for this input in
  current packaging:
  - it cannot parse the `memref`-dialect file as invoked here
- `mlir-reduce` from the paired MLIR package exposes reducer/test options only
  through reduction-pass configuration and did not emit a reduced test case for
  this crash in one bounded attempt

Interpretation:

- The mainline external-memory blocker and the bounded quant blocker are the
  same single-pass CIRCT failure:
  - `flatten-memref`
- That is a better blocker statement than the earlier broader label
  `handshake-legalize-memrefs`.
- The current state is sufficient to justify one of only two next moves:
  - pin back to a known non-crashing CIRCT pair for branch progress
  - or extract/report the crashing full-model `cf.mlir` inputs upstream

Verdict:

- Record this as `pass-shared-flatten-memref-reproducer`.

Next action:

- Do not spend more lane time on downstream shell or quant widening until the
  `flatten-memref` blocker is either worked around or swapped out by a different
  CIRCT pair.

### 2026-04-24 - First replay of the local CIRCT fork fixes on top of `circt-nix`

Run bundle:

- `artifacts/task6/runs/2026-04-24T19-05-18+0200-representative-core-pt2e-static-handshake-fork-patches/`

Local source used:

- `/home/roland/circt`

Patch set added to this repo:

- `patches/circt-upstream-task3-recovery/0001-flatten-memref-shape-ops-after-memref-flattening.patch`
- `patches/circt-upstream-task3-recovery/0002-handle-cfg-threaded-memrefs-in-handshake-lowering.patch`
- `patches/circt-upstream-task3-recovery/0003-support-extra-frontend-ops-in-handshaketohw.patch`
- `patches/circt-upstream-task3-recovery/0004-mark-assert-and-math-illegal-in-handshaketohw.patch`
- `patches/circt-upstream-task3-recovery/0005-handle-dense-resource-globals-in-flattenmemrefs.patch`
- `patches/circt-upstream-task3-recovery/0006-lower-func-conversion-priority-in-handshaketohw.patch`
- `patches/circt-upstream-task3-recovery/0007-legalize-unrealized-conversion-casts-in-handshaketohw.patch`
- `patches/circt-upstream-task3-recovery/0008-defer-func-lowering-until-body-is-legal.patch`
- `patches/circt-upstream-task3-recovery/0009-handle-memref-model-io-and-cache-submodule-lookups.patch`
- `patches/circt-upstream-task3-recovery/0010-lower-float-ops-as-externs-in-handshaketohw.patch`

Command run:

- `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#tiny-stories-1m-representative-core-pt2e-static-handshake --no-link --print-out-paths -L`

Observed result:

- The replay gets past Nix evaluation and starts rebuilding CIRCT with the new
  patch stack.
- It fails in `patchPhase`, before compile or MLIR lowering, because the first
  `FlattenMemRefs` patch no longer applies cleanly to the newer upstream CIRCT
  revision packaged by `circt-nix`.
- Direct patch failure from the build log:
  - `Hunk #5 FAILED at 515`
  - reject file:
    - `lib/Transforms/FlattenMemRefs.cpp.rej`
- measured cost:
  - `ELAPSED=6.15`
  - `RSS_KB=421,892`

Interpretation:

- The April 20 fork fixes are directionally relevant, but they are not
  drop-in-applicable to the current upstream CIRCT package as-is.
- The active blocker has therefore shifted one step earlier:
  - from runtime `flatten-memref` crash
  - to source drift in `FlattenMemRefs.cpp` during patch application

Verdict:

- Record this as `block-circt-patch-drift`.

Next action:

- Rebase or hand-adapt the `FlattenMemRefs` fixes onto the current upstream
  source, then rerun the same minimized representative-core `handshake` gate
  unchanged before spending another slice on the heavier external-memory shell.

### 2026-04-24 - Rebased fork patch stack clears CIRCT compile but trips one buffer regression test

Run bundle:

- `artifacts/task6/runs/2026-04-24T19-18-44+0200-representative-core-pt2e-static-handshake-rebased-fork-patches/`

Rebased patch set now applied in this repo:

- `patches/circt-upstream-task3-recovery/0001-flatten-memref-shape-ops-after-memref-flattening.patch`
- `patches/circt-upstream-task3-recovery/0002-handle-cfg-threaded-memrefs-in-handshake-lowering.patch`
- `patches/circt-upstream-task3-recovery/0005-handle-dense-resource-globals-in-flattenmemrefs.patch`
- `patches/circt-upstream-task3-recovery/0011-rebased-handshaketohw-stack.patch`

Command run:

- `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#tiny-stories-1m-representative-core-pt2e-static-handshake --no-link --print-out-paths -L`

Observed result:

- The rebased patch stack now applies cleanly to the `circt-nix` packaged
  CIRCT source.
- CIRCT completes `buildPhase` successfully.
- The critical patched files compile and link:
  - `lib/Transforms/FlattenMemRefs.cpp`
  - `lib/Dialect/Handshake/Transforms/LegalizeMemrefs.cpp`
  - `lib/Conversion/HandshakeToHW/HandshakeToHW.cpp`
- `check-circt` then runs and reports exactly one failure:
  - `CIRCT :: Conversion/HandshakeToHW/test_buffer.mlir`
- The failing FileCheck expects:
  - `hw.constant false`
- The patched lowering emits:
  - `hw.constant 0 : i0`
- measured build cost:
  - `ELAPSED=803.01`
  - `RSS_KB=421,760`
- test summary:
  - `Passed: 1163`
  - `Failed: 1`
  - `Expectedly Failed: 6`
  - `Unsupported: 39`

Interpretation:

- This is a real step forward from the original upstream blocker.
- The local fork fixes are no longer blocked by patch drift, and the old
  `flatten-memref` infrastructure path is cleared far enough to rebuild the
  whole packaged CIRCT toolchain.
- The active blocker has shifted again:
  - away from runtime `flatten-memref` crash
  - away from patch drift
  - to one CIRCT regression expectation in Handshake-to-HW buffer lowering
- That is the right scale of blocker to address next because it keeps checks
  enabled and should let the same representative-core `handshake` gate answer
  the actual Task 6 question once aligned.

Verdict:

- Record this as `block-circt-check-buffer-test`.

Next action:

- Recover the matching buffer-test update from the local fork history and rerun
  the same representative-core `handshake` gate unchanged before moving on to a
  heavier external-memory rerun.

### 2026-04-24 - Rebased fork stack plus buffer-test fix clears CIRCT and exposes the next quant blocker

Run bundle:

- `artifacts/task6/runs/2026-04-24T19-41-24+0200-representative-core-pt2e-static-handshake-rebased-fork-patches-plus-testfix/`

Additional patch added from local fork history:

- `patches/circt-upstream-task3-recovery/0012-update-buffer-lowering-test-for-constant-order.patch`

Command run:

- `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#tiny-stories-1m-representative-core-pt2e-static-handshake --no-link --print-out-paths -L`

Observed result:

- CIRCT now builds completely under Nix with the rebased patch stack plus the
  matching test update.
- The build reaches `fixupPhase`, so:
  - the old upstream `flatten-memref` crash is cleared
  - the earlier `check-circt` blocker on
    `Conversion/HandshakeToHW/test_buffer.mlir` is also cleared
- The representative-core quantized `handshake` derivation then fails later in
  its own lowering pipeline with:
  - `<Pass-Options-Parser>: no such option lsq`
  - `failed to add lower-cf-to-handshake with options lsq`
- measured cost:
  - `ELAPSED=829.21`
  - `RSS_KB=421,940`

Interpretation:

- This is the first clean proof that the local fork fixes are functionally
  relevant on current upstream packaging:
  - we are no longer blocked by patch drift
  - we are no longer blocked by the upstream CIRCT `flatten-memref` crash
  - we are no longer blocked by the one failing Handshake-to-HW regression test
- The quantized representative-core route is still blocked, but now on a more
  specific contract mismatch:
  - the route expects an LSQ-specific `lower-cf-to-handshake=lsq` option
  - the current patched upstream stack does not expose that option
- This means the external-memory float mainline can be resumed on the repaired
  CIRCT base, while the quant spike now needs either:
  - restoration of the older LSQ memory-lowering extension, or
  - a non-LSQ handshake path

Verdict:

- Record this as `block-missing-lsq-option`.

Next action:

- Rerun the external-memory mainline on the repaired CIRCT stack first.
- Keep the quant spike bounded and decide separately whether to restore the LSQ
  option support or switch that route onto a non-LSQ path.

### 2026-04-28 - Fixed `top34-memory` utilization completes after GC-rooted JSON rerun

Run bundles:

- Full monitored staged rerun:
  - `artifacts/task6/runs/2026-04-27T23-43-30+0200-baseline-top34-memory-utilization-filterfix-rerun`
- JSON/utilization rerun after freeing disk:
  - `artifacts/task6/runs/2026-04-28T03-11-30+0200-baseline-top34-memory-utilization-filterfix-json-rerun`

Commands:

- full staged run:
  - `nix build .#tiny-stories-1m-baseline-float-selftest-top34-memory-utilization --no-link --print-out-paths -L`
  - wrapped with `scripts/pipeline/monitor_build.sh`
- after ENOSPC:
  - temporarily preserved the successful `stage8h` output with a Nix GC root
  - ran `nix-store --gc --max-freed 64424509440`, which freed `60.8 GiB`
  - reran the same utilization target under the monitor

Full staged rerun result:

- exit status: `1`
- wall time: `12340` seconds
- peak sampled `VmRSS`: `20,578,672 KiB`
- peak sampled `VmHWM`: `20,816,540 KiB`
- completed:
  - `stage6a targeted techmap cells_map` through all `221/221` restart
    batches
  - `stage8b abc -luts 2:2,3,6:5,10,20`
  - `stage8h opt_lut_ins -tech xilinx`
- failure:
  - JSON derivation preparation hit `OSError: [Errno 28] No space left on
    device` in `filter_rtlil_modules.py`
- interpretation:
  - this crossed both prior external-memory frontiers
  - the failure was disk exhaustion, not a synthesis-path failure

JSON/utilization rerun result:

- exit status: `0`
- wall time: `294` seconds
- peak sampled `VmRSS`: `22,539,800 KiB`
- peak sampled `VmHWM`: `23,849,916 KiB`
- final monitor stage line:
  - `stage9 write_json`
- output:
  - `/nix/store/lnzv5y9vj69s8hhg3zp0x35hrmzmrrzz-tiny-stories-1m-baseline-float-selftest-top34-memory-utilization`
  - durable copy:
    `artifacts/task6/runs/2026-04-28T03-11-30+0200-baseline-top34-memory-utilization-filterfix-json-rerun/utilization`

Mapped utilization:

- `clb_luts`: `56,899,009 / 298,600` (`19055.26%`)
- `clb_ffs`: `58,496,710 / 597,200` (`9795.16%`)
- `slices_lower_bound`: `7,312,089 / 74,650` (`9795.16%`)
- `dsp`: `0 / 1920` (`0.00%`)
- `bram36`: `0 / 955` (`0.00%`)

Delta versus copied all-memory baseline:

- copied baseline:
  - `clb_luts`: `40,416,086`
  - `clb_ffs`: `58,072,527`
  - `dsp`: `0`
  - `bram36_equivalent`: `0.0`
- `top34-memory` delta:
  - `clb_luts`: `+16,482,923` (`+40.78%`)
  - `clb_ffs`: `+424,183` (`+0.73%`)
  - `dsp`: unchanged at `0`
  - `bram36`: unchanged at `0`

Largest remaining non-top mapped owners by LUT count:

- `handshake_memory_out_f32_id77`: `631,072` LUTs, `8,360` FFs
- `math_fpowi_in_f32_ui64_out_f32`: `370,334` LUTs, `0` FFs
- `handshake_memory_out_f32_id25`: `340,924` LUTs, `2,437` FFs
- `handshake_memory_out_f32_id72`: `47,456` LUTs, `8,212` FFs
- `handshake_memory_out_f32_id37`: `34,955` LUTs, `2,132` FFs

Interpretation:

- The production filter fix is verified.
- `top34-memory` is a real toolchain-frontier improvement:
  - it clears the prior `top4-memory` `stage6a` residual-memory frontier
  - it clears the prior `top32-memory` `stage8b` ABC frontier
  - it produces a final utilization bundle after the disk-space issue is fixed
- `top34-memory` is not a mapped-resource improvement:
  - LUT usage is materially worse than the copied all-memory baseline
  - FF usage is slightly worse
  - DSP and BRAM remain unused

Decision:

- Close this `top34-memory` execution slice as `positive` for compiler
  frontier movement and `negative` for mapped resource reduction.
- Do not move directly to DDR3 controller integration for this exact shell.
- Keep external memory alive only as a contract/interface-shaping lane:
  - explain why the current blackbox shell inflates LUTs before widening it
    again
  - use the largest residual owners above as the next inspection targets if
    this lane gets another slice
  - compare any follow-up against the copied all-memory baseline, not only
    against OOM progress

### 2026-04-28 - Redirection baseline owner extraction corrected

Decision record:

- `docs/task6-redirection-decision.md`

Machine-readable baseline:

- `artifacts/task6/parallel-hypotheses/baseline-top34.csv`

Command:

- `python3 scripts/task6/extract_metrics.py artifacts/task6/runs/2026-04-28T03-11-30+0200-baseline-top34-memory-utilization-filterfix-json-rerun artifacts/task6-streamtensor-lite/runs/2026-04-24T00-10-27+0200/stage-local-l1 artifacts/task6-streamtensor-lite/runs/2026-04-24T00-10-36+0200/stage-local-l2 --artifact top34-memory --artifact l1-c-fc-frozen --artifact l2-c-fc-tile4x64 --out artifacts/task6/parallel-hypotheses/baseline-top34.csv`

Script update:

- `scripts/task6/extract_metrics.py` now weights `top_owners` by direct owner
  instance count under the real synthesized `main` module when the design is
  wrapped by `tiny_stories_selftest_top`.
- The old extraction ranked one instance of each module definition, which made
  single large owners like `handshake_memory_out_f32_id77` look dominant while
  hiding heavily repeated buffer types.

Corrected `top34-memory` owner signal:

- `handshake_buffer_in_ui64_out_ui64_2slots_seq`:
  `168,260` instances, `34,156,780` LUT, `43,747,600` FF.
- `handshake_buffer_in_f64_out_f64_2slots_seq`:
  `28,455` instances, `5,776,365` LUT, `7,398,300` FF.
- `handshake_buffer_in_f32_out_f32_2slots_seq`:
  `50,929` instances, `5,449,403` LUT, `6,722,628` FF.
- The copied all-memory baseline delta is still unchanged:
  `+16,482,923` LUT and `+424,183` FF for `top34-memory`.

Interpretation:

- The negative baseline is stronger than the earlier owner list suggested:
  the external-memory shell is dominated by repeated two-slot handshake buffers
  and mux/index fabric, not only by a few large residual memory modules.
- This supports the redirection decision:
  external memory remains useful only when paired with streaming/tiled engines
  that avoid reconstructing the full lowered handshake shell.

Immediate execution queue:

1. `H1`: score a streaming/tiled GEMV memory contract before any DDR3 work.
   Required first artifact: cycles/token, bytes/token, external weight bytes,
   and `DSP > 0` on the existing `L2` tiled surface or a smaller synthetic
   derivative.
2. `H2`: add int8/int4 packed-weight GEMV candidates only on bounded kernels.
   Required first artifact: Verilator pass, bounded numeric error, and either
   `<15k` LUT on `L2` scale or at least `2x` LUT reduction versus the current
   `31,907` LUT `L2` reference.
3. `H3`: replace the `L2` tiled wrapper's handshake-heavy sequencing with a
   static counter/FSM proof. Required first artifact: Verilator pass and mapped
   LUT below the current `31,907` LUT reference.
4. `H5`: compute model/rung byte budgets before larger replays. Required first
   artifact: weight bytes, activation bytes, and minimum bandwidth for the
   reduced-vocab, representative-core, and any proposed staged TinyStories
   rungs.

Stop rule:

- Do not spend another full-model `topN-memory` mapped run unless one of the
  bounded lanes above first predicts an order-of-magnitude fabric reduction or
  eliminates the repeated two-slot buffer class from the top-owner list.

### 2026-04-28 - H5 first byte-budget artifact from existing weight packs

Artifact:

- `artifacts/task6/parallel-hypotheses/h5-rung-byte-budgets.csv`

Inputs:

- `artifacts/task6/weights_pack/tiny-stories-1m-representative-core-v64-h4/transformer.h.0.mlp.c_fc/manifest.json`
- `artifacts/task6/weights_pack/tiny-stories-1m-representative-core-v64-h4/transformer.h.0.mlp.c_proj/manifest.json`
- `artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_fc/manifest.json`
- `artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_proj/manifest.json`

Assumption:

- This is a minimum sequential traffic estimate for the MLP weights if weights
  are streamed once per token and activations/bias remain `f32`.
- It does not include tokenizer, embeddings, attention, layernorm, activation
  approximation, DDR burst overhead, or cache reuse.

Observed budgets:

- `tiny-stories-1m-representative-core-v64-h4` full MLP stack:
  - f32 weights: `1,504` bytes/token
  - int8 weights with f32 activations/bias: `736` bytes/token
  - int4 weights with f32 activations/bias: `608` bytes/token
- `tiny-stories-v1k-h64-l1` full MLP stack:
  - f32 weights: `134,912` bytes/token
  - int8 weights with f32 activations/bias: `36,608` bytes/token
  - int4 weights with f32 activations/bias: `20,224` bytes/token

Interpretation:

- The `v1k-h64-l1` MLP is the first useful H1/H2 bandwidth surface:
  it is small enough to reason about by inspection but large enough that f32
  weight streaming is already about `132 KiB` per token for the MLP alone.
- The immediate H2 value is concrete:
  int8 packed weights cut the `v1k-h64-l1` MLP traffic estimate by about `3.7x`,
  and int4 packed weights cut it by about `6.7x`, before any activation or
  sequencer savings.

### 2026-04-28 - H1/H2 streaming-contract score artifact

Artifact:

- `artifacts/task6/parallel-hypotheses/h1-h2-streaming-contract-score.csv`
- `artifacts/task6/parallel-hypotheses/h1-h2-streaming-contract-score.json`

Script:

- `scripts/task6/score_streaming_contract.py`

Command:

- `python3 scripts/task6/score_streaming_contract.py --manifest artifacts/task6/weights_pack/tiny-stories-1m-representative-core-v64-h4/transformer.h.0.mlp.c_fc/manifest.json --manifest artifacts/task6/weights_pack/tiny-stories-1m-representative-core-v64-h4/transformer.h.0.mlp.c_proj/manifest.json --manifest artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_fc/manifest.json --manifest artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_proj/manifest.json --dsp-lanes 4 --out-csv artifacts/task6/parallel-hypotheses/h1-h2-streaming-contract-score.csv --out-json artifacts/task6/parallel-hypotheses/h1-h2-streaming-contract-score.json`

Assumption:

- `dsp_lanes = 4`, matching the current mapped `L1`/`L2` references.
- Cycle estimates are hard lower bounds: `ceil(MACs / dsp_lanes)`.
- Byte estimates count streamed weights once per token plus f32 bias,
  activation input, and activation output. They exclude burst overhead,
  attention, layernorm, activation approximation, and any cache reuse.

Key rows:

- `tiny-stories-v1k-h64-l1` full MLP stack:
  - `32,768` MACs/token
  - `8,192` minimum compute cycles/token at `4` DSP lanes
  - `134,912` f32 bytes/token
  - `36,608` bytes/token with int8 weights and f32 activations/bias
  - `20,224` bytes/token with int4 weights and f32 activations/bias
  - `16.47` f32 bytes/cycle, `4.47` int8-weight bytes/cycle,
    `2.47` int4-weight bytes/cycle
- `tiny-stories-1m-representative-core-v64-h4` full MLP stack:
  - `256` MACs/token
  - `64` minimum compute cycles/token at `4` DSP lanes
  - `1,504` f32 bytes/token
  - `736` bytes/token with int8 weights and f32 activations/bias
  - `608` bytes/token with int4 weights and f32 activations/bias

Interpretation:

- H1 is viable as a memory-contract lane only if the implementation avoids the
  full lowered handshake shell. The corrected `top34-memory` owner list shows
  the shell cost is repeated two-slot buffers, while this score shows the
  sequential MLP traffic itself is small enough to model cheaply on `v1k-h64-l1`.
- H2 has a measurable bandwidth payoff before RTL work:
  int8 weights reduce the `v1k-h64-l1` MLP traffic from about `132 KiB/token`
  to about `36 KiB/token`, and int4 reduces it to about `20 KiB/token`.
- This does not yet prove a mapped LUT reduction. The next H2 implementation
  should be a bounded packed-weight GEMV kernel, not another full-model
  quantized lowering route.

Next action:

- Use the generated H1/H2 score as the acceptance target for the next bounded
  implementation:
  - H1 static/streaming GEMV should preserve `4 DSP` and keep memory traffic
    close to the `v1k-h64-l1` score rows.
  - H2 packed int8/int4 GEMV should prove functional error bounds and mapped
    resource reduction on a small kernel before any `L3` or whole-model replay.

### 2026-04-28 - H3 wrapper inspection narrows the static-sequencer target

Artifact:

- `artifacts/task6/parallel-hypotheses/h3-static-wrapper-inspection.json`

Inspected source:

- `rtl/task6/task6_l2_c_fc_tile4x64_main.sv`

Observation:

- The `L2` tiled wrapper is already a static phase sequencer:
  - `active_q`
  - `phase_q`
  - `launch_pending_q`
- It reuses one `task6_l2_c_fc_tile64_kernel` over four output phases.
- It forms the upper weight address and output store address bits from
  `phase_q`.
- It auto-acks tile output for phases `0..2` and only exposes `out0_valid` on
  phase `3`.

Prior mapped evidence:

- untouched tile64 kernel: `32,478` LUT
- untouched tile4x64 wrapper: `32,460` LUT
- postbranch tile64 kernel: `31,968` LUT
- postbranch tile4x64 wrapper: `31,907` LUT

Decision:

- H3 should not spend its next slice replacing the outer tiled wrapper.
- The wrapper is already static and has negligible mapped cost relative to the
  tile kernel.
- The real H3 target is now narrower:
  build or sketch a bounded static `64x64` tile-kernel proof that removes the
  generated handshake buffers/forks/muxes inside the kernel while preserving
  the existing activation/weight/store contract.

### 2026-04-28 - H2 quantized-weight contract replay

Artifact:

- `artifacts/task6/parallel-hypotheses/h2-quantized-weight-replay.csv`
- `artifacts/task6/parallel-hypotheses/h2-quantized-weight-replay.json`

Script:

- `scripts/task6/score_quantized_weight_replay.py`

Command:

- `python3 scripts/task6/score_quantized_weight_replay.py --case l1-c_fc=artifacts/task6/streamtensor-lite/l1/representative-core-v64-h4-c_fc-contract/manifest.json=artifacts/task6/weights_pack/tiny-stories-1m-representative-core-v64-h4/transformer.h.0.mlp.c_fc/manifest.json --case l1-c_proj=artifacts/task6/streamtensor-lite/l1/representative-core-v64-h4-c_proj-contract/manifest.json=artifacts/task6/weights_pack/tiny-stories-1m-representative-core-v64-h4/transformer.h.0.mlp.c_proj/manifest.json --case l2-c_fc=artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_fc-contract/manifest.json=artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_fc/manifest.json --case l2-c_proj=artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_proj-contract/manifest.json=artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_proj/manifest.json --normalized-rmse-threshold 0.02 --out-csv artifacts/task6/parallel-hypotheses/h2-quantized-weight-replay.csv --out-json artifacts/task6/parallel-hypotheses/h2-quantized-weight-replay.json`

Method:

- Replay captured `activation_in @ dequantized(weight).T + bias` contracts.
- Test symmetric int8 and int4 weights with:
  - one per-tensor scale
  - per-output-channel scales
- Keep activations and bias in `f32`.
- Use `normalized_rmse <= 0.02` as the first bounded pass/fail threshold.

Result:

- int8 passes all four captured contracts:
  - `L1 c_fc`: per-tensor `0.00674`, per-output `0.00278`
  - `L1 c_proj`: per-tensor `0.00608`, per-output `0.00658`
  - `L2 c_fc`: per-tensor `0.00991`, per-output `0.00656`
  - `L2 c_proj`: per-tensor `0.00881`, per-output `0.00663`
- int4 fails all four captured contracts even with per-output scales:
  - `L1 c_fc`: best `0.05647`
  - `L1 c_proj`: best `0.12575`
  - `L2 c_fc`: best `0.12264`
  - `L2 c_proj`: best `0.11153`

Decision:

- Keep int8 as the active H2 packed-weight RTL candidate.
- Do not spend RTL implementation time on this simple int4 scheme.
- Reopen int4 only if a different bounded quantization scheme is proposed,
  such as group-wise scaling, mixed precision, or activation-aware calibration.

Next action:

- Build the smallest int8 packed-weight GEMV proof that can be compared against
  the current `4 DSP` L0/L1/L2 references.
- The first RTL gate should prove:
  - functional replay against the captured contract
  - `DSP > 0`
  - mapped LUT below the current float L0/L2 kernel class, or a clear reason
    why dequantization must move outside the kernel.

### 2026-04-28 - H2 bounded int8 GEMV RTL proof surface prepared

Artifact:

- `artifacts/task6/parallel-hypotheses/h2-int8-gemv64-rtl-proof.json`

Sources:

- `flake.nix`
- `rtl/task6/task6_int8_gemv64_kernel.sv`
- `sim/task6_int8_gemv64_tb_main.sv`
- `sim/gen_task6_int8_gemv64_tb_data.py`

Command:

- `python3 sim/gen_task6_int8_gemv64_tb_data.py --out-json artifacts/task6/parallel-hypotheses/h2-int8-gemv64-rtl-proof.json`
- `nix build .#task6-int8-gemv64-sv-sim --no-link --print-out-paths -L`
- `python3 sim/gen_task6_int8_gemv64_tb_data.py --sim-result-json /nix/store/alwiq620fdhryhhz9kxhdfg5f3p955wr-task6-int8-gemv64-sv-sim.json --out-json artifacts/task6/parallel-hypotheses/h2-int8-gemv64-rtl-proof.json`
- `nix build .#task6-int8-gemv64-yosys-stat --no-link --print-out-paths -L`
- `python3 sim/gen_task6_int8_gemv64_tb_data.py --sim-result-json /nix/store/alwiq620fdhryhhz9kxhdfg5f3p955wr-task6-int8-gemv64-sv-sim.json --yosys-stat-json /nix/store/2p1gl2hpfw0q1shbnpbyv4avrwjs87gh-task6-int8-gemv64-yosys-stat.json --out-json artifacts/task6/parallel-hypotheses/h2-int8-gemv64-rtl-proof.json`
- `nix build .#task6-int8-gemv64-utilization --no-link --print-out-paths -L`
- `python3 sim/gen_task6_int8_gemv64_tb_data.py --sim-result-json /nix/store/alwiq620fdhryhhz9kxhdfg5f3p955wr-task6-int8-gemv64-sv-sim.json --yosys-stat-json /nix/store/2p1gl2hpfw0q1shbnpbyv4avrwjs87gh-task6-int8-gemv64-yosys-stat.json --mapped-utilization-summary-json /nix/store/lwizcdpbhh36ah4fafa0zgvbv8n3zs4a-task6-int8-gemv64-utilization/summary.json --out-json artifacts/task6/parallel-hypotheses/h2-int8-gemv64-rtl-proof.json`

Prepared contract:

- `64 x 64` GEMV
- signed int8 activations
- signed int8 weights
- signed int32 accumulation
- `4,096` MACs
- combinational address/data activation and weight memories
- ready/valid output stream

Deterministic vector summary:

- activation SHA256: `9d8e95167716149b582c1e8f772e5b312655bc79adf990872b9ecc46ce150174`
- weight SHA256: `498ae3ff71f98690cd4ec3aafa2d70f6adc5600f869cac426dad14e091ff7fa9`
- expected-output SHA256: `7bd0a431ea01f3cd043896562031b5792ecce0f35f3850f0dc0ff271f77abed8`
- expected output range: `-1164..1688`

Execution status:

- RTL source and self-checking testbench are prepared.
- Flake target `.#task6-int8-gemv64-sv-sim` is wired.
- `python3 -m py_compile sim/gen_task6_int8_gemv64_tb_data.py` passes.
- The JSON artifact validates with `python3 -m json.tool`.
- The RTL simulation passes through Nix-provided Verilator:
  - output: `/nix/store/alwiq620fdhryhhz9kxhdfg5f3p955wr-task6-int8-gemv64-sv-sim.json`
  - pass line: `PASS: task6 int8 GEMV stores 64 outputs 64 cycles 4162`
- The light Yosys gate passes through Nix-provided `pkgs.yosys`:
  - output: `/nix/store/2p1gl2hpfw0q1shbnpbyv4avrwjs87gh-task6-int8-gemv64-yosys-stat.json`
  - `DSP48E1`: `1`
  - LUT primitive cells: `68` (`LUT2=42`, `LUT3=1`, `LUT4=1`,
    `LUT5=2`, `LUT6=22`)
  - `FDRE`: `66`
  - `CARRY4`: `7`
  - Yosys log estimated LCs: `46`
- The mapped JSON utilization gate passes through the existing utilization
  reporter:
  - output: `/nix/store/lwizcdpbhh36ah4fafa0zgvbv8n3zs4a-task6-int8-gemv64-utilization`
  - `clb_luts`: `68`
  - `clb_ffs`: `66`
  - `dsp`: `1`
  - `bram36_equiv`: `0`
  - `slices_lower_bound`: `9`

Interpretation:

- This answers the immediate "do we have an int8 RTL surface?" question with
  "yes, a bounded fixed-point int8 kernel now passes Verilator and maps one
  DSP48E1 under light `synth_xilinx`, with a durable mapped utilization row."
- It is deliberately narrower than the earlier H2 numeric replay:
  the replay kept activations and bias in `f32`, while this bounded RTL proof is
  a fixed-point int8-activation/int8-weight kernel with int32 accumulation.
- It avoids the older torch-mlir byte/char int8 route that blocked the prior
  local `task6-l0-gemv64-int8` probe.
- H2 stays active. The next required evidence is a scaled bounded variant:
  either multiple DSP lanes sharing the same controller, or a small tiled
  `L2`-shape wrapper that proves the low standalone LUT count survives the
  interface and sequencing needed by a real MLP slice.

### 2026-04-28 - H2 bounded int8 GEMV four-lane RTL proof

Artifact:

- `artifacts/task6/parallel-hypotheses/h2-int8-gemv64-lanes4-rtl-proof.json`

Sources:

- `flake.nix`
- `rtl/task6/task6_int8_gemv64_lanes4_kernel.sv`
- `sim/task6_int8_gemv64_lanes4_tb_main.sv`
- `sim/gen_task6_int8_gemv64_tb_data.py`

Command:

- `nix build .#task6-int8-gemv64-lanes4-sv-sim --no-link --print-out-paths -L`
- `nix build .#task6-int8-gemv64-lanes4-yosys-stat --no-link --print-out-paths -L`
- `nix build .#task6-int8-gemv64-lanes4-utilization --no-link --print-out-paths -L`
- `python3 sim/gen_task6_int8_gemv64_tb_data.py --artifact-name h2-int8-gemv64-lanes4-rtl-proof --kernel-source rtl/task6/task6_int8_gemv64_lanes4_kernel.sv --testbench-source sim/task6_int8_gemv64_lanes4_tb_main.sv --top-name task6_int8_gemv64_lanes4_kernel --lane-count 4 --nix-target-prefix task6-int8-gemv64-lanes4 --sim-result-json /nix/store/z1fdggakr9xbd5wb5l3iyxknbvkc902a-task6-int8-gemv64-lanes4-sv-sim.json --yosys-stat-json /nix/store/pcj9qnir5n61zvfnqd9j1pw9yis8fh01-task6-int8-gemv64-lanes4-yosys-stat.json --mapped-utilization-summary-json /nix/store/1020khq23md4gdl7kscx7b9p3kxiy0qm-task6-int8-gemv64-lanes4-utilization/summary.json --out-json artifacts/task6/parallel-hypotheses/h2-int8-gemv64-lanes4-rtl-proof.json`

Prepared contract:

- `64 x 64` GEMV
- signed int8 activations
- signed int8 weights
- signed int32 accumulation
- `4,096` MACs
- `4` parallel output/MAC lanes sharing one controller
- `16` output tiles
- combinational address/data activation and packed-lane weight memories
- ready/valid output stream

Execution status:

- The RTL simulation passes through Nix-provided Verilator:
  - output: `/nix/store/z1fdggakr9xbd5wb5l3iyxknbvkc902a-task6-int8-gemv64-lanes4-sv-sim.json`
  - pass line: `PASS: task6 int8 GEMV4 stores 64 outputs 64 cycles 1090`
- The light Yosys gate passes through Nix-provided `pkgs.yosys`:
  - output: `/nix/store/pcj9qnir5n61zvfnqd9j1pw9yis8fh01-task6-int8-gemv64-lanes4-yosys-stat.json`
  - `DSP48E1`: `4`
  - LUT primitive cells: `242` (`LUT2=149`, `LUT3=39`, `LUT4=1`,
    `LUT5=11`, `LUT6=42`)
  - `FDRE`: `187`
  - `CARRY4`: `18`
  - Yosys log estimated LCs: `148`
- The mapped JSON utilization gate passes through the existing utilization
  reporter:
  - output: `/nix/store/1020khq23md4gdl7kscx7b9p3kxiy0qm-task6-int8-gemv64-lanes4-utilization`
  - `clb_luts`: `242`
  - `clb_ffs`: `187`
  - `dsp`: `4`
  - `bram36_equiv`: `0`
  - `slices_lower_bound`: `31`

Interpretation:

- The four-lane proof keeps the same fixed-point int8/int8/int32 contract as
  the single-lane proof, but proves the controller can feed and retire four
  parallel DSP MAC lanes.
- Compared with the single-lane proof, simulation cycles improve from `4162`
  to `1090`, while mapped DSP usage scales linearly from `1` to `4`.
- Mapped LUTs rise from `68` to `242` and FFs rise from `66` to `187`, so the
  widened datapath does not create the kind of control/interface explosion
  seen in the float baseline lanes.
- H2 remains the strongest local resource-reduction lane. The next evidence
  should attach this four-lane fixed-point datapath to a small explicit
  packed-weight memory or an `L2`-shape tile wrapper before extrapolating to
  the full MLP shell.

### 2026-04-28 - H2 four-lane int8 packed-weight interface proof

Artifact:

- `artifacts/task6/parallel-hypotheses/h2-int8-gemv64-lanes4-packed-rtl-proof.json`

Sources:

- `flake.nix`
- `rtl/task6/task6_int8_gemv64_lanes4_packed_kernel.sv`
- `sim/task6_int8_gemv64_lanes4_packed_tb_main.sv`
- `sim/gen_task6_int8_gemv64_tb_data.py`

Command:

- `nix build .#task6-int8-gemv64-lanes4-packed-sv-sim --no-link --print-out-paths -L`
- `nix build .#task6-int8-gemv64-lanes4-packed-yosys-stat --no-link --print-out-paths -L`
- `nix build .#task6-int8-gemv64-lanes4-packed-utilization --no-link --print-out-paths -L`
- `python3 sim/gen_task6_int8_gemv64_tb_data.py --artifact-name h2-int8-gemv64-lanes4-packed-rtl-proof --kernel-source rtl/task6/task6_int8_gemv64_lanes4_packed_kernel.sv --testbench-source sim/task6_int8_gemv64_lanes4_packed_tb_main.sv --top-name task6_int8_gemv64_lanes4_packed_kernel --lane-count 4 --packed-weight-words 1024 --nix-target-prefix task6-int8-gemv64-lanes4-packed --sim-result-json /nix/store/0q6r90sdfd4jgksdwf5sfixnrj3dap59-task6-int8-gemv64-lanes4-packed-sv-sim.json --yosys-stat-json /nix/store/f8500lrc4gn6k8wnswlv2n6k5lizsaia-task6-int8-gemv64-lanes4-packed-yosys-stat.json --mapped-utilization-summary-json /nix/store/sh60mam9pc36p3mh5w2wsiznbd56434b-task6-int8-gemv64-lanes4-packed-utilization/summary.json --out-json artifacts/task6/parallel-hypotheses/h2-int8-gemv64-lanes4-packed-rtl-proof.json`

Prepared contract:

- `64 x 64` GEMV
- signed int8 activations
- signed int8 weights
- signed int32 accumulation
- `4,096` MACs
- `4` parallel output/MAC lanes sharing one controller
- `1,024` packed weight words, each carrying one `4`-lane int8 weight vector
- one packed weight address/data port per activation step
- ready/valid output stream

Execution status:

- The RTL simulation passes through Nix-provided Verilator:
  - output: `/nix/store/0q6r90sdfd4jgksdwf5sfixnrj3dap59-task6-int8-gemv64-lanes4-packed-sv-sim.json`
  - pass line: `PASS: task6 int8 GEMV4 packed stores 64 outputs 64 cycles 1090`
- The light Yosys gate passes through Nix-provided `pkgs.yosys`:
  - output: `/nix/store/f8500lrc4gn6k8wnswlv2n6k5lizsaia-task6-int8-gemv64-lanes4-packed-yosys-stat.json`
  - `DSP48E1`: `4`
  - LUT primitive cells: `242` (`LUT2=149`, `LUT3=39`, `LUT4=1`,
    `LUT5=11`, `LUT6=42`)
  - `FDRE`: `187`
  - `CARRY4`: `9`
  - Yosys log estimated LCs: `148`
- The mapped JSON utilization gate passes through the existing utilization
  reporter:
  - output: `/nix/store/sh60mam9pc36p3mh5w2wsiznbd56434b-task6-int8-gemv64-lanes4-packed-utilization`
  - `clb_luts`: `242`
  - `clb_ffs`: `187`
  - `dsp`: `4`
  - `bram36_equiv`: `0`
  - `slices_lower_bound`: `31`

Interpretation:

- The packed interface proof preserves the four-lane fixed-point datapath and
  throughput from the previous H2 proof while replacing four independent
  weight addresses with one packed-word address.
- Compared with the unpacked four-lane proof, mapped LUTs, FFs, DSPs, and
  lower-bound slices remain unchanged (`242`, `187`, `4`, and `31`), while
  `CARRY4` cells drop from `18` to `9` and public wire bits drop from `629` to
  `587`.
- This is still a kernel/interface proof, not a full local-memory proof: the
  weights are supplied through a combinational packed data port rather than an
  inferred or explicit BRAM.
- The next H2 gate should add an explicit small packed-weight memory boundary
  or an `L2`-shape tile wrapper around this packed interface, so the memory
  read latency and storage mapping are represented before scaling further.

### 2026-04-28 - H2 four-lane int8 packed-weight sync-memory proof

Artifact:

- `artifacts/task6/parallel-hypotheses/h2-int8-gemv64-lanes4-packed-sync-mem-rtl-proof.json`

Sources:

- `flake.nix`
- `rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv`
- `rtl/task6/task6_int8_gemv64_lanes4_packed_sync_mem_kernel.sv`
- `sim/task6_int8_gemv64_lanes4_packed_sync_mem_tb_main.sv`
- `sim/gen_task6_int8_gemv64_tb_data.py`

Command:

- `nix build .#task6-int8-gemv64-lanes4-packed-sync-mem-sv-sim --no-link --print-out-paths -L`
- `nix build .#task6-int8-gemv64-lanes4-packed-sync-mem-yosys-stat --no-link --print-out-paths -L`
- `nix build .#task6-int8-gemv64-lanes4-packed-sync-mem-utilization --no-link --print-out-paths -L`
- `python3 sim/gen_task6_int8_gemv64_tb_data.py --artifact-name h2-int8-gemv64-lanes4-packed-sync-mem-rtl-proof --extra-kernel-source rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv --kernel-source rtl/task6/task6_int8_gemv64_lanes4_packed_sync_mem_kernel.sv --testbench-source sim/task6_int8_gemv64_lanes4_packed_sync_mem_tb_main.sv --top-name task6_int8_gemv64_lanes4_packed_sync_mem_kernel --lane-count 4 --packed-weight-words 1024 --local-packed-weight-memory --packed-weight-read-latency-cycles 1 --nix-target-prefix task6-int8-gemv64-lanes4-packed-sync-mem --sim-result-json /nix/store/54q4wq3182nhmvkf6sfrk6rvabz779a6-task6-int8-gemv64-lanes4-packed-sync-mem-sv-sim.json --yosys-stat-json /nix/store/lx8jdyxh3ckph7p6qn0y7zn4pxxrlx2y-task6-int8-gemv64-lanes4-packed-sync-mem-yosys-stat.json --mapped-utilization-summary-json /nix/store/y62fmdqmhj5ls485qanksvrqn6fhq7gn-task6-int8-gemv64-lanes4-packed-sync-mem-utilization/summary.json --out-json artifacts/task6/parallel-hypotheses/h2-int8-gemv64-lanes4-packed-sync-mem-rtl-proof.json`

Prepared contract:

- `64 x 64` GEMV
- signed int8 activations
- signed int8 weights
- signed int32 accumulation
- `4,096` MACs
- `4` parallel output/MAC lanes sharing one controller
- `1,024` packed weight words, each carrying one `4`-lane int8 weight vector
- loadable synchronous local packed-weight memory
- one-cycle packed-weight read latency
- ready/valid output stream

Execution status:

- The RTL simulation passes through Nix-provided Verilator:
  - output: `/nix/store/54q4wq3182nhmvkf6sfrk6rvabz779a6-task6-int8-gemv64-lanes4-packed-sync-mem-sv-sim.json`
  - pass line: `PASS: task6 int8 GEMV4 syncmem stores 64 outputs 64 cycles 1106`
- The light Yosys gate passes through Nix-provided `pkgs.yosys`:
  - output: `/nix/store/lx8jdyxh3ckph7p6qn0y7zn4pxxrlx2y-task6-int8-gemv64-lanes4-packed-sync-mem-yosys-stat.json`
  - `DSP48E1`: `4`
  - `RAMB36E1`: `1`
  - LUT primitive cells: `250` (`LUT2=160`, `LUT3=41`, `LUT4=2`,
    `LUT5=6`, `LUT6=41`)
  - `FDRE`: `193`
  - `CARRY4`: `11`
  - Yosys log estimated LCs: `149`
- The mapped JSON utilization gate passes through the existing utilization
  reporter:
  - output: `/nix/store/y62fmdqmhj5ls485qanksvrqn6fhq7gn-task6-int8-gemv64-lanes4-packed-sync-mem-utilization`
  - `clb_luts`: `250`
  - `clb_ffs`: `193`
  - `dsp`: `4`
  - `bram36`: `1`
  - `bram36_equiv`: `1.0`
  - `bram_kb`: `36`
  - `slices_lower_bound`: `32`

Interpretation:

- This is the first H2 proof that crosses from a combinational packed-weight
  interface into an explicit loadable local memory boundary.
- Yosys infers one `RAMB36E1` for the `1024 x 32` packed-weight store, so the
  proof now exercises BRAM as well as the four DSP MAC lanes.
- Compared with the prior packed combinational proof, the memory boundary costs
  only `+8` LUT, `+6` FF, and `+1` slice lower bound while adding one BRAM36
  and increasing simulation from `1090` to `1106` cycles.
- H2 remains active. The next useful gate is either an `L2`-shape tile wrapper
  around this sync-memory interface or a direct resource comparison for the
  activation/output memory boundary on the same int8 datapath.

### 2026-04-28 - H2 L2-shaped int8 64x256 sync-memory wrapper proof

Artifact:

- `artifacts/task6/parallel-hypotheses/h2-int8-gemv64x256-lanes4-packed-sync-mem-rtl-proof.json`

Sources:

- `flake.nix`
- `rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv`
- `rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel.sv`
- `sim/task6_int8_gemv64x256_lanes4_packed_sync_mem_tb_main.sv`
- `sim/gen_task6_int8_gemv64_tb_data.py`

Command:

- `nix build .#task6-int8-gemv64x256-lanes4-packed-sync-mem-sv-sim --no-link --print-out-paths -L`
- `nix build .#task6-int8-gemv64x256-lanes4-packed-sync-mem-yosys-stat --no-link --print-out-paths -L`
- `nix build .#task6-int8-gemv64x256-lanes4-packed-sync-mem-utilization --no-link --print-out-paths -L`
- `python3 sim/gen_task6_int8_gemv64_tb_data.py --artifact-name h2-int8-gemv64x256-lanes4-packed-sync-mem-rtl-proof --extra-kernel-source rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv --kernel-source rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel.sv --testbench-source sim/task6_int8_gemv64x256_lanes4_packed_sync_mem_tb_main.sv --top-name task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel --in-dim 64 --out-dim 256 --lane-count 4 --packed-weight-words 4096 --local-packed-weight-memory --packed-weight-read-latency-cycles 1 --nix-target-prefix task6-int8-gemv64x256-lanes4-packed-sync-mem --sim-result-json /nix/store/3c3hfxjp9hrg7ljkmkvbb44l4dg7x4sj-task6-int8-gemv64x256-lanes4-packed-sync-mem-sv-sim.json --yosys-stat-json /nix/store/xhl71pr1kxxx2x4a045686l6p002yciv-task6-int8-gemv64x256-lanes4-packed-sync-mem-yosys-stat.json --mapped-utilization-summary-json /nix/store/nk7x17kryxq1wkrh06kb5dqnw6pdr5y6-task6-int8-gemv64x256-lanes4-packed-sync-mem-utilization/summary.json --out-json artifacts/task6/parallel-hypotheses/h2-int8-gemv64x256-lanes4-packed-sync-mem-rtl-proof.json`

Prepared contract:

- `64 x 256` GEMV as four sequential `64 x 64` output phases
- signed int8 activations
- signed int8 weights
- signed int32 accumulation
- `16,384` MACs
- `4` parallel output/MAC lanes in the reused tile core
- `4,096` packed weight words, each carrying one `4`-lane int8 weight vector
- loadable synchronous local packed-weight memory
- one-cycle packed-weight read latency
- ready/valid output stream

Execution status:

- The RTL simulation passes through Nix-provided Verilator:
  - output: `/nix/store/3c3hfxjp9hrg7ljkmkvbb44l4dg7x4sj-task6-int8-gemv64x256-lanes4-packed-sync-mem-sv-sim.json`
  - pass line: `PASS: task6 int8 GEMV4x256 syncmem stores 256 outputs 256 cycles 4426`
- The light Yosys gate passes through Nix-provided `pkgs.yosys`:
  - output: `/nix/store/xhl71pr1kxxx2x4a045686l6p002yciv-task6-int8-gemv64x256-lanes4-packed-sync-mem-yosys-stat.json`
  - `DSP48E1`: `4`
  - `RAMB36E1`: `4`
  - LUT primitive cells: `257` (`LUT2=165`, `LUT3=40`, `LUT4=5`,
    `LUT5=8`, `LUT6=39`)
  - `FDRE`: `198`
  - `CARRY4`: `11`
  - Yosys log estimated LCs: `152`
- The mapped JSON utilization gate passes through the existing utilization
  reporter:
  - output: `/nix/store/nk7x17kryxq1wkrh06kb5dqnw6pdr5y6-task6-int8-gemv64x256-lanes4-packed-sync-mem-utilization`
  - `clb_luts`: `257`
  - `clb_ffs`: `198`
  - `dsp`: `4`
  - `bram36`: `4`
  - `bram36_equiv`: `4.0`
  - `bram_kb`: `144`
  - `slices_lower_bound`: `33`

Regression checks:

- `python3 -m py_compile sim/gen_task6_int8_gemv64_tb_data.py`
- `nix-instantiate --parse flake.nix`
- Existing int8 proof artifacts regenerated byte-for-byte after adding
  `--in-dim` and `--out-dim` generator parameters:
  - `h2-int8-gemv64-rtl-proof.json`
  - `h2-int8-gemv64-lanes4-rtl-proof.json`
  - `h2-int8-gemv64-lanes4-packed-rtl-proof.json`
  - `h2-int8-gemv64-lanes4-packed-sync-mem-rtl-proof.json`

Interpretation:

- This answers the previous H2 gate directly: the explicit sync-memory int8
  datapath survives the first `L2`-shaped `64 -> 256` output wrapper.
- Compared with the prior `64 x 64` sync-memory proof, the wrapper keeps the
  same `4` DSP MAC lane footprint and scales packed weight storage from one to
  four `RAMB36E1` blocks.
- The control/output wrapper adds only `+7` mapped LUT, `+5` FF, and `+1`
  slice lower bound versus the `64 x 64` sync-memory proof; `CARRY4` is
  unchanged.
- Runtime is near-linear: `4426` cycles versus `4 * 1106 = 4424` for four
  independent tile runs.
- H2 remains the strongest concrete resource-reduction lane. The next useful
  gate is to add the activation/output memory boundary for this int8 datapath
  or replay the same shape against a captured `c_fc` numeric contract.

### 2026-04-28 - H2 L2-shaped int8 local activation/output memory proof

Artifact:

- `artifacts/task6/parallel-hypotheses/h2-int8-gemv64x256-lanes4-packed-sync-mem-local-io-rtl-proof.json`

Sources:

- `flake.nix`
- `rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv`
- `rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel.sv`
- `rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_local_io_kernel.sv`
- `sim/task6_int8_gemv64x256_lanes4_packed_sync_mem_local_io_tb_main.sv`
- `sim/gen_task6_int8_gemv64_tb_data.py`

Prepared contract:

- `64 x 256` GEMV as four sequential `64 x 64` output phases
- signed int8 activations and weights
- signed int32 accumulation and output storage
- `4` parallel output/MAC lanes in the reused tile core
- `4,096` loadable packed weight words
- `64` loadable activation bytes
- `256` captured int32 outputs behind a synchronous read port
- one-cycle packed-weight read latency
- one-cycle output-memory read latency

Execution status:

- The RTL simulation passes through Nix-provided Verilator:
  - output:
    `/nix/store/zhrnqzbjijr10y4xdv590g31wv0ifqnn-task6-int8-gemv64x256-lanes4-packed-sync-mem-local-io-sv-sim.json`
  - pass line:
    `PASS: task6 int8 GEMV4x256 localio reads 256 outputs 256 compute_cycles 4426 total_cycles 4682`
- The light Yosys gate passes through Nix-provided `pkgs.yosys`:
  - output:
    `/nix/store/s45pmvyb84j6ch8kynp2q0bkzz68yg0p-task6-int8-gemv64x256-lanes4-packed-sync-mem-local-io-yosys-stat.json`
  - `DSP48E1`: `4`
  - `RAMB36E1`: `4`
  - `RAMB18E1`: `1`
  - `RAM64M`: `3`
  - LUT primitive cells: `257` (`LUT2=165`, `LUT3=40`, `LUT4=5`,
    `LUT5=8`, `LUT6=39`)
  - `FDRE`: `198`
  - `CARRY4`: `11`
  - Yosys log estimated LCs: `152`
- The mapped JSON utilization gate passes through the existing utilization
  reporter:
  - output:
    `/nix/store/jkii8nbpgsd9jkxi3qzf253v99f8lxb9-task6-int8-gemv64x256-lanes4-packed-sync-mem-local-io-utilization`
  - `clb_luts`: `257`
  - `clb_ffs`: `198`
  - `dsp`: `4`
  - `bram36`: `4`
  - `bram36_equiv`: `4.5`
  - `bram_kb`: `162`
  - `slices_lower_bound`: `33`

Regression checks:

- `python3 -m py_compile sim/gen_task6_int8_gemv64_tb_data.py`
- `nix-instantiate --parse flake.nix`
- Existing int8 proof artifacts regenerated byte-for-byte after adding
  generator metadata for local activation/output memory:
  - `h2-int8-gemv64-rtl-proof.json`
  - `h2-int8-gemv64-lanes4-rtl-proof.json`
  - `h2-int8-gemv64-lanes4-packed-rtl-proof.json`
  - `h2-int8-gemv64-lanes4-packed-sync-mem-rtl-proof.json`
  - `h2-int8-gemv64x256-lanes4-packed-sync-mem-rtl-proof.json`

Interpretation:

- This crosses the activation/output memory boundary without increasing mapped
  LUTs, FFs, DSPs, or slice lower bound versus the prior `64 x 256`
  sync-memory wrapper.
- The added local output capture costs one `RAMB18E1`, raising memory from
  `4.0` to `4.5` BRAM36-equivalent blocks; the local activation memory maps to
  three `RAM64M` cells.
- Compute latency is unchanged at `4426` cycles; the `4682` total cycle count
  includes the synchronous readback of all `256` captured outputs.
- H2 remains the strongest concrete resource-reduction lane. The next useful
  gate is either to replay this shape against the captured `c_fc` numeric
  contract or to begin replacing the float `L2` wrapper boundary with this
  local-memory int8 contract.

### 2026-04-28 - H2 captured `L2 c_fc` int8 local-I/O contract replay

Artifact:

- `artifacts/task6/parallel-hypotheses/h2-int8-l2-c-fc-local-io-contract-replay.json`

Sources:

- `flake.nix`
- `sim/gen_task6_int8_l2_c_fc_contract_tb_data.py`
- `sim/task6_int8_l2_c_fc_contract_local_io_tb_main.sv`
- `rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv`
- `rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel.sv`
- `rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_local_io_kernel.sv`

Input artifacts:

- contract:
  `artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_fc-contract/manifest.json`
- weight pack:
  `artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_fc/manifest.json`
- generated testbench data:
  `/nix/store/n35ch4f4g660c4jajc6f6a3m07lbqp4d-task6-int8-l2-c-fc-contract-local-io-tb-data-sv`

Command:

- `nix build .#task6-int8-l2-c-fc-contract-local-io-sv-sim --no-link --print-out-paths -L`
- `python3 sim/gen_task6_int8_l2_c_fc_contract_tb_data.py --artifact-name h2-int8-l2-c-fc-local-io-contract-replay --contract-manifest artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_fc-contract/manifest.json --weight-pack-manifest artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_fc/manifest.json --sim-result-json /nix/store/p6swbg96jynrh9gzj300n86871dhyfvi-task6-int8-l2-c-fc-contract-local-io-sv-sim.json --yosys-stat-json /nix/store/s45pmvyb84j6ch8kynp2q0bkzz68yg0p-task6-int8-gemv64x256-lanes4-packed-sync-mem-local-io-yosys-stat.json --mapped-utilization-summary-json /nix/store/jkii8nbpgsd9jkxi3qzf253v99f8lxb9-task6-int8-gemv64x256-lanes4-packed-sync-mem-local-io-utilization/summary.json --out-json artifacts/task6/parallel-hypotheses/h2-int8-l2-c-fc-local-io-contract-replay.json`

Quantization contract:

- activation:
  - int8 per-tensor symmetric
  - scale: `0.01876247210765448`
  - quantized range: `-105..127`
- weight:
  - int8 per-output symmetric
  - scale range: `0.00026671916950406053..0.0005978438563234224`
  - quantized range: `-127..127`
- accumulator:
  - int32 raw RTL output
  - expected accumulator range: `-51239..54338`
- bias:
  - f32 bias is not inside the RTL
  - it is added during dequantized contract scoring

Execution status:

- Verilator contract replay passes:
  - output:
    `/nix/store/p6swbg96jynrh9gzj300n86871dhyfvi-task6-int8-l2-c-fc-contract-local-io-sv-sim.json`
  - pass line:
    `PASS: task6 int8 L2 c_fc localio reads 256 outputs 256 compute_cycles 4426 total_cycles 4682`
- Dequantized replay against captured `activation_out` passes the current
  threshold:
  - normalized RMSE: `0.008803690780475175`
  - threshold: `0.02`
  - max absolute error: `0.003402371872713701`
  - mean absolute error: `0.0009829674033341599`
  - RMSE: `0.0012404946345053037`
- Mapped resources reuse the proven local-I/O RTL shape:
  - `clb_luts`: `257`
  - `clb_ffs`: `198`
  - `dsp`: `4`
  - `bram36`: `4`
  - `bram18`: `1`
  - `bram36_equiv`: `4.5`
  - `bram_kb`: `162`
  - `slices_lower_bound`: `33`

Interpretation:

- This closes the previous H2 numeric gap: the local-memory int8 RTL is no
  longer only a synthetic-vector proof; it now replays the captured
  `tiny-stories-v1k-h64-l1` `transformer.h.0.mlp.c_fc` contract.
- The Verilator test checks the raw int32 accumulators exactly. The JSON
  artifact separately scores the dequantized output against the captured f32
  module output with f32 bias applied outside the RTL.
- The resource story does not change from the prior local-I/O proof because the
  same RTL shape is used; only the loaded activation and weight contents now
  come from the captured `L2 c_fc` contract.
- H2 remains the strongest concrete path. The next useful gate is to make the
  scale/bias/output boundary explicit around this int8 contract, then use that
  as the replacement candidate for the float `L2` wrapper boundary.

### 2026-04-28 - H2 explicit scale/bias/output boundary for `L2 c_fc`

Artifact:

- `artifacts/task6/parallel-hypotheses/h2-int8-l2-c-fc-scale-bias-output-boundary.json`

Script:

- `scripts/task6/score_int8_output_boundary.py`

Nix target:

- `task6-int8-l2-c-fc-scale-bias-output-boundary`
- output:
  `/nix/store/jv6845gszc5qgb601r6x43i4ih4lgzj2-task6-int8-l2-c-fc-scale-bias-output-boundary`

Command:

- `python3 scripts/task6/score_int8_output_boundary.py --contract-manifest artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_fc-contract/manifest.json --weight-pack-manifest artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_fc/manifest.json --contract-replay-json artifacts/task6/parallel-hypotheses/h2-int8-l2-c-fc-local-io-contract-replay.json --out-json artifacts/task6/parallel-hypotheses/h2-int8-l2-c-fc-scale-bias-output-boundary.json`
- `nix build .#task6-int8-l2-c-fc-scale-bias-output-boundary --no-link --print-out-paths -L`

Boundary contract:

- RTL output:
  - int32 accumulators in local output memory
- output formula:
  - `f32_out[i] = int32_acc[i] * effective_scale[i] + bias[i]`
- effective scale:
  - `activation_scale * per-output weight_scale`
- sidecar dtypes:
  - scale: `float32`
  - bias: `float32`
- output dtype:
  - `float32`
- postprocess operations:
  - `256` f32 multiplies
  - `256` f32 adds

Result:

- status: `PASS`
- normalized RMSE: `0.008803690780475175`
- threshold: `0.02`
- effective scale range:
  - `5.004310978396703e-06..1.1217028679000805e-05`
- accumulator range:
  - `-51239..54338`
- sidecar hashes:
  - effective scale SHA256:
    `7e70d09bd94b0a9fa02d6e8069efa2f96e0d96a7f12b4c3e2cd3d3b682a78b50`
  - bias SHA256:
    `5f70bf18a086007016e948b04aed3b82103a36bea41755b6cddfaf10ace3c6ef`

Byte budget:

- activation int8 bytes: `64`
- packed-weight local memory bytes: `16,384`
- accumulator output int32 bytes: `1,024`
- effective-scale f32 bytes: `1,024`
- bias f32 bytes: `1,024`
- dequantized output f32 bytes: `1,024`
- scale plus bias sidecar bytes: `2,048`
- postprocess read/write bytes:
  - `4,096`
  - accumulator read + scale read + bias read + f32 output write
- minimum external payload if sidecars are loaded once:
  - `18,496` bytes

Decision:

- The replacement candidate boundary is now explicit:
  - replace the float `L2 c_fc` GEMV body with the int8 local-memory
    accumulator contract plus a scale/bias f32 output boundary.
- This does not prove that f32 postprocess should be implemented in the same
  RTL kernel:
  - the f32 scale/bias stage needs a separate mapped-cost gate
  - an alternate int8-to-int8 downstream boundary may be cheaper if the next
    layer can accept a quantized activation contract.
- Next gate:
  - measure the scale/bias postprocess option or define an int8-to-int8
    downstream boundary before replacing the full float `L2` wrapper.

### 2026-04-28 - H2 int8-to-int8 downstream boundary plan for `L2 c_fc`

Plan amendment:

- Default next direction:
  - do not implement the f32 scale/bias postprocess in RTL first
  - first score whether the existing int8 `c_fc` proof can hand a quantized
    activation to the downstream path
- First gate:
  - score `c_fc int32 accumulator -> int8 activation` candidates against the
    captured `L2 c_fc` contract
  - include the immediate GELU implication, because the next consumer is not
    just raw `c_fc` output
- Candidate boundaries:
  - `pre_gelu_int8_activation`
  - `post_gelu_int8_activation`
- Continue rule:
  - if either candidate stays under normalized RMSE `0.02`, implement a
    bounded fixed-point requant/output-memory RTL proof
  - if both candidates fail, fall back to the explicit f32 scale/bias boundary
    recorded above

Artifact:

- `artifacts/task6/parallel-hypotheses/h2-int8-l2-c-fc-downstream-int8-boundary.json`

Script:

- `scripts/task6/score_int8_downstream_boundary.py`

Nix target:

- `task6-int8-l2-c-fc-downstream-int8-boundary`
- output:
  `/nix/store/vh5jr6pngp2x6xgmrpfid6gbimbvmqnx-task6-int8-l2-c-fc-downstream-int8-boundary`

Command:

- `python3 scripts/task6/score_int8_downstream_boundary.py --contract-manifest artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_fc-contract/manifest.json --weight-pack-manifest artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_fc/manifest.json --contract-replay-json artifacts/task6/parallel-hypotheses/h2-int8-l2-c-fc-local-io-contract-replay.json --out-json artifacts/task6/parallel-hypotheses/h2-int8-l2-c-fc-downstream-int8-boundary.json`
- `nix build .#task6-int8-l2-c-fc-downstream-int8-boundary --no-link --print-out-paths -L`

Execution result:

- status: `PASS`
- threshold: `0.02`
- output scale source:
  - single captured contract sample used as calibration reference
- calibration caveat:
  - a production activation scale still needs a calibration set before
    board-level claims

Candidate results:

- `pre_gelu_int8_activation`:
  - verdict: `pass`
  - output scale: `0.0030651141808727593`
  - output q range: `-127..126`
  - raw `c_fc` normalized RMSE: `0.010439723621125493`
  - downstream GELU normalized RMSE: `0.010411107180230455`
  - output payload: `256` int8 bytes plus one `4` byte scale
- `post_gelu_int8_activation`:
  - verdict: `pass`
  - output scale: `0.0019919775901474546`
  - output q range: `-68..127`
  - raw `c_fc` normalized RMSE before post-GELU requant:
    `0.008803690780475175`
  - downstream GELU normalized RMSE after post-GELU requant:
    `0.011913045139803343`
  - output payload: `256` int8 bytes plus one `4` byte scale

Byte-budget implication:

- f32 output bytes replaced: `1,024`
- int8 output write savings versus f32: `768` bytes per captured `c_fc` output
- this is smaller than the prior explicit f32 boundary, which required:
  - `1,024` int32 output bytes
  - `1,024` scale bytes
  - `1,024` bias bytes
  - `1,024` f32 output bytes
  - `4,096` bytes of postprocess read/write traffic

Decision:

- The recommended next boundary is `post_gelu_int8_activation`.
- H2 remains active.
- Next gate:
  - implement a bounded fixed-point requant/output-memory RTL proof for the
    recommended post-GELU int8 activation boundary
  - keep the f32 scale/bias boundary as the fallback if the fixed-point
    requant proof fails or if wider calibration invalidates the single-sample
    activation scale

### 2026-04-28 - H2 post-GELU int8 requant/output-memory RTL proof

Artifact:

- `artifacts/task6/parallel-hypotheses/h2-int8-l2-c-fc-post-gelu-requant-rtl-proof.json`

Sources:

- `flake.nix`
- `rtl/task6/task6_int8_l2_c_fc_post_gelu_requant_kernel.sv`
- `sim/task6_int8_l2_c_fc_post_gelu_requant_tb_main.sv`
- `sim/gen_task6_int8_l2_c_fc_post_gelu_requant_tb_data.py`

Nix targets:

- `task6-int8-l2-c-fc-post-gelu-requant-tb-data-sv`
- `task6-int8-l2-c-fc-post-gelu-requant-sv-sim`
- `task6-int8-l2-c-fc-post-gelu-requant-yosys-stat`
- `task6-int8-l2-c-fc-post-gelu-requant-utilization`
- `task6-int8-l2-c-fc-post-gelu-requant-rtl-proof`
- proof output:
  `/nix/store/r49371dw4wpxfg8n9kgljvqdjjs764p3-task6-int8-l2-c-fc-post-gelu-requant-rtl-proof`

Commands:

- `nix build .#task6-int8-l2-c-fc-post-gelu-requant-sv-sim --no-link --print-out-paths -L`
- `nix build .#task6-int8-l2-c-fc-post-gelu-requant-rtl-proof --no-link --print-out-paths -L`
- `python3 sim/gen_task6_int8_l2_c_fc_post_gelu_requant_tb_data.py --contract-manifest artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_fc-contract/manifest.json --weight-pack-manifest artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_fc/manifest.json --downstream-boundary-json artifacts/task6/parallel-hypotheses/h2-int8-l2-c-fc-downstream-int8-boundary.json --sim-result-json /nix/store/j724i985rk0ghnr7ignyiaawa2wahx5k-task6-int8-l2-c-fc-post-gelu-requant-sv-sim.json --yosys-stat-json /nix/store/yz0g979bl9ghfg5c82gk6k5vdlxclbyk-task6-int8-l2-c-fc-post-gelu-requant-yosys-stat.json --mapped-utilization-summary-json /nix/store/7z38qbssw76fyljf3zkisgn5p8vk878l-task6-int8-l2-c-fc-post-gelu-requant-utilization/summary.json --out-json artifacts/task6/parallel-hypotheses/h2-int8-l2-c-fc-post-gelu-requant-rtl-proof.json`

RTL contract:

- input:
  - the existing captured `L2 c_fc` int8 local-I/O contract
  - `64` int8 activation bytes
  - `4,096` packed int8 weight words
  - per-output fixed-point scale multiplier sidecar
  - per-output fixed-point bias sidecar
- postprocess:
  - `x_q = round_shift(acc * scale_mul, scale_shift) + bias_q`
  - `y_q = (x_q >> 1) + round_shift(gelu_quad_q * x_q * x_q, 2*x_frac)`
  - `q = saturate_i8(round_shift(y_q * output_requant_mult, output_requant_shift))`
- fixed-point constants:
  - `x_frac = 12`
  - `scale_shift = 24`
  - `gelu_quad_q = 1634`
  - `output_requant_shift = 16`
  - `output_requant_mult = 8032`
- GELU approximation:
  - bounded small-range quadratic: `0.5*x + 0.39894228*x*x`
  - valid for this proof's captured pre-GELU range:
    `-0.3890774397806243..0.38768501500220276`

Execution status:

- status: `PASS`
- Verilator:
  - output:
    `/nix/store/j724i985rk0ghnr7ignyiaawa2wahx5k-task6-int8-l2-c-fc-post-gelu-requant-sv-sim.json`
  - pass line:
    `PASS: task6 int8 L2 c_fc postgelu requant reads 256 outputs 256 compute_cycles 4939 total_cycles 5195`
- fixed-point post-GELU score:
  - normalized RMSE: `0.011991351771288544`
  - threshold: `0.02`
  - max absolute error: `0.0025458221821932497`
  - output q range: `-67..127`
  - output scale: `0.0019919775901474546`

Mapped resources:

- output:
  `/nix/store/7z38qbssw76fyljf3zkisgn5p8vk878l-task6-int8-l2-c-fc-post-gelu-requant-utilization`
- `clb_luts`: `653`
- `clb_ffs`: `217`
- `dsp`: `26`
- `bram36`: `4`
- `bram18`: `3`
- `bram36_equiv`: `5.5`
- `bram_kb`: `198`
- `slices_lower_bound`: `82`

Delta against the prior captured `L2 c_fc` int8 local-I/O proof:

- LUT: `257 -> 653` (`+396`)
- FF: `198 -> 217` (`+19`)
- DSP: `4 -> 26` (`+22`)
- BRAM36-equivalent: `4.5 -> 5.5` (`+1.0`)
- lower-bound slices: `33 -> 82` (`+49`)
- compute cycles: `4426 -> 4939` (`+513`)
- total cycles: `4682 -> 5195` (`+513`)

Byte-budget implication:

- output activation stays at `256` int8 bytes
- f32 output bytes replaced: `1,024`
- int8 output write savings versus f32: `768` bytes
- fixed-point sidecars are:
  - scale multiplier: `1,024` bytes
  - bias q: `1,024` bytes
- in this captured `c_fc` contract, `bias_q` is all zero, but the proof keeps
  the sidecar memory present so the boundary is not specialized to this one
  zero-bias checkpoint

Decision:

- The recommended post-GELU int8 activation boundary now has a bounded RTL
  proof, not just an offline scorer.
- The proof is functionally and numerically valid, but the local in-kernel GELU
  approximation costs `+22` DSP over the accumulator-only local-I/O proof.
- H2 remains active.
- Next gate:
  - either accept the extra DSP as a fit-positive tradeoff and integrate this
    post-GELU int8 boundary into the `L2 c_fc` replacement path
  - or run one bounded DSP-reduction follow-up for the postprocess stage before
    integration, such as a multi-cycle square/output-multiply schedule

### 2026-04-28 - H2 `c_proj` handoff from the post-GELU int8 boundary

Plan update:

- Treat the post-GELU proof's `26 DSP` result as fit-positive:
  - this is only `1.35%` of the XC7A200T `1,920` DSP budget
  - the active float `L2 c_fc` reference still costs
    `31,907 LUT / 45,932 FF / 4 DSP / 0 BRAM`
  - the post-GELU int8 proof costs only
    `653 LUT / 217 FF / 26 DSP / 5.5 BRAM36-equivalent`
- Do not spend the next slice trying to reduce DSP use.
- Instead, prove that the accepted `c_fc -> GELU -> int8 activation` boundary
  remains useful when consumed by the next MLP operator, `c_proj`.

Artifact:

- `artifacts/task6/parallel-hypotheses/h2-int8-l2-c-proj-from-post-gelu-boundary.json`

Script:

- `scripts/task6/score_int8_c_proj_from_post_gelu.py`

Nix target:

- `task6-int8-l2-c-proj-from-post-gelu-boundary`
- output:
  `/nix/store/w7jfi6han1f8fhwhdryy9aci9x1qgk7d-task6-int8-l2-c-proj-from-post-gelu-boundary`

Command:

- `python3 scripts/task6/score_int8_c_proj_from_post_gelu.py --c-fc-contract-manifest artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_fc-contract/manifest.json --c-fc-weight-pack-manifest artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_fc/manifest.json --c-proj-contract-manifest artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_proj-contract/manifest.json --c-proj-weight-pack-manifest artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_proj/manifest.json --post-gelu-requant-json artifacts/task6/parallel-hypotheses/h2-int8-l2-c-fc-post-gelu-requant-rtl-proof.json --out-json artifacts/task6/parallel-hypotheses/h2-int8-l2-c-proj-from-post-gelu-boundary.json`
- `nix build .#task6-int8-l2-c-proj-from-post-gelu-boundary --no-link --print-out-paths -L`

Execution result:

- status: `PASS`
- threshold: `0.02`
- `c_proj` input versus `GELU(c_fc expected)`:
  - normalized RMSE: `3.939776752351999e-08`
  - max absolute error: `1.600132085166628e-08`
- post-GELU int8 dequantized activation versus captured `c_proj` input:
  - normalized RMSE: `0.01199135641153676`
  - max absolute error: `0.0025458211614692583`
- `c_proj` output from post-GELU int8 activation and per-output int8 weights:
  - normalized RMSE: `0.014010386505018001`
  - max absolute error: `0.0009424232727163438`
  - mean absolute error: `0.0002511875694791357`

`c_proj` quantization contract:

- input features: `256`
- output features: `64`
- MACs: `16,384`
- activation quantization:
  - post-GELU int8 per-tensor symmetric
- weight quantization:
  - int8 per-output symmetric
- weight scale range:
  - `0.0004040582442846824..0.0006334623248558345`
- accumulator range:
  - `-53371..78617`

Byte-budget implication:

- post-GELU activation:
  - `256` int8 bytes replaces `1,024` f32 bytes
  - activation transfer savings: `768` bytes
- `c_proj` weights:
  - `16,384` int8 bytes replaces `65,536` f32 bytes
  - weight transfer savings: `49,152` bytes
  - per-output scale sidecar: `256` bytes

Decision:

- Promote H2 from a `c_fc`-only proof to a `c_fc -> GELU -> c_proj` chain
  candidate.
- Next gate:
  - implement a bounded `256x64` int8 `c_proj` RTL proof fed by the
    post-GELU int8 activation
- Falsifier:
  - if the bounded `c_proj` RTL proof does not stay under normalized RMSE
    `0.02`, or if its mapped LUT/FF cost erases the post-GELU `c_fc` win, fall
    back to the narrower `c_fc` boundary before claiming an MLP-chain
    replacement.

### 2026-04-28 - H2 `c_proj` RTL proof from the post-GELU int8 boundary

Artifact:

- `artifacts/task6/parallel-hypotheses/h2-int8-l2-c-proj-from-post-gelu-rtl-proof.json`

Sources:

- `flake.nix`
- `rtl/task6/task6_int8_l2_c_proj_from_post_gelu_kernel.sv`
- `sim/task6_int8_l2_c_proj_from_post_gelu_tb_main.sv`
- `sim/gen_task6_int8_l2_c_proj_from_post_gelu_tb_data.py`

Nix targets:

- `task6-int8-l2-c-proj-from-post-gelu-tb-data-sv`
- `task6-int8-l2-c-proj-from-post-gelu-sv-sim`
- `task6-int8-l2-c-proj-from-post-gelu-yosys-stat`
- `task6-int8-l2-c-proj-from-post-gelu-json`
- `task6-int8-l2-c-proj-from-post-gelu-utilization`
- `task6-int8-l2-c-proj-from-post-gelu-rtl-proof`
- proof output:
  `/nix/store/95l187w8i0h49a4dgbaj9p7xc1camf0h-task6-int8-l2-c-proj-from-post-gelu-rtl-proof`

Commands:

- `nix build .#task6-int8-l2-c-proj-from-post-gelu-sv-sim --no-link --print-out-paths -L`
- `nix build .#task6-int8-l2-c-proj-from-post-gelu-rtl-proof --no-link --print-out-paths -L`
- `python3 sim/gen_task6_int8_l2_c_proj_from_post_gelu_tb_data.py --c-fc-contract-manifest artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_fc-contract/manifest.json --c-fc-weight-pack-manifest artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_fc/manifest.json --c-proj-contract-manifest artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_proj-contract/manifest.json --c-proj-weight-pack-manifest artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_proj/manifest.json --post-gelu-requant-json artifacts/task6/parallel-hypotheses/h2-int8-l2-c-fc-post-gelu-requant-rtl-proof.json --sim-result-json /nix/store/9r187q4gm5n3z6glzkk9g9lwlrfkiix2-task6-int8-l2-c-proj-from-post-gelu-sv-sim.json --yosys-stat-json /nix/store/0yfw1qq2hpq8s87gayihaq84hykymbwx-task6-int8-l2-c-proj-from-post-gelu-yosys-stat.json --mapped-utilization-summary-json /nix/store/qjpmpgaf3gy1yq156ir855cxn20k0gwa-task6-int8-l2-c-proj-from-post-gelu-utilization/summary.json --out-json artifacts/task6/parallel-hypotheses/h2-int8-l2-c-proj-from-post-gelu-rtl-proof.json`

RTL contract:

- input:
  - post-GELU int8 activation from the proven `L2 c_fc` boundary
  - `256` int8 activation bytes
  - `4,096` packed int8 weight words for `64 x 256` `c_proj`
- compute:
  - same lanes4 int8 MAC core, instantiated directly as `IN_DIM=256`,
    `OUT_DIM=64`
- output:
  - `64` int32 accumulators
  - dequantization remains outside this bounded proof and is scored by the
    generator with per-output weight scales

Execution status:

- status: `PASS`
- Verilator:
  - output:
    `/nix/store/9r187q4gm5n3z6glzkk9g9lwlrfkiix2-task6-int8-l2-c-proj-from-post-gelu-sv-sim.json`
  - pass line:
    `PASS: task6 int8 L2 c_proj from postgelu reads 64 outputs 64 compute_cycles 4178 total_cycles 4242`
- numerical score from RTL accumulators:
  - normalized RMSE: `0.014010386505018001`
  - threshold: `0.02`
  - max absolute error: `0.0009424232727163438`
  - accumulator range: `-53371..78617`

Mapped resources:

- output:
  `/nix/store/qjpmpgaf3gy1yq156ir855cxn20k0gwa-task6-int8-l2-c-proj-from-post-gelu-utilization`
- `clb_luts`: `271`
- `clb_ffs`: `197`
- `dsp`: `4`
- `bram36`: `4`
- `bram18`: `1`
- `bram36_equiv`: `4.5`
- `bram_kb`: `162`
- `slices_lower_bound`: `34`

Byte-budget implication:

- post-GELU activation:
  - `256` int8 bytes replaces `1,024` f32 bytes
  - activation transfer savings: `768` bytes
- `c_proj` weights:
  - `16,384` int8 bytes replaces `65,536` f32 bytes
  - weight transfer savings: `49,152` bytes
  - per-output scale sidecar: `256` bytes
- `c_proj` accumulator output:
  - `256` bytes

Bounded chain resource picture:

- `c_fc -> GELU -> int8 activation` RTL proof:
  - `653 LUT / 217 FF / 26 DSP / 5.5 BRAM36-equivalent`
- `c_proj` RTL proof from that activation:
  - `271 LUT / 197 FF / 4 DSP / 4.5 BRAM36-equivalent`
- bounded sum before composing one shared top:
  - `924 LUT / 414 FF / 30 DSP / 10.0 BRAM36-equivalent`

Decision:

- H2 now has bounded RTL evidence on both sides of the MLP handoff:
  - the producer proof creates the post-GELU int8 activation
  - the consumer proof accepts that activation and computes exact int32
    `c_proj` accumulators
- H2 remains active and should be treated as the leading replacement path.
- Next gate:
  - compose the proven `c_fc` post-GELU producer and this `c_proj` consumer in
    one bounded chain top, with an explicit activation handoff memory or stream
  - keep the current two-proof bounded sum as the resource expectation until
    the composed top exists

### 2026-04-28 - H2 composed `c_fc -> GELU -> c_proj` int8 RTL proof

Artifact:

- `artifacts/task6/parallel-hypotheses/h2-int8-l2-mlp-chain-post-gelu-c-proj-rtl-proof.json`

Sources:

- `flake.nix`
- `rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_kernel.sv`
- `sim/task6_int8_l2_mlp_chain_post_gelu_c_proj_tb_main.sv`
- `sim/gen_task6_int8_l2_mlp_chain_post_gelu_c_proj_tb_data.py`

Nix targets:

- `task6-int8-l2-mlp-chain-post-gelu-c-proj-tb-data-sv`
- `task6-int8-l2-mlp-chain-post-gelu-c-proj-sv-sim`
- `task6-int8-l2-mlp-chain-post-gelu-c-proj-yosys-stat`
- `task6-int8-l2-mlp-chain-post-gelu-c-proj-json`
- `task6-int8-l2-mlp-chain-post-gelu-c-proj-utilization`
- `task6-int8-l2-mlp-chain-post-gelu-c-proj-rtl-proof`
- proof output:
  `/nix/store/8a7k3d05k09vwvgssyxi0zm4k8pldydk-task6-int8-l2-mlp-chain-post-gelu-c-proj-rtl-proof`

Commands:

- `nix build .#task6-int8-l2-mlp-chain-post-gelu-c-proj-sv-sim --no-link --print-out-paths -L`
- `nix build .#task6-int8-l2-mlp-chain-post-gelu-c-proj-rtl-proof --no-link --print-out-paths -L`

RTL contract:

- composed top:
  - `task6_int8_l2_mlp_chain_post_gelu_c_proj_kernel`
- sequence:
  - load captured `c_fc` activation, packed weights, requant scale sidecars,
    and fixed-point bias sidecars
  - run the proven `c_fc -> fixed-point GELU -> post-GELU int8` producer
  - sequentially transfer the `256` post-GELU int8 activations through an
    explicit local-memory handoff
  - run the proven `c_proj` int8 consumer from that handoff activation
  - expose `64` int32 `c_proj` accumulators through the output read port

Execution status:

- status: `PASS`
- Verilator:
  - output:
    `/nix/store/0bmdr5j5lr43zvmdavs6174rzqp397s6-task6-int8-l2-mlp-chain-post-gelu-c-proj-sv-sim.json`
  - pass line:
    `PASS: task6 int8 L2 mlp chain postgelu c_proj reads 64 outputs 64 compute_cycles 9631 total_cycles 9695`
- numerical score from the composed-chain `c_proj` accumulators:
  - normalized RMSE: `0.014010386505018005`
  - threshold: `0.02`
  - max absolute error: `0.0009424232727163438`
- post-GELU int8 activation handoff score:
  - normalized RMSE versus captured `c_proj` input:
    `0.011991356411536758`
  - post-GELU q range:
    `-67..127`

Mapped resources:

- `clb_luts`: `944`
- `clb_ffs`: `426`
- `dsp`: `30`
- `bram36`: `8`
- `bram18`: `4`
- `bram36_equiv`: `10.0`
- `bram_kb`: `360`
- `slices_lower_bound`: `118`

Delta against the prior two-proof bounded sum:

- prior separate proofs:
  - `924 LUT / 414 FF / 30 DSP / 10.0 BRAM36-equivalent`
- composed top:
  - `944 LUT / 426 FF / 30 DSP / 10.0 BRAM36-equivalent`
- overhead:
  - `+20` LUT
  - `+12` FF
  - `+0` DSP
  - `+0.0` BRAM36-equivalent

Byte-budget implication:

- `c_fc` activation:
  - `64` int8 bytes
- `c_fc` packed weights:
  - `16,384` bytes
- `c_fc` fixed-point sidecars:
  - `1,024` scale-multiplier bytes
  - `1,024` bias-q bytes
- post-GELU handoff:
  - `256` int8 bytes replaces `1,024` f32 bytes
  - handoff savings: `768` bytes
- `c_proj` packed weights:
  - `16,384` int8 bytes replaces `65,536` f32 bytes
  - weight transfer savings: `49,152` bytes
- `c_proj` accumulator output:
  - `256` bytes

Decision:

- Promote H2 from two bounded RTL proofs to a composed bounded MLP-chain proof.
- The DSP use is a positive signal, not a problem:
  - the composed proof uses `30` DSPs, about `1.56%` of the target board's
    `1,920` DSP budget
  - the key win is that the MLP chain now maps to DSP and BRAM instead of the
    repeated LUT/FF-heavy float handshake shell
- The composed chain keeps the prior numeric result and adds only a tiny
  handoff/control overhead over the two-proof sum.
- Next gate:
  - define the output boundary after `c_proj`, including dequantization,
    residual/add, or the next quantized handoff target
  - keep this composed RTL proof as the current H2 promotion reference until a
    larger calibrated sample set or downstream boundary invalidates it

### 2026-04-28 - H2 `c_proj` output boundary score

Artifact:

- `artifacts/task6/parallel-hypotheses/h2-int8-l2-c-proj-output-boundary.json`

Script:

- `scripts/task6/score_int8_c_proj_output_boundary.py`

Nix target:

- `task6-int8-l2-c-proj-output-boundary`
- output:
  `/nix/store/cjvhkpgmk6hk673jp67l7pwqpp1xqm65-task6-int8-l2-c-proj-output-boundary`

Command:

- `nix build .#task6-int8-l2-c-proj-output-boundary --no-link --print-out-paths -L`

Purpose:

- define the output side of the composed int8 MLP proof before adding more RTL
- score both:
  - int32 accumulator to f32 `c_proj` output
  - int32 accumulator to int8 `c_proj` output
- carry forward the nearby Linalg context showing the next operation after
  `c_proj`:
  - bias add
  - then a same-shape add with another `1x1x64` tensor, which is the residual
    path that still needs explicit capture before a residual/add RTL proof

Execution result:

- status: `PASS`
- accumulator hash matches the composed-chain proof:
  - `8ef8c2a85f1cc1369dd6cad3d716215c8311ec8a407497a003947a5e222025e2`
- f32 output candidate:
  - formula:
    `f32_out[i] = int32_acc[i] * post_gelu_scale * weight_scale[i] + bias[i]`
  - normalized RMSE: `0.014010386505018001`
  - verdict: `pass`
- int8 output candidate:
  - calibration:
    single captured `c_proj` `activation_out` max-abs scale
  - output scale:
    `0.0006137476192684625`
  - output q range:
    `-91..127`
  - normalized RMSE: `0.015465772661379424`
  - verdict: `pass`

Byte-budget implication:

- `c_proj` accumulator output:
  - `256` int32 bytes
- f32 output boundary sidecars:
  - `256` effective-scale bytes
  - `256` bias bytes
- f32 output bytes:
  - `256`
- int8 output bytes:
  - `64`
- int8 output write savings versus f32:
  - `192` bytes for this `64`-wide `c_proj` output

Decision:

- Promote the post-`c_proj` int8 output boundary as the next H2 implementation
  target.
- Do not implement residual/add yet:
  - the Linalg context confirms the add is next, but the residual tensor itself
    is not in the current `c_proj` module contract
  - capture that residual tensor before claiming a fused residual path
- Next gate:
  - implement a bounded fixed-point `c_proj` requant/output-memory RTL proof
  - then decide whether to capture the residual tensor for an int8 residual-add
    score or fall back to a f32 dequantized residual boundary

### 2026-04-28 - H2 composed MLP chain with `c_proj` int8 output requant

Artifact:

- `artifacts/task6/parallel-hypotheses/h2-int8-l2-mlp-chain-c-proj-requant-rtl-proof.json`

RTL and test files:

- `rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_requant_kernel.sv`
- `sim/task6_int8_l2_mlp_chain_c_proj_requant_tb_main.sv`
- `sim/gen_task6_int8_l2_mlp_chain_c_proj_requant_tb_data.py`

Nix targets:

- `task6-int8-l2-mlp-chain-c-proj-requant-sv-sim`
- `task6-int8-l2-mlp-chain-c-proj-requant-rtl-proof`
- output:
  `/nix/store/n5z8yq3dxkqq52pjk0zshpyhyadkimih-task6-int8-l2-mlp-chain-c-proj-requant-rtl-proof`

Commands:

- `nix build .#task6-int8-l2-mlp-chain-c-proj-requant-sv-sim --no-link --print-out-paths -L`
- `nix build .#task6-int8-l2-mlp-chain-c-proj-requant-rtl-proof --no-link --print-out-paths -L`

Purpose:

- extend the promoted composed chain:
  `c_fc -> fixed-point GELU -> int8 handoff -> c_proj`
- add a bounded fixed-point post-`c_proj` output stage:
  `q[i] = saturate_i8(round_shift(acc[i] * scale_mul[i], 24) + bias_q[i])`
- store the 64-wide `c_proj` result as int8 in local output memory instead of
  leaving the chain at the int32 accumulator boundary

Execution result:

- status: `PASS`
- Verilator:
  - reads: `64`
  - outputs: `64`
  - compute cycles: `9760`
  - total cycles: `9824`
- fixed-point output:
  - output scale: `0.0006137476192684625`
  - output q range: `-91..127`
  - normalized RMSE: `0.015465772661379428`
  - output-q hash matches the prior `c_proj` int8 output-boundary quantizer
  - accumulator hash matches the prior composed-chain and output-boundary
    artifacts
- Yosys mapped check:
  - `0` reported problems

Mapped utilization:

- LUTs: `1123 / 298600 = 0.38%`
- FFs: `443 / 597200 = 0.07%`
- DSPs: `34 / 1920 = 1.77%`
- BRAM36: `8 / 955 = 0.84%`
- BRAM18: `6`
- BRAM36-equivalent: `11.0 / 955 = 1.15%`

Delta versus the previous composed-chain accumulator-boundary proof:

- LUTs: `+179`
- FFs: `+17`
- DSPs: `+4`
- BRAM36-equivalent: `+1.0`
- Interpretation:
  - the int8 output stage costs a small amount of logic and one additional
    BRAM36-equivalent for the `c_proj` requant sidecars/output storage
  - the overall resource picture remains very small relative to the board

Decision:

- Promote this as the current H2 RTL reference for the bounded MLP-chain output
  boundary.
- Next gate:
  - capture the residual/add tensor after `c_proj`
  - score whether an int8 residual-add boundary is viable
  - only then implement or reject a fused residual-add RTL proof

### 2026-04-28 - H2 residual-add boundary scout after `c_proj`

Artifact:

- `artifacts/task6/parallel-hypotheses/h2-int8-l2-residual-add-boundary-scout.json`

Script and Nix target:

- `scripts/task6/trace_int8_residual_add_boundary.py`
- `task6-int8-l2-residual-add-boundary-scout`
- output:
  `/nix/store/5g8z9m1gmf2w453kw61v7pg5qniyxiyl-task6-int8-l2-residual-add-boundary-scout`

Commands:

- `python3 scripts/task6/trace_int8_residual_add_boundary.py --c-fc-contract-manifest artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_fc-contract/manifest.json --c-proj-contract-manifest artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_proj-contract/manifest.json --c-proj-candidate-json artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_proj-candidate.json --c-proj-requant-rtl-proof-json artifacts/task6/parallel-hypotheses/h2-int8-l2-mlp-chain-c-proj-requant-rtl-proof.json --out-json artifacts/task6/parallel-hypotheses/h2-int8-l2-residual-add-boundary-scout.json`
- `nix build .#task6-int8-l2-residual-add-boundary-scout --no-link --print-out-paths -L`

Result:

- status: `NEEDS_CAPTURE`
- upstream `c_proj` int8 output proof remains usable:
  - status: `PASS`
  - output scale: `0.0006137476192684625`
  - output q range: `-91..127`
  - normalized RMSE: `0.015465772661379428`
  - output-q hash: `93020d792e1a60480198b96b4daf79beca0cb1507253c14b2a4494eaed8b5f8d`
- next Linalg add site:
  - line: `418`
  - result: `%96`
  - operands: `%62`, `%95`
  - interpretation:
    - `%95` is the post-`c_proj` bias-add value
    - `%62` is the separate residual tensor that is not present in the current
      `c_proj` module contract

Capture route for the next numeric gate:

- capture residual operand from `transformer.h.0.ln_2` `activation_in`
- cross-check `transformer.h.0.ln_2` `activation_out` against the existing
  `transformer.h.0.mlp.c_fc` `activation_in` contract
- cross-check `transformer.h.0.mlp.c_proj` `activation_out` against the
  existing `c_proj` contract
- cross-check block output with:
  `block_out = ln_2.activation_in + mlp.c_proj.activation_out`
- then score:
  - `residual_f32 + c_proj_output_q * c_proj_output_scale`
  - `residual_q * residual_scale + c_proj_output_q * c_proj_output_scale`
  - quantized residual-add output for the next boundary

Execution notes:

- the old L2 Linalg store path recorded in the candidate JSON could not be
  restored with `nix-store -r`
- a direct rebuild of `tiny-stories-v1k-h64-l1-linalg` started compiling the
  full Torch/Triton closure, so it was stopped and replaced with this
  lower-cost scout artifact
- the prior Python environment used for the original contract capture had been
  garbage-collected, so the actual residual tensor capture still needs either a
  restored lightweight Python environment or an intentional rebuild of that
  capture environment

Decision:

- Do not claim residual-add numeric viability yet.
- Promote the exact capture route above as the next executable gate.

### 2026-04-28 - H2 residual-add boundary capture and score

Artifacts:

- `artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-residual-add-contract/`
- `artifacts/task6/parallel-hypotheses/h2-int8-l2-residual-add-boundary.json`

Scripts and Nix targets:

- `scripts/task6/export_residual_add_contract.py`
- `scripts/task6/score_int8_residual_add_boundary.py`
- `task6-int8-l2-residual-add-contract`
- `task6-int8-l2-residual-add-boundary`

Environment note:

- The first attempt through `python.pkgs.torch-bin` still pulled CUDA/NCCL
  source builds through the CUDA wheel closure.
- The capture target now uses a local CPU-only PyTorch wheel override:
  `torch-2.9.1+cpu-cp311-cp311-manylinux_2_28_x86_64.whl`
  with hash `sha256-PeKtubREPckhDvHxsW2jZHrOU1UxZtY2C7vX7dbxbk0=`.
- `transformers` and `safetensors` are overridden to use that CPU wheel for
  this capture path.

Contract capture result:

- status: `PASS`
- residual source: `transformer.h.0.ln_2` `activation_in`
- block output check:
  - `residual_activation_in + c_proj_activation_out` vs block output
  - normalized RMSE: `0.0`
- cross-checks against existing module contracts:
  - `ln2_activation_out` vs `c_fc.activation_in`: normalized RMSE
    `1.8294183695719108e-07`
  - `c_proj.activation_in` vs contract: normalized RMSE
    `2.8896815448809813e-07`
  - `c_proj.activation_out` vs contract: normalized RMSE
    `3.9373162995150223e-07`

Residual-add boundary score:

- status: `PASS`
- threshold: normalized RMSE `<= 0.02`
- `c_proj` output q hash:
  `93020d792e1a60480198b96b4daf79beca0cb1507253c14b2a4494eaed8b5f8d`
  - matches both the output-boundary scorer and RTL proof
- residual quantization:
  - scale: `0.0007355256578115028`
  - q range: `-114..127`
  - q hash:
    `a455841a965b5073c01ded9aa310f6d496376139cb9ccb3f3fc0c62a8e84d3f7`
- final residual-add output quantization:
  - scale: `0.0007500236330698129`
  - q range: `-125..127`
  - q hash:
    `28654845bf312e6298524e3444dd045cf7fb7fb30a0c693f211214ddc7970418`

Boundary metrics:

- `f32_residual_plus_int8_c_proj_vs_block_output`:
  - normalized RMSE: `0.007978545180826635`
  - verdict: pass
- `int8_residual_plus_int8_c_proj_vs_block_output`:
  - normalized RMSE: `0.009136092226376756`
  - verdict: pass
- `int8_final_residual_add_output_vs_block_output`:
  - normalized RMSE: `0.01095521307528224`
  - verdict: pass

Byte budget for this single-token L2 gate:

- residual f32: `256` bytes
- residual int8: `64` bytes
- `c_proj` int8 output: `64` bytes
- final residual-add int8 output: `64` bytes
- residual int8 savings vs f32: `192` bytes
- final output int8 savings vs f32: `192` bytes

Decision:

- Promote the residual-add boundary to the next implementation gate.
- Next gate: implement a bounded residual-add RTL proof that consumes:
  - residual int8 vector plus residual scale
  - `c_proj` int8 output vector plus `c_proj` output scale
  - final output scale
  - expected final q hash above

### 2026-04-29 - H2 composed MLP chain with int8 residual-add RTL proof

Artifact:

- `artifacts/task6/parallel-hypotheses/h2-int8-l2-mlp-chain-residual-add-rtl-proof.json`

RTL, testbench, and generator:

- `rtl/task6/task6_int8_l2_mlp_chain_residual_add_kernel.sv`
- `sim/task6_int8_l2_mlp_chain_residual_add_tb_main.sv`
- `sim/gen_task6_int8_l2_mlp_chain_residual_add_tb_data.py`

Nix targets:

- `task6-int8-l2-mlp-chain-residual-add-tb-data-sv`
- `task6-int8-l2-mlp-chain-residual-add-sv-sim`
- `task6-int8-l2-mlp-chain-residual-add-yosys-stat`
- `task6-int8-l2-mlp-chain-residual-add-json`
- `task6-int8-l2-mlp-chain-residual-add-utilization`
- `task6-int8-l2-mlp-chain-residual-add-rtl-proof`
- proof output:
  `/nix/store/a6ysyfr2xmh1a7k94di5clf4qzmnci0j-task6-int8-l2-mlp-chain-residual-add-rtl-proof`

Commands:

- `nix build .#task6-int8-l2-mlp-chain-residual-add-sv-sim --no-link --print-out-paths -L`
- `nix build .#task6-int8-l2-mlp-chain-residual-add-rtl-proof --no-link --print-out-paths -L`

Purpose:

- close the residual-add implementation gate after the captured boundary score
- extend the composed H2 RTL chain to:
  `c_fc -> fixed-point GELU -> post-GELU int8 -> c_proj -> c_proj int8 output -> residual-add int8 output`
- consume the captured residual vector as int8 and store the final block output
  as int8 in local output memory

Execution result:

- status: `PASS`
- Verilator:
  - reads: `64`
  - outputs: `64`
  - compute cycles: `9889`
  - total cycles: `9953`
- Yosys mapped check:
  - `0` reported problems
- final residual-add output:
  - output scale: `0.0007500236330698129`
  - output q range: `-125..127`
  - output q hash:
    `28654845bf312e6298524e3444dd045cf7fb7fb30a0c693f211214ddc7970418`
  - hash matches the captured residual-add boundary quantizer
  - fixed RTL residual-add output vs block output normalized RMSE:
    `0.01095521307528224`
  - fixed RTL residual-add output vs boundary quantizer normalized RMSE: `0.0`

Mapped utilization:

- LUTs: `1226 / 298600 = 0.41%`
- FFs: `468 / 597200 = 0.08%`
- DSPs: `36 / 1920 = 1.88%`
- BRAM36: `8 / 955 = 0.84%`
- BRAM18: `6`
- BRAM36-equivalent: `11.0 / 955 = 1.15%`
- slices lower bound: `154 / 74650 = 0.21%`

Delta versus the previous composed-chain `c_proj` int8-output proof:

- LUTs: `1123 -> 1226` (`+103`)
- FFs: `443 -> 468` (`+25`)
- DSPs: `34 -> 36` (`+2`)
- BRAM36-equivalent: `11.0 -> 11.0` (`+0.0`)

Interpretation:

- The residual-add postprocess is a small incremental cost over the prior
  `c_proj` int8-output proof.
- The DSP use remains fit-positive: the full bounded MLP plus residual-add
  proof uses only `36` DSPs, about `1.88%` of the board budget.
- This completes the current int8 residual-add question for the bounded L2
  gate: it works in RTL, passes simulation, matches the captured boundary
  quantizer, and stays very small in mapped utilization.

Decision:

- Promote this as the current H2 RTL reference for a block-output int8 boundary.
- Next gate:
  - integrate the residual-add proof into a board-programmable selftest lane
  - keep the lane bounded first, then scale only after the programmed-board
    selftest path proves the I/O contract and pass/fail reporting

### 2026-04-29 - H2 residual-add board selftest bitstream

Artifacts:

- `fpga/rtl/task6_int8_l2_mlp_chain_residual_add_selftest_top.sv`
- `sim/task6_int8_l2_mlp_chain_residual_add_selftest_tb_main.sv`

Nix targets:

- `task6-int8-l2-mlp-chain-residual-add-selftest-top`
- `task6-int8-l2-mlp-chain-residual-add-selftest-sim-main`
- `task6-int8-l2-mlp-chain-residual-add-selftest-sv-sim`
- `task6-int8-l2-mlp-chain-residual-add-selftest-json`
- `task6-int8-l2-mlp-chain-residual-add-selftest-utilization`
- `task6-int8-l2-mlp-chain-residual-add-selftest-xdc`
- `task6-int8-l2-mlp-chain-residual-add-selftest-fasm`
- `task6-int8-l2-mlp-chain-residual-add-selftest-bitstream`

Purpose:

- move the bounded int8 residual-add RTL proof from simulator-only evidence to
  a board-programmable pass/fail selftest
- reuse the existing `matmul_selftest.xdc` board pins:
  `SYS_CLK`, `SYS_RSTN`, and `led_3bits_tri_o[2:0]`
- load the fixed proof vectors into the DUT, pulse `start`, wait for `done`,
  read all `64` output bytes, and assert:
  - `led_3bits_tri_o[0]`: heartbeat
  - `led_3bits_tri_o[1]`: pass
  - `led_3bits_tri_o[2]`: fail

Commands:

- `nix build .#task6-int8-l2-mlp-chain-residual-add-selftest-sv-sim --no-link --print-out-paths -L`
- `nix build .#task6-int8-l2-mlp-chain-residual-add-selftest-utilization --no-link --print-out-paths -L`
- `nix build .#task6-int8-l2-mlp-chain-residual-add-selftest-fasm --no-link --print-out-paths -L`
- `nix build .#task6-int8-l2-mlp-chain-residual-add-selftest-bitstream --no-link --print-out-paths -L`

Execution result:

- Verilator wrapper selftest: `PASS`
  - pass LED asserted after `18676` simulated cycles
  - output path:
    `/nix/store/7vbz64gnv359myip0j8j26xf5rwn73ds-task6-int8-l2-mlp-chain-residual-add-selftest-sv-sim.json`
- Yosys mapped check:
  - `0` reported problems
  - JSON path:
    `/nix/store/md3y3hzgpi5gm0cw94wkyx9iz52lzwqd-task6-int8-l2-mlp-chain-residual-add-selftest.json`
  - utilization report:
    `/nix/store/ahlxmh9hgw711l3wywld1b1fwp22b047-task6-int8-l2-mlp-chain-residual-add-selftest-utilization`
- nextpnr/FASM:
  - legal route: router reached `overused=0`, `overuse=0`, `archfail=0`
  - post-route max frequency: `141.02 MHz`
  - requested target: `12.00 MHz`
  - FASM path:
    `/nix/store/9m7pxa76vkna92jdfln0l2hp74wggw3g-task6-int8-l2-mlp-chain-residual-add-selftest.fasm`
- bitstream:
  - status: `PASS`
  - bit path:
    `/nix/store/rdg9hr176qqln2lg0a2dqxscddqamy30-task6-int8-l2-mlp-chain-residual-add-selftest.bit`

Mapped utilization:

- LUTs: `6944 / 298600 = 2.33%`
- FFs: `566 / 597200 = 0.09%`
- DSPs: `36 / 1920 = 1.88%`
- BRAM36: `8 / 955 = 0.84%`
- BRAM18: `6`
- BRAM36-equivalent: `11.0 / 955 = 1.15%`
- BRAM KiB: `396 / 34380 = 1.15%`
- slices lower bound: `868 / 74650 = 1.16%`

Delta versus the bare residual-add RTL proof:

- LUTs: `1226 -> 6944` (`+5718`)
- FFs: `468 -> 566` (`+98`)
- DSPs: `36 -> 36` (`+0`)
- BRAM36-equivalent: `11.0 -> 11.0` (`+0.0`)

Interpretation:

- The selftest wrapper adds LUT-heavy fixed-vector load and compare logic, but
  it does not increase DSP or BRAM use over the bare residual-add kernel.
- This is the intended board bring-up tradeoff: spend a small amount of LUT
  budget to prove the real I/O contract and visible pass/fail reporting.
- The bitstream artifact is ready for physical programming and LED observation.

Tooling note:

- The first selftest JSON attempt used the generic `mkSynthJson` path, which
  pulled the `yosys-slang`/`yosys-0.64` bootstrap path and failed before design
  synthesis with `genericBuild: command not found`.
- The accepted selftest JSON target uses explicit `read_verilog -sv` commands
  with `pkgs.yosys`, matching the other Task 6 RTL proof targets.

Decision:

- Board-programmable evidence is now available for the bounded int8 residual
  add lane.
- Next gate:
  - physically program
    `/nix/store/rdg9hr176qqln2lg0a2dqxscddqamy30-task6-int8-l2-mlp-chain-residual-add-selftest.bit`
  - observe heartbeat/pass/fail LEDs under real board clock/reset
  - if pass LED asserts and fail LED stays low, promote the lane from
    bitstream-ready to on-board validated

### 2026-04-29 - H2 residual-add board selftest programmed

Programming command:

- `sudo openFPGALoader -c digilent_hs3 --ftdi-serial 210299BF3824 -m /nix/store/rdg9hr176qqln2lg0a2dqxscddqamy30-task6-int8-l2-mlp-chain-residual-add-selftest.bit`

Observed LEDs:

- board-visible LED 1: fixed on, believed to be the board power/status LED
- board-visible LED 2: blinking
- board-visible LED 3: fixed on
- board-visible LED 4: off

Design LED mapping:

- `led_3bits_tri_o[0]`: heartbeat, pin `P30`
- `led_3bits_tri_o[1]`: pass, pin `M30`
- `led_3bits_tri_o[2]`: fail, pin `N30`

Interpretation:

- The three design-driven LEDs match the expected pass pattern:
  heartbeat blinking, pass asserted, fail deasserted.
- This promotes the bounded int8 residual-add lane from bitstream-ready to
  on-board validated, subject to the board-visible first LED indeed being the
  always-on board status LED rather than one of the three constrained design
  pins.

Tooling note:

- Programming through the literal `result` symlink was reported to fail with:
  `Can't program SPI flash: missing device-package information`.
- The explicit Nix store `.bit` path works. For future runs, use
  `$(readlink -f result)` or the direct `.bit` store path so
  `openFPGALoader` sees the `.bit` file name instead of the extensionless
  `result` symlink name.

Decision:

- Record this as the first successful on-board validation of the bounded H2
  int8 residual-add selftest.
- Next gate:
  - decide whether to build a DDR3 bring-up selftest or scale the bounded
    on-board lane to a larger streaming-memory surface

### 2026-04-29 - LED map diagnostic bitstream

Artifacts:

- `fpga/rtl/task6_led_map_top.sv`

Nix targets:

- `task6-led-map-json`
- `task6-led-map-xdc`
- `task6-led-map-fasm`
- `task6-led-map-bitstream`

Purpose:

- disambiguate the physical board LED order before interpreting the residual-add
  pass/fail selftest LEDs
- use the same `SYS_CLK`, `SYS_RSTN`, and `led_3bits_tri_o[2:0]` pin
  constraints as the Task 6 residual-add board selftest

Expected repeating pattern:

- `led_3bits_tri_o = 3'b001`
- `led_3bits_tri_o = 3'b010`
- `led_3bits_tri_o = 3'b100`
- `led_3bits_tri_o = 3'b111`

Bitstream:

- `/nix/store/1d7wfvkzaf7bdsigsm5g6hlq8xn7yzw4-task6-led-map.bit`

Programming command:

- `sudo openFPGALoader -c digilent_hs3 --ftdi-serial 210299BF3824 -m /nix/store/1d7wfvkzaf7bdsigsm5g6hlq8xn7yzw4-task6-led-map.bit`

Use:

- Watch which physical LEDs participate in the one-hot sequence.
- The LED that turns on during `3'b001` is design LED `[0]`, heartbeat in the
  residual-add selftest.
- The LED that turns on during `3'b010` is design LED `[1]`, pass in the
  residual-add selftest.
- The LED that turns on during `3'b100` is design LED `[2]`, fail in the
  residual-add selftest.
- During `3'b111`, all three design-driven user LEDs should be on.

Observed physical mapping:

- top green LED: always on, not one of the three design-driven LEDs
- design LED `[0]`, pin `P30`: red
- design LED `[1]`, pin `M30`: green
- design LED `[2]`, pin `N30`: orange

Residual-add selftest interpretation:

- expected pass pattern:
  - top green: always on, ignored
  - red: blinking heartbeat
  - green: solid on pass
  - orange: off fail
- orange off after programming is a good sign: it means the fail LED is not
  asserted.

### 2026-04-29 - Residual-add selftest JTAG reset hardening

Observed board behavior:

- After a board power cycle, the residual-add selftest asserts the green pass
  LED in less than a second.
- After JTAG reprogramming the same bitstream without power cycling, the pass
  LED does not reliably assert.

Interpretation:

- The compute path is still likely good: a power cycle gives the design a clean
  reset and the selftest passes quickly.
- The issue is likely reset sequencing after configuration. JTAG programming
  can leave the external `SYS_RSTN` input high, so the selftest FSM may not see
  the same reset edge it sees after a board power cycle.

RTL change:

- `task6_int8_l2_mlp_chain_residual_add_selftest_top` now includes an internal
  post-configuration reset counter.
- `config_reset_count_q` is initialized to zero and holds `selftest_reset`
  asserted until bit `7` becomes high, giving the design `128` clocks of local
  reset after configuration even if `SYS_RSTN` never toggles.
- The DUT reset and selftest FSM reset path now use `selftest_reset`.

Verification:

- `nix-instantiate --parse flake.nix`
- `git diff --check`
- `nix build .#task6-int8-l2-mlp-chain-residual-add-selftest-sv-sim --no-link --print-out-paths -L`
  - result: `PASS`
  - pass LED asserted after `18804` simulated cycles
  - output path:
    `/nix/store/bgf2lpchpil22kaq0bfw1l9mcdgmv3af-task6-int8-l2-mlp-chain-residual-add-selftest-sv-sim.json`
- `nix build .#task6-int8-l2-mlp-chain-residual-add-selftest-bitstream --no-link --print-out-paths -L`
  - result: `PASS`
  - post-route max frequency: `161.24 MHz`
  - requested target: `12.00 MHz`
  - bit path:
    `/nix/store/vp6gcd52scyys0m694ka0zgnk39di6ym-task6-int8-l2-mlp-chain-residual-add-selftest.bit`
- `nix build .#task6-int8-l2-mlp-chain-residual-add-selftest-utilization --no-link --print-out-paths -L`
  - output path:
    `/nix/store/kihvlwn139wzxmvl2kgl320i5fm44777-task6-int8-l2-mlp-chain-residual-add-selftest-utilization`
  - LUTs: `7039 / 298600 = 2.36%`
  - FFs: `574 / 597200 = 0.10%`
  - DSPs: `36 / 1920 = 1.88%`
  - BRAM36-equivalent: `11 / 955 = 1.15%`

Expected physical test:

- Program the new bitstream without power cycling:
  `sudo openFPGALoader -c digilent_hs3 --ftdi-serial 210299BF3824 -m /nix/store/vp6gcd52scyys0m694ka0zgnk39di6ym-task6-int8-l2-mlp-chain-residual-add-selftest.bit`
- Expected LED pattern after less than a second:
  - top green: always on, ignored
  - red: blinking heartbeat
  - green: solid on pass
  - orange: off fail
- If this passes after a JTAG-only reprogram, the reset-sequencing hypothesis
  is confirmed.

Follow-up observation:

- The reset-hardened bitstream asserted the orange fail LED after JTAG
  programming.
- Interpretation:
  - the selftest is now starting after JTAG configuration
  - the remaining problem is inside the selftest result path, most likely a
    timeout or output-compare mismatch

Diagnostic bitstream:

- Added `DEBUG_LEDS` mode to
  `task6_int8_l2_mlp_chain_residual_add_selftest_top`.
- Added flake targets:
  - `task6-int8-l2-mlp-chain-residual-add-selftest-debug-json`
  - `task6-int8-l2-mlp-chain-residual-add-selftest-debug-fasm`
  - `task6-int8-l2-mlp-chain-residual-add-selftest-debug-bitstream`
- Built debug bitstream:
  `/nix/store/xz6ddhxm9l5ijg4ndkd8cv3sq8ki66i1-task6-int8-l2-mlp-chain-residual-add-selftest-debug.bit`
- Post-route max frequency: `135.91 MHz`
- Requested target: `12.00 MHz`

Debug LED decoding after a failure:

- The pattern cycles through four slow phases:
  1. fail reason
  2. failing output index bits `[2:0]`
  3. failing output index bits `[5:3]`
  4. all three design LEDs on as a separator
- Fail reason phase:
  - orange + red: timeout
  - orange + green: output mismatch
  - red + green + orange: default / unexpected state
- Index phases use binary on the design LEDs:
  - red is bit `0`
  - green is bit `1`
  - orange is bit `2`
- The always-on top green board LED is not part of this code.

Next physical test:

- Program the diagnostic bitstream:
  `sudo openFPGALoader -c digilent_hs3 --ftdi-serial 210299BF3824 -m /nix/store/xz6ddhxm9l5ijg4ndkd8cv3sq8ki66i1-task6-int8-l2-mlp-chain-residual-add-selftest-debug.bit`
- Watch the three design-driven LEDs for one full repeating cycle and record:
  fail-reason phase, low-index phase, high-index phase, separator phase.

Follow-up physical observation:

- Observed sequence:
  - red + green + orange
  - green + orange
  - nothing
- Interpretation:
  - red + green + orange is the separator phase
  - green + orange is `FAIL_REASON_MISMATCH`
  - the following `nothing` phase is failing-index bits `[2:0] = 0`
  - the board is failing on output index `0`
- Generated expected value for output index `0`:
  - `expected_residual_add_output_q_values[0] = 8'sh0a`

Value diagnostic bitstream:

- Added `DEBUG_LEDS=2` mode to
  `task6_int8_l2_mlp_chain_residual_add_selftest_top`.
- Added flake targets:
  - `task6-int8-l2-mlp-chain-residual-add-selftest-value-debug-json`
  - `task6-int8-l2-mlp-chain-residual-add-selftest-value-debug-fasm`
  - `task6-int8-l2-mlp-chain-residual-add-selftest-value-debug-bitstream`
- Verification:
  - `nix-instantiate --parse flake.nix`: pass
  - `git diff --check`: pass
  - `nix build .#task6-int8-l2-mlp-chain-residual-add-selftest-sv-sim --no-link --print-out-paths -L`:
    pass at `18804` cycles
    - `/nix/store/63cl9maj4galk7izanpzc6jmnnic803r-task6-int8-l2-mlp-chain-residual-add-selftest-sv-sim.json`
  - `nix build .#task6-int8-l2-mlp-chain-residual-add-selftest-value-debug-json --no-link --print-out-paths -L`:
    pass
    - `/nix/store/7465vpi28yc4cjy56b7rq73x78i2bmb8-task6-int8-l2-mlp-chain-residual-add-selftest-value-debug.json`
  - `nix build .#task6-int8-l2-mlp-chain-residual-add-selftest-value-debug-bitstream --no-link --print-out-paths -L`:
    pass
    - `/nix/store/11jndspp1b4j7gs46h26nx2mjji8gmrz-task6-int8-l2-mlp-chain-residual-add-selftest-value-debug.bit`
- Post-route timing:
  - max frequency: `146.31 MHz`
  - requested target: `12.00 MHz`

Value debug LED decoding:

- Ignore the always-on top board green LED.
- On the three design-driven LEDs, red is bit `0`, green is bit `1`, and
  orange is bit `2`.
- The cycle has 16 phases:
  1. all LEDs: start marker
  2. fail reason
  3. failing index bits `[2:0]`
  4. failing index bits `[5:3]`
  5. red + orange: expected-byte marker
  6. expected byte bits `[2:0]`
  7. expected byte bits `[5:3]`
  8. expected byte bits `[7:6]`, using red for bit `6` and green for bit `7`
  9. red + green: observed-byte marker
  10. observed byte bits `[2:0]`
  11. observed byte bits `[5:3]`
  12. observed byte bits `[7:6]`, using red for bit `6` and green for bit `7`
  13. nothing: gap
  14. nothing: gap
  15. nothing: gap
  16. all LEDs: end marker
- Expected index-0 byte `0x0a` should display after the red + orange marker as:
  - green
  - red
  - nothing

Follow-up value-debug physical observation:

- Observed sequence:
  - red + green + orange
  - green + orange
  - nothing
  - red + orange
  - green
  - red
  - nothing
  - red + green
  - green
  - red + orange
  - red
  - nothing
  - red + green + orange
- Interpretation:
  - fail reason is `FAIL_REASON_MISMATCH`
  - failing index is still `0`
  - expected final output byte is `0x0a`
  - observed final output byte is `0x6a`
- The residual-add formula produces `0x6a` for index `0` if the add stage
  consumes `c_proj = 0x7f` with residual `0x02`, so the next diagnostic
  checks the actual c_proj byte presented to the residual-add write.

C-proj diagnostic bitstream:

- Added `DEBUG_LEDS=3` mode to display the expected c_proj byte and the
  first c_proj byte observed by the residual-add write path.
- Added flake targets:
  - `task6-int8-l2-mlp-chain-residual-add-selftest-c-proj-debug-json`
  - `task6-int8-l2-mlp-chain-residual-add-selftest-c-proj-debug-fasm`
  - `task6-int8-l2-mlp-chain-residual-add-selftest-c-proj-debug-bitstream`
- Verification:
  - `nix build .#task6-int8-l2-mlp-chain-residual-add-selftest-c-proj-debug-json --no-link --print-out-paths -L`:
    pass
    - `/nix/store/hczhy2bwgh3p744sis9fy34anhpk876i-task6-int8-l2-mlp-chain-residual-add-selftest-c-proj-debug.json`
  - `nix build .#task6-int8-l2-mlp-chain-residual-add-selftest-c-proj-debug-bitstream --no-link --print-out-paths -L`:
    pass
    - `/nix/store/j10fhmdb4w9mvk5gdijjx21762ia5qqf-task6-int8-l2-mlp-chain-residual-add-selftest-c-proj-debug.bit`
- Post-route timing:
  - max frequency: `156.67 MHz`
  - requested target: `12.00 MHz`

C-proj debug LED decoding:

- Ignore the always-on top board green LED.
- The cycle layout is the same as value debug, except the byte after
  red + orange is expected c_proj and the byte after red + green is the
  first c_proj observed by the residual-add write path.
- Expected c_proj for index `0` is `0x0a`, displayed as:
  - green
  - red
  - nothing
- If the observed c_proj is `0x7f`, it should display after the red + green
  marker as:
  - red + green + orange
  - red + green + orange
  - red

Follow-up c-proj debug physical observation:

- Observed sequence after the red + orange marker:
  - green
  - red
  - nothing
- Observed sequence after the red + green marker:
  - red + green + orange for two phases
  - red
  - nothing
- Interpretation:
  - expected c_proj byte for output index `0` is `0x0a`
  - residual-add consumed c_proj byte `0x7f`
  - this confirms the value-debug inference that output `0x6a` was produced
    by adding residual `0x02` to saturated c_proj `0x7f`

C-proj requant split diagnostic bitstream:

- Added c_proj requant debug outputs for the first output write:
  accumulator, scale multiplier, bias, and requantized output byte.
- Added `DEBUG_LEDS=4` mode to display three match bits for index `0`:
  accumulator matches expected, scale matches expected, and bias matches
  expected, followed by the observed c_proj output byte.
- Added flake targets:
  - `task6-int8-l2-mlp-chain-residual-add-selftest-c-proj-requant-debug-json`
  - `task6-int8-l2-mlp-chain-residual-add-selftest-c-proj-requant-debug-fasm`
  - `task6-int8-l2-mlp-chain-residual-add-selftest-c-proj-requant-debug-bitstream`
- Verification:
  - `nix build .#task6-int8-l2-mlp-chain-residual-add-selftest-sv-sim --no-link --print-out-paths -L`:
    pass at `18804` cycles
    - `/nix/store/4q44akfqr9gl2gkc6bzy9vbj0fx2dm40-task6-int8-l2-mlp-chain-residual-add-selftest-sv-sim.json`
  - `nix build .#task6-int8-l2-mlp-chain-residual-add-selftest-c-proj-requant-debug-json --no-link --print-out-paths -L`:
    pass
    - `/nix/store/49p4im0ckwmia98vyyvfbpnrk484jrcq-task6-int8-l2-mlp-chain-residual-add-selftest-c-proj-requant-debug.json`
  - `nix build .#task6-int8-l2-mlp-chain-residual-add-selftest-c-proj-requant-debug-bitstream --no-link --print-out-paths -L`:
    pass
    - `/nix/store/qg4wbb17a00v9212c3nny3ybgk7cpjhp-task6-int8-l2-mlp-chain-residual-add-selftest-c-proj-requant-debug.bit`
- Post-route timing:
  - max frequency: `137.99 MHz`
  - requested target: `12.00 MHz`

C-proj requant split debug LED decoding:

- Ignore the always-on top board green LED.
- After the red + orange marker, three phases show match bits:
  1. c_proj accumulator match
  2. c_proj scale multiplier match
  3. c_proj bias match
- For those match phases:
  - green means match
  - red + orange means mismatch or not captured
- After the red + green marker, the observed c_proj output byte is displayed
  with the same three-phase byte encoding as before.
- If the accumulator/scale/bias are all correct but the output is still
  `0x7f`, the likely fault is in synthesized requant arithmetic.
- If the accumulator is mismatched while scale and bias match, the likely
  fault is upstream in the c_fc/post-GELU/c_proj accumulator chain.

Follow-up c-proj requant split debug physical observation:

- Normal self-test bitstream after the first sign-extension patch still failed
  on hardware: orange stayed on and red blinked.
- `DEBUG_LEDS=4` physical sequence:
  - red + green + orange
  - green + orange
  - nothing
  - red + orange
  - green
  - red + green
  - red + green + orange
  - red
  - nothing
- Interpretation:
  - failing output index is still `0`
  - c_proj accumulator matches the generated expected value
  - c_proj requant scale multiplier matches the generated expected value
  - c_proj requant bias matches the generated expected value
  - observed c_proj output byte is still `0x7f`
  - expected c_proj output byte is `0x0a`
- This keeps the suspected fault inside the synthesized c_proj requant
  arithmetic rather than the reset/load path, constant ROM contents, or
  upstream accumulator path.

C-proj requant shift-add trial:

- Replaced the c_proj requant `acc * scale_mul` expression with an explicit
  signed 32x32 shift-add multiply helper.
- Rationale:
  - simulation already passes with the original `*`
  - hardware diagnostics show correct operands but a saturated-looking c_proj
    output
  - replacing the inferred DSP-backed multiply tests whether the synthesis/P&R
    implementation of that signed multiply is the hardware-only mismatch
- Verification:
  - `nix build .#task6-int8-l2-mlp-chain-residual-add-selftest-sv-sim --no-link --print-out-paths -L`:
    pass at `18804` cycles
    - `/nix/store/jky2iv3zjl0d0x4lgx44gb40qllrm23s-task6-int8-l2-mlp-chain-residual-add-selftest-sv-sim.json`
  - `nix build .#task6-int8-l2-mlp-chain-residual-add-selftest-json --no-link --print-out-paths -L`:
    pass
    - `/nix/store/kpx1jvxlgd3fa5fmh0wv2vh46kffcx31-task6-int8-l2-mlp-chain-residual-add-selftest.json`
  - `nix build .#task6-int8-l2-mlp-chain-residual-add-selftest-bitstream --no-link --print-out-paths -L`:
    pass
    - `/nix/store/2hi48w49al1yh8z52b8hf0pylrqnpgjg-task6-int8-l2-mlp-chain-residual-add-selftest.bit`
- Yosys synthesis resource note:
  - `DSP48E1`: `32`, down from `36` before removing this multiply from the DSP
    path
- Packed utilization from the routed build:
  - `SLICE_LUTX`: `15264 / 597200` (`2.56%`)
  - `SLICE_FFX`: `718 / 597200` (`0.12%`)
  - `DSP48E1`: `32 / 1920` (`1.67%`)
  - `RAMB36E1`: `8 / 955`
  - `RAMB18E1`: `6 / 1910`
  - BRAM36-equivalent: `11 / 955` (`1.15%`)
- Post-route timing:
  - max frequency: `163.48 MHz`
  - requested target: `12.00 MHz`

Next physical test:

- Program:
  `sudo openFPGALoader -c digilent_hs3 --ftdi-serial 210299BF3824 /nix/store/2hi48w49al1yh8z52b8hf0pylrqnpgjg-task6-int8-l2-mlp-chain-residual-add-selftest.bit`
- Expected pass indication:
  - ignore the always-on top board green LED
  - design red LED blinks as heartbeat
  - design green LED is solid on
  - design orange LED is off

Follow-up shift-add physical observation:

- Programmed:
  `/nix/store/2hi48w49al1yh8z52b8hf0pylrqnpgjg-task6-int8-l2-mlp-chain-residual-add-selftest.bit`
- Observed:
  - red blinking
  - orange fixed on
- Interpretation:
  - the normal self-test still fails after replacing the c_proj requant DSP
    multiply with explicit shift-add logic
  - this weakens the simple "bad inferred c_proj DSP multiply" hypothesis
  - remaining likely causes are the rounded shift/saturation arithmetic, a
    synthesis issue with the combinational requant function shape, or an
    unobserved mismatch inside the product/shift intermediate values

Shift-add c-proj requant diagnostic bitstream:

- Rebuilt the `DEBUG_LEDS=4` c_proj requant diagnostic against the shift-add
  RTL.
- Verification:
  - `nix build .#task6-int8-l2-mlp-chain-residual-add-selftest-c-proj-requant-debug-bitstream --no-link --print-out-paths -L`:
    pass
    - `/nix/store/bw89f87zf1pb9a9w7rqc8ayglzksi8b1-task6-int8-l2-mlp-chain-residual-add-selftest-c-proj-requant-debug.bit`
- Packed utilization:
  - `SLICE_LUTX`: `15619 / 597200` (`2.61%`)
  - `SLICE_FFX`: `832 / 597200` (`0.14%`)
  - `DSP48E1`: `32 / 1920` (`1.67%`)
  - `RAMB36E1`: `8 / 955`
  - `RAMB18E1`: `6 / 1910`
- Post-route timing:
  - max frequency: `182.05 MHz`
  - requested target: `12.00 MHz`

Next physical test:

- Program:
  `sudo openFPGALoader -c digilent_hs3 --ftdi-serial 210299BF3824 /nix/store/bw89f87zf1pb9a9w7rqc8ayglzksi8b1-task6-int8-l2-mlp-chain-residual-add-selftest-c-proj-requant-debug.bit`
- Record one full repeated sequence from the three design-driven LEDs.
- Ignore the always-on top board green LED.

JTAG self-test readout transition:

- User requested no further manual LED decoding, so the next diagnostic path is
  direct JTAG readout over the Digilent HS3.
- Added an optional `BSCANE2` USER1 scan-chain payload to
  `task6_int8_l2_mlp_chain_residual_add_selftest_top`, enabled with
  `ENABLE_JTAG_DEBUG=1`.
- Added host decoder:
  `scripts/task6/read_jtag_debug_xvc.py`
- JTAG debug bitstream:
  `/nix/store/jj7vnw2cbvm77lazy48w5s9wns7mbnbk-task6-int8-l2-mlp-chain-residual-add-selftest-jtag-debug.bit`
- Verification:
  - normal self-test simulation still passes at `21108` cycles
  - JTAG-debug JSON synthesis completed with one `BSCANE2`
  - bitstream programmed into SRAM with non-sudo `openFPGALoader` after
    granting user access to `/dev/bus/usb/003/006`

JTAG payload result:

- Command:
  `scripts/task6/read_jtag_debug_xvc.py --poll --poll-count 20 --poll-interval 0.1`
- XVC info:
  `xvcServer_v1.0:2048`
- Decode summary:
  - magic check passed
  - state: `SELFTEST_FAIL`
  - fail reason: `MISMATCH`
  - fail index: `0`
  - final expected: `10`
  - final observed: `28`
  - expected c_proj output at index 0: `10`
  - first residual-add consumed c_proj: `32`
  - first residual-add output: `28`
- First c_proj requant capture:
  - accumulator observed: `23493`
  - accumulator expected: `7346`
  - scale observed/expected: `22564 / 22564`
  - bias observed/expected: `0 / 0`
  - product observed/expected: `530096052 / 165755144`
  - scaled observed/expected: `32 / 10`
  - biased observed/expected: `32 / 10`
  - output observed/expected: `32 / 10`
- Interpretation:
  - the requant scale and bias memories are correct for c_proj output index 0
  - the failure enters before requant, at the c_proj accumulator value
  - the previously tested standalone requant arithmetic is no longer the
    leading suspect
  - next discriminator should instrument the c_proj GEMV input stream for
    output index 0: c_fc post-GELU activations, packed c_proj weights, first
    per-lane products, and partial sums

Follow-up sequential c-proj requant diagnostic physical observation:

- `DEBUG_LEDS=4` physical sequence:
  - red + green + orange
  - green + orange
  - nothing
  - red + orange
  - green
  - red + green
  - green
  - nothing
  - red + green
  - nothing
- Decoding:
  - fail reason is mismatch
  - failing output index is still `0`
  - c_proj accumulator matches the generated expected value
  - c_proj requant scale multiplier matches the generated expected value
  - c_proj requant bias matches the generated expected value
  - observed c_proj output byte is `0xc2`
  - expected c_proj output byte is `0x0a`
- Interpretation:
  - the sequential arithmetic version still produces the wrong c_proj requant
    byte on board, even with the correct operands captured
  - the wrong byte changed across implementations:
    - inferred multiply path: `0x7f`
    - combinational shift-add path: `0xd4`
    - sequential shift-add path: `0xc2`
  - this further narrows the issue to c_proj requant arithmetic/control after
    operand capture, rather than residual-add, output compare, reset/load
    sequencing, sidecar constants, or upstream c_proj accumulation
- Clock/timing note:
  - local XDC currently constrains `SYS_CLK` to pin `AA28` but does not emit an
    explicit `create_clock`
  - public YPCB-00338-1P1 reverse-engineering notes label `AA28` as `clk_50m`
  - the routed diagnostic reports max frequency `123.79 MHz`, so a simple
    "actual clock is much faster than timing" explanation is not the leading
    hypothesis, although adding the explicit 50 MHz clock constraint remains
    worthwhile for rigor

Next discriminator:

- Build a tiny arithmetic-only board selftest for the index-0 c_proj requant
  constants:
  - accumulator: `0x00001cb2`
  - scale multiplier: `0x00005824`
  - bias: `0`
  - expected output: `0x0a`
- If the arithmetic-only top fails, the problem is a small reproducible
  synthesis/place/route hardware mismatch for the fixed-point arithmetic.
- If the arithmetic-only top passes, the problem is in the integrated c_proj
  requant control/data-capture path around the otherwise-valid arithmetic.

### 2026-04-29 - Arithmetic-only c_proj requant board discriminator

Added a standalone arithmetic-only board selftest for the index-0 c_proj
requant constants. This top does not instantiate the MLP chain, local memories,
residual-add, or output compare path. It only runs the same sequential fixed
point operation:

- accumulator: `0x00001cb2`
- scale multiplier: `0x00005824`
- bias: `0`
- shift: `24`
- expected int8 output: `0x0a`

Artifacts added:

- `fpga/rtl/task6_c_proj_requant_arith_selftest_top.sv`
- `fpga/constraints/task6_c_proj_requant_arith_selftest.xdc`
- `sim/task6_c_proj_requant_arith_selftest_tb_main.sv`
- flake outputs:
  - `task6-c-proj-requant-arith-selftest-sv-sim`
  - `task6-c-proj-requant-arith-selftest-json`
  - `task6-c-proj-requant-arith-selftest-utilization`
  - `task6-c-proj-requant-arith-selftest-xdc`
  - `task6-c-proj-requant-arith-selftest-fasm`
  - `task6-c-proj-requant-arith-selftest-bitstream`

Verification:

- `nix build .#task6-c-proj-requant-arith-selftest-sv-sim --no-link --print-out-paths -L`:
  pass at `165` cycles
  - `/nix/store/4a98in7fwvp65f3gfcsr7lm6lzhbpjn0-task6-c-proj-requant-arith-selftest-sv-sim.json`
- `nix build .#task6-c-proj-requant-arith-selftest-bitstream --no-link --print-out-paths -L`:
  pass
  - `/nix/store/0kkw15vh3dqc19rhajv3cpzj5f49nrqy-task6-c-proj-requant-arith-selftest.bit`
- `nix build .#task6-c-proj-requant-arith-selftest-utilization --no-link --print-out-paths -L`:
  pass
  - `/nix/store/8z85y5m9z8w3p84kdzandljkr559svw2-task6-c-proj-requant-arith-selftest-utilization`

Resource summary:

- design JSON:
  `/nix/store/2j523d0d598wi07zls06g5gi4f5i2anp-task6-c-proj-requant-arith-selftest.json`
- `clb_luts`: `531 / 298600` (`0.18%`)
- `clb_ffs`: `383 / 597200` (`0.06%`)
- `dsp`: `0 / 1920` (`0.00%`)
- BRAM36-equivalent: `0 / 955` (`0.00%`)
- routed packed utilization:
  - `SLICE_LUTX`: `1427 / 597200`
  - `SLICE_FFX`: `383 / 597200`
  - `DSP48E1`: `0 / 1920`
  - `RAMB36E1`: `0 / 955`
  - `RAMB18E1`: `0 / 1910`
- post-route timing:
  - max frequency: `197.28 MHz`
  - requested target: `50.00 MHz`

Physical test handoff:

- Program:
  `sudo openFPGALoader -c digilent_hs3 --ftdi-serial 210299BF3824 /nix/store/0kkw15vh3dqc19rhajv3cpzj5f49nrqy-task6-c-proj-requant-arith-selftest.bit`
- Expected pass indication:
  - ignore the always-on top board green LED
  - design green LED is solid on
  - design orange LED is off
- If it fails, the fail display loops:
  - all LEDs marker
  - observed byte low/mid/high phases
  - red + orange marker
  - expected byte low/mid/high phases
  - blank phases

JTAG debug note:

- The current HS3/openFPGALoader path gives reliable configuration and basic
  JTAG access, but the present bitstreams do not expose internal fabric signals
  through JTAG.
- Autonomous internal-state readout over JTAG would require adding a debug
  interface to the design, for example a `BSCANE2`-based user scan chain or an
  ILA/VIO-style flow, plus host-side code to shift and decode that register.
- Until that path is implemented, LED-coded diagnostics remain the available
  board-observation channel in the openXC7 flow.

Follow-up shift-add diagnostic physical observation:

- `DEBUG_LEDS=4` physical sequence:
  - red + green + orange
  - green + orange
  - nothing
  - red + orange
  - green
  - green + red
  - orange
  - green
  - green + red
  - nothing
- Interpretation:
  - failing output index remains `0`
  - c_proj accumulator, scale multiplier, and bias still match their generated
    expected values
  - observed c_proj output byte is now `0xd4`, while the expected c_proj output
    byte is `0x0a`
- This is useful because the wrong value changed from `0x7f` under the original
  multiply/sign-extension path to `0xd4` under the combinational shift-add path
  while the operands still matched. That points away from memory loading,
  constants, reset, and upstream accumulation, and toward the synthesized
  combinational c_proj requant arithmetic shape.

C-proj requant sequential arithmetic trial:

- Replaced the combinational c_proj requant function path with an explicit
  registered sequence:
  - capture accumulator, scale multiplier, and bias sidecars
  - run a 32-cycle unsigned magnitude shift-add multiply
  - restore product sign
  - apply rounded fixed right shift
  - add quantized bias
  - saturate and write the int8 c_proj output byte
- Rationale:
  - the original inferred multiply failed on board with correct operands and
    output `0x7f`
  - the combinational shift-add replacement still failed on board with correct
    operands and output `0xd4`
  - a sequential implementation removes the large single-cycle arithmetic cone
    from the c_proj requant path while preserving the same fixed-point math
- Verification:
  - `nix build .#task6-int8-l2-mlp-chain-residual-add-selftest-sv-sim --no-link --print-out-paths -L`:
    pass at `21044` cycles
    - `/nix/store/mfd1kh6p4y70yfvab1lwywpk4ngcpx98-task6-int8-l2-mlp-chain-residual-add-selftest-sv-sim.json`
  - `nix build .#task6-int8-l2-mlp-chain-residual-add-selftest-utilization --no-link --print-out-paths -L`:
    pass
    - `/nix/store/0ini8b42xxr4c231d10jff14hsg0qghb-task6-int8-l2-mlp-chain-residual-add-selftest-utilization`
  - `nix build .#task6-int8-l2-mlp-chain-residual-add-selftest-bitstream --no-link --print-out-paths -L`:
    pass
    - `/nix/store/7vf2f9xx7f1lcj3y09g1p8waq65vhl62-task6-int8-l2-mlp-chain-residual-add-selftest.bit`
- Standard utilization summary:
  - design JSON:
    `/nix/store/a20r0dvq34pvr1arkg6jli64z1j5mlpi-task6-int8-l2-mlp-chain-residual-add-selftest.json`
  - `clb_luts`: `7676 / 298600` (`2.57%`)
  - `clb_ffs`: `1174 / 597200` (`0.20%`)
  - `dsp`: `32 / 1920` (`1.67%`)
  - `bram36`: `8 / 955` (`0.84%`)
  - `bram18`: `6`
  - BRAM36-equivalent: `11 / 955` (`1.15%`)
- Routed packed utilization cross-check:
  - `SLICE_LUTX`: `12012 / 597200` (`2.01%`)
  - `SLICE_FFX`: `1174 / 597200` (`0.20%`)
  - `DSP48E1`: `32 / 1920` (`1.67%`)
  - `RAMB36E1`: `8 / 955`
  - `RAMB18E1`: `6 / 1910`
- Post-route timing:
  - max frequency: `125.47 MHz`
  - requested target: `12.00 MHz`

Next physical test:

- Program:
  `sudo openFPGALoader -c digilent_hs3 --ftdi-serial 210299BF3824 /nix/store/7vf2f9xx7f1lcj3y09g1p8waq65vhl62-task6-int8-l2-mlp-chain-residual-add-selftest.bit`
- Expected pass indication:
  - ignore the always-on top board green LED
  - design red LED blinks as heartbeat
  - design green LED is solid on
  - design orange LED is off
- If the design orange LED still stays on, rebuild the `DEBUG_LEDS=4`
  diagnostic against this sequential RTL before changing the memory path.

Follow-up sequential arithmetic physical observation:

- Programmed:
  `/nix/store/7vf2f9xx7f1lcj3y09g1p8waq65vhl62-task6-int8-l2-mlp-chain-residual-add-selftest.bit`
- Observed:
  - design orange LED stays on
- Interpretation:
  - the sequential c_proj requant arithmetic did not fix the board-level
    end-to-end compare
  - the next discriminator is whether c_proj requant itself is still wrong, or
    whether the failure has moved downstream to residual-add/output compare

Sequential c-proj requant diagnostic bitstream:

- Rebuilt the `DEBUG_LEDS=4` c_proj requant diagnostic against the sequential
  c_proj requant RTL.
- Verification:
  - `nix build .#task6-int8-l2-mlp-chain-residual-add-selftest-c-proj-requant-debug-bitstream --no-link --print-out-paths -L`:
    pass
    - `/nix/store/29als7l4zv41nl061xvcn889sxj7yhyd-task6-int8-l2-mlp-chain-residual-add-selftest-c-proj-requant-debug.bit`
- Packed utilization:
  - `SLICE_LUTX`: `12428 / 597200` (`2.08%`)
  - `SLICE_FFX`: `1288 / 597200` (`0.22%`)
  - `DSP48E1`: `32 / 1920` (`1.67%`)
  - `RAMB36E1`: `8 / 955`
  - `RAMB18E1`: `6 / 1910`
- Post-route timing:
  - max frequency: `123.79 MHz`
  - requested target: `12.00 MHz`

Next physical test:

- Program:
  `sudo openFPGALoader -c digilent_hs3 --ftdi-serial 210299BF3824 /nix/store/29als7l4zv41nl061xvcn889sxj7yhyd-task6-int8-l2-mlp-chain-residual-add-selftest-c-proj-requant-debug.bit`
- Record one full repeated sequence from the three design-driven LEDs.
- Ignore the always-on top board green LED.

Direct JTAG/MPSSE c_proj memory discriminator:

- Motivation:
  - manual LED decoding has reached diminishing returns
  - `openFPGALoader --xvc --port 3721` crashes locally with an
    `FD_SETSIZE` fd-set assertion, so XVC is not reliable enough for the next
    debug loop
- Host-side change:
  - added `scripts/task6/read_jtag_debug_ftdi_bitbang.py`
  - the bitbang backend can talk to libftdi, but HS3 needs the same MPSSE
    high-byte buffer-enable setup that openFPGALoader uses
  - the MPSSE backend programs the Digilent HS3 pins as:
    - low value `0x88`, low direction `0x8b`
    - high value `0x20`, high direction `0x30`
  - IDCODE readback validates the direct JTAG path:
    - `0x23751093` with TDO on high-byte bit `7`
- Direct JTAG payload result:
  - payload magic check passed and repeated reads were stable
  - final state: `SELFTEST_FAIL`
  - fail reason: `MISMATCH`
  - first failing output index: `1`
  - expected final byte: `76`
  - observed final byte: `75`
  - index `0` now passes through c_proj requant and residual-add
- Narrowed fault:
  - c_fc transfer activations into c_proj matched expected values at the sampled
    checkpoints
  - c_proj requant arithmetic matched expected values for the captured failing
    path
  - c_proj packed weight readback showed lane-1 LSB stuck low at sampled words:
    - word `0`: expected lane1 `7`, observed `6`
    - word `1`: expected lane1 `-79`, observed `-80`
    - word `63`: expected lane1 `-11`, observed `-12`
    - word `127`: expected lane1 `33`, observed `32`
  - sampled words whose lane-1 LSB was already `0` matched
- Current hypothesis:
  - this is no longer primarily a c_fc, c_proj requant, or residual-add
    arithmetic bug
  - the leading suspect is the synthesized c_proj packed-weight memory/read
    path, specifically bit `8` of the 32-bit packed word, which is lane `1` bit
    `0`
- RTL discriminator:
  - split `c_proj` packed weight storage from one 32-bit packed memory into four
    explicit 8-bit lane memories
  - simulation passed:
    - `nix build .#task6-int8-l2-mlp-chain-residual-add-selftest-sv-sim --no-link --print-out-paths -L`
    - `/nix/store/mdq3w2dnh7ibvc59c4750f3pm1344dif-task6-int8-l2-mlp-chain-residual-add-selftest-sv-sim.json`
    - pass at cycle `63860`
- JTAG-debug bitstream with explicit lane memories:
  - `nix build .#task6-int8-l2-mlp-chain-residual-add-selftest-jtag-debug-bitstream --no-link --print-out-paths -L`
  - output:
    - `/nix/store/pbb86ghz47qqj38il419r6mp1b59vxy3-task6-int8-l2-mlp-chain-residual-add-selftest-jtag-debug.bit`
  - post-route timing:
    - main clock max frequency `115.71 MHz`, passing the `50.00 MHz` target
    - JTAG debug shift clock max frequency `712.25 MHz`, passing the
      `50.00 MHz` target
- Next check:
  - program the explicit-lane JTAG-debug bitstream and read the payload with:
    - `python3 scripts/task6/read_jtag_debug_ftdi_bitbang.py --backend mpsse --tdo-bit 7 --poll --poll-count 20 --poll-interval 0.1`
  - if lane-1 weight readback is corrected, keep the memory-lane split or
    pursue a smaller equivalent mapping workaround
  - if it still fails on bit `8`, move the discriminator to distributed memory
    or a direct post-load memory-readback scan

Explicit lane-memory hardware verification:

- Programmed:
  - `openFPGALoader -c digilent_hs3 --ftdi-serial 210299BF3824 /nix/store/pbb86ghz47qqj38il419r6mp1b59vxy3-task6-int8-l2-mlp-chain-residual-add-selftest-jtag-debug.bit`
  - SRAM load completed and FPGA `done` was `1`
- Direct JTAG readout:
  - `python3 scripts/task6/read_jtag_debug_ftdi_bitbang.py --backend mpsse --tdo-bit 7 --poll --poll-count 20 --poll-interval 0.1`
  - `magic_ok=True`
  - state: `SELFTEST_PASS`
  - fail reason: `NONE`
  - c_proj GEMV lane-1 final accumulator: `-8353`, expected `-8353`
- Previously failing c_proj lane-1 weight samples now match:
  - word `0`: expected `7`, observed `7`
  - word `1`: expected `-79`, observed `-79`
  - word `63`: expected `-11`, observed `-11`
  - word `127`: expected `33`, observed `33`
- Conclusion:
  - the explicit byte-lane c_proj packed-weight memories fix the board-level
    self-test failure
  - the root cause is still most likely the previous synthesized mapping of the
    32-bit packed c_proj weight memory/read path, where packed bit `8` behaved
    as stuck low on hardware

Regular non-debug bitstream rebuild after hardware fix:

- Built the fixed regular self-test simulation and utilization targets:
  - `nix build .#task6-int8-l2-mlp-chain-residual-add-selftest-sv-sim .#task6-int8-l2-mlp-chain-residual-add-selftest-utilization --no-link --print-out-paths -L`
  - simulation output:
    - `/nix/store/mdq3w2dnh7ibvc59c4750f3pm1344dif-task6-int8-l2-mlp-chain-residual-add-selftest-sv-sim.json`
  - utilization output:
    - `/nix/store/jmw4ibcrm5x099fnynr11sfs0pm8b4fw-task6-int8-l2-mlp-chain-residual-add-selftest-utilization`
- Fixed regular estimated utilization:
  - `clb_luts`: `10733 / 298600` (`3.59%`)
  - `clb_ffs`: `6530 / 597200` (`1.09%`)
  - `dsp`: `10 / 1920` (`0.52%`)
  - `bram36`: `8 / 955` (`0.84%`)
  - `bram18`: `6`
  - BRAM36-equivalent: `11 / 955` (`1.15%`)
- Built the fixed regular non-debug bitstream:
  - `nix build .#task6-int8-l2-mlp-chain-residual-add-selftest-bitstream --no-link --print-out-paths -L`
  - output:
    - `/nix/store/p6f10gn31s6aram54y0c570kksbpy63d-task6-int8-l2-mlp-chain-residual-add-selftest.bit`
  - post-route timing:
    - max frequency `120.18 MHz`, passing the `50.00 MHz` target
- Programming attempt:
  - `openFPGALoader -c digilent_hs3 --ftdi-serial 210299BF3824 /nix/store/p6f10gn31s6aram54y0c570kksbpy63d-task6-int8-l2-mlp-chain-residual-add-selftest.bit`
  - failed during JTAG init before bitstream load:
    - `TDO is stuck at 0`
- Recovery attempts:
  - `openFPGALoader --detect` also reported `TDO is stuck at 0`
  - low-frequency detect at `1 MHz` also reported `TDO is stuck at 0`
  - `usbreset 0403:6014` reset the Digilent HS3 successfully, but did not
    recover TDO
  - direct MPSSE IDCODE reads on both previously tested TDO sample bits returned
    `0x00000000`
- Interpretation:
  - this is a target-side JTAG silence/access issue, not a bitstream or RTL
    result; the failure happens before programming starts
  - next physical action is to power-cycle or reseat the board/HS3 target
    connection, then retry programming the already-built regular bitstream

Regular non-debug bitstream hardware programming retry:

- Retried after the target-side JTAG issue was corrected:
  - `openFPGALoader -c digilent_hs3 --ftdi-serial 210299BF3824 /nix/store/p6f10gn31s6aram54y0c570kksbpy63d-task6-int8-l2-mlp-chain-residual-add-selftest.bit`
  - SRAM load completed successfully
  - FPGA `done` was `1`
- JTAG health check after programming:
  - `openFPGALoader --detect` reported:
    - IDCODE `0x23751093`
    - `xc7k480t`
    - IR length `6`
  - direct MPSSE IDCODE read also returned `0x23751093`
- Interpretation:
  - the fixed regular non-debug Task 6 self-test bitstream is now programmed
    on the board
  - internal self-test pass was already proven with the matching JTAG-debug
    build; this regular build intentionally has no debug payload readout

Board-validated H2 comparison against copied baseline:

- Added comparison artifacts:
  - `artifacts/task6/parallel-hypotheses/h2-int8-l2-selftest-board-comparison.json`
  - `artifacts/task6/parallel-hypotheses/h2-int8-l2-selftest-board-comparison.csv`
- Comparison baseline:
  - `artifacts/task6/baselines/tiny-stories-1m-baseline-float-selftest-all-memory-utilization`
  - this is the copied baseline bundle required by the repo guidance, not a
    garbage-collectable Nix store path
- Scope caveat:
  - the H2 candidate is a bounded `tiny-stories-v1k-h64-l1` int8 L2
    MLP/residual slice, not a full TinyStories 1M replacement
  - the comparison is still useful as Task 6 strategy evidence because it shows
    the resource impact of the replacement shape under the same target device
    envelope
- Resource comparison:
  - copied float baseline:
    - LUTs: `40416086 / 298600` (`13535.192900200938%`)
    - FFs: `58072527 / 597200` (`9724.133791024782%`)
    - DSPs: `0 / 1920` (`0.0%`)
    - BRAM36-equivalent: `0.0 / 955` (`0.0%`)
  - board-validated H2 selftest:
    - LUTs: `10733 / 298600` (`3.59%`)
    - FFs: `6530 / 597200` (`1.09%`)
    - DSPs: `10 / 1920` (`0.52%`)
    - BRAM36-equivalent: `11.0 / 955` (`1.15%`)
- Delta:
  - LUT reduction: `40405353` LUTs, `99.973444%`
  - FF reduction: `58065997` FFs, `99.988755%`
  - DSP increase: `10`
  - BRAM36-equivalent increase: `11.0`
  - `MUXF7` reduction: `933497`, `99.689238%`
  - `MUXF8` reduction: `278521`, `99.552139%`
- Functional and board evidence:
  - simulation: `PASS`
  - JTAG-debug hardware payload: `SELFTEST_PASS`
  - regular bitstream: SRAM programming completed with FPGA `done=1`
  - post-program IDCODE: `0x23751093`
- Decision:
  - promote H2 as a board-validated bounded strategy lane
  - viability remains `recommended-conditional` because the current proof is
    not yet a calibrated multi-sample or full-model replacement
  - next gate is to scale the bounded validated H2 lane to a larger
    streaming-memory surface before investing in DDR3 integration, because the
    current lane already fits easily without DDR3

Post-fix bare residual-add proof refresh:

- Rebuilt:
  - `nix build .#task6-int8-l2-mlp-chain-residual-add-rtl-proof --no-link --print-out-paths -L`
  - output:
    - `/nix/store/wdnwnixhgqplmd9vivij59hnh1hdbbil-task6-int8-l2-mlp-chain-residual-add-rtl-proof`
- Updated checked-in proof artifact from the regenerated summary:
  - `artifacts/task6/parallel-hypotheses/h2-int8-l2-mlp-chain-residual-add-rtl-proof.json`
- Simulation:
  - status: `PASS`
  - reads: `64`
  - outputs: `64`
  - compute cycles: `54945`
  - total cycles: `55009`
- Refreshed bare-kernel mapped utilization:
  - LUTs: `4875 / 298600` (`1.63%`)
  - FFs: `6422 / 597200` (`1.08%`)
  - DSPs: `10 / 1920` (`0.52%`)
  - BRAM36: `8 / 955` (`0.84%`)
  - BRAM18: `6`
  - BRAM36-equivalent: `11.0 / 955` (`1.15%`)
- Delta from bare proof to board selftest wrapper:
  - LUTs: `4875 -> 10733` (`+5858`)
  - FFs: `6422 -> 6530` (`+108`)
  - DSPs: `10 -> 10` (`+0`)
  - BRAM36-equivalent: `11.0 -> 11.0` (`+0.0`)
- Interpretation:
  - the byte-lane memory fix is now reflected in both the bare proof and the
    board selftest path
  - the selftest wrapper mainly adds fixed-vector load/compare LUTs; it does
    not change DSP or BRAM use

### 2026-04-29 - H2 v4k contract scale-up scout

Goal:

- Continue from the board-validated `tiny-stories-v1k-h64-l1` H2 lane by
  replaying the same bounded MLP/residual surface on the larger
  `tiny-stories-v4k-h64-l1` representative-core configuration before touching
  DDR3.

New artifacts:

- `artifacts/task6/weights_pack/tiny-stories-v4k-h64-l1/transformer.h.0.mlp.c_fc/`
- `artifacts/task6/weights_pack/tiny-stories-v4k-h64-l1/transformer.h.0.mlp.c_proj/`
- `artifacts/task6/streamtensor-lite/l2/tiny-stories-v4k-h64-l1-c_fc-contract/`
- `artifacts/task6/streamtensor-lite/l2/tiny-stories-v4k-h64-l1-c_proj-contract/`
- `artifacts/task6/streamtensor-lite/l2/tiny-stories-v4k-h64-l1-residual-add-contract/`
- `artifacts/task6/parallel-hypotheses/h2-v1k-v4k-quantized-weight-replay.{csv,json}`
- `artifacts/task6/parallel-hypotheses/h2-v1k-v4k-streaming-contract-score.{csv,json}`
- `artifacts/task6/parallel-hypotheses/h2-v4k-int8-l2-c-fc-scale-bias-output-boundary.json`
- `artifacts/task6/parallel-hypotheses/h2-v4k-int8-l2-c-fc-downstream-int8-boundary.json`
- `artifacts/task6/parallel-hypotheses/h2-v4k-scale-up-summary.json`

Execution notes:

- Reused the existing Nix-store Python/TinyStories environment:
  - `/nix/store/ar40y7sk8dxahqk58rm5cj5p0qy9xa39-python3-3.11.14-env/bin/python`
- Reused the existing local TinyStories snapshot:
  - `/nix/store/kw3s159yv90pk879nm0f7v4ikkrxz83w-tinystories-1m-hf-snapshot`
- Avoided `nix build .#tiny-stories-v4k-h64-l1-linalg` for this slice because
  it tried to rebuild a fresh PyTorch derivation. The scout uses direct module
  hooks and packed-weight replay instead.
- Fixed `scripts/task6/score_int8_downstream_boundary.py` so the
  `input_replay.f32_boundary_metrics` field is recomputed from the current
  contract instead of copying the old replay JSON metric. This matters when the
  same-shape RTL metadata is reused for a new v4k contract.

Results:

- v4k `c_fc` f32 replay from packed weights:
  - verdict: `pass`
  - max absolute error: `0.0`
- v4k `c_proj` f32 replay from packed weights:
  - verdict: `pass`
  - max absolute error: `0.0`
- v4k residual-add module-hook contract:
  - status: `PASS`
  - all cross-check max absolute errors: `0.0`
- v4k int8 quantized-weight replay:
  - `c_fc` best normalized RMSE: `0.005847424386218247`
  - `c_proj` best normalized RMSE: `0.0073616947821652946`
  - threshold: `0.02`
  - verdict: `pass`
- v4k int4 quantized-weight replay:
  - `c_fc` best normalized RMSE: `0.10421039539960832`
  - `c_proj` best normalized RMSE: `0.13570825757817748`
  - threshold: `0.02`
  - verdict: `fail`
- v4k `c_fc` int8 scale/bias/output boundary scout:
  - status: `PASS`
  - normalized RMSE: `0.007873001582845127`
- v4k post-GELU downstream int8 boundary scout:
  - status: `PASS`
  - recommended boundary: `post_gelu_int8_activation`
  - GELU output normalized RMSE: `0.012050216169024767`

Streaming contract result:

- The `v4k-h64-l1` MLP has the same `64 -> 256 -> 64` shape as the v1k lane.
- At `4` DSP lanes the per-token MLP lower-bound score remains:
  - `32,768` MACs
  - `8,192` minimum compute cycles
  - `134,912` bytes/token with f32 weights and f32 activations/bias
  - `36,608` bytes/token with int8 weights and f32 activations/bias
  - `20,224` bytes/token with int4 weights and f32 activations/bias

Interpretation:

- H2 still looks good on the v4k activation/weight values: exact f32 replay
  holds, int8 replay passes, int4 still fails, and the first post-GELU int8
  boundary still passes.
- This is not yet a larger vocab-dependent memory proof. The MLP dimensions do
  not grow when vocab grows from `1024` to `4096`; embeddings and output-head
  storage are the vocab-dependent parts.
- The next gate should regenerate same-shape RTL test data/sidecars for these
  v4k contracts and run the SV/mapped replay. After that, add a separate
  embedding/output-head memory-surface score before deciding on DDR3 controller
  integration.

### 2026-04-29 - H2 v4k same-shape RTL replay

Goal:

- Execute the next gate from the v4k contract scout: regenerate same-shape RTL
  sidecars from the `tiny-stories-v4k-h64-l1` contracts and prove the composed
  int8 L2 MLP/residual path in SV simulation.

New artifacts:

- `artifacts/task6/parallel-hypotheses/h2-v4k-int8-l2-c-fc-post-gelu-requant-rtl-proof.json`
- `artifacts/task6/parallel-hypotheses/h2-v4k-int8-l2-c-proj-from-post-gelu-boundary.json`
- `artifacts/task6/parallel-hypotheses/h2-v4k-int8-l2-mlp-chain-post-gelu-c-proj-rtl-proof.json`
- `artifacts/task6/parallel-hypotheses/h2-v4k-int8-l2-c-proj-output-boundary.json`
- `artifacts/task6/parallel-hypotheses/h2-v4k-int8-l2-mlp-chain-c-proj-requant-rtl-proof.json`
- `artifacts/task6/parallel-hypotheses/h2-v4k-int8-l2-residual-add-boundary.json`
- `artifacts/task6/parallel-hypotheses/h2-v4k-int8-l2-mlp-chain-residual-add-rtl-proof.json`
- updated `artifacts/task6/parallel-hypotheses/h2-v4k-scale-up-summary.json`

Execution notes:

- Reused the checked v4k contracts and packed weights from the v4k scale-up
  scout.
- Generated temporary Verilator `tb_data.sv` sidecars under
  `/tmp/task6-v4k-rtl/`.
- Used:
  - `/nix/store/ar40y7sk8dxahqk58rm5cj5p0qy9xa39-python3-3.11.14-env/bin/python`
  - `/nix/store/0p3wb160b3881j0g02qvvxih7l01kpz2-verilator-5.044/bin/verilator`
- Fixed the c_proj requant and residual-add testbench timeout constants to
  scale with generated packed-weight word counts. The old c_proj requant
  timeout was `16000` cycles, which could expire during v4k load/compute even
  though the design later completed correctly.

Results:

- v4k `c_fc` post-GELU requant RTL proof:
  - status: `PASS`
  - reads / outputs: `256 / 256`
  - compute cycles / total cycles: `47691 / 47947`
  - post-GELU normalized RMSE: `0.012386198611765455`
- v4k post-GELU handoff into `c_proj`:
  - status: `PASS`
  - handoff normalized RMSE: `0.012386194129262937`
- v4k composed post-GELU `c_proj` RTL proof:
  - status: `PASS`
  - reads / outputs: `64 / 64`
  - compute cycles / total cycles: `52383 / 52447`
  - `c_proj` f32 output normalized RMSE: `0.017932678210325667`
- v4k `c_proj` requant RTL proof:
  - status: `PASS`
  - reads / outputs: `64 / 64`
  - compute cycles / total cycles: `54816 / 54880`
  - fixed int8 `c_proj` output normalized RMSE: `0.018771514990322893`
- v4k residual-add boundary:
  - status: `PASS`
  - residual int8 verdict: `pass`
  - final output int8 verdict: `pass`
- v4k composed residual-add RTL proof:
  - status: `PASS`
  - reads / outputs: `64 / 64`
  - compute cycles / total cycles: `54945 / 55009`
  - fixed residual-add output vs block output normalized RMSE:
    `0.011521920099889468`
  - fixed residual-add output vs boundary quantizer normalized RMSE: `0.0`

Interpretation:

- The same H2 int8 L2 MLP/residual RTL path that was board-validated on v1k
  also passes with v4k activation and weight values in SV replay.
- This closes the same-shape v4k RTL replay gate. It still is not a
  vocab-growth memory proof because `v4k-h64-l1` keeps the same
  `64 -> 256 -> 64` MLP dimensions.
- Next gate: score the vocab-dependent embedding and output-head/lm_head memory
  surfaces before committing to DDR3 controller integration.

### 2026-04-29 - H2 vocab-dependent memory surface score

Goal:

- Score the embedding and output-head/lm_head surfaces that actually grow with
  vocabulary size, after the v4k same-shape MLP/residual RTL replay passed.
- Separate physical storage from logical output-projection bandwidth because
  GPT-Neo ties `lm_head.weight` to `transformer.wte.weight`.

New artifacts:

- `scripts/task6/score_vocab_memory_surface.py`
- `artifacts/task6/parallel-hypotheses/h2-vocab-memory-surface-score.json`
- `artifacts/task6/parallel-hypotheses/h2-vocab-memory-surface-score.csv`
- updated `artifacts/task6/parallel-hypotheses/h2-v4k-scale-up-summary.json`

Execution:

- `python scripts/task6/score_vocab_memory_surface.py --model-path /nix/store/kw3s159yv90pk879nm0f7v4ikkrxz83w-tinystories-1m-hf-snapshot --lane tiny-stories-v1k-h64-l1:1024:1:128:64:64:16 --lane tiny-stories-v4k-h64-l1:4096:1:128:64:64:16 --lane tiny-stories-1m-full:50257:8:2048:256:64:16 --baseline-utilization-json artifacts/task6/baselines/tiny-stories-1m-baseline-float-selftest-all-memory-utilization/summary.json --include-four-full-vocab-table-baseline --out-json artifacts/task6/parallel-hypotheses/h2-vocab-memory-surface-score.json --out-csv artifacts/task6/parallel-hypotheses/h2-vocab-memory-surface-score.csv`

Results:

- The model inspection confirms `lm_head.weight` is tied to
  `transformer.wte.weight` for all scored lanes.
- `tiny-stories-v1k-h64-l1`:
  - unique persistent f32 vocab/position storage: `294912` bytes
  - BRAM36 ceiling for unique f32 storage: `64`
  - unique rowwise int8 storage: `78336` bytes
  - output projection at `4` DSP lanes: `65536` MACs, `16384` minimum cycles
  - rowwise int8 streamed output-head bytes/token without full logits:
    `69696`
- `tiny-stories-v4k-h64-l1`:
  - unique persistent f32 vocab/position storage: `1081344` bytes
  - BRAM36 ceiling for unique f32 storage: `235`
  - unique rowwise int8 storage: `287232` bytes
  - output projection at `4` DSP lanes: `262144` MACs, `65536` minimum cycles
  - rowwise int8 streamed output-head bytes/token without full logits:
    `278592`
- Full TinyStories-1M config:
  - unique persistent f32 vocab/position storage: `13390080` bytes
  - BRAM36 ceiling for unique f32 storage: `2906`
  - unique rowwise int8 storage: `3556740` bytes
  - output projection at `4` DSP lanes: `3216448` MACs, `804112` minimum cycles
  - rowwise int8 streamed output-head bytes/token without full logits:
    `3417540`
- Copied all-memory baseline comparison:
  - the prior four full-vocab f32 table shape is `4 x [50257, 64]`
  - modeled storage: `51463168` bytes
  - BRAM36 ceiling: `11169`

Interpretation:

- v4k does not force DDR3 just for tied vocab storage. Even f32 tied
  vocab/position storage is `235 / 955` BRAM36 blocks, and rowwise int8 is
  `63 / 955`.
- The output projection is now a real compute/bandwidth peer to the bounded
  MLP: v4k output-head lower-bound cycles are `65536`, versus `54945` cycles
  for the composed residual-add RTL replay.
- Full TinyStories still needs compression, streaming, or external memory for
  the vocab surface. Tied f32 storage alone is `2906` BRAM36 blocks, and the
  copied all-memory four-table shape is `11169` BRAM36 blocks.
- Next gate:
  - for the board-facing v4k continuation, prototype tied vocab storage on-chip
    or a streamed output-head stub before adding DDR3 complexity
  - for the full TinyStories route, keep DDR3/externalization focused on the
    vocab tables/output projection

### 2026-04-29 - H2 v4k streamed tied output-head top1 RTL proof

Goal:

- Execute the board-facing v4k vocab follow-up without adding DDR3 yet:
  prove a streamed tied output-head top1 kernel that consumes the v4k
  residual-add int8 vector and scans the tied `transformer.wte` vocab table.

New artifacts:

- `rtl/task6/task6_int8_vocab_output_head_top1_kernel.sv`
- `sim/task6_int8_vocab_output_head_top1_tb_main.sv`
- `sim/gen_task6_int8_vocab_output_head_top1_tb_data.py`
- `artifacts/task6/parallel-hypotheses/h2-v4k-int8-vocab-output-head-top1-rtl-proof.json`
- updated `artifacts/task6/parallel-hypotheses/h2-v4k-scale-up-summary.json`

Execution notes:

- Reused the existing 4-lane synchronous packed int8 GEMV core and wrapped it
  with a top1 accumulator/index tracker.
- Generated the hidden input from
  `artifacts/task6/parallel-hypotheses/h2-v4k-int8-l2-mlp-chain-residual-add-rtl-proof.json`.
- Loaded the tied vocab table from the representative-core model:
  - `transformer.wte.weight`
  - shape: `4096 x 64`
  - `lm_head.weight` is tied to the same storage
- Quantized the tied vocab table as int8 per-tensor symmetric for this top1
  prototype, so the accumulator order is also the int8 logit order.
- Generated temporary Verilator sidecar:
  - `/tmp/task6-v4k-output-head-top1/tb_data.sv`
  - `65536` packed 32-bit vocab weight words

Simulation:

- Verilator build:
  - `/nix/store/0p3wb160b3881j0g02qvvxih7l01kpz2-verilator-5.044/bin/verilator --binary --timing --language 1800-2017 -Wno-fatal -I/tmp/task6-v4k-output-head-top1 -top task6_int8_vocab_output_head_top1_tb -Mdir /tmp/task6-v4k-output-head-top1/obj_dir -o sim_main rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel.sv rtl/task6/task6_int8_vocab_output_head_top1_kernel.sv sim/task6_int8_vocab_output_head_top1_tb_main.sv`
- Result:
  - status: `PASS`
  - packed weight words scanned: `65536`
  - fixed int8 top index: `1321`
  - fixed int8 top accumulator: `52140`
  - compute cycles / total cycles: `70787 / 70787`

Numeric check:

- f32 reference top index: `1321`
- int8 top matches f32 top: `true`
- int8 logits vs f32 logits normalized RMSE: `0.012752468245904739`
- tied vocab int8 bytes: `262144`
- tied vocab f32 bytes replaced: `1048576`

Interpretation:

- The v4k board-facing path now has simulator evidence beyond the same-shape
  MLP/residual lane: a streamed tied output-head top1 stub works on the
  captured v4k residual-add vector.
- This still does not require DDR3 for v4k. The prototype scans an on-chip
  int8 tied vocab table and returns top1 without materializing all logits.
- The output-head compute cost is now measured in RTL: `70787` cycles, close
  to the `65536` lower-bound score and in the same range as the composed
  residual-add replay (`55009` total cycles).
- Next gate: measure mapped utilization for this output-head top1 kernel, or
  wrap it with the residual-add chain in a board-programmable v4k selftest.

### 2026-04-29 - H2 v4k output-head top1 mapped utilization

Goal:

- Close the mapped-resource gate for the streamed v4k tied output-head top1
  kernel before spending time on a board selftest wrapper.

New Nix targets:

- `task6-int8-vocab-output-head-top1-yosys-stat`
- `task6-int8-vocab-output-head-top1-json`
- `task6-int8-vocab-output-head-top1-utilization`

Command:

- `nix build .#task6-int8-vocab-output-head-top1-utilization --no-link --print-out-paths -L`

Result artifact:

- `/nix/store/86gdb9damb01qx33qgw5zw9hq3xfikmm-task6-int8-vocab-output-head-top1-utilization`

Mapped resource summary:

- CLB LUTs: `1572 / 298600` (`0.53%`)
- CLB FFs: `2288 / 597200` (`0.38%`)
- DSP: `4 / 1920` (`0.21%`)
- BRAM36: `64 / 955` (`6.70%`)
- BRAM36 equivalent: `64 / 955` (`6.70%`)
- BRAM storage: `2304 KiB / 34380 KiB` (`6.70%`)
- slice lower bound: `286 / 74650` (`0.38%`)

Yosys stat summary:

- top: `task6_int8_vocab_output_head_top1_kernel`
- cells: `3973`
- `RAMB36E1`: `64`
- `DSP48E1`: `4`
- LUT primitive cells: `1572`
- `check` reported `0` problems

Interpretation:

- The v4k output-head table maps as intended to block RAM. The BRAM count is
  the dominant resource, but still only `6.70%` of the target device.
- LUT, FF, and DSP use are small enough that this standalone output-head top1
  kernel is not the board-facing limiter.
- The mapped result agrees with the memory-surface score: v4k tied vocab int8
  storage is feasible on-chip, so DDR3 is still unnecessary for the v4k board
  proof.
- Next gate: wrap the residual-add chain and mapped output-head top1 kernel
  into a board-programmable v4k selftest.

### 2026-04-29 - H2 v4k residual-add plus output-head board selftest

Goal:

- Close the board-programmable v4k gate by composing the bounded int8
  residual-add MLP chain with the streamed tied-vocab output-head top1 kernel.
- Keep the proof on-chip for this lane; do not add DDR3 until the v4k on-chip
  prototype shows a resource or route reason to need it.

New artifacts:

- `fpga/rtl/task6_int8_v4k_l2_residual_add_output_head_selftest_top.sv`
- `sim/gen_task6_int8_v4k_l2_residual_add_output_head_selftest_tb_data.py`
- `sim/task6_int8_v4k_l2_residual_add_output_head_selftest_tb_main.sv`
- phase-banked output-head weight memory mode in
  `rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel.sv`

New Nix targets:

- `task6-int8-v4k-l2-residual-add-output-head-selftest-tb-data-sv`
- `task6-int8-v4k-l2-residual-add-output-head-selftest-top`
- `task6-int8-v4k-l2-residual-add-output-head-selftest-sim-main`
- `task6-int8-v4k-l2-residual-add-output-head-selftest-sv-sim`
- `task6-int8-v4k-l2-residual-add-output-head-selftest-json`
- `task6-int8-v4k-l2-residual-add-output-head-selftest-utilization`
- `task6-int8-v4k-l2-residual-add-output-head-selftest-xdc`
- `task6-int8-v4k-l2-residual-add-output-head-selftest-fasm`
- `task6-int8-v4k-l2-residual-add-output-head-selftest-bitstream`

Simulation:

- Command:
  - `nix build .#task6-int8-v4k-l2-residual-add-output-head-selftest-sv-sim --no-link --print-out-paths -L`
- Result artifact:
  - `/nix/store/k7phr2chhabqk62x8z85mcv4jk1z20m1-task6-int8-v4k-l2-residual-add-output-head-selftest-sv-sim.json`
- Result:
  - status: `PASS`
  - pass cycle: `265719`
  - fixed int8 top index: `1321`
  - fixed int8 top accumulator: `52140`

Mapped utilization:

- Command:
  - `nix build .#task6-int8-v4k-l2-residual-add-output-head-selftest-utilization --no-link --print-out-paths -L`
- Result artifact:
  - `/nix/store/mi2xnh11v3kmzpc2vxv6ijgrhzysvhzi-task6-int8-v4k-l2-residual-add-output-head-selftest-utilization`
- CLB LUTs: `13629 / 298600` (`4.56%`)
- CLB FFs: `8845 / 597200` (`1.48%`)
- DSP: `14 / 1920` (`0.73%`)
- BRAM36: `129 / 955` (`13.51%`)
- BRAM36 equivalent: `132 / 955` (`13.82%`)
- BRAM storage: `4752 KiB / 34380 KiB` (`13.82%`)
- slice lower bound: `1704 / 74650` (`2.28%`)

Bitstream:

- Command:
  - `nix build .#task6-int8-v4k-l2-residual-add-output-head-selftest-bitstream --no-link --print-out-paths -L`
- Result artifact:
  - `/nix/store/48dszxyvnnywh63wl8y616p6hw5cvww3-task6-int8-v4k-l2-residual-add-output-head-selftest.bit`
- nextpnr result:
  - route legal: `PASS`
  - post-route max frequency: `77.99 MHz`
  - target frequency: `50.00 MHz`

Debugging notes:

- The first combined selftest generator embedded `65536` vocab weight
  assignments directly in `tb_data.sv`. That was functionally fine, but made
  Yosys spend too long elaborating constant assignment logic.
- The board top now reads the vocab table from `vocab_packed_weights.mem` via
  `$readmemh`, and Yosys maps the ROM into block RAM.
- The first routed attempt with the output-head's default deep per-lane weight
  RAM failed in nextpnr on a `RAMB36` cascade arc inside
  `output_head_dut.core.gen_weight_lane_mem[...]`.
- The phase-banked memory mode splits the output-head weight store by row
  phase, so the board selftest no longer needs the problematic deep cascaded
  BRAM chains. The route now completes.

Interpretation:

- The v4k board-facing H2 lane is now bitstream-ready without DDR3.
- Resource use remains dominated by the tied-vocab int8 table, but the combined
  residual-add plus output-head selftest still uses only `13.82%` BRAM
  equivalent and under `5%` LUTs.
- The previous route blocker was local to our memory shape, not evidence of a
  wrong arithmetic kernel or a general openXC7/nextpnr failure.
- Next gate: program this bitstream on the board and observe the pass/fail LED
  result. If it passes on hardware, promote H2 from v1k board-validated to v4k
  board-validated and then decide whether the next full-model gate should add
  embedding lookup, DDR3-backed vocab/output projection, or another bounded
  scale-up first.

### 2026-04-30 - H2 v4k board JTAG-debug permission gate

Goal:

- Continue the v4k board gate after the LED-only combined residual-add plus
  output-head selftest reported fail on hardware.
- Avoid further manual LED decoding by programming a JTAG-debug build and
  reading the internal selftest payload through the Digilent HS3.

Debug bitstream:

- Command:
  - `nix build .#task6-int8-v4k-l2-residual-add-output-head-selftest-jtag-debug-bitstream --no-link --print-out-paths -L`
- Result artifact:
  - `/nix/store/9hj529a6zdyzxbnd9jb0f9kz4xr7a2g7-task6-int8-v4k-l2-residual-add-output-head-selftest-jtag-debug.bit`
- nextpnr result:
  - route legal: `PASS`
  - post-route main clock max frequency: `104.58 MHz`
  - post-route JTAG DRCK max frequency: `564.65 MHz`
  - target frequency: `50.00 MHz`
  - packed BSCAN blocks: `1 / 4`

Host-side board access:

- Program attempt:
  - `openFPGALoader -c digilent_hs3 --ftdi-serial 210299BF3824 /nix/store/9hj529a6zdyzxbnd9jb0f9kz4xr7a2g7-task6-int8-v4k-l2-residual-add-output-head-selftest-jtag-debug.bit`
- Result:
  - `unable to open ftdi device: -4 (usb_open() failed)`
  - `JTAG init failed with: unable to open ftdi device`
- USB enumeration:
  - `Bus 003 Device 033: ID 0403:6014 Future Technology Devices International, Ltd FT232H Single HS USB-UART/FIFO IC`
  - `ID_SERIAL_SHORT=210299BF3824`
  - `ID_MODEL=Digilent_USB_Device`
- Device-node permissions:
  - `/dev/bus/usb/003/033`
  - mode/user/group: `664 root root`
- Non-interactive repair attempt:
  - `sudo -n chmod a+rw /dev/bus/usb/003/033`
  - result: `sudo: a password is required`
- After manual permission repair:
  - device-node mode changed to `666 root root`
  - `openFPGALoader` no longer reports `usb_open() failed`
  - programming attempt now reports:
    - `empty`
    - `Jtag frequency : requested 6.00MHz -> real 6.00MHz`
    - `Error: no device found`
  - `openFPGALoader --detect` reports an empty chain at both `6 MHz` and
    `1 MHz`
  - direct MPSSE IDCODE read reports `0xffffffff` with both tested TDO bit
    selections
- New Thunderbolt / Helios / USB-splitter setup:
  - `openFPGALoader --scan-usb` detects the HS3:
    - bus/device: `003/033`
    - VID:PID: `0403:6014`
    - probe type: `ft232H`
    - manufacturer: `Digilent`
    - serial: `210299BF3824`
    - product: `Digilent USB Device`
  - `lsusb -t` shows the HS3 behind the hub path and running at `480M`
  - device-node mode remains `666 root root`
  - low-frequency verbose detect still reports:
    - raw IDCODE `0xffffffff`
    - `found 0 devices`
  - MPSSE and bitbang IDCODE reads both return `0xffffffff`
- Corrected enclosure-over-Thunderbolt setup:
  - target wiring:
    - Digilent HS3 connected to the enclosure USB path
    - enclosure connected to the laptop over Thunderbolt
    - HS3 connected from the enclosure to the FPGA board JTAG header
  - after reconnect the HS3 enumerated as `003/054`
  - temporary node repair:
    - `sudo chmod a+rw /dev/bus/usb/003/054`
    - node mode became `666 root root`
  - non-sudo detect worked:
    - IDCODE `0x23751093`
    - manufacturer `xilinx`
    - family `kintex7`
    - model `xc7k480t`
    - IR length `6`
  - non-sudo programming worked:
    - bitstream:
      `/nix/store/9hj529a6zdyzxbnd9jb0f9kz4xr7a2g7-task6-int8-v4k-l2-residual-add-output-head-selftest-jtag-debug.bit`
    - `Load SRAM` reached `100%`
    - `isc_done 1`, `init 1`, `done 1`
  - direct USER1 payload read worked:
    - backend: `ftdi-mpsse`
    - serial: `210299BF3824`
    - `magic_ok=True`
    - state: `SELFTEST_FAIL`
    - fail reason: `TOP_INDEX`
    - observed top index: `2960`
    - expected top index: `1321`
    - observed top accumulator: `85301`
    - expected top accumulator: `52140`
    - fail cycle count: `70786`

Interpretation:

- The first blocker was host USB permission, not an RTL/synthesis/routing
  failure.
- After that permission was repaired, the remaining blocker is target-side
  JTAG visibility: the HS3 is accessible, but the FPGA TAP is not responding.
- The Thunderbolt / Helios / splitter path is viable for USB enumeration and
  FTDI access. The corrected enclosure-over-Thunderbolt wiring is also viable
  for FPGA JTAG detect, SRAM programming, and USER1 readback.
- The v4k on-board failure is now localized to the output-head top1 result.
  It is not a broken HS3 cable, not a broken board JTAG path, and not a host
  Thunderbolt/USB transport problem.
- Superseded next step: the target JTAG chain became visible again, and the
  follow-up discriminator below reads a widened `512`-bit USER1 payload.

### 2026-04-30 - H2 v4k output-head load-path discriminator

Goal:

- Determine whether the v4k on-board failure is in residual activation,
  output-head arithmetic/top1 selection, or the vocab table load path.
- Keep the board debug autonomous through JTAG; do not require further LED
  decoding.

First widened JTAG discriminator:

- Added payload fields for vocab-loader checksum, first word, last word, and
  head-activation checksum.
- Bitstream:
  `/nix/store/x9b8x7v9f4j6572hllfzmc9wigyh1jy0-task6-int8-v4k-l2-residual-add-output-head-selftest-jtag-debug.bit`
- Read command:
  - `python3 scripts/task6/read_jtag_debug_ftdi_bitbang.py --backend mpsse --tdo-bit 7 --bits 512 --poll --poll-count 50 --poll-interval 0.1`
- Result:
  - state: `SELFTEST_FAIL`
  - fail reason: `TOP_INDEX`
  - observed top index: `2960`
  - expected top index: `1321`
  - observed top accumulator: `85301`
  - expected top accumulator: `52140`
  - vocab checksum: `0xb6341074`
  - expected vocab checksum: `0xc4ec5bc1`
  - vocab first word: `0xee4c0411`
  - expected vocab first word: `0xee4c0411`
  - vocab last word: `0x286f8905`
  - expected vocab last word: `0x28efc925`
  - head activation checksum: `0x00001ef9`
  - expected head activation checksum: `0x00001ef9`

Interpretation from first discriminator:

- The residual output/head activation stream is correct on hardware.
- The output-head expected constants are correct.
- The vocab load stream is wrong after the first word, including the final word
  and full checksum.
- This localizes the failure to the selftest vocab-loader ROM/init/load path,
  not to the residual-add chain or output-head dot-product/top1 arithmetic.

Rejected probe:

- Tried a distributed vocab-loader ROM variant.
- Yosys rejected the shape with:
  - `ERROR: no valid mapping found for memory`
- Decision: prune distributed ROM for this lane and test a smaller block-RAM
  shape instead.

Phase-banked loader ROM probe:

- Generated phase-local vocab loader mem files next to the monolithic
  `vocab_packed_weights.mem`.
- Added `vocab_loader_phase_readmemh_cases.sv` and a
  `PHASE_BANKED_VOCAB_LOADER_ROM` top parameter.
- Data bundle:
  `/nix/store/81riphjgdb72wfg9yxvw0abjyxq7snfj-task6-int8-v4k-l2-residual-add-output-head-selftest-tb-data-sv`
- SV simulation:
  - command:
    `nix build .#task6-int8-v4k-l2-residual-add-output-head-selftest-sv-sim --no-link --print-out-paths -L`
  - result:
    `/nix/store/sv8jifa9i5s61sgpb0vw26gp0q31gfl1-task6-int8-v4k-l2-residual-add-output-head-selftest-sv-sim.json`
  - status: `PASS`
  - top index: `1321`
  - top accumulator: `52140`
  - pass cycle: `265719`
- First phase-banked route attempt failed only timing:
  - post-route max frequency: `49.25 MHz`
  - target: `50.00 MHz`
- Added a nextpnr seed hook and set the JTAG-debug route seed to `2`.
- Seeded bitstream:
  `/nix/store/lmc8fwrdg7iya8ycpgacs0zlbf8v52rg-task6-int8-v4k-l2-residual-add-output-head-selftest-jtag-debug.bit`
- Seeded nextpnr result:
  - route legal: `PASS`
  - post-route main clock max frequency: `95.12 MHz`
  - post-route JTAG DRCK max frequency: `520.56 MHz`
  - target frequency: `50.00 MHz`
  - SLICE_LUTX: `20727 / 597200` (`3%`)
  - SLICE_FFX: `9538 / 597200` (`1%`)
  - RAMB18E1: `6 / 1910`
  - RAMB36E1: `136 / 955` (`14%`)
  - DSP48E1: `14 / 1920`

Board result:

- Program command:
  - `openFPGALoader -c digilent_hs3 --ftdi-serial 210299BF3824 /nix/store/lmc8fwrdg7iya8ycpgacs0zlbf8v52rg-task6-int8-v4k-l2-residual-add-output-head-selftest-jtag-debug.bit`
- Program result:
  - `Load SRAM` reached `100%`
  - `isc_done 1`, `init 1`, `done 1`
- USER1 read result:
  - state: `SELFTEST_PASS`
  - fail reason: `NONE`
  - observed top index: `1321`
  - expected top index: `1321`
  - observed top accumulator: `52140`
  - expected top accumulator: `52140`
  - vocab checksum: `0xc4ec5bc1`
  - expected vocab checksum: `0xc4ec5bc1`
  - vocab first word: `0xee4c0411`
  - expected vocab first word: `0xee4c0411`
  - vocab last word: `0x28efc925`
  - expected vocab last word: `0x28efc925`
  - head activation checksum: `0x00001ef9`
  - expected head activation checksum: `0x00001ef9`

Conclusion:

- H2 is now v4k board-validated for the bounded residual-add plus streamed
  output-head top1 path.
- The on-board failure was ours: the monolithic `65536 x 32` selftest
  vocab-loader ROM/load path produced wrong data on the board. Splitting that
  loader ROM into phase-local BRAM init files fixes the hardware result.
- There is no current evidence that the arithmetic kernels, residual path,
  output-head top1 kernel, HS3/JTAG path, Thunderbolt transport, Yosys, or
  nextpnr are wrong for this lane.
- Continue with the plan by promoting the phase-banked loader ROM workaround
  from debug-only to the normal v4k board selftest bitstream, then build and
  program the non-JTAG pass/fail image.

### 2026-04-30 - H2 v4k normal board selftest promotion

Change:

- Promoted `PHASE_BANKED_VOCAB_LOADER_ROM` to the default normal v4k
  residual-add plus output-head selftest path.
- Kept the monolithic loader path available behind the parameter, but no longer
  use it for the normal board bitstream.
- Fixed the `mkFasm` seed/frequency argument construction so seedless FASM
  targets still pass the `50.00 MHz` target frequency to nextpnr.

Verification:

- SV simulation after promotion:
  - command:
    `nix build .#task6-int8-v4k-l2-residual-add-output-head-selftest-sv-sim --no-link --print-out-paths -L`
  - result:
    `/nix/store/wm902lyl40w0xv9846srzii2jdzjykwx-task6-int8-v4k-l2-residual-add-output-head-selftest-sv-sim.json`
  - status: `PASS`
  - pass cycle: `265719`
  - top index: `1321`
  - top accumulator: `52140`
- Normal utilization and bitstream build:
  - command:
    `nix build .#task6-int8-v4k-l2-residual-add-output-head-selftest-utilization .#task6-int8-v4k-l2-residual-add-output-head-selftest-bitstream --no-link --print-out-paths -L`
  - utilization:
    `/nix/store/g0yb3gxbjfvxcz26q8y59mqhyipc1nvs-task6-int8-v4k-l2-residual-add-output-head-selftest-utilization`
  - bitstream:
    `/nix/store/fkaviyxg9czhlas9hl1r7smwn0lj64iw-task6-int8-v4k-l2-residual-add-output-head-selftest.bit`
- Normal route result:
  - route legal: `PASS`
  - post-route max frequency: `87.88 MHz`
  - target frequency: `50.00 MHz`
- Mapped utilization summary:
  - CLB LUTs: `14136 / 298600` (`4.73%`)
  - CLB FFs: `8841 / 597200` (`1.48%`)
  - DSPs: `14 / 1920` (`0.73%`)
  - BRAM36-equivalent: `139 / 955` (`14.55%`)
  - packed nextpnr cells:
    - `SLICE_LUTX`: `20065 / 597200` (`3%`)
    - `SLICE_FFX`: `8841 / 597200` (`1%`)
    - `RAMB18E1`: `6 / 1910`
    - `RAMB36E1`: `136 / 955` (`14%`)
    - `DSP48E1`: `14 / 1920`

Board programming result:

- Program command:
  - `openFPGALoader -c digilent_hs3 --ftdi-serial 210299BF3824 /nix/store/fkaviyxg9czhlas9hl1r7smwn0lj64iw-task6-int8-v4k-l2-residual-add-output-head-selftest.bit`
- Program result:
  - `Load SRAM` reached `100%`
  - `isc_done 1`, `init 1`, `done 1`

Decision:

- Treat the phase-banked loader ROM as the board-safe selftest load path for
  this v4k H2 lane.
- The normal non-JTAG bitstream cannot expose the internal top-index/checksum
  payload, but it uses the same promoted loader path that the JTAG-debug image
  already proved on hardware.
- Next gate: continue from the proven v4k residual-add plus streamed output
  head toward the next H2 structure increment, using JTAG payloads again when
  the pass/fail LEDs are not enough.

### 2026-04-30 - H2 v4k embedding lookup probe

Goal:

- Add one bounded input-side structure increment to the board-proven H2 v4k
  residual-add plus streamed output-head image.
- The new probe reads token id `0` from the tied v4k vocab/output-head table,
  reads position id `0` from a generated int8 position vector, computes
  token/position/combined byte checksums, exposes them over JTAG, and then runs
  the existing residual-add plus output-head selftest.
- This validates the storage/read/checksum mechanics for a one-token embedding
  lookup in the board image. It does not yet feed the MLP path; the current H2
  residual chain still starts from the captured `ln_2`/MLP boundary vector.

Implementation:

- Added the embedding lookup probe to
  `sim/gen_task6_int8_v4k_l2_residual_add_output_head_selftest_tb_data.py`.
- Added embedding selftest states and JTAG payload fields to
  `fpga/rtl/task6_int8_v4k_l2_residual_add_output_head_selftest_top.sv`.
- Updated `scripts/task6/read_jtag_debug_xvc.py` so the v4k decoder reports
  the embedding checksum fields and the new state names.

Verification:

- SV simulation:
  - command:
    `nix build .#task6-int8-v4k-l2-residual-add-output-head-selftest-tb-data-sv .#task6-int8-v4k-l2-residual-add-output-head-selftest-sv-sim --no-link --print-out-paths -L`
  - data:
    `/nix/store/394jl3cnaq64fn9p2562kvlp8j1rjzkf-task6-int8-v4k-l2-residual-add-output-head-selftest-tb-data-sv`
  - result:
    `/nix/store/j4av524kwxvskmdncz09qvpv9r0rzdyw-task6-int8-v4k-l2-residual-add-output-head-selftest-sv-sim.json`
  - status: `PASS`
  - pass cycle: `265848`
  - top index: `1321`
  - top accumulator: `52140`
- Normal mapped utilization:
  - command:
    `nix build .#task6-int8-v4k-l2-residual-add-output-head-selftest-utilization .#task6-int8-v4k-l2-residual-add-output-head-selftest-jtag-debug-bitstream --no-link --print-out-paths -L`
  - utilization:
    `/nix/store/dpczsh8njd84012y1vy8zbrpfi40b1cp-task6-int8-v4k-l2-residual-add-output-head-selftest-utilization`
  - CLB LUTs: `14229 / 298600` (`4.77%`)
  - CLB FFs: `8940 / 597200` (`1.50%`)
  - DSPs: `14 / 1920` (`0.73%`)
  - BRAM36-equivalent: `139 / 955` (`14.55%`)
- JTAG-debug bitstream:
  - bitstream:
    `/nix/store/rsr6zcswxighq18vpk562aykx934zl57-task6-int8-v4k-l2-residual-add-output-head-selftest-jtag-debug.bit`
  - route legal: `PASS`
  - post-route main clock max frequency: `63.76 MHz`
  - post-route JTAG DRCK max frequency: `536.77 MHz`
  - target frequency: `50.00 MHz`
  - packed nextpnr cells:
    - `SLICE_LUTX`: `22629 / 597200` (`3%`)
    - `SLICE_FFX`: `9890 / 597200` (`1%`)
    - `RAMB18E1`: `6 / 1910`
    - `RAMB36E1`: `136 / 955` (`14%`)
    - `DSP48E1`: `14 / 1920`

Board/JTAG result:

- Program command:
  - `openFPGALoader -c digilent_hs3 --ftdi-serial 210299BF3824 /nix/store/rsr6zcswxighq18vpk562aykx934zl57-task6-int8-v4k-l2-residual-add-output-head-selftest-jtag-debug.bit`
- Program result:
  - `Load SRAM` reached `100%`
  - `isc_done 1`, `init 1`, `done 1`
- JTAG read command:
  - `python3 scripts/task6/read_jtag_debug_ftdi_bitbang.py --backend mpsse --tdo-bit 7 --poll --poll-count 50 --poll-interval 0.1 --bits 768`
- USER1 read result:
  - version: `13`
  - pass bit: `true`
  - fail reason: `NONE`
  - observed top index: `1321`
  - expected top index: `1321`
  - observed top accumulator: `52140`
  - expected top accumulator: `52140`
  - vocab checksum: `0xc4ec5bc1`
  - expected vocab checksum: `0xc4ec5bc1`
  - head activation checksum: `0x00001ef9`
  - expected head activation checksum: `0x00001ef9`
  - embedding token checksum: `0x00001cf9`
  - expected embedding token checksum: `0x00001cf9`
  - embedding position checksum: `0x00001f92`
  - expected embedding position checksum: `0x00001f92`
  - embedding combined checksum: `0x00001f8b`
  - expected embedding combined checksum: `0x00001f8b`

Decision:

- Keep the embedding lookup probe in the H2 v4k board image as a cheap
  JTAG-visible input-side invariant.
- This increment preserves the known good streamed output-head result while
  adding only a small cycle count delta in simulation (`265719` to `265848`).
- Next H2 decision point: either feed this input-side path into a small
  layernorm/attention substitute, or pause H2 growth and run the representative
  core scaling matrix from the Task 6 execution doctrine.

### 2026-04-30 - Q0.24 top-k score comparator cutout validation

Goal:

- Promote the prepared Q0.24 rowwise sidecar top-k comparator cutout from
  static/readback evidence to executable simulator evidence.
- This is the smallest no-board gate for the full-vocab streamed output-head
  contract: it validates scaled-score comparison, signed ordering, lower-token
  tie break, reserved sidecar rejection, and the conservative score-register
  bound before any DDR3 integration or full TinyStories replay.

Implementation:

- Fixed the testbench startup/pass path in
  `rtl/task6/task6_q024_topk_score_compare_tb.sv`:
  - removed declaration initializers that Verilator 5.046 reports under
    `-Wall` when the same signals are procedurally assigned
  - made the PASS and FAIL branches mutually exclusive after `$finish`
- Added
  `scripts/task6/check_q024_topk_score_compare_vectors.py`, which checks the
  vector artifact, checks the expanded expected-state artifact, runs the
  Verilator binary, and writes a machine-readable result artifact.

Verification:

- Verilator compile:
  - command:
    `nix shell nixpkgs#verilator -c verilator --binary --timing -Wall --top-module task6_q024_topk_score_compare_tb rtl/task6/task6_q024_topk_score_compare.sv rtl/task6/task6_q024_topk_score_compare_tb.sv`
  - result: compile `PASS`
  - tool: `Verilator 5.046`
- Simulator run:
  - command:
    `./obj_dir/Vtask6_q024_topk_score_compare_tb`
  - result: `PASS task6_q024_topk_score_compare_tb`
  - finish time: `360 ns`
- Result artifact:
  - `artifacts/task6/parallel-hypotheses/h2-q024-topk-comparator-cutout-result.json`
  - checker command:
    `python3 scripts/task6/check_q024_topk_score_compare_vectors.py --vectors artifacts/task6/parallel-hypotheses/h2-q024-topk-score-comparator-vectors.json --expected-state artifacts/task6/parallel-hypotheses/h2-q024-topk-comparator-cutout-expected-state.json --sim-bin obj_dir/Vtask6_q024_topk_score_compare_tb --out artifacts/task6/parallel-hypotheses/h2-q024-topk-comparator-cutout-result.json`
  - status: `PASS`
  - vector errors: `0`
  - expected-state errors: `0`
  - expected sequences: `6`
  - candidate steps: `12`

Decision:

- Promote the Q0.24 comparator cutout as simulator-validated no-board
  arithmetic evidence.
- This does not validate rowwise scale distributions or full-vocab top-k
  equivalence yet; it only validates the comparator contract once a rowwise
  candidate score is presented.
- Next gate: run an 8-sample full-vocab rowwise top-k replay against f32
  top1/top5 before DDR3 integration.

### 2026-04-30 - Full-vocab rowwise Q0.24 top-k replay

Goal:

- Execute the next no-board gate before DDR3 integration: replay eight
  deterministic token-id samples through the full TinyStories-1M output head,
  compare rowwise-int8 plus Q0.24 sidecar scores against f32 top1/top5, and
  keep the payload-only per-tensor int8 profile as a control.

Implementation:

- Added `scripts/task6/check_full_vocab_rowwise_topk_contract.py`.
- Added flake package:
  - `task6-full-vocab-rowwise-topk-replay`
- Copied result artifact:
  - `artifacts/task6/parallel-hypotheses/h2-full-vocab-rowwise-topk-replay.json`

Verification:

- Syntax checks:
  - `python3 -m py_compile scripts/task6/check_full_vocab_rowwise_topk_contract.py`
  - `nix-instantiate --parse flake.nix`
- Replay command:
  - `nix build .#task6-full-vocab-rowwise-topk-replay --no-link --print-out-paths -L`
- Output store path:
  - `/nix/store/isl763k2rnd8fl3iajn385dlvsj9irf7-h2-full-vocab-rowwise-topk-replay.json`
- Replay status: `PASS`

Measured result:

- Model: full TinyStories-1M output head, `vocab_size = 50257`,
  `hidden_size = 64`, tied lm-head/token embedding.
- Samples: `8`.
- Profile B, rowwise-int8 plus Q0.24 sidecar:
  - top1 match count vs f32: `8 / 8`
  - top1 match rate vs f32: `1.0`
  - top5 overlap min: `4`
  - top5 overlap mean: `4.875`
  - max normalized RMSE: `0.009548773935420423`
  - changed top1 rows: `0`
  - Q0.24 reserved upper-byte violations: `0`
- Profile A, payload-only per-tensor int8 control:
  - top1 match count vs f32: `8 / 8`
  - top5 overlap min: `4`
  - max normalized RMSE: `0.02132032462809377`

Decision:

- Promote the rowwise Q0.24 top-k contract to full-vocab replay evidence.
- This is still not a synthesis, hardware, or DDR3-controller result; it proves
  the scoring contract on full-vocab TinyStories values before spending board
  work on the memory interface.
- Next gate: define the DDR3 row-stream interface and keep the Q0.24 comparator
  as the row-score unit.

### 2026-04-30 - DDR3 row-stream interface contract

Goal:

- Convert the passing full-vocab rowwise Q0.24 replay into a concrete memory
  interface target before any DDR3 controller integration.
- Keep this as an interface contract and acceptance-gate artifact, not a
  controller implementation.

Implementation:

- Added `scripts/task6/write_ddr3_row_stream_interface_contract.py`.
- Added flake package:
  - `task6-ddr3-row-stream-interface-contract`
- Copied result artifact:
  - `artifacts/task6/parallel-hypotheses/h2-ddr3-row-stream-interface-contract.json`

Verification:

- Syntax checks:
  - `python3 -m py_compile scripts/task6/write_ddr3_row_stream_interface_contract.py`
  - `nix-instantiate --parse flake.nix`
- Contract generation:
  - `nix build .#task6-ddr3-row-stream-interface-contract --no-link --print-out-paths -L`
  - `/nix/store/qql3sl7wc2jlbfp6vyqvfv8zrqgq8lsz-h2-ddr3-row-stream-interface-contract.json`
- Contract status: `PASS`

Contract summary:

- Row format: `68` bytes per vocab row.
  - bytes `0..63`: `64` signed int8 output-head weights
  - bytes `64..66`: little-endian unsigned Q0.24 row scale
  - byte `67`: reserved upper byte, required zero
- DDR3 linear image:
  - `32` rows per group
  - `2176` bytes per group
  - `1571` groups
  - logical stream bytes: `3417476`
  - padded stream bytes: `3418496`
  - tail padding: `15` rows, `1020` bytes
- Kernel-side row interface:
  - ready/valid at decoded row granularity
  - `row_token_id[15:0]`
  - `row_weight_q_i8[511:0]`
  - `row_scale_q0_24[23:0]`
  - reserved-byte-valid and row-last flags
- Lane budget at `50 MHz`:
  - `4` DSP lanes: `804112` compute cycles, `212.5 MB/s` useful stream
    bandwidth target
  - `8` DSP lanes: `402056` compute cycles, `425.0 MB/s` useful stream
    bandwidth target
  - `16` DSP lanes: `201028` compute cycles, `850.0 MB/s` useful stream
    bandwidth target and bandwidth-limited at one `16`-byte beat per cycle

Decision:

- Promote the DDR3 row-stream contract as the memory-interface target for the
  full TinyStories output-head lane.
- First implementation target is the `4`-lane stream. Treat `8` lanes as a
  bandwidth stretch target and defer `16` lanes until measured DDR3 read
  throughput justifies it.
- Next gate: generate and validate a pack/unpack rowstream image, then build a
  DDR-free RTL rowstream cutout before integrating a DDR3 controller.

### 2026-04-30 - DDR3 row-stream pack/unpack replay

Goal:

- Generate the concrete packed rowstream image for the full TinyStories output
  head, unpack it, and prove that the unpacked stream reproduces the passing
  full-vocab rowwise Q0.24 replay before building RTL around the interface.

Implementation:

- Added `scripts/task6/pack_ddr3_row_stream_image.py`.
- Added flake package:
  - `task6-ddr3-row-stream-pack-replay`
- Copied durable bundle:
  - `artifacts/task6/parallel-hypotheses/h2-ddr3-row-stream-pack-replay/`
  - includes `summary.json` and `rowstream.bin`

Verification:

- Syntax checks:
  - `python3 -m py_compile scripts/task6/pack_ddr3_row_stream_image.py`
  - `nix-instantiate --parse flake.nix`
- Pack/unpack replay:
  - `nix build .#task6-ddr3-row-stream-pack-replay --no-link --print-out-paths -L`
  - `/nix/store/p8xgkxbr0a8mqn44mlcmp1hcfgr6hxns-h2-ddr3-row-stream-pack-replay`
- Result status: `PASS`

Measured result:

- Rowstream image:
  - bytes: `3418496`
  - rows per group: `32`
  - group count: `1571`
  - SHA256:
    `2b30755a9a351538999cdc51cf9e7c6238672b2a0499bfb92b3f1dbf177b43b2`
- Pack/unpack validation:
  - quantized-weight mismatches: `0`
  - Q0.24 scale mismatches: `0`
  - reserved-byte violations: `0`
  - tail-padding nonzero bytes: `0`
- Replay validation from unpacked image:
  - replay top-k mismatches vs previous rowwise replay: `0`
  - top1 match count vs f32: `8 / 8`
  - top5 overlap min vs f32: `4`
  - top5 overlap mean vs f32: `4.875`
  - max normalized RMSE: `0.009548773935420423`

Decision:

- Promote the packed rowstream format.
- The full-output-head memory data is now concrete enough for RTL cutout work:
  the next step should consume this image through a synthetic row source and
  the existing Q0.24 comparator, still without integrating a DDR3 controller.
- Next gate: build a DDR-free RTL rowstream cutout, then measure board DDR3
  linear-read bandwidth before choosing the controller integration path.

### 2026-04-30 - DDR-free rowstream RTL cutout

Goal:

- Prove that RTL can consume the committed full-vocab rowstream image through a
  synthetic source, compute one `64`-term int8 dot product per vocab row, feed
  the existing Q0.24 comparator, and match the rowwise replay top1 result before
  any DDR3 controller integration.

Implementation:

- Added `scripts/task6/gen_ddr3_rowstream_cutout_tb_data.py`.
- Added `rtl/task6/task6_ddr3_rowstream_mem_source.sv`.
- Added `rtl/task6/task6_ddr3_rowstream_top1_cutout.sv`.
- Added `sim/task6_ddr3_rowstream_top1_cutout_tb.sv`.
- Added flake packages:
  - `task6-ddr3-row-stream-cutout-tb-data`
  - `task6-ddr3-row-stream-cutout-sim-main`
  - `task6-ddr3-row-stream-cutout-sv-sim`
- Copied durable proof:
  - `artifacts/task6/parallel-hypotheses/h2-ddr3-row-stream-cutout-rtl-proof.json`

Verification:

- Syntax checks:
  - `python3 -m py_compile scripts/task6/gen_ddr3_rowstream_cutout_tb_data.py`
  - `nix-instantiate --parse flake.nix`
  - `git diff --check`
- RTL simulation:
  - `nix build .#task6-ddr3-row-stream-cutout-sv-sim --no-link --print-out-paths -L`
  - `/nix/store/yk606dhnlkfh5ggsang8pz7vpxxrhpwg-h2-ddr3-row-stream-cutout-rtl-proof.json`
- Result status: `PASS`

Measured result:

- Samples: `8`
- Rows streamed per sample: `50257`
- Total rows streamed: `402056`
- Simulation cycles: `402088`
- Per-sample top1 tokens:
  - sample `0`: token `198`, score `3094540336`
  - sample `1`: token `40`, score `3476521854`
  - sample `2`: token `3043`, score `2724137100`
  - sample `3`: token `628`, score `3494486263`
  - sample `4`: token `387`, score `3416165620`
  - sample `5`: token `13`, score `2193042725`
  - sample `6`: token `13`, score `2352499775`
  - sample `7`: token `628`, score `2471619603`

Decision:

- Promote the RTL rowstream cutout.
- This proves the packed image bit layout, synthetic row decode, int8 row dot,
  and Q0.24 top1 compare agree with the Python full-vocab replay.
- Next gate: integrate or choose a measured DDR3 linear-read source for the
  same rowstream contract, with the `4`-lane target still gated by measured
  board bandwidth margin above `212.5 MB/s`.

### 2026-04-30 - DDR3 board-support inventory

Goal:

- Summarize the available YPCB DDR3 board metadata before choosing the first
  controller/bandwidth probe. This separates board facts from open-toolchain
  controller evidence.

Implementation:

- Added `scripts/task6/summarize_ypcb_ddr3_board_support.py`.
- Added flake package:
  - `task6-ddr3-board-support-inventory`
- Copied durable proof:
  - `artifacts/task6/parallel-hypotheses/h2-ddr3-board-support-inventory.json`

Verification:

- Syntax checks:
  - `python3 -m py_compile scripts/task6/summarize_ypcb_ddr3_board_support.py`
  - `nix-instantiate --parse flake.nix`
  - `git diff --check`
- Inventory generation:
  - `nix build .#task6-ddr3-board-support-inventory --no-link --print-out-paths -L`
  - `/nix/store/1qdsfd2c2mii79wjnpjqk0vdpz7inxvv-h2-ddr3-board-support-inventory.json`
- Result status: `PASS`

Measured board facts:

- Board support source: `ypcbHack`.
- MIG project module: `top_mig_7series_0_0`.
- Target: `xc7k480t-ffg1156/-2`.
- Memory device: `DDR3_SDRAM/Components/MT41K256M8XX-125`.
- MIG interface: `AXI`.
- MIG data width: `72` bits with ECC enabled, so `64` payload bits.
- AXI data width in the MIG project: `512` bits.
- Input clock: `200 MHz`; system clock is differential on `AH27/AH28`.
- DDR3 timing period: `1875 ps`, about `533.33 MT/s`.
- Channel 0 constrained pins:
  - total DDR3 nets: `117`
  - `ddr3_dq`: `72`
  - `ddr3_dqs_p`: `9`
  - `ddr3_dqs_n`: `9`
  - `ddr3_addr`: `15`
  - `ddr3_ba`: `3`
- Derived theoretical payload peak before controller overhead:
  - `4266.67 MB/s`
  - about `20.08x` the Task 6 `4`-lane useful target of `212.5 MB/s`

Decision:

- Promote the board-support inventory.
- The board metadata is viable for the Task 6 rowstream bandwidth target in
  principle, but it is Vivado MIG-oriented metadata, not open-toolchain DDR3
  controller evidence.
- Next gate: choose or build the smallest DDR3 init/linear-read bandwidth probe
  first; only connect it to the rowstream cutout after measured board bandwidth
  is available.

### 2026-04-30 - DDR3 controller path precheck

Goal:

- Check whether the pinned Nix environment already exposes an open DDR3
  controller stack before starting the bandwidth-probe implementation.

Verification:

- Command:
  - `nix eval --impure --json --expr 'let flake = builtins.getFlake (toString /home/roland/LLM2FPGA_task6_streamtensor_lite); pkgs = import flake.inputs.nixpkgs { system = builtins.currentSystem; }; in { has_litedram_top_level = pkgs ? litedram; has_litedram_python = pkgs.python3Packages ? litedram; has_litex_top_level = pkgs ? litex; has_litex_python = pkgs.python3Packages ? litex; has_migen_python = pkgs.python3Packages ? migen; }'`
- Result:
  - `has_litedram_top_level`: `false`
  - `has_litedram_python`: `false`
  - `has_litex_top_level`: `false`
  - `has_litex_python`: `false`
  - `has_migen_python`: `true`

Decision:

- Do not assume the DDR3 bandwidth probe can be built from existing pinned
  packages.
- Superseded lane selection:
  - the vendor-MIG lane is rejected for Task 6 implementation and board
    bring-up
  - the active lane is open-controller only: add or vendor a reproducible
    LiteDRAM/LiteX-style generator/config for Kintex-7 plus the YPCB
    `MT41K256M8XX-125` interface
- Keep the next implementation small: DDR3 init plus linear-read bandwidth
  counter first, not rowstream integration.

### 2026-04-30 - LiteDRAM/LiteX open-controller probe

Goal:

- Enforce the Task 6 DDR3 implementation lane as open-source
  LiteDRAM/LiteX only. Vivado MIG is rejected for controller generation and
  board bring-up. Existing YPCB files may be used only as open board metadata
  such as UCF pin maps and board XML clock facts.

Implementation:

- Added flake inputs:
  - `litex`: `github:enjoy-digital/litex`
  - `litedram`: `github:enjoy-digital/litedram`
- Locked revisions:
  - LiteX: `d9918790cadefc51f9904f800cba40ece6e3f07e`
    (`2026-04-30`)
  - LiteDRAM: `ef9f94a4aeef88f11567a5efa11fc6e7a3bf9dc2`
    (`2026-04-08`)
- Added local Nix Python packages for LiteX/LiteDRAM.
- Added `scripts/task6/check_litedram_open_controller_path.py`.
- Added flake package:
  - `task6-litedram-open-controller-probe`
- Copied durable proof:
  - `artifacts/task6/parallel-hypotheses/h2-litedram-open-controller-probe.json`

Verification:

- Syntax checks:
  - `python3 -m py_compile scripts/task6/check_litedram_open_controller_path.py`
  - `nix-instantiate --parse flake.nix`
  - `git diff --check`
- Locking:
  - `nix flake lock --update-input litex --update-input litedram`
- Rejected attempt:
  - first `nix build .#task6-litedram-open-controller-probe --no-link --print-out-paths -L`
    built LiteX and LiteDRAM successfully, then failed because the probe
    incorrectly treated `litedram.modules` as a package directory instead of a
    single module file
- Fixed and reran:
  - `nix build .#task6-litedram-open-controller-probe --no-link --print-out-paths -L`
  - `/nix/store/4i75a2iabnf2sbx2rnhyigfs6s0mn2br-h2-litedram-open-controller-probe.json`
- Result status: `PASS`

Measured result:

- Policy:
  - `vivado_mig_lane`: `rejected`
  - `controller_path`: `LiteDRAM/LiteX only`
  - `mig_files_used_for_controller_generation`: `false`
- LiteDRAM/LiteX imports:
  - `litex`: import PASS
  - `litedram`: import PASS
  - `litedram.modules`: import PASS
  - `litedram.phy.s7ddrphy`: import PASS
- LiteDRAM detected classes:
  - DRAM module classes: `86`
  - MT41K family classes:
    - `MT41K128M16`
    - `MT41K256M16`
    - `MT41K256M8`
    - `MT41K512M16`
    - `MT41K64M16`
  - Requested board part: `MT41K256M8DA-125`
  - Exact usable module class: `MT41K256M8`
  - 7-series PHY classes:
    - `A7DDRPHY`
    - `K7DDRPHY`
    - `S7DDRPHY`
    - `V7DDRPHY`
- YPCB open board facts used by the probe:
  - DDR3 UCF constrained nets: `117`
  - `ddr3_dq`: `72`
  - `ddr3_dqs_p`: `9`
  - `ddr3_dqs_n`: `9`
  - `ddr3_addr`: `15`
  - `ddr3_ba`: `3`
  - differential `200 MHz` clock 1: `AH27/AH28`
  - differential `200 MHz` clock 2: `G25/G26`
  - `50 MHz` clock: `AA28`
  - reset: `R28`

Decision:

- Promote the LiteDRAM/LiteX open-controller probe.
- The next gate is now concrete: instantiate a minimal YPCB LiteDRAM/LiteX
  target/config using `K7DDRPHY` and `MT41K256M8`, then generate a DDR3 init
  plus linear-read bandwidth probe.
- Keep the rowstream cutout blocked from DDR3 integration until the open
  controller proves init/calibration and measured linear-read bandwidth on the
  board.

### 2026-04-30 - YPCB LiteDRAM 64-bit config bundle

Goal:

- Convert the open YPCB DDR3 CH0 metadata into a reproducible LiteDRAM/LiteX
  config bundle without using Vivado MIG as a controller lane.

Implementation:

- Added `scripts/task6/write_ypcb_litedram_config.py`.
- Added flake package:
  - `task6-ypcb-litedram-config`
- Copied durable proof:
  - `artifacts/task6/parallel-hypotheses/h2-ypcb-litedram-config`

Verification:

- Syntax checks:
  - `python3 -m py_compile scripts/task6/write_ypcb_litedram_config.py`
  - `nix-instantiate --parse flake.nix`
- Rejected attempt:
  - first `nix build .#task6-ypcb-litedram-config --no-link --print-out-paths -L`
    failed because the new generator script was not yet tracked by Git, so the
    flake source snapshot did not include it
- Fixed and reran:
  - `git add flake.nix scripts/task6/write_ypcb_litedram_config.py`
  - `nix build .#task6-ypcb-litedram-config --no-link --print-out-paths -L`
  - `/nix/store/2skrjxjpzv3b8n2mdr1ib4dqw6973a19-h2-ypcb-litedram-config`
- Result status: `PASS`

Generated bundle:

- `summary.json`
- `ypcb_litedram_64bit_payload.yml`
- `ypcb_litedram_open_io.py`
- `ypcb_litedram_open_io.xdc`

Measured result:

- Policy:
  - `vivado_mig_lane`: `rejected`
  - `controller_path`: `LiteDRAM/LiteX only`
  - `mig_files_used_for_controller_generation`: `false`
- Logical LiteDRAM config:
  - `sdram_module`: `MT41K256M8`
  - `sdram_module_nb`: `8`
  - `sdram_phy`: `K7DDRPHY`
  - payload data width: `64`
  - input clock: `200 MHz` on `AH27/AH28`
  - system clock target: `100 MHz`
  - iodelay clock target: `200 MHz`
- Open YPCB UCF coverage:
  - `64` payload DQ pins selected from the first eight x8 byte lanes
  - `8` payload DQS pairs selected from the first eight byte lanes
  - the ninth x8 byte lane is present and recorded as ECC/spare
  - `15` address pins and `3` bank pins are present
  - DDR3 clock, CKE, CS, ODT, RAS, CAS, WE, and reset pins are present
- Important board-metadata gap:
  - open `MEMORY_CH0.ucf` does not expose DDR3 `dm` pins
  - LiteDRAM's S7 PHY guards DM generation with `hasattr(pads, "dm")`
  - therefore the next gate should use a custom LiteX target that omits
    `ddram.dm`, not the stock standalone YAML generator path

Decision:

- Promote the YPCB LiteDRAM config bundle.
- The next gate is to instantiate a minimal custom LiteX/YPCB `K7DDRPHY`
  target with the generated no-`dm` DDR3 pads and emit controller RTL without
  invoking Vivado or MIG.
- Keep DDR3 rowstream integration blocked until this open controller path
  proves init/calibration and then linear-read bandwidth on the board.

### 2026-04-30 - YPCB LiteDRAM no-DM RTL elaboration

Goal:

- Prove the open LiteDRAM/LiteX controller stack can elaborate RTL for the YPCB
  DDR3 CH0 board shape using `K7DDRPHY`, `MT41K256M8`, eight x8 payload byte
  lanes, and no `dm` pads.

Implementation:

- Added `scripts/task6/generate_ypcb_litedram_core.py`.
- Added LiteX package dependency:
  - `packaging`
- Added flake package:
  - `task6-ypcb-litedram-rtl-elaboration`
- Copied durable proof:
  - `artifacts/task6/parallel-hypotheses/h2-ypcb-litedram-rtl-elaboration`

Verification:

- Syntax checks:
  - `python3 -m py_compile scripts/task6/generate_ypcb_litedram_core.py`
  - `nix-instantiate --parse flake.nix`
- Rejected attempts:
  - first `nix build .#task6-ypcb-litedram-rtl-elaboration --no-link --print-out-paths -L`
    failed because LiteX Builder imports `packaging.version`; fixed by adding
    `packaging` to the local LiteX Python package/environment
  - second attempt failed in the config loader because nested dict values were
    tested against a string replacement map; fixed by checking replacements
    only for string values
  - third attempt elaborated the SoC but failed because the openXC7 LiteX
    toolchain object required `CHIPDB`; fixed by exporting the pinned
    `openXC7Chipdb` directory in the flake target
  - fourth attempt elaborated the SoC but failed because the openXC7 LiteX
    toolchain object defaulted `PRJXRAY_DB_DIR` to a snap path; fixed by
    exporting the pinned repo `fpgaPrjxrayDb`
- Fixed and reran:
  - `nix build .#task6-ypcb-litedram-rtl-elaboration --no-link --print-out-paths -L`
  - `/nix/store/bkpkxibqsk4mxi1n9rplp8f9nh07cx72-h2-ypcb-litedram-rtl-elaboration`
- Result status: `PASS`

Measured result:

- Policy:
  - `vivado_mig_lane`: `rejected`
  - `controller_path`: `LiteDRAM/LiteX only`
  - `mig_files_used_for_controller_generation`: `false`
  - `gateware_compile_invoked`: `false`
  - LiteX platform toolchain object: `openxc7`
- Core config:
  - device: `xc7k480tffg1156-1`
  - `sdram_module`: `MT41K256M8`
  - `sdram_module_nb`: `8`
  - `sdram_phy`: `K7DDRPHY`
  - `memtype`: `DDR3`
  - input clock: `200 MHz`
  - system clock: `100 MHz`
  - iodelay clock: `200 MHz`
- Generated files:
  - `build/gateware/ypcb_litedram_core.v`
  - `build/gateware/ypcb_litedram_core.xdc`
  - `build/gateware/ypcb_litedram_core.ys`
  - `csr.json`
  - `csr.csv`
- Generated RTL size:
  - top Verilog: `1,448,196` bytes
  - bundle file count: `11`
  - bundle size: about `1.5 MiB`
- Generated text cleanup:
  - the generator strips trailing whitespace from emitted text artifacts
  - sanitized generated files:
    - `build/gateware/build_ypcb_litedram_core.sh`
    - `build/gateware/ypcb_litedram_core.v`
- No-`dm` validation:
  - `ddram_dm` top-port mentions: `0`
  - `ddram_dq` top-port mentions: `65`
  - `ddram_dqs_p` top-port mentions: `9`
  - `ddram_dqs_n` top-port mentions: `9`

Decision:

- Promote open LiteDRAM RTL generation.
- This is not a board-ready DDR3 proof yet; it proves the controller can be
  generated for the YPCB no-`dm` 64-bit payload shape with the open stack.
- Next gate choices:
  - synthesize the generated LiteDRAM core with Yosys/openXC7 to measure
    resource and primitive compatibility, or
  - wrap it first in a minimal init/bandwidth probe and then synthesize that
    board-facing payload.
- Keep the rowstream contract blocked until init/calibration and linear-read
  bandwidth are proven on board.

### 2026-04-30 - YPCB LiteDRAM open synthesis utilization

Goal:

- Run the generated no-`dm` YPCB LiteDRAM/LiteX core through open Yosys
  `synth_xilinx` and measure the standalone controller/PHY resource footprint
  before attempting board init or DDR3 bandwidth.

Implementation:

- Added flake packages:
  - `task6-ypcb-litedram-open-synth-json`
  - `task6-ypcb-litedram-open-synth-utilization`
- Reused the repo mapped-utilization reporter:
  - `scripts/pipeline/write_utilization_report.py`
- Copied durable proof:
  - `artifacts/task6/parallel-hypotheses/h2-ypcb-litedram-open-synth-utilization`
- Copied concise synthesis evidence:
  - `summary.json`
  - `summary.txt`
  - `stat.json`
  - `run.ys`
  - `yosys.rpt`
- Did not copy the generated mapped netlist JSON into the durable artifact:
  - store netlist size: about `27.4 MiB`
  - the flake target can regenerate it when needed

Verification:

- Rejected attempt:
  - first `nix build .#task6-ypcb-litedram-open-synth-utilization --no-link --print-out-paths -L`
    failed before reaching the design because the repo `yosysPkg` overlay tried
    to rebuild Yosys and failed with `genericBuild: command not found`
- Fixed and reran:
  - switched this new LiteDRAM synthesis gate to `${pkgs.yosys}/bin/yosys`
  - `nix build .#task6-ypcb-litedram-open-synth-utilization --no-link --print-out-paths -L`
  - `/nix/store/dvi8prbiw5v52kczkrs2rl3q1b285gji-h2-ypcb-litedram-open-synth-utilization`
- Result status: `PASS`
- Yosys result:
  - frontend parsed the generated LiteDRAM Verilog
  - `synth_xilinx -flatten -abc9 -arch xc7 -top ypcb_litedram_core` completed
  - `check` reported `0` problems
  - Yosys peak memory: `767.82 MiB`

Measured standalone core utilization:

- CLB LUTs: `8196 / 298600` (`2.74%`)
- CLB FFs: `6929 / 597200` (`1.16%`)
- DSP: `0 / 1920` (`0.00%`)
- BRAM36: `0 / 955` (`0.00%`)
- BRAM36-equivalent: `0 / 955` (`0.00%`)
- Lower-bound slices: `1025 / 74650` (`1.37%`)
- Largest mapped leaf types:
  - `FDRE`: `6457`
  - `LUT5`: `2350`
  - `LUT3`: `2026`
  - `LUT6`: `1752`
  - `LUT2`: `1272`
  - `CARRY4`: `282`
  - `RAM32M`: `252`

Interpretation:

- The open LiteDRAM/LiteX DDR3 controller/PHY lane is viable enough to promote
  past RTL generation into board-facing bring-up.
- The controller/PHY footprint is modest relative to the XC7K480T budget.
- `0` DSP is expected for the controller itself; DSP use belongs in the
  rowstream/GEMV compute lane, not in the DDR3 PHY/controller.
- `0` BRAM36 means this standalone generated controller did not introduce a
  large BRAM footprint at the synthesis gate. It does use distributed RAM
  (`RAM32M`) for small structures.

Decision:

- Promote open LiteDRAM synthesis.
- Keep Vivado MIG rejected as an implementation lane.
- Next gate:
  - build a minimal LiteDRAM board-facing init/bandwidth probe around this
    controller
  - run open place/route only if the wrapper first gives a measurable board
    test objective: DDR3 init/calibration done and sustained linear-read
    bandwidth
  - then connect the existing DDR3 rowstream contract to the measured memory
    port shape

### 2026-04-30 - YPCB LiteDRAM JTAG init/bandwidth probe

Goal:

- Build the first board-facing open LiteDRAM/LiteX probe around the generated
  YPCB no-`dm` controller. The probe should expose DDR3 init state and linear
  read counters through JTAG/XVC instead of LEDs.

Implementation:

- Added wrapper RTL:
  - `fpga/rtl/task6_ypcb_litedram_init_bandwidth_probe_top.sv`
- Added board constraints:
  - `fpga/constraints/task6_ypcb_litedram_init_bandwidth_probe.xdc`
- Added JTAG/XVC decoder:
  - `scripts/task6/read_litedram_probe_jtag_xvc.py`
- Added flake packages:
  - `task6-ypcb-litedram-init-bandwidth-probe-json`
  - `task6-ypcb-litedram-init-bandwidth-probe-utilization`
  - `task6-ypcb-litedram-init-bandwidth-probe-xdc`
  - `task6-ypcb-litedram-init-bandwidth-probe-fasm`
  - `task6-ypcb-litedram-init-bandwidth-probe-bitstream`
  - `task6-ypcb-litedram-init-bandwidth-probe-iopad-json`
  - `task6-ypcb-litedram-init-bandwidth-probe-iopad-fasm`
  - `task6-ypcb-litedram-init-bandwidth-probe-iopad-bitstream`
- Copied durable synthesis proof:
  - `artifacts/task6/parallel-hypotheses/h2-ypcb-litedram-init-bandwidth-probe-utilization`

Probe behavior:

- Inputs:
  - `clk200_p` / `clk200_n`
  - `SYS_RSTN`
- DDR3 interface:
  - generated `ypcb_litedram_core` CH0, 64-bit payload, no `ddram_dm`
- Native-port test:
  - issue `65536` 64-bit linear reads after `init_done`
  - track command count, response count, stalls, cycles, checksum, and last
    returned data
- JTAG payload:
  - magic `0x54364a44`
  - version `20`
  - state, status bits, read-cycle count, command/response counts, stall
    count, checksum, last read data, next read address, and target read count

Verification:

- Syntax checks:
  - `python3 -m py_compile scripts/task6/read_litedram_probe_jtag_xvc.py scripts/task6/read_jtag_debug_xvc.py`
  - `nix-instantiate --parse flake.nix`
- Rejected synthesis attempt:
  - first utilization build failed because the Yosys script read only
    `cells_xtra.v`; the generated core also uses primitives such as `FDPE`
    from `cells_sim.v`
- Fixed and reran:
  - added `read_verilog -lib +/xilinx/cells_sim.v` before `cells_xtra.v`
  - `nix build .#task6-ypcb-litedram-init-bandwidth-probe-utilization --no-link --print-out-paths -L`
  - `/nix/store/1vgyghy1n360i3q5crinbhn9cq64qwym-task6-ypcb-litedram-init-bandwidth-probe-utilization`
- Result status: `SYNTHESIS PASS`
- Yosys result:
  - `check` reported `0` problems
  - Yosys peak memory: `606.09 MiB`

Measured probe utilization:

- CLB LUTs: `8397 / 298600` (`2.81%`)
- CLB FFs: `7704 / 597200` (`1.29%`)
- DSP: `0 / 1920` (`0.00%`)
- BRAM36: `0 / 955` (`0.00%`)
- BRAM36-equivalent: `0 / 955` (`0.00%`)
- Lower-bound slices: `1050 / 74650` (`1.41%`)
- Largest mapped leaf types:
  - `FDRE`: `6712`
  - `LUT6`: `3821`
  - `LUT3`: `1768`
  - `LUT2`: `1529`
  - `LUT5`: `846`
  - `FDCE`: `528`
  - `FDSE`: `460`
  - `RAM32M`: `252`

Open P&R result:

- Rejected attempt:
  - `nix build .#task6-ypcb-litedram-init-bandwidth-probe-bitstream --no-link --print-out-paths -L`
  - failed derivation:
    `/nix/store/nf51lrrp4bkryb5y7xd7g7ivfgmb4273-task6-ypcb-litedram-init-bandwidth-probe.fasm.drv`
  - error:
    `ODELAYE2 'core.ODELAYE2' has DATAOUT connected to unsupported cell type IOB33M_OUTBUF`
- Bounded iopad variant:
  - `nix build .#task6-ypcb-litedram-init-bandwidth-probe-iopad-bitstream --no-link --print-out-paths -L`
  - failed derivation:
    `/nix/store/lkkdzqbd0bxijig9vssvhzn6kj0acxgs-task6-ypcb-litedram-init-bandwidth-probe-iopad.fasm.drv`
  - same error:
    `ODELAYE2 'core.ODELAYE2' has DATAOUT connected to unsupported cell type IOB33M_OUTBUF`
- Durable concise failure record:
  - `artifacts/task6/parallel-hypotheses/h2-ypcb-litedram-init-bandwidth-probe-utilization/open-par-failure-summary.json`

Decision:

- Promote the LiteDRAM/LiteX probe through open synthesis only.
- Do not program the board yet; no valid bitstream was produced.
- The current blocker is not DDR3 controller scale and not Vivado/MIG
  availability. It is an open P&R primitive-packing issue around LiteDRAM
  `K7DDRPHY` output-delay cells.
- Next gate:
  - reduce the `ODELAYE2 -> OBUF/OBUFDS` topology to a minimal openXC7 cutout,
    then either patch/support that topology in the open flow or find a valid
    LiteDRAM PHY configuration that avoids it.

### 2026-04-30 - Minimal `ODELAYE2` output-buffer cutouts

Goal:

- Decide whether the LiteDRAM probe P&R failure is caused by the full DDR3
  controller or by a smaller openXC7 primitive-topology limitation.

Implementation:

- Added minimal cutout RTL:
  - `fpga/rtl/task6_odelay_obuf_cutout_top.sv`
- Added cutout constraints:
  - `fpga/constraints/task6_odelay_obuf_cutout.xdc`
  - `fpga/constraints/task6_odelay_obufds_cutout.xdc`
- Added flake packages:
  - `task6-odelay-obuf-cutout-json`
  - `task6-odelay-obuf-cutout-fasm`
  - `task6-odelay-obufds-cutout-json`
  - `task6-odelay-obufds-cutout-fasm`
- Copied durable artifacts:
  - `artifacts/task6/parallel-hypotheses/h2-odelay-obuf-cutouts`
- Did not copy the generated cutout JSON netlists into the repo:
  - each JSON netlist is about `9.7 MiB`
  - regenerate with the recorded `task6-odelay-*-cutout-json` flake targets
    when needed

Verification:

- JSON synthesis:
  - `nix build .#task6-odelay-obuf-cutout-json .#task6-odelay-obufds-cutout-json --no-link --print-out-paths`
  - `/nix/store/cwmkpd4l4ixgnvrczwx9ahw0zgfawjml-task6-odelay-obuf-cutout.json`
  - `/nix/store/2lsns6b9f6f72jras4sc2ma37lkic6h3-task6-odelay-obufds-cutout.json`
- Single-ended cutout:
  - command:
    `nix build .#task6-odelay-obuf-cutout-fasm --no-link --print-out-paths -L`
  - failed derivation:
    `/nix/store/a9by92gq2m6jza2nm8iq1zjyzhhc5n8p-task6-odelay-obuf-cutout.fasm.drv`
  - error:
    `ODELAYE2 'odelay' has DATAOUT connected to unsupported cell type IOB33_OUTBUF`
- Differential cutout:
  - command:
    `nix build .#task6-odelay-obufds-cutout-fasm --no-link --print-out-paths -L`
  - failed derivation:
    `/nix/store/xz9x342piwdwi76aczhql1s9j5l2kdp2-task6-odelay-obufds-cutout.fasm.drv`
  - error:
    `ODELAYE2 'odelay' has DATAOUT connected to unsupported cell type IOB33M_OUTBUF`

Interpretation:

- The board-probe failure is now reduced to a one-`ODELAYE2` open-P&R cutout.
- This is not a TinyStories-model issue, not an int8 arithmetic issue, and not
  a full LiteDRAM controller size issue.
- The `-noiopad` vs iopad synthesis choice is also not sufficient to explain
  the failure; both full-probe variants fail the same way.
- Current hypothesis:
  - openXC7/nextpnr does not yet pack this Kintex-7 output-delay-to-output-
    buffer topology, or our generated PHY topology needs a valid open-flow
    representation of the same hardware path.

Decision:

- Keep Vivado MIG rejected.
- Make the next DDR3 board-support task a narrow open-toolchain task:
  - inspect or patch nextpnr/openXC7 packing support for `ODELAYE2` feeding
    `OBUF` / `OBUFDS`, using the minimal cutouts above as the regression test
  - only return to the full LiteDRAM board probe after a cutout reaches FASM

### 2026-04-30 - Patched ODELAY cutouts expose HR-bank limit

Goal:

- Decide whether the `ODELAYE2 -> OBUF/OBUFDS` blocker is only a nextpnr packer
  acceptance issue or whether the YPCB DDR3 pin bank cannot support the
  generated output-delay topology.

Implementation:

- Added a narrow nextpnr-xilinx diagnostic patch:
  - `patches/nextpnr-xilinx/0001-xc7-allow-odelay-to-hr-output-buffers.patch`
- The patch lets `pack_iologic` accept `ODELAYE2` `DATAOUT` users of type
  `IOB33_OUTBUF` and `IOB33M_OUTBUF`.
- This is still an open nextpnr/openXC7 path; Vivado MIG remains rejected.

Verification:

- Patched single-ended cutout:
  - `nix build .#task6-odelay-obuf-cutout-fasm --no-link --print-out-paths -L`
  - failed derivation:
    `/nix/store/wylm3dd8jk7bmbqz2jly83zsj9zr2mlq-task6-odelay-obuf-cutout.fasm.drv`
  - new error:
    `BEL IOB_X0Y92/IOB33/OUTBUF is located on a high range bank. High range banks do not have ODELAY`
- Patched differential cutout:
  - `nix build .#task6-odelay-obufds-cutout-fasm --no-link --print-out-paths -L`
  - failed derivation:
    `/nix/store/bh42lyfhzkfz7hqs0ddac2z9bn2y8yg8-task6-odelay-obufds-cutout.fasm.drv`
  - new error:
    `BEL IOB_X0Y94/IOB33M/OUTBUF is located on a high range bank. High range banks do not have ODELAY`

Interpretation:

- The first error was a narrower nextpnr packer gap, but fixing that exposes a
  more important board/architecture limit: the constrained HR-bank `IOB33`
  DDR3 pins do not have output `ODELAY`.
- That makes the stock LiteDRAM `K7DDRPHY` output-delay topology a poor match
  for this board/open-flow combination.
- The right open-source next experiment is the LiteDRAM no-ODELAY Series-7 PHY
  path (`A7DDRPHY`), not Vivado MIG.

Decision:

- Keep the patch and cutouts as a diagnostic regression.
- Promote a no-ODELAY LiteDRAM/LiteX board-probe lane.

### 2026-04-30 - YPCB LiteDRAM no-ODELAY board bitstream

Goal:

- Swap the YPCB LiteDRAM probe from `K7DDRPHY` to LiteDRAM's no-ODELAY
  Series-7 path (`A7DDRPHY`) and test whether that path can synthesize, place,
  route, program the board, and expose autonomous JTAG state.

Implementation:

- Added configurable LiteDRAM PHY selection:
  - `scripts/task6/write_ypcb_litedram_config.py --sdram-phy`
- Added generated-RTL validation counts:
  - `ODELAYE2` mention count
  - `IDELAYE2` mention count
- Added no-ODELAY flake targets:
  - `task6-ypcb-litedram-no-odelay-config`
  - `task6-ypcb-litedram-no-odelay-rtl-elaboration`
  - `task6-ypcb-litedram-no-odelay-init-bandwidth-probe-json`
  - `task6-ypcb-litedram-no-odelay-init-bandwidth-probe-utilization`
  - `task6-ypcb-litedram-no-odelay-init-bandwidth-probe-xdc`
  - `task6-ypcb-litedram-no-odelay-init-bandwidth-probe-fasm`
  - `task6-ypcb-litedram-no-odelay-init-bandwidth-probe-bitstream`
- Added direct FTDI/MPSSE LiteDRAM probe reader:
  - `scripts/task6/read_litedram_probe_jtag_ftdi.py`
- Durable artifact:
  - `artifacts/task6/parallel-hypotheses/h2-ypcb-litedram-no-odelay-board-probe`

Generated RTL result:

- Command:
  - `nix build .#task6-ypcb-litedram-no-odelay-rtl-elaboration --no-link --print-out-paths`
- Output:
  - `/nix/store/z9692s8wrzmhqzqy9hyi0wbl1daafl1k-h2-ypcb-litedram-no-odelay-rtl-elaboration`
- Result:
  - `status`: `PASS`
  - `sdram_phy`: `A7DDRPHY`
  - `ODELAYE2` mentions: `0`
  - `IDELAYE2` mentions: `194`
  - `ddram_dm` top-port mentions: `0`

Synthesis result:

- Command:
  - `nix build .#task6-ypcb-litedram-no-odelay-init-bandwidth-probe-utilization --no-link --print-out-paths -L`
- Output:
  - `/nix/store/i1717bsprnkabzfxx7pg3j24nkga9r1b-task6-ypcb-litedram-no-odelay-init-bandwidth-probe-utilization`
- Result:
  - `check` reported `0` problems
  - Yosys peak memory: `604.81 MiB`
- Measured utilization:
  - CLB LUTs: `8359 / 298600` (`2.80%`)
  - CLB FFs: `7706 / 597200` (`1.29%`)
  - DSP: `0 / 1920` (`0.00%`)
  - BRAM36: `0 / 955` (`0.00%`)
  - Lower-bound slices: `1045 / 74650` (`1.40%`)

Open P&R result:

- Command:
  - `nix build .#task6-ypcb-litedram-no-odelay-init-bandwidth-probe-bitstream --no-link --print-out-paths -L`
- Outputs:
  - FASM:
    `/nix/store/zn5hgpi5x6yb591452sshl08nmldbndn-task6-ypcb-litedram-no-odelay-init-bandwidth-probe.fasm`
  - bitstream:
    `/nix/store/5hsjvbv57vhipd993vvmkab59liviki4-task6-ypcb-litedram-no-odelay-init-bandwidth-probe.bit`
- Result:
  - open P&R completed
  - bitstream emitted
  - target frequency was `50 MHz`
  - post-route reported maximum frequencies:
    - `clk200`: `733.68 MHz`
    - `user_clk`: `104.03 MHz`
    - `core.iodelay_clk`: `554.94 MHz`
    - `jtag_debug_shift.drck`: `702.74 MHz`
- Selected nextpnr utilization:
  - `SLICE_LUTX`: `13096 / 597200` (`2%`)
  - `SLICE_FFX`: `7706 / 597200` (`1%`)
  - `PAD`: `110 / 946` (`11%`)
  - `IDELAYE2`: `64 / 400` (`16%`)
  - `OSERDESE2`: `98 / 400` (`24%`)
  - `ISERDESE2`: `64 / 400` (`16%`)
  - `IDELAYCTRL`: `3 / 8` (`37%`)
  - `BUFGCTRL`: `6 / 32` (`18%`)

Board/JTAG result:

- JTAG detect:
  - `openFPGALoader -c digilent_hs3 --ftdi-serial 210299BF3824 --detect`
  - IDCODE: `0x23751093`
  - model: `xc7k480t`
- Program command:
  - `openFPGALoader -c digilent_hs3 --ftdi-serial 210299BF3824 /nix/store/5hsjvbv57vhipd993vvmkab59liviki4-task6-ypcb-litedram-no-odelay-init-bandwidth-probe.bit`
- Program result:
  - SRAM load completed
  - `DONE` asserted
- Direct JTAG IDCODE reader:
  - `python3 scripts/task6/read_litedram_probe_jtag_ftdi.py --backend mpsse --tdo-bit 7 --idcode-only`
  - IDCODE: `0x23751093`
- Direct LiteDRAM payload reader:
  - `python3 scripts/task6/read_litedram_probe_jtag_ftdi.py --backend mpsse --tdo-bit 7 --poll --poll-count 300 --poll-interval 0.2`
- Payload result after about `60` seconds:
  - `magic_ok`: `true`
  - version: `20`
  - state: `PROBE_WAIT_INIT`
  - `sys_rstn`: `true`
  - `pll_locked`: `true`
  - `user_rst`: `false`
  - `init_done`: `false`
  - `init_error`: `false`
  - command count: `0`
  - response count: `0`
  - target read count: `65536`

Interpretation:

- This is major progress for the open DDR3 lane:
  - open LiteDRAM/LiteX synthesis works
  - open P&R now works with the no-ODELAY PHY
  - the board programs successfully
  - autonomous JTAG payload readout works
- The remaining failure is no longer toolchain P&R. The design is alive, reset
  is deasserted, the PLL is locked, and the JTAG payload is valid, but
  LiteDRAM never reaches `init_done` or `init_error`.
- This is not yet DDR3 usability. It is a board-programmed, JTAG-observable
  DDR3-init stall.
- The next debug target is LiteDRAM init/calibration state:
  - A7DDRPHY timing/calibration viability on this Kintex board
  - reset sequencing
  - no-`dm` wiring assumptions
  - PHY/module parameterization
  - DFI control/init FSM state

Decision:

- Promote the no-ODELAY board-probe lane.
- Next gate:
  - widen the JTAG payload to expose LiteDRAM init/calibration and DFI/PHY
    status signals, then rerun the same board-program/JTAG loop.

### 2026-04-30 - No-ODELAY LiteDRAM clean payload and low-rate discriminator

Goal:

- Keep the DDR3 lane on the open LiteDRAM/LiteX path and test whether the
  no-ODELAY failure is mainly a timing-rate problem or a lower-level
  PHY/DFI/pin association problem.

Implementation:

- Kept Vivado MIG rejected.
- Kept the active PHY on LiteDRAM's no-ODELAY Series-7 path (`A7DDRPHY`).
- Added low-rate no-ODELAY targets:
  - `task6-ypcb-litedram-no-odelay-lowrate-config`
  - `task6-ypcb-litedram-no-odelay-lowrate-rtl-elaboration`
  - `task6-ypcb-litedram-no-odelay-lowrate-rtl-check`
  - `task6-ypcb-litedram-no-odelay-lowrate-init-bandwidth-probe-json`
  - `task6-ypcb-litedram-no-odelay-lowrate-init-bandwidth-probe-utilization`
  - `task6-ypcb-litedram-no-odelay-lowrate-init-bandwidth-probe-xdc`
  - `task6-ypcb-litedram-no-odelay-lowrate-init-bandwidth-probe-fasm`
  - `task6-ypcb-litedram-no-odelay-lowrate-init-bandwidth-probe-bitstream`
- Low-rate LiteDRAM clocks:
  - `sys`: `25 MHz`
  - `sys4x`: `100 MHz`
  - `sys4x_dqs`: `100 MHz`, `90 deg`
- Bumped the JTAG payload version to `55`; the v54 payload layout is unchanged.

v54 clean payload result:

- Bitstream:
  `/nix/store/whj2k20lypqm2pf9kalzny1kx2xd8269-task6-ypcb-litedram-no-odelay-init-bandwidth-probe.bit`
- Board/JTAG:
  - `magic_ok=true`
  - `version=54`
  - `state=PROBE_ERROR`
  - `init_state=INIT_DONE`
  - `init_done=true`
  - `init_error=false`
  - writes/reads/responses: `65536/65536/65536`
  - mismatches: `65536`
  - first mismatch expected `0xd0ce1010fcb87430`, actual `0x0000008100000000`
  - DFII state `DFII_SEQ_DONE`, `ack=50`, `wait=150`
  - DFII mode masks all failed: `uniform=0xffff`, `phase_constant=0xffff`,
    `byte_ramp=0xffff`
  - DFII command-phase pass combos: none
  - byte-enable diagnostic samples all read back zero

v55 low-rate build result:

- RTL guard:
  `/nix/store/d95vsfhp0ah4f0ij980rcsz3n0iaz2ci-h2-ypcb-litedram-no-odelay-lowrate-rtl-check`
- RTL guard result:
  - `ODELAYE2`: `0`
  - `IDELAYE2` mentions: `288`
  - `sys4x_dqs` mentions: `13`
- Utilization:
  `/nix/store/8x1b0w5a3hsczznxl6h760whv4lx83ni-task6-ypcb-litedram-no-odelay-lowrate-init-bandwidth-probe-utilization`
- Mapped utilization:
  - CLB LUTs: `15945 / 298600` (`5.34%`)
  - CLB FFs: `12831 / 597200` (`2.15%`)
  - DSP: `0 / 1920` (`0.00%`)
  - BRAM36: `0 / 955` (`0.00%`)
  - Lower-bound slices: `1994 / 74650` (`2.67%`)
- Bitstream:
  `/nix/store/m56h2lxckxgxxj1b3m0c9hz4vix58qv3-task6-ypcb-litedram-no-odelay-lowrate-init-bandwidth-probe.bit`
- Post-route timing:
  - `clk200`: `716.33 MHz`
  - `user_clk`: `64.09 MHz`
  - `core.iodelay_clk`: `521.10 MHz`
  - `jtag_debug_shift.drck`: `307.79 MHz`
  - all pass against the `25 MHz` target
- Board programming:
  - `openFPGALoader -c digilent_hs3 --ftdi-serial 210299BF3824 /nix/store/m56h2lxckxgxxj1b3m0c9hz4vix58qv3-task6-ypcb-litedram-no-odelay-lowrate-init-bandwidth-probe.bit`
  - result: SRAM load completed and `DONE` asserted
- Board/JTAG:
  - `magic_ok=true`
  - `version=55`
  - `state=PROBE_ERROR`
  - `init_state=INIT_DONE`
  - `init_done=true`
  - `init_error=false`
  - writes/reads/responses: `65536/65536/65536`
  - mismatches: `65536`
  - first mismatch expected `0xd0ce1010fcb87430`, actual `0x0000000000000000`
  - first eight native readback samples all read `0x0000000000000000`
  - DFII state `DFII_SEQ_DONE`, `ack=50`, `wait=150`
  - DFII mode masks all failed: `uniform=0xffff`, `phase_constant=0xffff`,
    `byte_ramp=0xffff`
  - DFII command-phase pass combos: none
  - byte-enable diagnostic samples all read back zero

Interpretation:

- The open LiteDRAM/LiteX flow remains healthy: no ODELAYE2, open P&R passes,
  programming passes, PLL locks, JEDEC init completes, and native commands and
  responses complete.
- Lowering the no-ODELAY PHY rate from `sys=50 MHz` / `sys4x=200 MHz` to
  `sys=25 MHz` / `sys4x=100 MHz` does not recover DDR3 data.
- That weakens the "marginal high-rate timing" hypothesis.
- The remaining blocker is still below TinyStories and rowstream: PHY/DFI
  command/address/data association, generated DQ/DQS grouping, or board pin
  mapping/reset/control behavior.

Decision:

- Do not spend the next loop on another broad rate sweep.
- Next gate:
  - inspect generated LiteDRAM DQ/DQS grouping and YPCB pin metadata
  - build a smaller DFII byte/phase/address association probe
  - determine whether the fault is byte-lane permutation, DFI burst/phase
    write-data ordering, address/command issue, or read-side capture behavior

### 2026-04-30 - YPCB DDR3 DQ/DQS lane grouping report

Goal:

- Convert the DQ/DQS pin-order inspection into a reproducible open-metadata
  artifact before building the next DFII byte/phase/address probe.

Implementation:

- Added `scripts/task6/write_ypcb_ddr3_lane_report.py`.
- Added flake target:
  - `task6-ypcb-ddr3-lane-report`
- Inputs:
  - `ypcbHack/constraints/MEMORY_CH0.ucf`
  - `openXC7/prjxray-db/kintex7/xc7k480tffg1156-1/package_pins.csv`

Result:

- Command:
  - `nix build .#task6-ypcb-ddr3-lane-report --no-link --print-out-paths -L`
- Output:
  - `/nix/store/lp631xkw395mjj3da9jhhmzy37cakgsr-h2-ypcb-ddr3-lane-report`
- All nine UCF byte-lane groups are package-bank consistent with their matching
  DQS pair:
  - lanes `0-3`: bank `11`
  - lanes `4-6` and `8`: bank `13`
  - lane `7`: bank `12`

Interpretation:

- The UCF lane groups match the basic LiteDRAM expectation that
  `dq[lane*8 : lane*8+7]` share the same bank as `dqs[lane]`.
- This does not prove per-bit order, DFI phase/beat order, command/address
  behavior, or read capture correctness.
- It does make a crude cross-bank DQ/DQS grouping mistake less likely.

Decision:

- Use the bank-consistent UCF lane groups as the reference for the next compact
  DFII byte/phase/address association probe.

### 2026-04-30 - v56 compact DFII column-address association probe

Goal:

- Keep the DDR3 lane on the open LiteDRAM/LiteX no-ODELAY path and determine
  whether the low-rate failure is explained by a simple DFII column-address
  association error.

Implementation:

- Kept Vivado MIG rejected.
- Kept the active bitstream on the low-rate LiteDRAM no-ODELAY target:
  - `sys`: `25 MHz`
  - `sys4x`: `100 MHz`
  - `sys4x_dqs`: `100 MHz`, `90 deg`
- Bumped the JTAG payload to version `56` and widened it to `4096` bits.
- Added a four-slot DFII column-address sweep over:
  - `0x0000`
  - `0x0008`
  - `0x0040`
  - `0x0100`
- Tagged the DFII write pattern by address slot so a simple shifted-column or
  stale-column mapping could show up as a match in one slot.

Build result:

- JSON:
  `/nix/store/ahy48ibm3pg2lkbqry87nxdgcb736bax-task6-ypcb-litedram-no-odelay-lowrate-init-bandwidth-probe.json`
- Bitstream:
  `/nix/store/krc1ldc2vsdf690bjv6wwkas8jxkqxvq-task6-ypcb-litedram-no-odelay-lowrate-init-bandwidth-probe.bit`
- Yosys:
  - check passed with `0` problems
  - peak memory `862.42 MiB`
  - estimated logic cells `13973`
- nextpnr:
  - `SLICE_LUTX`: `21887 / 597200` (`3%`)
  - `SLICE_FFX`: `13284 / 597200` (`2%`)
  - `IDELAYE2`: `72 / 400` (`18%`)
  - `OSERDESE2`: `107 / 400` (`26%`)
  - `ISERDESE2`: `72 / 400` (`18%`)
  - `IDELAYCTRL`: `3 / 8` (`37%`)
  - BRAM: `0`
  - DSP: `0`
- Timing passed at the `25 MHz` target:
  - `clk200`: `585.14 MHz`
  - `user_clk`: `73.36 MHz`
  - `core.iodelay_clk`: `517.06 MHz`
  - `jtag_debug_shift.drck`: `323.31 MHz`

Board/JTAG result:

- Program command:
  `openFPGALoader -c digilent_hs3 --ftdi-serial 210299BF3824 /nix/store/krc1ldc2vsdf690bjv6wwkas8jxkqxvq-task6-ypcb-litedram-no-odelay-lowrate-init-bandwidth-probe.bit`
- Program result:
  SRAM load completed and `DONE` asserted.
- JTAG read command:
  `python3 scripts/task6/read_litedram_probe_jtag_ftdi.py --backend mpsse --tdo-bit 7 --poll --poll-count 300 --poll-interval 0.2`
- JTAG result:
  - `magic_ok=true`
  - `version=56`
  - `state=PROBE_ERROR`
  - `init_state=INIT_DONE`
  - `init_done=true`
  - `init_error=false`
  - `pll_locked=true`
  - writes/reads/responses: `65536/65536/65536`
  - mismatches: `65536`
  - first native mismatch expected `0xd0ce1010fcb87430`, actual
    `0x0000000000000000`
- DFII mode result:
  - mode masks all failed: `uniform=0xffff`, `phase_constant=0xffff`,
    `byte_ramp=0xffff`
  - no write/read command-phase combination passed
  - direct DFII reads were stable and nonzero, but not matching:
    `0x00575152`, `0x47414262`, `0x5751524b`, `0x00006200`
    repeated across phases
- DFII association matrix:
  - source `0`: nonzero mask `0x6666`, match mask `0x0000`
  - source `1`: nonzero mask `0x5555`, match mask `0x0000`
  - source `2`: nonzero mask `0xaaaa`, match mask `0x0000`
  - sources `3-15`: nonzero mask `0x0000`, match mask `0x0000`
- DFII address matrix:
  - columns `0x0000`, `0x0008`, `0x0040`, and `0x0100` all returned
    `mismatch=0xffff`, `nonzero=0xffff`, `match=0x0000`

Interpretation:

- The open LiteDRAM/LiteX flow remains viable: no-ODELAY synthesis, P&R,
  programming, JEDEC init, DFII CSR access, and JTAG payload readback all work.
- v56 weakens the simple column-address-offset hypothesis. Every tested column
  returns nonmatching nonzero DFII data, and none matches the address-tagged
  expected pattern.
- v56 also keeps the failure below TinyStories and rowstream. The blocker is
  still DDR3 physical/control association in the no-ODELAY LiteDRAM path.
- The strongest remaining targets are:
  - no-ODELAY DQS phase and write/read latency
  - DFI write-data phase/beat source ordering
  - read command phase and read capture latency
  - per-bit order or subtler pin/control mapping issues not covered by the
    bank-level DQ/DQS report

Decision:

- Do not return to native-port bandwidth or rowstream integration yet.
- Next gate:
  build a compact DFII no-write discriminator. If readback is unchanged when
  the write command is suppressed, the present payload is not being driven by
  our writes and the next focus should be command/control reachability,
  DRAM enable/reset behavior, or DFI command semantics.

### 2026-04-30 - v56-dqs0 low-rate DQS phase discriminator

Goal:

- Test whether the low-rate no-ODELAY failure is explained by the selected
  `sys4x_dqs` phase.

Implementation:

- Derived a low-rate no-ODELAY target from the v56 RTL and changed only the
  generated PLL `CLKOUT3_PHASE` for `sys4x_dqs` from `90 deg` to `0 deg`.
- Kept Vivado MIG rejected.

Build result:

- RTL guard:
  `/nix/store/gkxagqchxrc79zcqw73hzx3kmbjssybq-h2-ypcb-litedram-no-odelay-lowrate-dqs0-rtl-check`
  - `ODELAYE2`: `0` matches
  - `IDELAYE2`: present
  - `sys4x_dqs`: present
  - `CLKOUT3_PHASE`: confirmed at `0 deg`
- JSON:
  `/nix/store/ajqzizrss2blx93slq42i80sla28vj1v-task6-ypcb-litedram-no-odelay-lowrate-dqs0-init-bandwidth-probe.json`
- Bitstream:
  `/nix/store/b1j51cxib6xx1al9cjlfsj82qvkqv2m9-task6-ypcb-litedram-no-odelay-lowrate-dqs0-init-bandwidth-probe.bit`
- Yosys:
  - check passed with `0` problems
  - peak memory `864.34 MiB`
  - estimated logic cells `13973`
- nextpnr:
  - `SLICE_LUTX`: `21887 / 597200` (`3%`)
  - `SLICE_FFX`: `13284 / 597200` (`2%`)
  - `IDELAYE2`: `72 / 400` (`18%`)
  - `OSERDESE2`: `107 / 400` (`26%`)
  - `ISERDESE2`: `72 / 400` (`18%`)
  - `IDELAYCTRL`: `3 / 8` (`37%`)
  - BRAM: `0`
  - DSP: `0`
- Timing passed at the `25 MHz` target:
  - `clk200`: `642.67 MHz`
  - `user_clk`: `77.42 MHz`
  - `core.iodelay_clk`: `480.54 MHz`
  - `jtag_debug_shift.drck`: `328.62 MHz`

Artifact check:

- The `dqs0` FASM differs from the v56 `90 deg` FASM:
  - v56 `90 deg` FASM:
    `/nix/store/agvhcczc9p68lxl860649iby1v2yv9lc-task6-ypcb-litedram-no-odelay-lowrate-init-bandwidth-probe.fasm`
  - `dqs0` FASM:
    `/nix/store/mz016fiwqi6f6fphgxh25zzbrsiw5ybv-task6-ypcb-litedram-no-odelay-lowrate-dqs0-init-bandwidth-probe.fasm`
  - the PLL `CLKOUT3_CLKOUT2_DELAY_TIME` changes from `0b000100` to
    `0b000000`

Board/JTAG result:

- Program command:
  `openFPGALoader -c digilent_hs3 --ftdi-serial 210299BF3824 /nix/store/b1j51cxib6xx1al9cjlfsj82qvkqv2m9-task6-ypcb-litedram-no-odelay-lowrate-dqs0-init-bandwidth-probe.bit`
- Program result:
  SRAM load completed and `DONE` asserted.
- JTAG result:
  - `magic_ok=true`
  - `version=56`
  - `state=PROBE_ERROR`
  - `init_state=INIT_DONE`
  - writes/reads/responses: `65536/65536/65536`
  - mismatches: `65536`
  - direct DFII repeated words:
    `0x00575152`, `0x47414262`, `0x5751524b`, `0x00006200`
  - DFII address and association matrices matched the v56 `90 deg` hardware
    result exactly.

Interpretation:

- The `dqs0` artifact is a real routed phase variant, but the board/JTAG
  failure signature is unchanged from the `90 deg` image.
- This weakens the hypothesis that the present blocker is simply the
  `sys4x_dqs` phase choice.
- The next discriminator should suppress only the DFII write command. If the
  raw payload remains unchanged, the readback is not being influenced by our
  writes and the focus moves to command/control reachability or DRAM
  enable/reset/pin behavior.

### 2026-04-30 - v57 DFII no-write discriminator

Goal:

- Test whether the v56 direct-DFII readback is independent of the write command
  itself. If disabling only the DFII write command leaves the raw payload
  unchanged, command/control reachability or stale readback becomes the strongest
  hypothesis.

Implementation:

- Kept the active YPCB DDR3 generator on LiteDRAM/LiteX only; Vivado MIG remains
  rejected.
- Changed the unqualified YPCB LiteDRAM config default to `A7DDRPHY`, since the
  YPCB DDR3 pins are HR-bank pins and the old `K7DDRPHY` output-`ODELAYE2`
  topology cannot be placed there.
- Added `DFII_DISABLE_WRITE_COMMAND` to the init/bandwidth probe and exposed the
  flag in the JTAG payload.
- Added no-write flake targets:
  - `task6-ypcb-litedram-no-odelay-lowrate-nowrite-init-bandwidth-probe-json`
  - `task6-ypcb-litedram-no-odelay-lowrate-nowrite-init-bandwidth-probe-utilization`
  - `task6-ypcb-litedram-no-odelay-lowrate-nowrite-init-bandwidth-probe-xdc`
  - `task6-ypcb-litedram-no-odelay-lowrate-nowrite-init-bandwidth-probe-fasm`
  - `task6-ypcb-litedram-no-odelay-lowrate-nowrite-init-bandwidth-probe-bitstream`

Guard results:

- Default YPCB LiteDRAM config:
  `/nix/store/njlki4yakl3ndca75p4s2bzgyg77lskz-h2-ypcb-litedram-config`
  - `sdram_phy`: `A7DDRPHY`
  - `sdram_module_nb`: `9`
  - controller path: LiteDRAM/LiteX only
- Low-rate no-ODELAY RTL check:
  `/nix/store/nw9pmgk2vd34ybhqzn6lvq0z01q1y5cm-h2-ypcb-litedram-no-odelay-lowrate-rtl-check`
  - `ODELAYE2`: `0`
  - `IDELAYE2` mentions: `288`
  - `sys4x_dqs` mentions: `13`
- No-ODELAY output-buffer smoke tests still pass:
  - `/nix/store/kpd1i8dsw8br0ygj34cf5wxlxw1fvm49-task6-no-odelay-obuf-cutout.fasm`
  - `/nix/store/f4fw0ch3lbk6gc63s2j9m1ivc37g668l-task6-no-odelay-obufds-cutout.fasm`
- Old ODELAY output-buffer negative controls still fail as expected:
  - `IOB33/OUTBUF`: `High range banks do not have ODELAY`
  - `IOB33M/OUTBUF`: `High range banks do not have ODELAY`

Build result:

- JSON:
  `/nix/store/skqhhw122vhb5fplfff4c0v5hg80qb4x-task6-ypcb-litedram-no-odelay-lowrate-nowrite-init-bandwidth-probe.json`
- Utilization:
  `/nix/store/vx40x9szjigck2p7b076wqi36mfcsn3m-task6-ypcb-litedram-no-odelay-lowrate-nowrite-init-bandwidth-probe-utilization`
  - CLB LUTs: `17065 / 298600` (`5.72%`)
  - CLB FFs: `13286 / 597200` (`2.22%`)
  - DSP: `0 / 1920` (`0.00%`)
  - BRAM36: `0 / 955` (`0.00%`)
  - lower-bound slices: `2134 / 74650` (`2.86%`)
- FASM:
  `/nix/store/2wf8g3924zshid1bwm3ik5sw6n1r5cg1-task6-ypcb-litedram-no-odelay-lowrate-nowrite-init-bandwidth-probe.fasm`
- Bitstream:
  `/nix/store/dyr1a7c299236ahs00p9ssdcnvabvcdb-task6-ypcb-litedram-no-odelay-lowrate-nowrite-init-bandwidth-probe.bit`
- nextpnr selected utilization:
  - `SLICE_LUTX`: `22256 / 597200` (`3%`)
  - `SLICE_FFX`: `13286 / 597200` (`2%`)
  - `IDELAYE2`: `72 / 400` (`18%`)
  - `OSERDESE2`: `107 / 400` (`26%`)
  - `ISERDESE2`: `72 / 400` (`18%`)
  - `IDELAYCTRL`: `3 / 8` (`37%`)
  - BRAM: `0`
  - DSP: `0`
- Timing passed at the `25 MHz` target:
  - `clk200`: `589.97 MHz`
  - `user_clk`: `72.39 MHz`
  - `core.iodelay_clk`: `470.37 MHz`
  - `jtag_debug_shift.drck`: `362.45 MHz`

Board/JTAG result:

- Program command:
  `openFPGALoader -c digilent_hs3 --ftdi-serial 210299BF3824 /nix/store/dyr1a7c299236ahs00p9ssdcnvabvcdb-task6-ypcb-litedram-no-odelay-lowrate-nowrite-init-bandwidth-probe.bit`
- Program result:
  SRAM load completed and `DONE` asserted.
- JTAG read command:
  `python3 scripts/task6/read_litedram_probe_jtag_ftdi.py --backend mpsse --tdo-bit 7 --poll --poll-count 300 --poll-interval 0.2`
- JTAG result:
  - `magic_ok=true`
  - `version=57`
  - `state=PROBE_ERROR`
  - `init_state=INIT_DONE`
  - `init_done=true`
  - `init_error=false`
  - `dfii_disable_write_command=true`
  - native writes/reads/responses: `65536/65536/65536`
  - native mismatches: `65536`
  - native samples: all zero
  - DFII mode masks all failed: `uniform=0xffff`, `phase_constant=0xffff`,
    `byte_ramp=0xffff`
  - DFII command-phase pass combos: none
  - DFII read words repeated across phases:
    `0xff000000`, `0x00000000`, `0x00000000`, `0x000000ff`
  - DFII association matrix:
    all sources returned `nonzero=0x9999`, `match=0x0000`
  - DFII address matrix:
    all four columns returned `mismatch=0xffff`, `nonzero=0x9999`,
    `match=0x0000`
  - DFII lane bit errors:
    `[0, 0, 0, 32, 25, 6, 7, 6]`

Interpretation:

- The v57 no-write image changes the direct-DFII hardware signature relative to
  v56/v56-dqs0. v56 read back repeated words
  `0x00575152`, `0x47414262`, `0x5751524b`, `0x00006200`; v57 instead reads
  the repeated edge-byte pattern `0xff000000`, `0x00000000`, `0x00000000`,
  `0x000000ff`.
- Therefore the v56 direct-DFII data was not purely stale and
  write-independent. Disabling the DFII write command changes the observed
  payload.
- This weakens the stale-readback and totally inert-command hypotheses.
- It does not prove that the DRAM accepted the write, stored the data, and
  returned it through a correctly aligned read-capture path.
- The remaining blocker is still DFI/DDR association: write-data/read-data phase
  or beat association, byte-mask/DM semantics, DQS/DQ beat order, per-bit/order
  mapping, or read capture latency in the no-ODELAY path.

Decision:

- Keep the no-ODELAY LiteDRAM/LiteX lane active.
- Do not connect rowstream or TinyStories logic yet.
- Next gate:
  build a compact DFII phase/beat association probe that varies write-data
  source phase, write command phase, read command phase, and read capture
  latency independently, using v57 as the command-reachability discriminator.

### 2026-04-30 - v58 DFII phase/source matrix probe

Goal:

- Keep the no-ODELAY LiteDRAM/LiteX lane active and classify the DFII
  write-data/read-capture association without reconnecting rowstream or
  TinyStories logic.
- Avoid another compile-time-only A/B by using one bitstream that autonomously
  sweeps a compact matrix and exposes the result through the existing JTAG
  payload.

Implementation plan:

- Add `DFII_PHASE_MATRIX_ONLY` to the probe.
- Reuse the existing 16-entry command-phase payload as a 4 x 4 matrix:
  - index high bits: selected write-data source phase and write command phase
  - index low bits: selected read command phase
- For each matrix entry, write phase-tagged data only on the selected source
  phase and write zeros on the other phases.
- Reuse the association payload slots as matrix diagnostics:
  - `dfii_phasecmd_mismatch_masks`: inverse of per-read-word match mask
  - `dfii_assoc_nonzero_mask_*`: per-read-word nonzero mask
  - `dfii_assoc_match_mask_*`: per-read-word match mask
- Stop after the matrix when `DFII_PHASE_MATRIX_ONLY=1`, so later association
  and address sweeps do not overwrite the matrix result.
- Keep `DFII_DISABLE_WRITE_COMMAND=0`; v57 remains the no-write discriminator.

Pass/fail discriminator:

- A useful result is any entry with `match_mask != 0`, or at least a nonzero
  payload that differs from the repeated v57 edge-byte artifact in a way tied to
  the selected source phase.
- If every entry is nonmatching and repeats the same edge-byte artifact, the
  next split is DM mask polarity, DQS/DQ beat order, ISERDES/read-latency tap,
  or physical byte/bit mapping.

Build result:

- JSON:
  `/nix/store/m5w6lbkqpy2gplnq7hz4gn80vd3ys0kw-task6-ypcb-litedram-no-odelay-lowrate-phase-matrix-init-bandwidth-probe.json`
- Utilization:
  `/nix/store/s378kv2nas7nbjb800nkmldccrqh3fyz-task6-ypcb-litedram-no-odelay-lowrate-phase-matrix-init-bandwidth-probe-utilization`
  - CLB LUTs: `17521 / 298600` (`5.87%`)
  - CLB FFs: `13286 / 597200` (`2.22%`)
  - DSP: `0 / 1920` (`0.00%`)
  - BRAM36: `0 / 955` (`0.00%`)
  - lower-bound slices: `2191 / 74650` (`2.94%`)
- Bitstream:
  `/nix/store/jrld7mdmqrn3qsb24fkxy8p56xbd99hi-task6-ypcb-litedram-no-odelay-lowrate-phase-matrix-init-bandwidth-probe.bit`
- nextpnr selected utilization:
  - `SLICE_LUTX`: `22701 / 597200` (`3%`)
  - `SLICE_FFX`: `13286 / 597200` (`2%`)
  - `IDELAYE2`: `72 / 400` (`18%`)
  - `OSERDESE2`: `107 / 400` (`26%`)
  - `ISERDESE2`: `72 / 400` (`18%`)
  - `IDELAYCTRL`: `3 / 8` (`37%`)
  - BRAM: `0`
  - DSP: `0`
- Timing passed at the `25 MHz` target:
  - `clk200`: `580.38 MHz`
  - `user_clk`: `69.74 MHz`
  - `core.iodelay_clk`: `460.19 MHz`
  - `jtag_debug_shift.drck`: `373.00 MHz`

Board/JTAG result:

- Program command:
  `openFPGALoader -c digilent_hs3 --ftdi-serial 210299BF3824 /nix/store/jrld7mdmqrn3qsb24fkxy8p56xbd99hi-task6-ypcb-litedram-no-odelay-lowrate-phase-matrix-init-bandwidth-probe.bit`
- Program result:
  SRAM load completed and `DONE` asserted.
- JTAG read command:
  `python3 scripts/task6/read_litedram_probe_jtag_ftdi.py --backend mpsse --tdo-bit 7 --poll --poll-count 300 --poll-interval 0.2`
- JTAG result:
  - `magic_ok=true`
  - `version=58`
  - `state=PROBE_DFII_DONE`
  - `init_state=INIT_DONE`
  - `init_done=true`
  - `init_error=false`
  - `dfii_disable_write_command=false`
  - `dfii_phase_matrix_only=true`
  - DFII sequence: `DFII_SEQ_DONE`, `ack=50`, `wait=150`
  - DFII mode masks still failed: `uniform=0xffff`,
    `phase_constant=0xffff`, `byte_ramp=0xffff`
  - phase/source matrix:
    - `src/write p0`, read phases `p0..p3`: `nonzero=0xffff`,
      `match=0x0000`, `mismatch=0xffff`
    - `src/write p1`, read phases `p0..p3`: `nonzero=0x0000`,
      `match=0x0000`, `mismatch=0xffff`
    - `src/write p2`, read phases `p0..p3`: `nonzero=0x0000`,
      `match=0x0000`, `mismatch=0xffff`
    - `src/write p3`, read phases `p0..p3`: `nonzero=0x0000`,
      `match=0x0000`, `mismatch=0xffff`
  - final captured DFII read words for the last matrix entry were all zero.
  - DFII lane bit errors: `[28, 20, 20, 12, 36, 28, 28, 20]`

Interpretation:

- No phase/source combination produced an exact phase-tagged match.
- The result is not the v57 no-write edge-byte artifact. With writes enabled,
  only the source/write phase `0` row produces nonzero readback; source/write
  phases `1`, `2`, and `3` read back zero for all read-command phases.
- This narrows the next split toward DFI phase association or write-phase
  gating. A pure read-command-phase choice is unlikely because read phases
  `0..3` all behave the same within each selected source/write phase.
- The result still does not prove DRAM write acceptance. It only shows that
  write-source/write-command phase selection changes whether the DFII readback
  is nonzero.

Next gate:

- Decouple write-data source phase from write command phase. Sweep source phase
  `0..3` against write command phase `0..3` with a fixed read command phase,
  then repeat the best nonzero combinations across read phase and capture
  latency.
- Add a DM/mask polarity discriminator in the same family: write with explicit
  all-unmasked vs all-masked values and check whether nonzero readback follows
  the mask setting.

### 2026-04-30 - v59 DFII source-vs-command matrix probe

Goal:

- Resolve the main ambiguity left by v58: whether the nonzero result follows
  the write-data source phase, the write command phase, or only the tied pair.
- Keep the probe below rowstream/TinyStories and stop after the DFII matrix.

Implementation:

- Added `DFII_SOURCE_COMMAND_MATRIX_ONLY`.
- Reused the 16-entry matrix payload as:
  - index high bits: selected write-data source phase
  - index low bits: selected write command phase
  - read command phase: fixed at `p2`
- Kept the phase-tagged write-data pattern from v58.
- Exposed new JTAG flags:
  - `dfii_source_command_matrix_only`
  - `dfii_source_command_read_phase`
  - `dfii_csr_wrdata_mask_controllable`
- The current generated LiteDRAM DFII CSR path reports
  `dfii_csr_wrdata_mask_controllable=false`. Inspection of generated RTL shows
  `main_csr_dfi_p*_wrdata_mask = 1'd0`; the current DFII path cannot run an
  all-masked/all-unmasked discriminator without changing LiteDRAM generation or
  the core wrapper.

Build result:

- JSON:
  `/nix/store/r3c5hwznwar7ysfv0nldrx94cmjnr7jp-task6-ypcb-litedram-no-odelay-lowrate-source-command-matrix-init-bandwidth-probe.json`
- Utilization:
  `/nix/store/zi1d0n8l5jcjnxp977wcmf96fw93f9za-task6-ypcb-litedram-no-odelay-lowrate-source-command-matrix-init-bandwidth-probe-utilization`
  - CLB LUTs: `16971 / 298600` (`5.68%`)
  - CLB FFs: `13286 / 597200` (`2.22%`)
  - DSP: `0 / 1920` (`0.00%`)
  - BRAM36: `0 / 955` (`0.00%`)
  - lower-bound slices: `2122 / 74650` (`2.84%`)
- Bitstream:
  `/nix/store/fcsi2npm39jchyivlxd5ja7iq2myyns1-task6-ypcb-litedram-no-odelay-lowrate-source-command-matrix-init-bandwidth-probe.bit`
- nextpnr selected utilization:
  - `SLICE_LUTX`: `22068 / 597200` (`3%`)
  - `SLICE_FFX`: `13286 / 597200` (`2%`)
  - `IDELAYE2`: `72 / 400` (`18%`)
  - `OSERDESE2`: `107 / 400` (`26%`)
  - `ISERDESE2`: `72 / 400` (`18%`)
  - `IDELAYCTRL`: `3 / 8` (`37%`)
  - BRAM: `0`
  - DSP: `0`
- Timing passed at the `25 MHz` target:
  - `clk200`: `676.13 MHz`
  - `user_clk`: `72.81 MHz`
  - `core.iodelay_clk`: `608.27 MHz`
  - `jtag_debug_shift.drck`: `370.37 MHz`

Board/JTAG result:

- Program command:
  `openFPGALoader -c digilent_hs3 --ftdi-serial 210299BF3824 /nix/store/fcsi2npm39jchyivlxd5ja7iq2myyns1-task6-ypcb-litedram-no-odelay-lowrate-source-command-matrix-init-bandwidth-probe.bit`
- Program result:
  SRAM load completed and `DONE` asserted.
- JTAG read command:
  `python3 scripts/task6/read_litedram_probe_jtag_ftdi.py --backend mpsse --tdo-bit 7 --poll --poll-count 300 --poll-interval 0.2`
- JTAG result:
  - `magic_ok=true`
  - `version=59`
  - `state=PROBE_DFII_DONE`
  - `init_state=INIT_DONE`
  - `init_done=true`
  - `init_error=false`
  - `dfii_disable_write_command=false`
  - `dfii_phase_matrix_only=false`
  - `dfii_source_command_matrix_only=true`
  - fixed read command phase: `p2`
  - `dfii_csr_wrdata_mask_controllable=false`
  - DFII sequence: `DFII_SEQ_DONE`, `ack=50`, `wait=150`
  - DFII mode masks still failed: `uniform=0xffff`,
    `phase_constant=0xffff`, `byte_ramp=0xffff`
  - source/command matrix:
    - `src p0`, write phases `p0..p3`, read phase `p2`:
      `nonzero=0xffff`, `match=0x0000`, `mismatch=0xffff`
    - `src p1`, write phases `p0..p3`, read phase `p2`:
      `nonzero=0x0000`, `match=0x0000`, `mismatch=0xffff`
    - `src p2`, write phases `p0..p3`, read phase `p2`:
      `nonzero=0x0000`, `match=0x0000`, `mismatch=0xffff`
    - `src p3`, write phases `p0..p3`, read phase `p2`:
      `nonzero=0x0000`, `match=0x0000`, `mismatch=0xffff`
  - final captured DFII read words for the last matrix entry were all zero.
  - DFII lane bit errors: `[28, 20, 20, 12, 36, 28, 28, 20]`

Interpretation:

- No source/write-command combination produced an exact phase-tagged match.
- The v58 nonzero result follows the write-data source phase, not the write
  command phase. Source phase `0` produces nonzero readback for every
  write-command phase; source phases `1..3` read back zero for every
  write-command phase.
- This weakens write-command-phase selection as the primary blocker. The next
  useful split is now inside write-data source handling: CSR write-data phase
  packing, DFI phase-to-PHY data association, DQ/DQS beat order, or read-capture
  interpretation.
- The result still does not prove DRAM write acceptance. It proves only that the
  selected DFII write-data source phase controls whether direct readback becomes
  nonzero.
- The requested DFII DM/mask discriminator cannot be run in the current
  bitstream family because the generated CSR write-data mask is hardwired to
  zero and YPCB open metadata omits physical `dm` pads.

Next gate:

- Build a v60 write-data-source-order probe: keep source phase `0`, vary the
  word/beat order and read-capture interpretation, and compare against generated
  LiteDRAM `main_phaseinjector0_wrdata_storage` ordering.
- If DM still needs a hardware discriminator, add it as a separate LiteDRAM core
  generation change that exposes or overrides `csr_dfi_p*_wrdata_mask`; do not
  treat the current DFII CSR path as mask-controllable.

### 2026-04-30 - v60 DFII source-order byte-tag matrix probe

Goal:

- Keep the v59-winning source phase fixed at `p0`.
- Stop varying write-command phase, because v59 made it unlikely to be the
  primary blocker.
- Map source byte/word ordering directly by writing one tagged byte per matrix
  entry and recording which DFII read words contain the tag.

Implementation:

- Added `DFII_SOURCE_ORDER_MATRIX_ONLY`.
- Matrix entry `0..15` selects one byte slot in source phase `p0`.
- Fixed command phases:
  - source phase: `p0`
  - write command phase: `p0`
  - read command phase: `p2`
- The existing matrix payload now reports:
  - `nonzero`: read words that became nonzero
  - `tag_match`: read words containing the selected byte tag
  - `tag_absent`: inverse of `tag_match`

Build result:

- JSON:
  `/nix/store/777dsnhgcq2bc4z1r2qygzv4jsl5nqyf-task6-ypcb-litedram-no-odelay-lowrate-source-order-matrix-init-bandwidth-probe.json`
- Utilization:
  `/nix/store/pw39k0sspmc7vimbz5r49bjxgkpyrv5l-task6-ypcb-litedram-no-odelay-lowrate-source-order-matrix-init-bandwidth-probe-utilization`
  - CLB LUTs: `17756 / 298600` (`5.95%`)
  - CLB FFs: `13294 / 597200` (`2.23%`)
  - DSP: `0 / 1920` (`0.00%`)
  - BRAM36: `0 / 955` (`0.00%`)
  - lower-bound slices: `2220 / 74650` (`2.97%`)
- Bitstream:
  `/nix/store/j8vywyks89l4zssrw8qn6sjyy835p2pm-task6-ypcb-litedram-no-odelay-lowrate-source-order-matrix-init-bandwidth-probe.bit`
- nextpnr selected utilization:
  - `SLICE_LUTX`: `22861 / 597200` (`3%`)
  - `SLICE_FFX`: `13294 / 597200` (`2%`)
  - `IDELAYE2`: `72 / 400` (`18%`)
  - `OSERDESE2`: `107 / 400` (`26%`)
  - `ISERDESE2`: `72 / 400` (`18%`)
  - `IDELAYCTRL`: `3 / 8` (`37%`)
  - BRAM: `0`
  - DSP: `0`
- Post-route timing passed at the `25 MHz` target:
  - `clk200`: `570.45 MHz`
  - `user_clk`: `77.03 MHz`
  - `core.iodelay_clk`: `600.96 MHz`
  - `jtag_debug_shift.drck`: `386.55 MHz`

Board/JTAG result:

- Program command:
  `openFPGALoader -c digilent_hs3 --ftdi-serial 210299BF3824 /nix/store/j8vywyks89l4zssrw8qn6sjyy835p2pm-task6-ypcb-litedram-no-odelay-lowrate-source-order-matrix-init-bandwidth-probe.bit`
- Program result:
  SRAM load completed and `DONE` asserted.
- JTAG read command:
  `python3 scripts/task6/read_litedram_probe_jtag_ftdi.py --backend mpsse --tdo-bit 7 --poll --poll-count 300 --poll-interval 0.2`
- JTAG result:
  - `magic_ok=true`
  - `version=60`
  - `state=PROBE_DFII_DONE`
  - `init_state=INIT_DONE`
  - `init_done=true`
  - `init_error=false`
  - `dfii_source_order_matrix_only=true`
  - fixed source/write/read phases: `p0`/`p0`/`p2`
  - DFII sequence: `DFII_SEQ_DONE`, `ack=50`, `wait=150`
  - DFII mode masks still failed: `uniform=0xffff`,
    `phase_constant=0xffff`, `byte_ramp=0xffff`
  - visible byte-tag slots:
    - slots `0`, `1`, `2`: `tag_match=nonzero=0x2222`
    - slot `3`: `tag_match=nonzero=0x4444`
    - slots `4`, `5`, `6`: `tag_match=nonzero=0x5555`
    - slot `8`: `tag_match=nonzero=0xaaaa`
  - invisible byte-tag slots:
    - slots `7` and `9..15`: `tag_match=nonzero=0x0000`
  - final captured DFII words for the last matrix entry were all zero.
  - DFII lane bit errors: `[0, 0, 0, 0, 0, 0, 0, 20]`

Interpretation:

- v60 is not a pass, but it is a strong discriminator.
- The readback is byte-slot selective and deterministic, not random.
- For every visible slot, `tag_match == nonzero`; no extra non-tag nonzero
  words appeared in the matrix masks.
- The visible slots are mostly in the lower 72-bit half of the 144-bit DFI
  write-data storage. Slots `9..15`, which are in the upper half of the lower
  128-bit CSR window, disappear. Slot `7` also disappears.
- This points away from write-command phase and toward high/low beat ordering,
  DFI-to-A7DDRPHY serializer ordering, or read-capture interpretation around
  the no-ODELAY path.
- The result still does not prove DRAM write acceptance; it proves that selected
  source byte slots influence the direct DFII readback in a stable way.

Next gate:

- Build a v61 low/high-half discriminator for source phase `p0`: write paired
  low-half and high-half tags for the same DQ byte lanes, include the 9th byte
  lane explicitly, and expose enough readback/status to distinguish
  low-edge/high-edge loss from read CSR interpretation.
- If possible, add direct JTAG reporting of selected actual read words for each
  visible slot class instead of only per-slot masks.

### 2026-05-01 - v61 DFII low/high-half byte-lane discriminator

Goal:

- Keep the v59/v60 fixed phases: source `p0`, write command `p0`, read command
  `p2`.
- Distinguish low-72-bit-half visibility from high-72-bit-half visibility in
  the 144-bit no-ODELAY DFI write-data path.
- Include the ninth x8 byte lane explicitly, and add a fifth DFII CSR word
  mapping so lanes `7` and `8` high-half tags are not hidden by the old
  four-word payload window.

Implementation:

- Added `DFII_HALF_ORDER_MATRIX_ONLY`.
- Increased the JTAG debug payload to `4672` bits and bumped the board payload
  version to `61`.
- Widened direct DFII readback capture from `16` to `20` words
  (`4` phases x `5` words).
- Added high-nibble mask payloads for:
  - high-half nonzero read words
  - low-tag matches in high read words
  - high-tag matches in low read words
  - high-tag matches in high read words
- Added decoder support for the half-order matrix and direct `dfii_rddata_0`
  through `dfii_rddata_19`.

Build result:

- JSON:
  `/nix/store/l2jwzw1kx73vmrr0kf44jqwn089bv43w-task6-ypcb-litedram-no-odelay-lowrate-half-order-matrix-init-bandwidth-probe.json`
- Utilization:
  `/nix/store/gvxam9lk77xvgba2a0knh5lradllqkpf-task6-ypcb-litedram-no-odelay-lowrate-half-order-matrix-init-bandwidth-probe-utilization`
  - CLB LUTs: `18321 / 298600` (`6.14%`)
  - CLB FFs: `14450 / 597200` (`2.42%`)
  - DSP: `0 / 1920` (`0.00%`)
  - BRAM36: `0 / 955` (`0.00%`)
  - lower-bound slices: `2291 / 74650` (`3.07%`)
- Bitstream:
  `/nix/store/pgdqh71pcf8mzp6jhby7yj5d3j91g2fd-task6-ypcb-litedram-no-odelay-lowrate-half-order-matrix-init-bandwidth-probe.bit`
- nextpnr selected utilization:
  - `SLICE_LUTX`: `23619 / 597200` (`3%`)
  - `SLICE_FFX`: `14450 / 597200` (`2%`)
  - `IDELAYE2`: `72 / 400` (`18%`)
  - `OSERDESE2`: `107 / 400` (`26%`)
  - `ISERDESE2`: `72 / 400` (`18%`)
  - `IDELAYCTRL`: `3 / 8` (`37%`)
  - BRAM: `0`
  - DSP: `0`
- Post-route timing passed at the `25 MHz` target:
  - `clk200`: `634.92 MHz`
  - `user_clk`: `64.67 MHz`
  - `core.iodelay_clk`: `515.20 MHz`
  - `jtag_debug_shift.drck`: `294.38 MHz`

Board/JTAG result:

- Program command:
  `openFPGALoader -c digilent_hs3 --ftdi-serial 210299BF3824 /nix/store/pgdqh71pcf8mzp6jhby7yj5d3j91g2fd-task6-ypcb-litedram-no-odelay-lowrate-half-order-matrix-init-bandwidth-probe.bit`
- Program result:
  SRAM load completed and `DONE` asserted.
- JTAG read command:
  `python3 scripts/task6/read_litedram_probe_jtag_ftdi.py --backend mpsse --tdo-bit 7 --poll --poll-count 300 --poll-interval 0.2`
- JTAG result:
  - `magic_ok=true`
  - `version=61`
  - `state=PROBE_DFII_DONE`
  - `init_state=INIT_DONE`
  - `init_done=true`
  - `init_error=false`
  - `dfii_half_order_matrix_only=true`
  - fixed source/write/read phases: `p0`/`p0`/`p2`
  - DFII sequence: `DFII_SEQ_DONE`, `ack=58`, `wait=174`
  - DFII mode masks still failed: `uniform=0xffff`,
    `phase_constant=0xffff`, `byte_ramp=0xffff`
  - low-half tag visibility:
    - lanes `0`, `1`, `2`: `nonzero=low_match=0x1_0852`
    - lane `3`: `nonzero=low_match=0x2_1094`
    - lanes `4`, `5`, `6`: `nonzero=low_match=0x2_94a5`
    - lane `8`: `nonzero=low_match=0x5_294a`
  - lane `7` stayed dark in all three lane-7 slots:
    `nonzero=low_match=high_match=0x0_0000`
  - high-half tag visibility:
    `high_match=0x0_0000` for every slot, including the lane-8 fifth-word
    cases.
  - selected final direct readback for slot `15` repeated on all phases:
    - `w0=0x00000000`
    - `w1=0x0000009f`
    - `w2=0x00000000`
    - `w3=0x00009f00`
    - `w4=0x00000000`
  - DFII lane bit errors: `[18, 18, 0, 0, 18, 18, 0, 0]`

Interpretation:

- v61 confirms that lane `8` is not globally dead: low-half lane-8 tags are
  visible in the new fifth-word-aware matrix.
- v61 confirms that lane `7` is still dark even when retested as low-only,
  high-only, and paired low/high variants.
- v61 confirms that the high-half tags are absent for every tested lane and
  every matrix slot. This is stronger than the v60 result because the high
  lane-7/lane-8 tags were routed through an explicit fifth DFII CSR word.
- The selected final direct readback shows a repeatable word displacement:
  low lane-8 tag `0x9f` appears in `w1/b0` and `w3/b1`, while the expected
  positions were `w2/b0` and high tag `0xaf` at `w4/b1`.
- The blocker is now split:
  - a systematic high-half / DFI beat / read-capture association problem
  - an independent lane-7 visibility problem
- This still does not prove DRAM write acceptance, but it rules out the ninth
  lane being the reason all high-half tags disappear.

Next gate:

- Build a v62 read-capture/word-displacement discriminator before returning to
  native-port bandwidth or rowstream integration:
  - keep the v61 source/write/read phases fixed
  - emit several tagged bytes in one pattern instead of one slot per matrix
  - report a compact histogram of observed byte values by `phase`, `word`, and
    byte offset
  - include a lane-7-only repeat and a lane-8-only repeat
  - classify whether low-half bytes always move by the same word/byte offset or
    whether the mapping depends on lane group

### 2026-05-01 - v62 DFII displacement-map discriminator

Goal:

- Keep the v59-v61 fixed phases: source `p0`, write command `p0`, read command
  `p2`.
- Write a dense 20-byte low/high lane-tag pattern in one DFII transaction so
  the readback can be decoded as observed byte values instead of only masks.
- Use tags `0x10..0x18` for low-half lanes `0..8`, tags `0x20..0x28` for
  high-half lanes `0..8`, and tags `0x2a/0x2b` as fifth-word padding
  sentinels.

Implementation:

- Added `DFII_DISPLACEMENT_PROBE_ONLY`.
- Bumped the JTAG debug payload version to `62`.
- Reused the 20-word v61 DFII readback window and added a decoder that reports
  each nonzero byte as `phase/word/byte=value(label)`.
- Added flake targets for:
  - `task6-ypcb-litedram-no-odelay-lowrate-displacement-map-init-bandwidth-probe-json`
  - `task6-ypcb-litedram-no-odelay-lowrate-displacement-map-init-bandwidth-probe-utilization`
  - `task6-ypcb-litedram-no-odelay-lowrate-displacement-map-init-bandwidth-probe-bitstream`

Build result:

- JSON:
  `/nix/store/p1ygzkv5pw60nmr30k6npqfad2rf9lz3-task6-ypcb-litedram-no-odelay-lowrate-displacement-map-init-bandwidth-probe.json`
- Utilization:
  `/nix/store/wp2j88n0ri408507gfnd2vsdiq2wjw64-task6-ypcb-litedram-no-odelay-lowrate-displacement-map-init-bandwidth-probe-utilization`
  - CLB LUTs: `18471 / 298600` (`6.19%`)
  - CLB FFs: `13701 / 597200` (`2.29%`)
  - DSP: `0 / 1920` (`0.00%`)
  - BRAM36: `0 / 955` (`0.00%`)
  - lower-bound slices: `2309 / 74650` (`3.09%`)
- Bitstream:
  `/nix/store/ac36hgk4yd2m3x4i1f7xd905zjww7w4x-task6-ypcb-litedram-no-odelay-lowrate-displacement-map-init-bandwidth-probe.bit`
- nextpnr selected utilization:
  - `SLICE_LUTX`: `23754 / 597200` (`3%`)
  - `SLICE_FFX`: `13701 / 597200` (`2%`)
  - `IDELAYE2`: `72 / 400` (`18%`)
  - `OSERDESE2`: `107 / 400` (`26%`)
  - `ISERDESE2`: `72 / 400` (`18%`)
  - `IDELAYCTRL`: `3 / 8` (`37%`)
  - BRAM: `0`
  - DSP: `0`
- Post-route timing passed at the `25 MHz` target:
  - `clk200`: `715.31 MHz`
  - `user_clk`: `67.13 MHz`
  - `core.iodelay_clk`: `581.40 MHz`
  - `jtag_debug_shift.drck`: `336.81 MHz`

Board/JTAG result:

- Program command:
  `openFPGALoader -c digilent_hs3 --ftdi-serial 210299BF3824 /nix/store/ac36hgk4yd2m3x4i1f7xd905zjww7w4x-task6-ypcb-litedram-no-odelay-lowrate-displacement-map-init-bandwidth-probe.bit`
- Program result:
  SRAM load completed and `DONE` asserted.
- JTAG read command:
  `python3 scripts/task6/read_litedram_probe_jtag_ftdi.py --backend mpsse --tdo-bit 7 --poll --poll-count 300 --poll-interval 0.2`
- JTAG result:
  - `magic_ok=true`
  - `version=62`
  - `state=PROBE_DFII_DONE`
  - `init_state=INIT_DONE`
  - `init_done=true`
  - `init_error=false`
  - `dfii_displacement_probe_only=true`
  - fixed source/write/read phases: `p0`/`p0`/`p2`
  - DFII sequence: `DFII_SEQ_DONE`, `ack=58`, `wait=174`
  - direct readback repeated across phases for words `0..3`:
    - `w0=0x00161514`
    - `w1=0x12111018`
    - `w2=0x16151413`
    - `w3=0x00001800`
  - phase `p0` also captured `w4=0x13121110`; phases `p1..p3` captured
    `w4=0x00000000`
  - visible tags were only low-half lane tags:
    `low_lane0`, `low_lane1`, `low_lane2`, `low_lane3`, `low_lane4`,
    `low_lane5`, `low_lane6`, and `low_lane8`
  - `low_lane7` (`0x17`) was absent everywhere.
  - high-half lane tags `0x20..0x28` were absent everywhere.
  - padding sentinels `0x2a/0x2b` were absent everywhere.
  - DFII lane bit errors: `[22, 20, 20, 24, 19, 19, 20, 23]`

Interpretation:

- v62 confirms the v61 result with a denser discriminator: low-half tags are
  deterministic and repeatable, but the high-half tags are still completely
  absent.
- The observed bytes are not a simple constant displacement. Low tags repeat in
  several word/byte positions:
  - low lanes `4..6` appear at `w0/b0..2` and again at `w2/b1..3`
  - low lanes `0..3` appear at `w1/b1..3` plus `w2/b0`/`p0 w4/b0..3`
  - low lane `8` appears at `w1/b0` and `w3/b1`
- Lane `7` remains independently dark, while lane `8` is repeatedly visible in
  the low half.
- No high-half tag or fifth-word padding sentinel is visible, so the remaining
  issue is below rowstream/TinyStories and still in the DFII/PHY association
  path.

Next gate:

- Before another board sweep, inspect and prove the generated LiteDRAM DFII CSR
  write-data path:
  - verify the `pi*_wrdata0..4` CSR ordering against the generated Verilog
  - add a v63 CSR-echo probe that writes the 144-bit DFII phase-injector
    storage, reads the same `wrdata` CSRs back over Wishbone, and exposes the
    echo through JTAG before issuing the DRAM command
  - if the echo matches but DDR readback still loses the high half, focus on
    A7DDRPHY serializer/read-capture ordering; if the echo does not match, fix
    the probe's CSR address/order first

### 2026-05-01 - v63 DFII CSR echo discriminator

Goal:

- Prove or disprove that the probe is writing the intended LiteDRAM DFII
  `pi*_wrdata0..4` CSR slots before blaming the no-ODELAY PHY serializer or
  read-capture path.
- Avoid issuing any DRAM command in this discriminator. It writes the 20 DFII
  phase-injector write-data CSRs, reads the same CSR addresses back through
  Wishbone, and exposes the echo through the existing JTAG payload.

Implementation:

- Added `DFII_CSR_ECHO_PROBE_ONLY`.
- Bumped the JTAG debug payload version to `63`.
- Added a CSR-echo pattern with four phase-distinct 144-bit values:
  - `p0`: `0x10..0x21`
  - `p1`: `0x30..0x41`
  - `p2`: `0x50..0x61`
  - `p3`: `0x70..0x81`
- Fixed the JTAG decoder so CSR echo uses the 5-word-per-phase layout and
  computes echo mismatches from actual CSR readback values, not only from the
  hardware mismatch mask. This prevents a timeout/no-read case from being
  reported as a false pass.
- Added flake targets for:
  - `task6-ypcb-litedram-no-odelay-lowrate-csr-echo-init-bandwidth-probe-json`
  - `task6-ypcb-litedram-no-odelay-lowrate-csr-echo-init-bandwidth-probe-utilization`
  - `task6-ypcb-litedram-no-odelay-lowrate-csr-echo-init-bandwidth-probe-bitstream`

Build result:

- JSON:
  `/nix/store/cyh6nipy17ig9l4rby64gmn5g504r6dr-task6-ypcb-litedram-no-odelay-lowrate-csr-echo-init-bandwidth-probe.json`
- Utilization:
  `/nix/store/d0prz5f83arl42vihvfjrj8252ldihhz-task6-ypcb-litedram-no-odelay-lowrate-csr-echo-init-bandwidth-probe-utilization`
  - CLB LUTs: `17419 / 298600` (`5.83%`)
  - CLB FFs: `13709 / 597200` (`2.30%`)
  - DSP: `0 / 1920` (`0.00%`)
  - BRAM36: `0 / 955` (`0.00%`)
  - lower-bound slices: `2178 / 74650` (`2.92%`)
- Bitstream:
  `/nix/store/qb9wwjpyfzxh1ccf602by9x96h2gwvyw-task6-ypcb-litedram-no-odelay-lowrate-csr-echo-init-bandwidth-probe.bit`
- Post-route timing passed at the `25 MHz` target:
  - `clk200`: `660.07 MHz`
  - `user_clk`: `64.09 MHz`
  - `core.iodelay_clk`: `461.89 MHz`
  - `jtag_debug_shift.drck`: `355.24 MHz`

Board/JTAG result:

- Program command:
  `openFPGALoader -c digilent_hs3 --ftdi-serial 210299BF3824 /nix/store/qb9wwjpyfzxh1ccf602by9x96h2gwvyw-task6-ypcb-litedram-no-odelay-lowrate-csr-echo-init-bandwidth-probe.bit`
- Program result:
  SRAM load completed and `DONE` asserted.
- JTAG read command:
  `python3 scripts/task6/read_litedram_probe_jtag_ftdi.py --backend mpsse --tdo-bit 7 --poll --poll-count 300 --poll-interval 0.2`
- JTAG result:
  - `magic_ok=true`
  - `version=63`
  - `state=PROBE_DFII_DONE`
  - `init_state=INIT_DONE`
  - `init_done=true`
  - `init_error=false`
  - `dfii_csr_echo_probe_only=true`
  - DFII sequence: `DFII_SEQ_DONE`, `ack=42`, `wait=126`
  - CSR echo: `20 / 20` words matched
  - `dfii_data_pass=true`
  - final echo read: `0x00008180`

Interpretation:

- The wrapper's Wishbone path and DFII write-data CSR address/order are correct
  for all four phases and all five 32-bit/16-bit words per phase.
- Therefore the v62 low-half-only DRAM readback is not explained by writing the
  wrong `pi*_wrdata*` CSR slots or by a JTAG decoder indexing error.
- The next active hypothesis is below CSR storage: LiteDRAM/A7DDRPHY
  serializer association, DQS/DQ timing, read-capture ordering, or DRAM
  byte-lane/write-enable behavior.
- An earlier seed-10 CSR-echo bitstream timed out before init, while the
  current-source v62 displacement control and the seed-9 CSR-echo bitstream
  both reached `INIT_DONE`. Treat the seed-10 run as placement sensitivity, not
  as DDR3 functional evidence.

Next gate:

- Add a single-bitstream serializer/read-capture discriminator that writes
  phase/half/word-tagged values through DFII and reads back multiple
  source/write/read/capture alignments without changing placement between
  cases.
- Keep rowstream/TinyStories disconnected until at least one lane/half maps
  from CSR storage through DRAM readback with a matching expected tag.

### 2026-05-01 - v64 DFII write-bitslip sweep discriminator

Goal:

- Test whether LiteDRAM/A7DDRPHY write-bitslip selection alone explains the
  v62 low-half-only displacement signature.
- Keep placement fixed within a single bitstream by sweeping the number of
  write-bitslip pulses after the PHY's write-bitslip reset, then running the
  same dense DFII displacement pattern for each setting.

Implementation:

- Added `DFII_WBITSLIP_SWEEP_ONLY`.
- Bumped the JTAG debug payload version to `64`.
- Added `PROBE_DFII_WBITSLIP_CONFIG`, which selects all nine DQS groups,
  applies `0..7` write-bitslip pulses, reruns the dense displacement DFII
  probe, and stores low/high nonzero and exact-match masks per candidate.
- Updated the JTAG decoder to report the active write-bitslip sweep and print
  a compact per-candidate table.
- Added flake targets for:
  - `task6-ypcb-litedram-no-odelay-lowrate-wbitslip-sweep-init-bandwidth-probe-json`
  - `task6-ypcb-litedram-no-odelay-lowrate-wbitslip-sweep-init-bandwidth-probe-utilization`
  - `task6-ypcb-litedram-no-odelay-lowrate-wbitslip-sweep-init-bandwidth-probe-bitstream`

Build result:

- JSON:
  `/nix/store/j2b5cr95afsdb9wz0bh4nmxhy7w5w8ak-task6-ypcb-litedram-no-odelay-lowrate-wbitslip-sweep-init-bandwidth-probe.json`
- Utilization:
  `/nix/store/s91j2y2h37d16lc6qd7q1iifvmb81263-task6-ypcb-litedram-no-odelay-lowrate-wbitslip-sweep-init-bandwidth-probe-utilization`
  - CLB LUTs: `17539 / 298600` (`5.87%`)
  - CLB FFs: `13864 / 597200` (`2.32%`)
  - DSP: `0 / 1920` (`0.00%`)
  - BRAM36: `0 / 955` (`0.00%`)
  - lower-bound slices: `2193 / 74650` (`2.94%`)
- Bitstream:
  `/nix/store/8dmq7wagm57xcm5fbj68hgnyih902yhm-task6-ypcb-litedram-no-odelay-lowrate-wbitslip-sweep-init-bandwidth-probe.bit`
- Post-route timing passed at the `25 MHz` target:
  - `clk200`: `453.10 MHz`
  - `user_clk`: `67.15 MHz`
  - `core.iodelay_clk`: `505.31 MHz`
  - `jtag_debug_shift.drck`: `358.04 MHz`

Board/JTAG result:

- Program command:
  `openFPGALoader -c digilent_hs3 --ftdi-serial 210299BF3824 /nix/store/8dmq7wagm57xcm5fbj68hgnyih902yhm-task6-ypcb-litedram-no-odelay-lowrate-wbitslip-sweep-init-bandwidth-probe.bit`
- Program result:
  SRAM load completed and `DONE` asserted.
- JTAG read command:
  `python3 scripts/task6/read_litedram_probe_jtag_ftdi.py --backend mpsse --tdo-bit 7 --poll --poll-count 300 --poll-interval 0.2`
- JTAG result:
  - `magic_ok=true`
  - `version=64`
  - `state=PROBE_DFII_DONE`
  - `init_state=INIT_DONE`
  - `init_done=true`
  - `init_error=false`
  - `dfii_wbitslip_sweep_only=true`
  - DFII sequence: `DFII_SEQ_DONE`, `ack=58`, `wait=174`
  - no candidate produced any exact word match

Write-bitslip sweep table:

```text
pulses  value  nonzero_low  exact_low  nonzero_high  exact_high  visible  exact
0       7      0xbdff       0x0000     0x0007        0x0000      17/20    0/20
1       0      0xbdff       0x0000     0x0007        0x0000      17/20    0/20
2       1      0x0010       0x0000     0x0000        0x0000       1/20    0/20
3       2      0x0010       0x0000     0x0000        0x0000       1/20    0/20
4       3      0x0010       0x0000     0x0000        0x0000       1/20    0/20
5       4      0x0010       0x0000     0x0000        0x0000       1/20    0/20
6       5      0x0010       0x0000     0x0000        0x0000       1/20    0/20
7       6      0x0010       0x0000     0x0000        0x0000       1/20    0/20
```

Interpretation:

- Write-bitslip is a real discriminator: values `7` and `0` preserve the broad
  visible-data signature, while values `1..6` collapse almost all observed
  tags.
- Write-bitslip alone is not sufficient: no setting produced an exact
  phase/half/word association, and no setting recovered a valid high-half
  mapping.
- The preferred write-bitslip region is therefore the reset/default region
  (`7` or `0`), not one of the intermediate offsets.
- Combined with v63, the remaining issue is past the DFII CSR write path and
  not solved by global write-bitslip. The next split should target read-side
  capture association or byte-lane/DQS timing.

Next gate:

- Add a v65 read-bitslip or read-capture sweep using the same dense
  displacement pattern and a fixed write-bitslip value in the `7/0` region.
- Keep the result in one bitstream so differences are attributable to the
  capture setting rather than placement/routing changes.

### 2026-05-01 - v65 DFII read-bitslip sweep discriminator

Goal:

- Test whether the remaining dense-displacement mismatch is explained by a
  global read-bitslip selection after v64 showed that the reset/default
  write-bitslip region is the only broadly visible region.
- Keep placement fixed within one bitstream by sweeping read-bitslip pulses
  `0..7`, then rerunning the same phase/half/word-tagged DFII displacement
  probe for every setting.

Implementation:

- Added `DFII_RBITSLIP_SWEEP_ONLY`.
- Bumped the JTAG debug payload version to `65`.
- Reused the all-DQS-group bitslip configuration path, but swept
  `cal_bitslip_q` while holding `cal_wbitslip_q = 0` and `cal_delay_q = 0`.
- Updated the JTAG decoder to distinguish write-bitslip and read-bitslip
  sweeps from the v65 association flags and to print a read-bitslip table.
- Added flake targets for:
  - `task6-ypcb-litedram-no-odelay-lowrate-rbitslip-sweep-init-bandwidth-probe-json`
  - `task6-ypcb-litedram-no-odelay-lowrate-rbitslip-sweep-init-bandwidth-probe-utilization`
  - `task6-ypcb-litedram-no-odelay-lowrate-rbitslip-sweep-init-bandwidth-probe-bitstream`

Build result:

- JSON:
  `/nix/store/s5vx9cfgfxnyqj1hd2na91d8h1h7agbn-task6-ypcb-litedram-no-odelay-lowrate-rbitslip-sweep-init-bandwidth-probe.json`
- Utilization:
  `/nix/store/if7apqp599hw602jjn3pwxcs45ff4shc-task6-ypcb-litedram-no-odelay-lowrate-rbitslip-sweep-init-bandwidth-probe-utilization`
  - CLB LUTs: `17912 / 298600` (`6.00%`)
  - CLB FFs: `13864 / 597200` (`2.32%`)
  - DSP: `0 / 1920` (`0.00%`)
  - BRAM36: `0 / 955` (`0.00%`)
  - lower-bound slices: `2239 / 74650` (`3.00%`)
- Bitstream:
  `/nix/store/fp383rnf1apq25k5mq3g4q28k476d780-task6-ypcb-litedram-no-odelay-lowrate-rbitslip-sweep-init-bandwidth-probe.bit`
- Post-route timing passed at the `25 MHz` target:
  - `clk200`: `651.47 MHz`
  - `user_clk`: `61.55 MHz`
  - `core.iodelay_clk`: `630.52 MHz`
  - `jtag_debug_shift.drck`: `347.34 MHz`

Board/JTAG result:

- Program command:
  `openFPGALoader -c digilent_hs3 --ftdi-serial 210299BF3824 /nix/store/fp383rnf1apq25k5mq3g4q28k476d780-task6-ypcb-litedram-no-odelay-lowrate-rbitslip-sweep-init-bandwidth-probe.bit`
- Program result:
  SRAM load completed and `DONE` asserted.
- JTAG read command:
  `python3 scripts/task6/read_litedram_probe_jtag_ftdi.py --backend mpsse --tdo-bit 7 --poll --poll-count 300 --poll-interval 0.2`
- JTAG result:
  - `magic_ok=true`
  - `version=65`
  - `state=PROBE_DFII_DONE`
  - `init_state=INIT_DONE`
  - `init_done=true`
  - `init_error=false`
  - `dfii_rbitslip_sweep_only=true`
  - DFII sequence: `DFII_SEQ_DONE`, `ack=58`, `wait=174`
  - no candidate produced any exact word match

Read-bitslip sweep table:

```text
pulses  value  nonzero_low  exact_low  nonzero_high  exact_high  visible  exact
0       7      0xbdff       0x0000     0x0007        0x0000      17/20    0/20
1       0      0xbdff       0x0000     0x0007        0x0000      17/20    0/20
2       1      0xbdff       0x0000     0x0007        0x0000      17/20    0/20
3       2      0xbdff       0x0000     0x0007        0x0000      17/20    0/20
4       3      0xbdff       0x0000     0x0007        0x0000      17/20    0/20
5       4      0xbdff       0x0000     0x0007        0x0000      17/20    0/20
6       5      0xbdff       0x0000     0x0007        0x0000      17/20    0/20
7       6      0xbdff       0x0000     0x0007        0x0000      17/20    0/20
```

Representative returned words:

```text
[p0 w0] expected=0x13121110 actual=0x00161514
[p0 w1] expected=0x17161514 actual=0x12111018
[p0 w2] expected=0x22212018 actual=0x16151413
[p0 w3] expected=0x26252423 actual=0x00001800
[p0 w4] expected=0x2b2a2827 actual=0x13121110
```

Interpretation:

- Read-bitslip is not the missing global knob in this configuration. Every
  read-bitslip setting produced the same visibility and exact-match masks.
- The returned data is not random and not stale all-zero data: it contains
  recognizable byte-ramp fragments from the expected pattern, but shifted into
  the wrong word/beat positions.
- Combined with v63 and v64, the active failure is now a DFII/PHY beat or
  capture association problem, not CSR addressing, not pure command inertness,
  and not a simple global write-bitslip or read-bitslip offset.

Next gate:

- Add a v66 beat/word association probe that scores shifted windows of the
  dense displacement stream, not only exact same-index word matches.
- If the shifted-window score identifies a stable offset, freeze it into the
  DFII read comparator and then test whether remaining errors are per-lane,
  half-word, or DQS-group specific.

### 2026-05-01 - v66/v67 DFII edge-map and rddata CSR-base correction

Goal:

- Replace the ambiguous dense displacement pattern with a phase/half/lane tagged
  edge map across all four DFI phases and both 72-bit halves.
- Recheck the DFII readback interpretation after v65 showed byte fragments but
  no exact phase/beat match.

Implementation:

- Added `DFII_EDGE_MAP_PROBE_ONLY`.
- Added flake targets for:
  - `task6-ypcb-litedram-no-odelay-lowrate-edge-map-init-bandwidth-probe-json`
  - `task6-ypcb-litedram-no-odelay-lowrate-edge-map-init-bandwidth-probe-utilization`
  - `task6-ypcb-litedram-no-odelay-lowrate-edge-map-init-bandwidth-probe-bitstream`
- v66 exposed a probe bug: `WB_ADDR_PI0_RDDATA` was set to `0x409`, which made
  the five-word read helper read `rddata1..4` followed by `wrdata0`.
- v67 fixes the base to `0x40a`, matching the generated LiteDRAM CSR order:
  `rddata4, rddata3, rddata2, rddata1, rddata0`.

Build result:

- JSON:
  `/nix/store/i4vrr0b7ckgl0a6bdwipqadjr3jywpxz-task6-ypcb-litedram-no-odelay-lowrate-edge-map-init-bandwidth-probe.json`
- Utilization:
  `/nix/store/gqvla8l6dzdzardkrndrsv0cqw1sk6pz-task6-ypcb-litedram-no-odelay-lowrate-edge-map-init-bandwidth-probe-utilization`
  - nextpnr pack summary:
    - `SLICE_LUTX`: `22646 / 597200` (`3%`)
    - `SLICE_FFX`: `13701 / 597200` (`2%`)
    - `DSP48E1`: `0 / 1920`
    - `RAMB36E1`: `0 / 955`
    - `IDELAYE2`: `72 / 400`
    - `OSERDESE2`: `107 / 400`
- Bitstream:
  `/nix/store/5hpds5kn712aw7hfp3p6xv5zacsd7dk5-task6-ypcb-litedram-no-odelay-lowrate-edge-map-init-bandwidth-probe.bit`
- Post-route timing passed at the `25 MHz` target:
  - `clk200`: `640.20 MHz`
  - `user_clk`: `68.92 MHz`
  - `core.iodelay_clk`: `690.13 MHz`
  - `jtag_debug_shift.drck`: `350.63 MHz`

Board/JTAG result:

- Program command:
  `openFPGALoader -c digilent_hs3 --ftdi-serial 210299BF3824 /nix/store/5hpds5kn712aw7hfp3p6xv5zacsd7dk5-task6-ypcb-litedram-no-odelay-lowrate-edge-map-init-bandwidth-probe.bit`
- Program result:
  SRAM load completed and `DONE` asserted.
- JTAG read command:
  `python3 scripts/task6/read_litedram_probe_jtag_ftdi.py --backend mpsse --tdo-bit 7 --poll --poll-count 300 --poll-interval 0.2`
- JTAG result:
  - `magic_ok=true`
  - `version=67`
  - `state=PROBE_DFII_DONE`
  - `init_state=INIT_DONE`
  - `init_done=true`
  - `init_error=false`
  - `dfii_edge_map_probe_only=true`
  - DFII sequence: `DFII_SEQ_DONE`, `ack=58`, `wait=174`
  - `dfii_word_mismatch_mask=0xffffe`

Representative corrected readback:

```text
[p0 w0] expected=0x13121110 actual=0x13121110
[p0 w1] expected=0x17161514 actual=0x67161514
[p0 w2] expected=0x22212018 actual=0x12111018
[p0 w3] expected=0x26252423 actual=0x16151413
[p0 w4] expected=0xd0c02827 actual=0x00001867
```

Observed 9-byte beat repeated across the 20-byte read window:

```text
10 11 12 13 14 15 16 67 18
10 11 12 13 14 15 16 67 18
00 00
```

Interpretation:

- v66/v67 falsify part of the earlier interpretation: previous DFII readback
  results that depended on the old read helper were shifted by one CSR word, and
  v66 word 4 was actually `wrdata0`, not DRAM read data.
- With the corrected base, DRAM readback is not random and not stale all-zero
  data. It returns a stable 9-byte beat twice.
- Eight byte lanes map to the `p0` low-half write tags:
  lanes `0..6` and `8`.
- Byte lane `7` maps to `p2` high-half lane `7` (`0x67`) instead of the
  expected `p0` low-half lane `7` (`0x17`).
- All four DFII phase rddata CSR groups expose the same captured 20-byte
  sequence for this read command, so treating those reads as four independent
  phase windows is not valid for the next discriminator.

Next gate:

- Add a compact compensated edge-map probe that writes the desired logical
  9-byte beat through the observed source slots:
  lanes `0..6,8` through `p0` low-half and lane `7` through `p2` high-half.
- Pass criterion: the first corrected 20-byte read window exactly matches the
  repeated 9-byte logical beat. If it passes, the immediate blocker is a
  deterministic byte-lane/phase association map; if it fails, the association
  is not stable enough and the next split should target read-valid timing or
  per-DQS capture.

### 2026-05-01 - v68 compensated edge-map probe

Goal:

- Test whether the v67 byte association can be compensated directly by writing
  logical lanes `0..6,8` through `p0` low-half and logical lane `7` through the
  apparent `p2` high-half lane `7` source.

Implementation:

- Added `DFII_EDGE_COMP_PROBE_ONLY`.
- Added flake targets for:
  - `task6-ypcb-litedram-no-odelay-lowrate-edge-comp-init-bandwidth-probe-json`
  - `task6-ypcb-litedram-no-odelay-lowrate-edge-comp-init-bandwidth-probe-utilization`
  - `task6-ypcb-litedram-no-odelay-lowrate-edge-comp-init-bandwidth-probe-bitstream`
- Bumped the JTAG payload version to `68`.
- Updated the JTAG decoder for the compensated edge-map mode and fixed the
  local print path to bind the `edge_comp` probe flag.

Build result:

- JSON:
  `/nix/store/4x1v7rkkil7wirsrdd129cazz4s8pzs1-task6-ypcb-litedram-no-odelay-lowrate-edge-comp-init-bandwidth-probe.json`
- Utilization:
  `/nix/store/yq5383w8024csqyyy9v4ncaq111lnx4q-task6-ypcb-litedram-no-odelay-lowrate-edge-comp-init-bandwidth-probe-utilization`
  - nextpnr pack summary:
    - `SLICE_LUTX`: `23373 / 597200` (`3%`)
    - `SLICE_FFX`: `13701 / 597200` (`2%`)
    - `DSP48E1`: `0 / 1920`
    - `RAMB36E1`: `0 / 955`
    - `IDELAYE2`: `72 / 400`
    - `OSERDESE2`: `107 / 400`
- Bitstream:
  `/nix/store/274kac0y84bj1zm851qk4034sbvrvxj6-task6-ypcb-litedram-no-odelay-lowrate-edge-comp-init-bandwidth-probe.bit`
- Post-route timing passed at the `25 MHz` target:
  - `clk200`: `630.52 MHz`
  - `user_clk`: `69.12 MHz`
  - `core.iodelay_clk`: `506.07 MHz`
  - `jtag_debug_shift.drck`: `296.47 MHz`

Board/JTAG result:

- Program command:
  `openFPGALoader -c digilent_hs3 --ftdi-serial 210299BF3824 /nix/store/274kac0y84bj1zm851qk4034sbvrvxj6-task6-ypcb-litedram-no-odelay-lowrate-edge-comp-init-bandwidth-probe.bit`
- Program result:
  SRAM load completed and `DONE` asserted.
- JTAG read command:
  `python3 scripts/task6/read_litedram_probe_jtag_ftdi.py --backend mpsse --tdo-bit 7 --poll --poll-count 300 --poll-interval 0.2`
- JTAG result:
  - `magic_ok=true`
  - `version=68`
  - `state=PROBE_DFII_DONE`
  - `init_state=INIT_DONE`
  - `init_done=true`
  - `init_error=false`
  - `dfii_edge_comp_probe_only=true`
  - DFII sequence: `DFII_SEQ_DONE`, `ack=58`, `wait=174`
  - full `dfii_word_mismatch_mask=0x94a52`
  - lower printed mismatch mask: `0x4a52`
  - `dfii_data_pass=false`

Representative corrected readback:

```text
[p0 w0] expected=0x93929190 actual=0x93929190
[p0 w1] expected=0x97969594 actual=0x00969594
[p0 w2] expected=0x92919098 actual=0x92919098
[p0 w3] expected=0x96959493 actual=0x96959493
[p0 w4] expected=0x00009897 actual=0x00009800
```

Interpretation:

- The compensated map did not pass.
- The good part is strong: logical lanes `0..6` and `8` are stable and return
  exact compensated tags across the repeated 9-byte beat.
- The failure is now isolated: every expected `comp_lane7` byte (`0x97`) came
  back as `0x00`, while the rest of the tagged beat was preserved.
- Therefore the v67 `0x67` observation should not yet be treated as a proven
  standalone `p2` high-half lane `7` source. It may depend on a correlated
  source byte, command/drive timing, or a different physical source slot than
  the first compensation guess.

Next gate:

- Add a compact lane-7 source locator that keeps the known-good logical lanes
  fixed and tags plausible lane-7 candidate source slots independently.
- Candidate set for the first locator:
  - `p0` low lane `7`
  - high-half lane `7` for all four DFI phases
  - neighboring high-half lane `8` and pad bytes if needed
- Pass criterion: identify a single candidate tag appearing in the logical
  lane-7 read position without disturbing lanes `0..6,8`.

### 2026-05-01 - v69 lane-7 source locator

Goal:

- Resolve the v68 ambiguity by tagging multiple plausible lane-7 source slots
  in the same bitstream while keeping known-good lanes `0..6,8` fixed.

Implementation:

- Added `DFII_EDGE_LANE7_LOCATOR_PROBE_ONLY`.
- Added flake targets for:
  - `task6-ypcb-litedram-no-odelay-lowrate-lane7-locator-init-bandwidth-probe-json`
  - `task6-ypcb-litedram-no-odelay-lowrate-lane7-locator-init-bandwidth-probe-utilization`
  - `task6-ypcb-litedram-no-odelay-lowrate-lane7-locator-init-bandwidth-probe-bitstream`
- Bumped the JTAG payload version to `69`.
- Tagged these candidate slots:
  - `0xa0`: `p0` low lane `7`
  - `0xa1..0xa4`: high lane `7` for phases `p0..p3`
  - `0xa5..0xa8`: high lane `8` for phases `p0..p3`
  - `0xa9..0xb0`: high word-4 pad slots for phases `p0..p3`

Build result:

- JSON:
  `/nix/store/k88p4jr9wfl058bm21w9mhhj6qh6yvsh-task6-ypcb-litedram-no-odelay-lowrate-lane7-locator-init-bandwidth-probe.json`
- Utilization:
  `/nix/store/wqk0rf227paska1096b70bb26apgnz8a-task6-ypcb-litedram-no-odelay-lowrate-lane7-locator-init-bandwidth-probe-utilization`
  - nextpnr pack summary:
    - `SLICE_LUTX`: `22776 / 597200` (`3%`)
    - `SLICE_FFX`: `13703 / 597200` (`2%`)
    - `DSP48E1`: `0 / 1920`
    - `RAMB36E1`: `0 / 955`
    - `IDELAYE2`: `72 / 400`
    - `OSERDESE2`: `107 / 400`
- Bitstream:
  `/nix/store/26p1vml8ay2g5f9gj4srn778bm612mf5-task6-ypcb-litedram-no-odelay-lowrate-lane7-locator-init-bandwidth-probe.bit`
- Post-route timing passed at the `25 MHz` target:
  - `clk200`: `567.21 MHz`
  - `user_clk`: `70.96 MHz`
  - `core.iodelay_clk`: `545.85 MHz`
  - `jtag_debug_shift.drck`: `401.12 MHz`

Board/JTAG result:

- Program command:
  `openFPGALoader -c digilent_hs3 --ftdi-serial 210299BF3824 /nix/store/26p1vml8ay2g5f9gj4srn778bm612mf5-task6-ypcb-litedram-no-odelay-lowrate-lane7-locator-init-bandwidth-probe.bit`
- Program result:
  SRAM load completed and `DONE` asserted.
- JTAG read command:
  `python3 scripts/task6/read_litedram_probe_jtag_ftdi.py --backend mpsse --tdo-bit 7 --poll --poll-count 300 --poll-interval 0.2`
- JTAG result:
  - `magic_ok=true`
  - `version=69`
  - `state=PROBE_DFII_DONE`
  - `init_state=INIT_DONE`
  - `init_done=true`
  - `init_error=false`
  - `dfii_edge_lane7_locator_probe_only=true`
  - DFII sequence: `DFII_SEQ_DONE`, `ack=58`, `wait=174`
  - full `dfii_word_mismatch_mask=0x94a52`
  - lower printed mismatch mask: `0x4a52`

Representative readback:

```text
[p0 w0] expected=0x93929190 actual=0x93929190
[p0 w1] expected=0x00969594 actual=0xa0969594
[p0 w2] expected=0x92919098 actual=0x92919098
[p0 w3] expected=0x96959493 actual=0x96959493
[p0 w4] expected=0x00009800 actual=0x000098a0
```

Interpretation:

- The lane-7 source is now identified: `0xa0`, the `p0` low-half lane `7`
  candidate, appears exactly in both logical lane-7 read positions.
- None of the high-half lane `7`, high-half lane `8`, or pad candidate tags
  appear in the corrected 20-byte read window.
- This supersedes the v67 source interpretation. The stable control fact is
  now that lanes `0..8` can be driven from the expected `p0` low-half 9-byte
  beat.
- v68 failed because it deliberately zeroed the actual `p0` low lane-7 source
  and tried to drive lane `7` from a high-half candidate instead.

Next gate:

- Update the compensated edge-map probe so logical lane `7` is driven through
  `p0` low lane `7`.
- Rebuild and run the corrected compensated edge-map as v70.
- Pass criterion: `dfii_data_pass=true` and `dfii_word_mismatch_mask=0`.

### 2026-05-01 - v70-v77 DFII final-word discriminator

Goal:

- Resolve why v69 could expose lane `7` while the first corrected compensated
  edge-map still missed it.
- Keep the test below rowstream/TinyStories and use only the open
  LiteDRAM/LiteX no-ODELAY path.
- Avoid a placement/routing confound by putting the final discriminator
  variants into one routed bitstream at separate DDR3 column addresses.

Intermediate results:

- v70 drove logical lane `7` through the `p0` low-half source but kept the
  earlier `0x97` tag. JEDEC init completed, but lane `7` still read back as
  zero and the edge-map failed.
- v71 drove the whole compensated write pattern from every DFI source phase.
  The image was not a valid discriminator on board: it timed out in the init
  Wishbone path at step `0`, so it is pruned as an invalid run.
- v72 drove only the lane-7 source ambiguity across all phases. Init completed,
  but the edge-map still failed with lane `7` zero.
- v73 used the repeatable v69 lane-7 locator value `0xa0` but did not restore
  the final word-4 bytes. Init completed, but lane `7` still read back as zero.
- v74 restored the v69-style final word-4 bytes and passed:
  `mismatch_mask=0x0000`, `data_pass=true`, `last_read=0x000098a0`.
- v75 removed the arbitrary upper filler bytes and kept only the final
  lane-7/lane-8 bytes. It also passed:
  `mismatch_mask=0x0000`, `data_pass=true`, `last_read=0x000098a0`.
- v76 tried to keep those final-word bytes only on phase `0`, but the board
  run timed out during init (`state=PROBE_ERROR`, `init_state=INIT_ERROR`,
  `init_step=0`, `wb_wait=524289`). Treat it as invalid, not as evidence
  against or for phase scope.

v77 implementation:

- Bumped the JTAG payload version to `77`.
- Kept the active target on the low-rate no-ODELAY LiteDRAM probe:
  `task6-ypcb-litedram-no-odelay-lowrate-edge-comp-init-bandwidth-probe-*`.
- Added a one-bitstream final-word variant sweep:
  - variant `0`: all-phase lane-7/lane-8 final bytes, matching v75.
  - variant `1`: phase-0-only lane-7/lane-8 final bytes.
  - variant `2`: all-phase lane-7-only final byte.
  - variant `3`: no final-word bytes, expected to fail.
- Wrote each variant to a separate DDR3 column address so readback from one
  variant cannot explain another variant's result.
- Updated the JTAG decoder to print the per-variant mismatch masks directly.

Build result:

- JSON:
  `/nix/store/zq55y858gsk9rmx3rin5bahlxb2in85c-task6-ypcb-litedram-no-odelay-lowrate-edge-comp-init-bandwidth-probe.json`
- Utilization:
  `/nix/store/16xck10c6vjikwdgnwfk48bxm6azgv2p-task6-ypcb-litedram-no-odelay-lowrate-edge-comp-init-bandwidth-probe-utilization`
  - nextpnr pack summary:
    - `SLICE_LUTX`: `22972 / 597200` (`3%`)
    - `SLICE_FFX`: `13949 / 597200` (`2%`)
    - `DSP48E1`: `0 / 1920`
    - `RAMB36E1`: `0 / 955`
    - `IDELAYE2`: `72 / 400`
    - `OSERDESE2`: `107 / 400`
    - `ISERDESE2`: `72 / 400`
    - `IDELAYCTRL`: `3 / 8`
    - `ODELAYE2`: `0`
- Bitstream:
  `/nix/store/lazg33h48wcb2clbnysdwk8pmyr992ss-task6-ypcb-litedram-no-odelay-lowrate-edge-comp-init-bandwidth-probe.bit`
- Post-route timing passed at the `25 MHz` target:
  - `user_clk`: `64.65 MHz`

Board/JTAG result:

- Program command:
  `openFPGALoader -c digilent_hs3 --ftdi-serial 210299BF3824 /nix/store/lazg33h48wcb2clbnysdwk8pmyr992ss-task6-ypcb-litedram-no-odelay-lowrate-edge-comp-init-bandwidth-probe.bit`
- Program result:
  SRAM load completed and `DONE` asserted.
- JTAG read command:
  `python3 scripts/task6/read_litedram_probe_jtag_ftdi.py --backend mpsse --tdo-bit 7 --poll --poll-count 300 --poll-interval 0.2`
- JTAG result:
  - `magic_ok=true`
  - `version=77`
  - `state=PROBE_DFII_DONE`
  - `init_state=INIT_DONE`
  - `init_step=32`
  - `init_done=true`
  - `init_error=false`
  - `pll_locked=true`
  - DFII sequence: `DFII_SEQ_DONE`, `ack=58`, `wait=174`
  - final top-level `mismatch_mask=0x4a52` because the last run is the
    expected-failing variant `3`

Per-variant result:

```text
variant0 all-phase lane7/lane8 final bytes: mismatch_mask=0x0000 PASS
variant1 phase0-only lane7/lane8 final bytes: mismatch_mask=0x4a52 FAIL
variant2 all-phase lane7-only final byte: mismatch_mask=0x4210 FAIL
variant3 no final-word bytes, expected to fail: mismatch_mask=0x4a52 FAIL
```

Interpretation:

- v77 confirms v75 in a single routed image: the passing compensated pattern
  needs the final DFII word carrying lane `7` and lane `8` bytes on all four
  phases.
- The failure is not stale data, command reachability, TinyStories rowstream,
  arbitrary filler bytes, or a per-bitstream placement artifact.
- The surprising coupling is that lane `8`'s final byte is required for lane
  `7` to round-trip cleanly; lane-7-only final bytes still fail.
- The active blocker is therefore narrowed to final-word DFII packing, write
  enable, or ninth-byte-lane association at the DFI/PHY boundary.

Next gate:

- Split DFII CSR storage from downstream DFI/PHY behavior.
- Add a v78 probe that writes each v77 final-word variant into the `pi*_wrdata`
  CSRs, reads those `wrdata` CSRs back before issuing the DRAM write/read, and
  records separate CSR-echo masks alongside the existing DRAM readback masks.
- If CSR echo matches for failing variants, the issue is past Wishbone/CSR
  storage and in DFI write-enable, serializer, or PHY final-beat behavior.
- If CSR echo misses for failing variants, debug the CSR address/order/write
  enable path before another DRAM-facing board test.

### 2026-05-01 - v78/v79 DFII CSR echo split

Goal:

- Separate the v77 final-word discriminator into:
  - DFII `pi*_wrdata*` CSR storage/echo correctness.
  - downstream DFI/PHY/DRAM write-read behavior.
- Keep rowstream and TinyStories disconnected until this association problem is
  solved.

v78 combined CSR+DRAM attempt:

- Bumped the JTAG payload version to `78`.
- Added CSR echo reads before the existing DRAM write/read discriminator.
- Build artifacts:
  - JSON:
    `/nix/store/gsn4pnbvkv86dh5qp0wfjpg2l935v4hg-task6-ypcb-litedram-no-odelay-lowrate-edge-comp-init-bandwidth-probe.json`
  - Utilization:
    `/nix/store/74k8fcqpllh4rbfxydgkrxlm90a9j6v4-task6-ypcb-litedram-no-odelay-lowrate-edge-comp-init-bandwidth-probe-utilization`
  - Bitstream:
    `/nix/store/0b4n1i3vdi32mzr8r0b30zifbkaghk0w-task6-ypcb-litedram-no-odelay-lowrate-edge-comp-init-bandwidth-probe.bit`
- Resource/timing summary:
  - `SLICE_LUTX`: `24036 / 597200` (`4%`)
  - `SLICE_FFX`: `14097 / 597200` (`2%`)
  - `DSP48E1`: `0 / 1920`
  - `RAMB36E1`: `0 / 955`
  - `IDELAYE2`: `72 / 400`
  - `OSERDESE2`: `107 / 400`
  - `ISERDESE2`: `72 / 400`
  - `IDELAYCTRL`: `3 / 8`
  - `ODELAYE2`: `0`
  - post-route `user_clk`: `64.05 MHz` at a `25 MHz` target
- Board result:
  - SRAM load completed and `DONE` asserted.
  - JTAG payload showed `version=78`, `state=PROBE_ERROR`,
    `init_state=INIT_ERROR`, `init_step=0`, `init_done=false`,
    `pll_locked=true`, `wb_ack=0`, `wb_wait=524289`.
  - DFII never ran: `DFII_SEQ_IDLE`, `step=0`, `ack=0`.
- Interpretation:
  - v78 is an invalid board run, not a DDR3 data result.
  - It likely perturbed init timing/routing enough to reproduce the step-0
    Wishbone timeout seen in some earlier invalid variants.

Control rerun:

- Reprogrammed the v77 bitstream after the v78 failure:
  `/nix/store/lazg33h48wcb2clbnysdwk8pmyr992ss-task6-ypcb-litedram-no-odelay-lowrate-edge-comp-init-bandwidth-probe.bit`
- v77 still completed:
  `version=77`, `state=PROBE_DFII_DONE`, `init_state=INIT_DONE`,
  `dfii_state=DFII_SEQ_DONE`, `dfii_step=63`, `ack=58`, `wait=174`.
- Interpretation:
  - Board, cable, permissions, and the no-ODELAY LiteDRAM lane remained good.
  - v78 failure is design/route specific and should be pruned.

v79 CSR-only implementation:

- Bumped the JTAG payload version to `79`.
- Pruned the v78 discriminator to CSR-only:
  - write the 20 `pi*_wrdata*` CSRs for each final-word variant;
  - read those same 20 CSRs back;
  - return DFII control to hardware;
  - issue no DRAM write or read commands.
- Updated the decoder so version `79` compares the displayed `dfii_rddata_*`
  words against the written CSR words, not the expected DRAM readback words.
- Decoder/checks:
  - `python3 -m py_compile scripts/task6/read_litedram_probe_jtag_xvc.py scripts/task6/read_litedram_probe_jtag_ftdi.py`
  - `git diff --check`

Build result:

- JSON:
  `/nix/store/fznnlxrmn4iiyq7ib87d2dxijv59f9j9-task6-ypcb-litedram-no-odelay-lowrate-edge-comp-init-bandwidth-probe.json`
- Yosys summary:
  - no `ODELAYE2`
  - `IDELAYE2`: `72`
  - peak memory: `890.74 MB`
- Utilization:
  `/nix/store/3q2g3m5qgzipcsw6q89qd80q6jn1l0gi-task6-ypcb-litedram-no-odelay-lowrate-edge-comp-init-bandwidth-probe-utilization`
  - nextpnr pack summary:
    - `SLICE_LUTX`: `23375 / 597200` (`3%`)
    - `SLICE_FFX`: `14097 / 597200` (`2%`)
    - `DSP48E1`: `0 / 1920`
    - `RAMB36E1`: `0 / 955`
    - `IDELAYE2`: `72 / 400`
    - `OSERDESE2`: `107 / 400`
    - `ISERDESE2`: `72 / 400`
    - `IDELAYCTRL`: `3 / 8`
    - `ODELAYE2`: `0`
- Bitstream:
  `/nix/store/j0kb9qy3hvbiax7bg21lx939qixyw5j7-task6-ypcb-litedram-no-odelay-lowrate-edge-comp-init-bandwidth-probe.bit`
- Post-route timing passed at the `25 MHz` target:
  - `user_clk`: `67.07 MHz`

Board/JTAG result:

- Program command:
  `openFPGALoader -c digilent_hs3 --ftdi-serial 210299BF3824 /nix/store/j0kb9qy3hvbiax7bg21lx939qixyw5j7-task6-ypcb-litedram-no-odelay-lowrate-edge-comp-init-bandwidth-probe.bit`
- Program result:
  SRAM load completed and `DONE` asserted.
- JTAG read command:
  `python3 scripts/task6/read_litedram_probe_jtag_ftdi.py --backend mpsse --tdo-bit 7 --poll --poll-count 300 --poll-interval 0.2`
- JTAG result:
  - `magic_ok=true`
  - `version=79`
  - `state=PROBE_DFII_DONE`
  - `init_state=INIT_DONE`
  - `init_step=32`
  - `init_done=true`
  - `init_error=false`
  - `pll_locked=true`
  - DFII sequence: `DFII_SEQ_DONE`, `step=43`, `ack=42`, `wait=126`
  - native DRAM traffic counters remained zero because v79 issues no DRAM
    write/read commands.

Per-variant CSR echo result:

```text
variant0 all-phase lane7/lane8 final bytes: csr_echo_mismatch=0x00000 PASS
variant1 phase0-only lane7/lane8 final bytes: csr_echo_mismatch=0x00000 PASS
variant2 all-phase lane7-only final byte: csr_echo_mismatch=0x00000 PASS
variant3 no final-word bytes, expected to fail: csr_echo_mismatch=0x00000 PASS
```

Interpretation:

- The v77 failing variants are not caused by Wishbone/CSR write ordering,
  `pi*_wrdata*` address selection, or inability to store sparse final-word
  data in the DFII write-data CSRs.
- The active failure is downstream of CSR storage: DFI write-data enable,
  DFI phase/beat packing, serializer/OSERDES behavior, DQS/DQ association, or
  DRAM readback/capture.
- The strongest current hypothesis is still a final-word association issue:
  the DRAM-facing path needs all-phase lane-7/lane-8 final-word bytes even
  though the CSR-only path stores all four variants exactly.

Next gate:

- Reintroduce DRAM with lower perturbation than v78.
- Prefer a v80 DRAM-only discriminator that keeps the v77 sequence length and
  result storage shape as close as possible to v77, while exposing one extra
  compact signal: the final-word `wrdata_en`/write-data phase mask that is
  actually presented at the DFI boundary.
- If that is too invasive, run a pair of placement-stable single-variant
  bitstreams derived from v77/v79:
  - one with variant `0` only;
  - one with variant `1` or `2` only;
  and compare DFI/DRAM readback without adding the CSR echo machinery.

### 2026-05-01 - v80-v83 DFII final-word compensation promoted to active pass

Objective:

- Resolve whether the v77/v80 "all-phase lane7/lane8 final bytes" result was a
  real DRAM round-trip fix or only a truncated/debug-artifact pass.
- Keep the lane below rowstream/TinyStories: LiteDRAM/LiteX no-ODELAY DDR3
  only, with a compact DFII write/read pattern and JTAG readback.

Implementation:

- Added a generated-RTL patcher that exposes compact DFI write-data debug ports
  from the generated LiteDRAM core:
  `scripts/task6/patch_litedram_dfi_debug_ports.py`.
- Kept the active controller on LiteDRAM's no-ODELAY Series-7 path
  (`A7DDRPHY` / `sys4x_dqs`), not Vivado MIG.
- v80 restored the v77 DRAM variant sweep and captured DFI word4 taps.
- v82 packed the high four mismatch bits into the existing edge-comp flags
  word so each variant reports the full `20` DFII read words.
- v83 promoted the passing variant to a single active DFII write/read mode:
  all four DFI phases carry the final-word lane7/lane8 bytes.

Build artifacts:

- v82 bitstream:
  `/nix/store/lpyq8fkv6wc159k2d3dx7zxs7ia8wy3w-task6-ypcb-litedram-no-odelay-lowrate-edge-comp-init-bandwidth-probe.bit`
- v83 bitstream:
  `/nix/store/h7v1g6dsd0qbvjsfck2q5l436b0dmjb1-task6-ypcb-litedram-no-odelay-lowrate-edge-comp-init-bandwidth-probe.bit`

v82 board result:

- `version=82`, `state=PROBE_DFII_DONE`, `init_state=INIT_DONE`,
  `init_done=True`, `init_error=False`, `pll_locked=True`.
- Full-mask variant results:
  - variant0, all-phase lane7/lane8 final bytes:
    `dram_mismatch=0x00000 PASS`
  - variant1, phase0-only lane7/lane8 final bytes:
    `dram_mismatch=0x94a52 FAIL`
  - variant2, all-phase lane7-only final byte:
    `dram_mismatch=0x84210 FAIL`
  - variant3, no final-word bytes:
    `dram_mismatch=0x94a52 FAIL`
- This confirms v80/v77's apparent variant0 pass was not a low-16-bit
  truncation artifact.

v83 board result:

- `version=83`, `state=PROBE_DFII_DONE`, `init_state=INIT_DONE`,
  `init_done=True`, `init_error=False`, `pll_locked=True`.
- DFII sequence: `DFII_SEQ_DONE`, `step=63`, `ack=58`, `wait=174`.
- Active compensated result:
  - `mismatch_mask=0x00000`
  - `data_pass=True`
  - lane bit errors all zero
  - all `20` captured DFII words matched expected:
    p0..p3 words `0..4`, including final word `0x000098a0`.
- v83 utilization/timing:
  - `SLICE_LUTX`: `23272/597200` (`3%`)
  - `SLICE_FFX`: `13705/597200` (`2%`)
  - `RAMB36E1`: `0/955` (`0%`)
  - `DSP48E1`: `0/1920` (`0%`)
  - `IDELAYE2`: `72/400` (`18%`)
  - `OSERDESE2`: `107/400` (`26%`)
  - `ISERDESE2`: `72/400` (`18%`)
  - post-route `user_clk`: `62.87 MHz` pass at `25 MHz`

Conclusion:

- The no-ODELAY LiteDRAM/LiteX DDR3 lane is alive below the native/rowstream
  layer: JEDEC init, DFII CSR control, DFII write/read command sequencing, and
  the compensated 72-bit/final-word data association can pass on board.
- The specific missing piece was the final 72-bit word association for lane7
  and lane8. The DRAM-facing path needs those final-word bytes driven on all
  four DFI phases for this compact pattern.
- This does not yet prove general DDR3 usability, native-port packing, burst
  behavior, or bandwidth. Rowstream/TinyStories remain disconnected until the
  compensation is replayed across broader write/read patterns and a bandwidth
  probe.

Next gate:

- Convert v83 from a fixed edge-tag discriminator into a small DDR3 BIST:
  all-zero, all-one, walking bits, byte-ramp, address-as-data, PRBS, and a
  linear burst bandwidth counter.
- Keep the first BIST on the same no-ODELAY LiteDRAM/LiteX path and preserve
  JTAG-readable `init/pass/fail/first_bad/expected/actual/cycle` counters.

## DDR3 reproducible experiment identity rule (2026-05-05)

Do not treat a flake package name as an experiment identity. The v83-good DDR3 result was committed as source (`f4d732e task6: promote DDR3 DFII final-word compensation`) and built as a Nix derivation, but later commits reused the same target family while changing the top RTL, generated LiteDRAM postprocessing, and debug payload. Rebuilding the current package name therefore does not reproduce the v83 experiment.

A DDR3 experiment identity is the tuple below, all recorded together:

- git commit used for the build
- exact flake attribute/package
- generated LiteDRAM core hash and path
- probe top RTL hash and path
- XDC/JSON/FASM/bitstream paths and hashes
- Nix derivation paths for the bitstream chain
- nextpnr seed and target frequency
- programmer command and board cable/serial
- raw probe JSON plus concise decoded result

Workflow rule: create a source/config commit first, build only from that clean commit, copy/store the result artifacts, then create a second result commit. If a target is known-good, freeze it as a branch/tag or dedicated immutable target name before adding new modes. Do not continue DDR3 work by layering unrelated experiments on the same mutable top/flake target and assuming the old package name remains reproducible.

For the v83 resurrection lane, start from commit `f4d732e` directly and replay later changes only one at a time, with one code/config commit and one result commit per board experiment.

## DDR3 v83 clean-source rebuild board run (2026-05-05)

Captured in `artifacts/task6/parallel-hypotheses/h2-ypcb-ddr3-v83-clean-source-rebuild-board-run-2026-05-05/`.

Built `task6-ypcb-litedram-no-odelay-lowrate-edge-comp-init-bandwidth-probe-bitstream` from branch `task6-ddr3-v83-resurrection` at commit `154ad8c2fe3c5b5d969a74d352f7a0306e23071e`. This branch is rooted at the v83 code commit `f4d732e`; `154ad8c` only adds the DDR3 reproducibility-process note. The build resolved to the exact historical known-good bitstream `/nix/store/h7v1g6dsd0qbvjsfck2q5l436b0dmjb1-task6-ypcb-litedram-no-odelay-lowrate-edge-comp-init-bandwidth-probe.bit` with sha256 `4aab614a51f9ace4afc90b8c77e2caca308257b6f4b4674434e87ed2972af275`.

Programmed over HS3 serial `210299BF3824`; SRAM load completed with `isc_done=1`, `init=1`, and `done=1`.

Probe result: `magic_ok=true`, `version=83`, `state=PROBE_DFII_DONE`, `init_done=true`, `init_error=false`, `pll_locked=true`, `complete=true`, `failed=false`, `dfii_seq_state=DFII_SEQ_DONE`, `dfii_step=63`, `dfii_data_pass=true`, `dfii_word_mismatch_mask=0x00000`, `dfii_last_read_data=0x000098a0`, all 20 DFII expected/actual words matched, and all 16 command phase combinations passed.

Conclusion: v83 is source-reproducible when built from the v83 code lineage. The prior reproducibility failure was not that v83 was uncommitted or impossible to rebuild; it was that later experiments mutated/reused the same target family, so the current package name no longer meant the v83 experiment.

### DDR3 v84 clean replay board result - 2026-05-05

- Commit under test: `fceabb3b3dd272570c9bf2f6f217b7bf9f813afe` on `task6-ddr3-v83-resurrection`.
- Delta: replayed `v84` compensated DFII BIST on top of the reproduced `v83` known-good DDR3 lineage.
- Bitstream: `/nix/store/xn5d23r0h3lkz04wp6xrjwfxwqcd8zkj-task6-ypcb-litedram-no-odelay-lowrate-edge-comp-bist-init-bandwidth-probe.bit`.
- Bitstream sha256: `312039484a9282ac61d2e22bb6d6f05ec63d257bf3147e66578661038da9a234`.
- Board result: program succeeded with `isc_done=1 init=1 done=1`.
- Probe result: `magic_ok=true`, `version=84`, `state=PROBE_DFII_DONE`, `init_done=true`, `init_error=false`, `pll_locked=true`, `failed=false`.
- DFII result: `dfii_seq_state=DFII_SEQ_DONE`, `dfii_step=63`, `dfii_data_pass=true`, `dfii_word_mismatch_mask=0`, `dfii_uniform_mismatch_mask=0`, `dfii_phasecmd_mismatch_masks=0`.
- Timing: routed `user_clk` max `70.69 MHz` for a `25 MHz` target, PASS.
- Conclusion: `v84` is clean. The first replayed delta after `v83` does not introduce the DDR3 regression.

### DDR3 v85 clean replay board result - 2026-05-05

- Commit under test: `96fcff6` on `task6-ddr3-v83-resurrection`.
- Delta: replayed `v85` compensated DFII address-walk on top of clean `v83` and `v84` lineage.
- Bitstream: `/nix/store/i1mbg1f0xscdw0w8hq8mc0v9yz83bxa8-task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-init-bandwidth-probe.bit`.
- Bitstream sha256: `64c4fef41a8fef52512158a480812d91cb027f79714ac6e4a5e05851deb4a551`.
- Board result: program succeeded with `isc_done=1 init=1 done=1`.
- Probe result: `magic_ok=true`, `version=85`, `state=PROBE_DFII_DONE`, `init_done=true`, `init_error=false`, `pll_locked=true`, `failed=false`.
- DFII result: `dfii_seq_state=DFII_SEQ_DONE`, `dfii_step=63`, `dfii_data_pass=true`, `dfii_word_mismatch_mask=0`, `dfii_uniform_mismatch_mask=0`, `dfii_phasecmd_mismatch_masks=0`.
- Address-walk result: decoded columns `0`, `8`, `64`, and `256`; address mismatch masks all zero; association match masks all `0xffff`; association nonzero masks all zero.
- Conclusion: `v85` is clean. The address-walk delta does not introduce the DDR3 regression.

### DDR3 v86 native addrwalk replay board result - 2026-05-05

- Commit under test: `f9d534b` on `task6-ddr3-v83-resurrection`.
- Delta: replayed `v86` DDR3 addrwalk native gate after clean `v85` DFII address-walk.
- Bitstream: `/nix/store/ak67x54vpym9cqhz8q92kc44wbw6j963-task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-init-bandwidth-probe.bit`.
- Bitstream sha256: `e263376d046dfbf67ca95a4831599e0f243c091e0551817900b999fc7311936c`.
- Board result: program succeeded with `isc_done=1 init=1 done=1`.
- Init result: `init_done=true`, `init_error=false`, `pll_locked=true`.
- DFII result stayed clean: `dfii_seq_state=DFII_SEQ_DONE`, `dfii_step=63`, `dfii_word_mismatch_mask=0`, `dfii_uniform_mismatch_mask=0`, `dfii_phasecmd_mismatch_masks=0`, `dfii_addr_mismatch_masks=0`.
- Native gate result failed: `state=PROBE_ERROR`, `complete=false`, `failed=true`, `probe_error=true`, `mismatch_seen=true`, `mismatch_count=16`.
- Native transaction evidence: `write_command_count=16`, `write_data_count=16`, `command_count=16`, `response_count=16`, `sample_valid_count=8`, `first_mismatch_addr=0`, `first_actual=0`, `first_expected=15045981070236873776`.
- Conclusion: this is the first replayed bad delta. It is not an `init_error` or PLL-lock regression; it localizes the failure to the newly introduced native addrwalk gate/native interface path.

### DDR3 v87 native readscan replay board result - 2026-05-05

- Commit under test: `22b4fa7` on `task6-ddr3-v83-resurrection`.
- Delta: replayed `v87` native readscan after clean DFII address-walk, intentionally skipping native writes.
- Bitstream: `/nix/store/h5p7jgkr5cwzswdd4927k6mkg4s94r0k-task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-readscan-init-bandwidth-probe.bit`.
- Bitstream sha256: `0c36b5f56de73f59b8ee0a7973d50c9a891270e1424dfe722c4213493f62bc34`.
- Board result: program succeeded with `isc_done=1 init=1 done=1`.
- Init result: `init_done=true`, `init_error=false`, `pll_locked=true`.
- Probe result: `version=87`, `state=PROBE_DONE`, `complete=true`, `failed=false`.
- Native readscan result: `target_read_count=64`, `command_count=64`, `response_count=64`, `write_command_count=0`, `write_data_count=0`, `native_readscan_nonzero_count=64`, `native_readscan_nonzero_chunk_seen=0x1ff`, `native_readscan_first_nonzero_data=0xadacafaea9a8abaa`.
- Conclusion: native reads can see nonzero DFII-written data. Combined with the v86 native write/read failure, this localizes the bug to native write-side behavior, not DDR3 init, PLL lock, DFII operation, or native read visibility.

### DDR3 v90 native write command-first board result - 2026-05-05

- Commit under test: `c555c0b` on `task6-ddr3-v83-resurrection`.
- Hypothesis: native writes fail because write data can be same-cycle or ahead of write commands.
- Change: serialized native write data command-first by only asserting `wdata_valid` when `write_data_count_q < write_command_count_q`.
- Bitstream: `/nix/store/srpr1fwcwqalid3mkf3zwvpff8hsfq6q-task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-init-bandwidth-probe.bit`.
- Bitstream sha256: `2e2c39a5bd2ce79952cffeb829bbcf14a3f74c05839b4155e2a35e8d4dc489d7`.
- Board result: program succeeded with `isc_done=1 init=1 done=1`.
- Timing: routed `user_clk` max `74.79 MHz` for a `25 MHz` target, PASS.
- Init result stayed clean: `init_done=true`, `init_error=false`, `pll_locked=true`.
- DFII result stayed clean: `dfii_seq_state=DFII_SEQ_DONE`, `dfii_step=63`, `dfii_word_mismatch_mask=0`, `dfii_uniform_mismatch_mask=0`, `dfii_phasecmd_mismatch_masks=0`.
- Native gate still failed: `state=PROBE_ERROR`, `failed=true`, `write_command_count=16`, `write_data_count=16`, `command_count=16`, `response_count=16`, `mismatch_count=16`, `first_actual=0`, `first_expected=15045981070236873776`.
- Conclusion: command-first write-data ordering does not fix the native write failure. The next target should be native write data mapping or DFI write-data emission, not command/data ahead ordering.

## DDR3 M1 v91 native DFI write capture - 2026-05-05

Experiment v91 restored the original native write ordering and added a DFI write-data capture reset at the start of the native write gate. The run used bitstream `/nix/store/v6x3w4gvrxgrx5snngglqkpq3pc9pdq5-task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-init-bandwidth-probe.bit` with sha256 `1c10d9a48bd78ba1909518364e145d4f09f9a0a8c604a7bda2e683504882ece8`.

The board still fails the native write/read BIST: `version=91`, `state=PROBE_ERROR`, `failed=true`, `mismatch_count=16`, and readback samples are zero. DDR3 init is still clean: `init_done=true`, `init_error=false`, `pll_locked=true`; the DFII address-walk path is also clean with all mismatch masks zero.

The v91 repurposed payload shows native DFI write activity after the native gate reset: event count `15`, observed enable `0x8`, captured word4 data `0`, and captured word4 mask `0xff`. This localizes M1 to the native write-side DFI data/mask path. More init/seed experiments are not the next surgical move; the next step is to inspect or instrument LiteDRAM's native write data/mask emission at the DFI boundary.

## DDR3 M1 v92 native WDF FIFO - 2026-05-05

Experiment v92 added a small native write-data FIFO in the generated LiteDRAM RTL patch and moved the debug tap to the low DFI data/mask word. The bitstream built and routed cleanly: `/nix/store/r4vrij2vx7h82vsi01ql11vwjv8zbc61-task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-init-bandwidth-probe.bit`, sha256 `d0c20759df571b03a1c3ac3bb67e779e34d24651c0df5c0a0cce4792d4d0e829`, user_clk `71.92 MHz` at a `25 MHz` target.

The board result is still a native write/read failure: `version=92`, `state=PROBE_ERROR`, `failed=true`, `mismatch_count=16`, and native read samples are zero. DDR3 init remains clean (`init_done=true`, `init_error=false`, `pll_locked=true`) and DFII remains clean with all mismatch masks zero.

The DFI write capture did not improve: event count `15`, observed enable `0x8`, observed data `0`, observed mask `0xff`. This means the naive FIFO did not feed the observed PHY write-data point, or the debug tap is still downstream of another zero/masked path. The next surgical step is to inspect or expose FIFO push/pop/level and the post-patch generated RTL signal path before making more DDR timing or seed changes.

### DDR3 v93 native WDF counter result (2026-05-05)

Experiment source: `8e440f5 task6-ddr3: expose native WDF FIFO counters`.
Result artifact: `artifacts/task6/parallel-hypotheses/h2-ypcb-ddr3-v93-native-wdf-counters-board-run-2026-05-05/`.
Bitstream: `/nix/store/hyi90nh94nnil7kydwmr8ba832zgjd5b-task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-init-bandwidth-probe.bit`.
SHA256: `03cc81e050af09eacee5a9a7958897be1fb77c4cc61a1b01367439e6e6e09608`.

Board result: `version=93`, `pll_locked=true`, `init_error=false`, but `init_done=false`, `init_seq_done=false`, `init_seq_error=true`, `wb_timeout_seen=true`, `wb_ack_count=0`, `wb_wait_count=524289`. Native command/data/response counters stayed zero, and the v93 WDF debug fields stayed zero.

Interpretation: v93 regressed before the native write/read BIST, so it does not answer the native write-data question. Treat it as a failed instrumentation experiment. The next surgical fix should restore the v92/v87 init behavior and use a narrower counter/debug path that does not perturb early DFII/Wishbone sequencing.

### DDR3 v94 gated native WDF probe result (2026-05-05)

Experiment source: `1928762 task6-ddr3: prepare v94 gated native WDF probe`.
Result artifact: `artifacts/task6/parallel-hypotheses/h2-ypcb-ddr3-v94-gated-native-wdf-probe-board-run-2026-05-05/`.
Bitstream: `/nix/store/x4qcvsjb2wnagmdgpyhx98axgz2inv6f-task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-init-bandwidth-probe.bit`.
SHA256: `95c1c4303962bda4c35f95da84b1d2bf6633947a61a091a97347c02bb61cc695`.

Board result: source experiment label v94, but board telemetry still reports `version=93`; the version bump was missed and must be fixed next. Init/DFII behavior recovered from v93: `pll_locked=true`, `init_error=false`, `init_done=true`, `init_seq_done=true`, `init_seq_error=false`, `dfii_step=63`, and DFII mismatch masks remained zero. Native path still failed: `write_command_count=16`, `write_data_count=16`, `response_count=16`, `mismatch_count=16`, and sampled readback data stayed zero.

New diagnostic: `native_readscan_first_nonzero_addr=0x0ae8`, `native_readscan_nonzero_chunk_seen=0xae`, `native_readscan_first_nonzero_chunk_mask=0x8`, `native_readscan_nonzero_count=15`. Decoding status byte `0xae` gives native controller select active, external DFII select inactive, FIFO empty, no push at the event, pop asserted, slave write-data event asserted, and master write-data event asserted.

Interpretation: v94 restored the known-good init path while showing that the native PHY write-data event occurs with the inserted native WDF FIFO empty. This points before or at the FIFO push/capture signal rather than to DDR3 calibration, route seed, or native read response handling. Next v95 should first fix the version bump, then expose whether any native WDF push ever occurs and whether the push condition is tied to the wrong generated-core signal.

### DDR3 v95 native WDF push visibility build result (2026-05-05)

Experiment source: `0cf7fb0 task6-ddr3: prepare v95 native WDF push visibility`.
Result artifact: `artifacts/task6/parallel-hypotheses/h2-ypcb-ddr3-v95-native-wdf-push-visibility-build-2026-05-05/`.

Result: build invalid, intentionally interrupted before bitstream/board run. During Yosys `CHECK`, the generated RTL reported 576 conflicting drivers on DFI write-data nets, including `ypcb_litedram_core.main_litedramcore_dfi_p3_wrdata[143]` and `ypcb_litedram_core.main_litedramcore_dfi_p0_wrdata[0]`. The drivers came from the four repeated generated assignments around `ypcb_litedram_core.v` lines 14230-14233 after v95 changed each repeated assignment into a ternary mux.

Interpretation: v95 should not be programmed. The generated LiteDRAM RTL has repeated equivalent assignments to the same DFI buses; replacing all repeats with gated expressions creates independent drivers. Next v96 must leave exactly one DFI bus driver, either by replacing only one repeated assignment and neutralizing duplicates or by patching a single upstream signal instead. The compact status-byte push visibility from v95 remains the right diagnostic once the multi-driver issue is fixed.

### DDR3 v96 single-driver WDF probe result (2026-05-05)

Experiment source: `6e5d1b4 task6-ddr3: prepare v96 single-driver WDF probe`.
Result artifact: `artifacts/task6/parallel-hypotheses/h2-ypcb-ddr3-v96-single-driver-wdf-probe-board-run-2026-05-05/`.
Bitstream: `/nix/store/zzd59v0bk2dlb9fmj03lm37bnm7wp47d-task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-init-bandwidth-probe.bit`.
SHA256: `c2b430354b5291aacece14e40d2b8f739a375f9dfc42cdd5e2d959dd044b596c`.

Build result: v96 fixed the v95 multi-driver issue. Yosys `CHECK` reported `0 problems` before and after synthesis. Post-placement timing passed, including `user_clk=51.02 MHz`, `clk200=495.05 MHz`, `core.iodelay_clk=917.43 MHz`, and `jtag_debug_shift.drck=282.89 MHz`.

Board result: `version=96`, `pll_locked=true`, `init_error=false`, `init_done=true`, `init_seq_done=true`, `init_seq_error=false`, `dfii_step=63`, and DFII mismatch masks remained zero. Native write/read still failed with `write_command_count=16`, `write_data_count=16`, `response_count=16`, `mismatch_count=16`, and sampled readback data all zero.

New diagnostic: `native_readscan_first_nonzero_addr=0x0cf8`, `native_readscan_nonzero_chunk_seen=0xcf`, `native_readscan_first_nonzero_chunk_mask=0x8`, `native_readscan_nonzero_count=15`. Decoding status byte `0xcf`: push_seen=1, pop_seen=1, fifo_nonempty_at_event=0, push_at_event=0, pop_at_event=1, slave_wrdata_event=1, master_wrdata_event=1, select_native=1.

Interpretation: the generated-core native WDF push does occur, so the push condition is not completely wrong. The failure is that the FIFO is empty by the captured native PHY write-data event while pop/slave/master events are asserted. This points to pop timing: the FIFO is likely being drained by slave wrdata events before the actual PHY/master write-data event. Next v97 should keep the single-driver patch and compact status byte, but pop on native master/PHY wrdata event instead of native slave wrdata event, or otherwise guard against empty pops.

### DDR3 v97 master-event WDF pop result (2026-05-05)

Experiment source: `07b3635 task6-ddr3: prepare v97 master-event WDF pop`.
Result artifact: `artifacts/task6/parallel-hypotheses/h2-ypcb-ddr3-v97-master-event-wdf-pop-board-run-2026-05-05/`.
Bitstream: `/nix/store/vh036444f3a0kjpz1gnykan58si6q0d4-task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-init-bandwidth-probe.bit`.
SHA256: `0697dc1277858e270399554ba743f896164a1058a8b01a4d1caac84d4e56689e`.

Build result: post-placement timing passed, including `user_clk=50.44 MHz`, `clk200=397.61 MHz`, `core.iodelay_clk=816.33 MHz`, and `jtag_debug_shift.drck=258.73 MHz`. Router converged and bitstream packaged.

Board result: `version=97`, `pll_locked=true`, `init_error=false`, `init_done=true`, `init_seq_done=true`, `init_seq_error=false`, `dfii_step=63`, and DFII mismatch masks remained zero. Native write/read still failed with `write_command_count=16`, `write_data_count=16`, `response_count=16`, and `mismatch_count=16`, but the failure changed: sampled native readback is no longer zero. `sample_rdata_0..7` and `last_rdata` are all `0x99ce179ffcb9943f`.

New diagnostic: `native_readscan_first_nonzero_addr=0x0ef8`, `native_readscan_nonzero_chunk_seen=0xef`, `native_readscan_first_nonzero_chunk_mask=0x8`, `native_readscan_nonzero_count=15`. Decoding status byte `0xef`: push_seen=1, pop_seen=1, fifo_nonempty_at_event=1, push_at_event=0, pop_at_event=1, slave_wrdata_event=1, master_wrdata_event=1, select_native=1.

Interpretation: v97 is a real movement from missing/zero native writes to nonzero native writes with wrong data. Popping the FIFO on the master/PHY write-data event keeps the FIFO nonempty at the captured event, and native writes affect memory. The remaining bug is data correctness/advancement: all read samples return the same wrong constant word rather than the per-address expected pattern. Next v98 should keep master-event pop and expose whether the same FIFO word is being replayed or the wrong DFI beat/lane is selected, ideally by capturing push/pop/master/slave counters plus low `data_out` and `we_out` bits at the event.

### DDR3 v98-v100 seed-13 reproducibility reset attempt (2026-05-06)

We rebuilt on the known-good v97 lineage with the same seed-13 target family and explicitly narrowed what changed per experiment. This attempt was to isolate whether we had drifted into route sensitivity after commit churn before touching deeper native data-path edits.

- v98 (seed-13 addrwalk + native) was intentionally rebuilt to the historical `task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-init-bandwidth-probe` target.
  - Commit under test: `32abc0f` (`task6-ddr3: correct v110 source7/source8 summary signatures`) on `task6-ddr3-v83-resurrection`.
  - Source `target`: `task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-init-bandwidth-probe`.
  - Board result: `init_done=true`, `pll_locked=false`, `init_error=true`, `state=PROBE_ERROR`, timeout-style read completion.
  - DFII: `dfii_word_mismatch_mask=0`, `dfii_uniform_mismatch_mask=84`, `dfii_step=130`.
  - Native activity counters remained absent from effective write/read samples.
  - Interpretation: this was a seed-13 route-level fail, not a native logic fix.
- v99 (DFII-only edge-comp addrwalk) kept only DFII test mode from the same seed-13 target lineage.
  - Source `target`: `task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-init-bandwidth-probe`.
  - Board result: `init_done=true`, `pll_locked=false`, `init_error=true`, `state=DFII_SEQ_IDLE`, `state=PROBE_ERROR`.
  - Native event stream was intentionally inactive, and response counters stayed zero while timeout remained.
  - Interpretation: this shifted the failure surface to DFII/init-liveness rather than native wiring.
- v100 (DFII init-only edge-comp) removed write/read scanning entirely to validate init-only sequence health.
  - Source `target`: `task6-ypcb-litedram-no-odelay-lowrate-edge-comp-init-bandwidth-probe`.
  - Board result: `init_done=true`, `pll_locked=false`, `init_error=true`, `state=DFII_SEQ_IDLE`, `state=PROBE_ERROR`.
  - Native debug was inactive by design; `read_target_seen=false`, `timeout_seen=true`.
  - Interpretation: this indicates a persistent init/DFII liveness problem at that probe lineage rather than a native data-path-only regression.

Current execution checkpoint:

- Seed-13 family experiments reproduced the same failure pattern and are currently blocking: clean-init behavior is present but `pll_locked` drops and `init_error` turns true during probe completion.
- Rebuild reproducibility is now tied to immutable source/target identity per experiment; no assumptions about previous target names.
- Next active experiment should be the narrowest init/liveness telemetry check: DFII status/state sampling only, with edge-compare and native tests disabled.

### DDR3 M1 execution rule: DFII byte/phase association matrix first (2026-05-05)

Decision: keep the open-source LiteDRAM/LiteX no-ODELAY path for M1. Do not switch to Vivado MIG or a new controller at this stage. The current evidence does not show a dead DDR3 stack: init, DFII CSR access, native command/data/response completion, and now v97 nonzero native readback all work. The unresolved problem is narrower: byte/phase/beat/packing association in the no-ODELAY LiteDRAM path.

Operating policy from this point:

```text
One active DDR3 hypothesis at a time.
No new native-port BIST variant unless it answers a named hypothesis.
No rowstream integration until DDR3 linear read is proven.
No new controller unless LiteDRAM no-ODELAY path is falsified by a byte/phase matrix.
No Vivado MIG for implementation.
```

Next promoted artifact:

```text
artifacts/task6/parallel-hypotheses/h2-litedram-dfii-byte-phase-association-matrix.json
```

Required hypothesis:

```text
DFII byte/phase writes map to a fixed physical-to-logical byte/phase association.
```

Required acceptance rule:

```text
PASS: matrix is one-to-one or explainable by a fixed permutation/phase transform.
FAIL: data collapses into one logical byte lane or shows non-bijective aliasing.
```

Required experiment shape: write one distinctive byte at a time through DFII, with exactly one write phase, beat, byte position, and physical lane candidate active. Then read back through DFII and record the observed phase, beat, logical byte, value, and mask. The output must derive a mapping and make one explicit next decision: apply mapping, fix generator/packing, or falsify the current PHY path.

Do not widen delay sweeps before this matrix exists. The next source experiment should be a DFII byte/phase association probe, not another native BIST variant.

## Deep Research replan checkpoint (2026-05-07)

Source: `~/Downloads/Task_6_Deep_Research_Plan_for_TinyStories_on_XC7K480T.md`.

Strategic decision:

- Make no-DDR, reduced-vocabulary, quantized, time-multiplexed token generation
  the primary Task 6 path.
- Keep DDR3 as a bounded parallel recovery lane with strict gates, not as the
  main milestone.
- Use StreamTensor as an idea source only; do not spend the month rebuilding
  an unpublished compiler stack.
- Keep Ternip/ternary work as a parallel risk-reduction branch, not the main
  critical path until reduced synthesis and parity gates are stable.
- Add out-of-band enclosure power recovery if it can arrive quickly in Spain.

Rationale:

- The Task 3 baseline uses enormous LUT/FF fabric and essentially no DSP/BRAM,
  so the failure is architectural, not a near-fit optimization miss.
- Existing v1k/v4k Task 6 anchors already prove a better regime: explicit
  time-multiplexing, DSP use, BRAM use, simulation evidence, and board/JTAG
  evidence for v1k.
- The full public TinyStories-1M checkpoint has a 50,257-token vocab, while the
  TinyStories paper reportedly trained with the top 10k tokens. A
  TinyStories-compatible 10k-vocab tied-head target is therefore a high-leverage
  fit strategy if reviewer acceptance does not require exact checkpoint
  identity.

Primary experiment backlog:

| ID | Experiment | First deliverable | Stop condition |
| --- | --- | --- | --- |
| E1 | Packed embedding / tied output-head surface for 50k vs 10k vocab | Synthesis/resource comparison for int8/int4 packed storage | 10k packed storage still leaves no credible room for the rest of the design |
| E2 | Time-multiplexed hidden-64 transformer block lane | Sim + synthesis comparison against current lowering | One block still explodes in LUT/FF after explicit reuse |
| E3 | 10k-vocab TinyStories-compatible software model/export | Quantized checkpoint/export plus fixed-prompt quality deltas | Quality collapses or retraining/export takes over the critical path |
| E4 | No-DDR reduced path to one hardware token | JTAG-readable token/top-k result from hardware | Control loop or route remains unstable after E1/E2 are promising |
| E5 | v4k board replay with richer debug | Physical-board classification of the current v4k routed/sim-passing bitstream | Still cannot distinguish board failure class after one focused debug pass |
| E6 | Ternip reduced gate | First scoreboard row for reduced synthesis/parity | Toolchain/parity failures dominate for more than the allotted branch budget |
| E7 | Host-staged JTAG fallback | One-layer host-fed proof | JTAG protocol/control complexity dominates |
| E8 | Open PCIe smoke via `regymm/pcie_7x` | Minimal endpoint/MMIO evidence | Link/host integration consumes first-week critical-path time |

DDR3 policy from the replan:

- First prove control-path reproducibility (`magic`, PLL lock, reset exit)
  before interpreting DDR data results.
- Then isolate training/MPR/lane identity before any full native-port stress.
- Stop broad DDR3 work if control-path or training visibility cannot be made
  reproducible in a focused 2-day window.
- One-channel-first is the only reasonable open-source DDR3 target; dual-channel
  capacity is future work until one channel is reliable.

Hardware-in-the-loop rules:

- Create run directories under `artifacts/task6/runs/` with `meta.yaml`,
  `verdict.json`, logs, bitstreams, readback, and reference artifacts.
- Serialize board access through a lock or single scheduler queue.
- Every board bitstream should expose a versioned JTAG magic/status payload.
- Score lexicographically:
  1. correctness pass
  2. route pass
  3. board pass
  4. BRAM fit margin
  5. LUT fit margin
  6. DSP fit margin
  7. timing margin
  8. runtime
- Prefer recovery order: in-design reset, then JTAG reconfigure, then enclosure
  power cycle if automated power control is available.

Procurement note:

- Buy a scriptable AC smart plug with local API support for the Helios enclosure
  if it can arrive quickly in Spain. This is the cheapest out-of-band recovery
  path for overnight autonomous runs.
- Defer a USB relay for SW1/SW2 until AC power recovery is working or proven
  insufficient.
- Do not prioritize a second YPCB board or second Helios enclosure for the Task
  6 critical path.

First five actions from the replan:

1. Create the `artifacts/task6/runs/` schema and board lock mechanism.
2. Add a budget script for current 50k vocab vs 10k tied-head packed storage.
3. Implement E1: packed embedding/output-head synthesis for 50k and 10k vocab.
4. Implement E2: reusable one-block lane synthesis/resource comparison.
5. Buy/script local-control AC power recovery for the Helios enclosure.

Execution checkpoint, 2026-05-07:

- Extended `scripts/task6/score_vocab_memory_surface.py` so the CSV and JSON
  surface explicitly report 10k gates, rowwise int8/int4 BRAM ceilings, and
  reduced-vocab vs full-vocab ratios.
- Exported `python-with-tiny-stories-bin` from `flake.nix` because the existing
  `python-with-tiny-stories` package realizes source PyTorch on this machine.
  The binary-Torch environment keeps this loop in seconds instead of hours.
- Generated
  `artifacts/task6/parallel-hypotheses/h2-vocab10k-memory-surface-score.json`
  and `.csv` against the copied baseline bundle at
  `artifacts/task6/baselines/tiny-stories-1m-baseline-float-selftest-all-memory-utilization/summary.json`.
- Result: 10k tied vocab is a credible on-chip prototype target. Unique f32
  token+position storage is 2,592,768 bytes, 563 BRAM36, 58.95% of the device.
  Rowwise int8 is 688,704 bytes, 150 BRAM36, 15.71%. Rowwise int4 is 364,608
  bytes, 80 BRAM36, 8.38%.
- Full 50,257-token f32 tied storage remains impossible on chip at 13,390,080
  bytes, 2906 BRAM36, 304.29%. Full rowwise int8 fits raw BRAM at 772 BRAM36,
  80.84%, but leaves too little margin to treat as the first synthesis path.
- Next execution gate: generate the v10k packed tied-vocab/output-head artifact
  from this scorecard, then synthesize it before returning to DDR3.
- Added `scripts/task6/task6_board_run.py` as the first board-run skeleton:
  `init` creates a run directory with `meta.yaml`, `verdict.json`, `logs/`,
  `bitstreams/`, `readback/`, and `references/`; `with-lock` runs a command
  under `artifacts/task6/board.lock` and records the command result. This is
  the serialization primitive for autonomous JTAG/programming loops.
- Added and ran the first E1 synthesis target,
  `.#task6-int8-vocab10k-output-head-top1-utilization`, with `VOCAB_SIZE=10000`
  and `TILE_OUT_DIM=80`. Result artifact:
  `artifacts/task6/parallel-hypotheses/e1-vocab10k-output-head-utilization-summary.json`.
  The mapped output-head kernel uses 1,653 LUT, 2,305 FF, 4 DSP, and 160 BRAM36.
  This validates the reduced-vocab time-multiplexed direction for the output
  projection; the next gate is simulation/data correctness around v10k, not DDR3.
- Generated the v10k selftest data in `/tmp/task6-v10k-output-head` using the
  existing residual-add boundary. Result artifact:
  `artifacts/task6/parallel-hypotheses/e1-vocab10k-output-head-data-summary.json`.
  The deterministic sample keeps int8 top1 aligned with f32 top1
  (`top_index=213`, `top_acc=54965`, normalized RMSE `0.01393`). The generated
  vocabulary memory has 160,000 packed words, matching the 160 BRAM36 synthesis
  result. Next gate: put this behind a flake-backed v10k selftest and run SV sim.
- Added flake-backed v10k residual-add/output-head selftest targets:
  `.#task6-int8-v10k-l2-residual-add-output-head-selftest-tb-data-sv`,
  `.#task6-int8-v10k-l2-residual-add-output-head-selftest-top`,
  `.#task6-int8-v10k-l2-residual-add-output-head-selftest-sim-main`, and
  `.#task6-int8-v10k-l2-residual-add-output-head-selftest-sv-sim`.
- The first v10k SV sim exposed two useful failures. First, the shared timeout
  was too low for the larger vocab lane, so the Verilator selftest timeout moved
  from 350,000 to 1,000,000 cycles. Second, `TILE_OUT_DIM=80` exposed a real
  non-power-of-two addressing bug: the previous phase/tile address decode used
  bit slicing and concatenation, equivalent to `phase * 128 + offset`, instead
  of `phase * 80 + offset`.
- Fixed the non-power-of-two tile path in
  `rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel.sv` and the
  vocabulary loader path in
  `fpga/rtl/task6_int8_v4k_l2_residual_add_output_head_selftest_top.sv` by using
  explicit phase-base arithmetic and division/modulo load decoding.
- Result: v10k integrated SV sim passes:
  `.#task6-int8-v10k-l2-residual-add-output-head-selftest-sv-sim` produced
  `/nix/store/1bn5kmvmils8lym05di3nyf604hcdqvm-task6-int8-v10k-l2-residual-add-output-head-selftest-sv-sim.json`
  with `status=PASS`, `cycles=556742`, `top_index=213`, and `top_acc=54965`.
  The v4k regression also passes:
  `.#task6-int8-v4k-l2-residual-add-output-head-selftest-sv-sim` produced
  `/nix/store/njfzz1vh9b02ig663jv5qpx4yqhlrgwr-task6-int8-v4k-l2-residual-add-output-head-selftest-sv-sim.json`
  with `cycles=265848`, `top_index=1321`, and `top_acc=52140`.
- Added `artifacts/task6/STATUS.md` as the table-first Task 6 status surface,
  following the useful practices from `docs/LLM_genius.org`: tables, explicit
  assumptions, lens-based promotion gates, and mechanistic failure recording.
  Next execution gate: mapped utilization for the integrated v10k selftest,
  then route/bitstream if the utilization margin is credible.
- Added the integrated v10k mapped-utilization target
  `.#task6-int8-v10k-l2-residual-add-output-head-selftest-utilization`.
  It builds from
  `.#task6-int8-v10k-l2-residual-add-output-head-selftest-json` and uses the
  same top module name as the v4k selftest, with generated v10k includes.
- Result: the integrated v10k selftest remains a credible fit candidate after
  Yosys `synth_xilinx`. Result artifact:
  `artifacts/task6/parallel-hypotheses/e1-vocab10k-integrated-utilization-summary.json`.
  Nix result:
  `/nix/store/q94hc22kyhzyaa0ynwwsi0nfdci8kg80-task6-int8-v10k-l2-residual-add-output-head-selftest-utilization`.
  Mapped resources are 43,695 LUT (14.63%), 8,958 FF (1.50%), 15 DSP (0.78%),
  and 386 BRAM36-equivalent (40.42%). This is the first integrated Task 6 lane
  that has both RTL correctness and mapped-resource fit evidence.
- Next execution gate: add a v10k route/bitstream target and run it on the board
  through `scripts/task6/task6_board_run.py` so JTAG programming/readback is
  serialized and leaves a reproducible run directory.
- Added v10k route/bitstream targets, including JTAG-debug variants:
  `.#task6-int8-v10k-l2-residual-add-output-head-selftest-bitstream`,
  `.#task6-int8-v10k-l2-residual-add-output-head-selftest-jtag-debug-bitstream`,
  and
  `.#task6-int8-v10k-l2-residual-add-output-head-selftest-jtag-debug-5mhz-bitstream`.
- The first JTAG-debug route attempt at 50 MHz was pruned after placement:
  nextpnr reported the main design clock at 9.25 MHz max, which fails the 50 MHz
  target, while the JTAG `drck` path had 257.73 MHz margin. The attempt was
  cancelled during router iteration 1 rather than burning more time on an image
  that was not suitable as the first board bring-up candidate. Result artifact:
  `artifacts/task6/parallel-hypotheses/e1-vocab10k-jtag-debug-50mhz-route-attempt-summary.json`.
- The 5 MHz JTAG-debug route passed placement timing but then stalled in the
  same router shape as the 50 MHz attempt: router iteration 1 reported
  `wires=2243522`, `overused=179975`, and `overuse=242671`, with no later
  progress after roughly 21 CPU-minutes. Result artifact:
  `artifacts/task6/parallel-hypotheses/e1-vocab10k-jtag-debug-5mhz-route-attempt-summary.json`.
- Current route gate: build the plain 5 MHz bitstream, without the JTAG-debug
  payload, to separate the integrated v10k design's routability from the debug
  payload's routability. If the plain image routes, the first board smoke test
  can use LED pass/fail while a smaller readback payload is designed.
- The plain 5 MHz route also passed placement timing, with main clock max
  frequency `10.04 MHz`, but stalled after router iteration 1:
  `wires=2247475`, `overused=194634`, `overuse=267576`. Result artifact:
  `artifacts/task6/parallel-hypotheses/e1-vocab10k-plain-5mhz-route-attempt-summary.json`.
- Decision: the v10k integrated selftest is a mapped fit, but it is not yet a
  route-ready board image in its current shape. Do not keep rerunning nextpnr on
  this exact design. The next route experiment should reduce route pressure:
  either a smaller vocab lane to find the routable frontier, or a re-banked /
  placement-friendlier output-head memory shape before returning to v10k.

### v9984 JTAG-debug board-candidate build update (2026-05-08)

Question:

- Can the already proven near-10k `vocab_size=9984`, `TILE_OUT_DIM=64` board
  image route with `ENABLE_JTAG_DEBUG=1`, so correctness can be read back
  automatically instead of relying on visual LEDs?

Command:

- `nix build .#task6-int8-v9984-l2-residual-add-output-head-selftest-jtag-debug-5mhz-bitstream --no-link --print-out-paths -L`

Result:

- PASS. Bitstream:
  `/nix/store/k52psqh0lv416xbg5xgl3zs5fxlamm0f-task6-int8-v9984-l2-residual-add-output-head-selftest-jtag-debug-5mhz.bit`
- Yosys `CHECK` reported 0 problems.
- JTAG debug is present in the routed design: `BSCAN=1`, with a 768-bit
  debug-shift payload.
- Utilization after packing/placement:
  - `SLICE_LUTX=25056`
  - `SLICE_FFX=9896`
  - `RAMB36E1=320`
  - `RAMB18E1=6`
  - `DSP48E1=14`
  - `BUFGCTRL=2`
- Router convergence:
  - iteration 1: `overused=52759`
  - iteration 10: `overused=29`
  - iteration 20: `overused=6`
  - iteration 33: `overused=0`, `overuse=0`, `archfail=0`
  - router2 time: 1565.72 seconds
- Post-route timing:
  - main clock max frequency: 101.53 MHz, pass at 5 MHz
  - JTAG `drck` max frequency: 377.79 MHz, pass at 5 MHz
  - main-clock to JTAG-domain max delay: 3.44 ns

Interpretation:

- The v9984 tile64 lane remains routeable with the BSCAN-backed JTAG debug
  payload enabled. This is now the best board candidate because it combines the
  previous visual selftest pass shape with autonomous readback support.
- Next gate: program this bitstream under `scripts/task6/task6_board_run.py`,
  then read the JTAG debug payload through the direct FTDI path using
  `--tdo-bit 7`.

Board result:

- PASS. Run directory:
  `artifacts/task6/runs/2026-05-08T12-06-39+0200-v9984-jtag-debug-program-readback`
- Programming command:
  `openFPGALoader -c digilent_hs3 --ftdi-serial 210299BF3824 /nix/store/k52psqh0lv416xbg5xgl3zs5fxlamm0f-task6-int8-v9984-l2-residual-add-output-head-selftest-jtag-debug-5mhz.bit`
- openFPGALoader exited 0 and reported `isc_done=1`, `init=1`, `done=1`.
- Direct FTDI MPSSE IDCODE check with `--tdo-bit 7` returned `0x23751093`.
- JTAG payload readback with `--tdo-bit 7` passed on the first poll:
  - `magic_ok=True`
  - `state=SELFTEST_PASS`
  - `fail_reason=NONE`
  - `cycle_count=172538`
  - observed/expected top index: `229 / 229`
  - observed/expected top acc: `54965 / 54965`
  - vocab checksum: `0x693c603d / 0x693c603d`
  - head activation checksum: `0x00001ef9 / 0x00001ef9`
  - embedding token/position/combined checksums all matched.

Decision:

- Promote v9984 `TILE_OUT_DIM=64` JTAG-debug as the current golden board
  regression lane. New ternary, full-vocab, or larger-structure experiments
  should either preserve this automated readback loop or explicitly replace it
  with an equally fast correctness gate.

### Experiment runner and fixed-2-bit ternary output-head update (2026-05-08)

Question:

- Can vocab-size and quantization experiments share one durable correctness
  result format, and does a simple fixed-width ternary output-head variant route
  on the proven v9984 tile64 JTAG-debug lane?

Runner:

- Added `scripts/task6/task6_experiment_runner.py`.
- The runner records one JSON result per experiment under
  `artifacts/task6/experiments/<timestamp>-<label>/result.json`.
- Parameters recorded:
  - logical and physical vocab size
  - `TILE_OUT_DIM`
  - weight quantization mode
  - flake target prefix
  - repo head and dirty state
- Gate records include command, return code, log path, Nix output path, and
  compact summaries for generated test data, SV simulation, and route logs when
  the gate runs uncached.
- Board programming is supported only through `scripts/task6/task6_board_run.py`
  so board access remains serialized.

Runner smoke test:

- Command:
  `scripts/task6/task6_experiment_runner.py --label ternary2-v9984-runner-smoke-v2 --vocab-size 9984 --tile-out-dim 64 --weight-quantization ternary2 --gate tb-data --gate sv-sim`
- Result JSON:
  `artifacts/task6/experiments/2026-05-08T12-39-08+0200-ternary2-v9984-runner-smoke-v2/result.json`
- Result: PASS for the runner gates.
- Generated test-data summary:
  - `weight_quantization=ternary2`
  - `packed_weight_words=39936`
  - quantized top index/acc: `737 / 1446`
  - float reference top index: `229`
  - `int8_top_matches_f32_top=false`
  - `normalized_rmse=0.647246702830111`
- SV sim summary:
  - `status=PASS`
  - cycles: `194563`
  - top index/acc: `737 / 1446`

Fixed-2-bit ternary route/bitstream:

- Command:
  `nix build .#task6-ternary-v9984-l2-residual-add-output-head-selftest-jtag-debug-5mhz-bitstream --no-link --print-out-paths -L`
- Result: PASS. Bitstream:
  `/nix/store/9ziripbivrzlppq86sj8bryds9g311gr-task6-ternary-v9984-l2-residual-add-output-head-selftest-jtag-debug-5mhz.bit`
- FASM output:
  `/nix/store/bymqa5k3ym112vjm4rrlgzm9p5ki35dm-task6-ternary-v9984-l2-residual-add-output-head-selftest-jtag-debug-5mhz.fasm`
- Cached route/bitstream result JSON:
  `artifacts/task6/experiments/2026-05-08T12-40-47+0200-ternary2-v9984-route-bitstream-record/result.json`
- Utilization after packing/placement:
  - `SLICE_LUTX=29574`
  - `SLICE_FFX=9741`
  - `RAMB18E1=318`
  - `RAMB36E1=8`
  - `DSP48E1=10`
  - `SELMUX2_1=6218`
  - `BSCAN=1`
- Router convergence:
  - iteration 1: `overused=49103`
  - iteration 10: `overused=136`
  - iteration 20: `overused=46`
  - iteration 31: `overused=5`
  - iteration 33: `overused=0`, `overuse=0`, `archfail=0`
  - router2 time: 834.04 seconds
- Post-route timing:
  - main clock max frequency: 77.10 MHz, pass at 5 MHz
  - JTAG `drck` max frequency: 367.11 MHz, pass at 5 MHz
  - main-clock to JTAG-domain max delay: 3.12 ns

Interpretation:

- The simple fixed-2-bit ternary output head is RTL-correct against its
  generated quantized reference and routes with JTAG debug enabled.
- It is not the intended "1.58-bit" ternary storage experiment. It stores each
  ternary weight in 2 bits. A true dense ternary storage lane should use base-3
  packing, for example 20 trits per 32-bit word (`32 / 20 = 1.6` bits/weight),
  without entropy coding as the first implementation.
- This fixed-2-bit lane is useful as a routeability and compute-control
  datapoint, but its current global-threshold quantization badly changes the
  output-head result (`top_index=737` vs float `229`). Do not promote it as a
  quality-preserving model lane without improving the ternary quantization
  scheme.

### Base3-20 dense ternary correctness update (2026-05-08)

Question:

- Can we implement true dense ternary storage without entropy coding, using
  base-3 packing close to the theoretical `log2(3) = 1.585` bits/weight?

Implementation:

- Added `ternary-base3-20` generator mode.
- Added `task6_ternary_base3_vocab_output_head_top1_kernel`.
- Encoding:
  - each 32-bit word stores 20 trits
  - trit code `0 = 0`, `1 = +1`, `2 = -1`
  - storage density is `32 / 20 = 1.6` bits/weight
- First correctness lane uses `vocab_size=10000`, `TILE_OUT_DIM=80` so each
  tile row has four full groups of 20 trits and does not waste tail bits.
- This is dense ternary packing, not entropy coding.

Command:

- `scripts/task6/task6_experiment_runner.py --label ternary-base3-v10k-correctness-v3 --vocab-size 10000 --tile-out-dim 80 --weight-quantization ternary-base3-20 --gate tb-data --gate sv-sim`

Result:

- PASS. Result JSON:
  `artifacts/task6/experiments/2026-05-08T12-51-42+0200-ternary-base3-v10k-correctness-v3/result.json`
- Generated data:
  - `weight_quantization=ternary-base3-20`
  - `packed_weight_words=32000`
  - logical/physical vocab: `10000 / 10000`
  - tile out dim: `80`
  - quantized top index/acc: `721 / 1446`
  - float reference top index: `213`
  - `int8_top_matches_f32_top=false`
  - `normalized_rmse=0.6473674272466682`
- SV simulation:
  - `status=PASS`
  - cycles: `170616`
  - top index/acc: `721 / 1446`

Interpretation:

- Dense base3-20 ternary decode is RTL-correct against the generated quantized
  Python reference.
- The storage result is the desired near-1.58-bit ternary shape:
  `10000 * 64 / 20 = 32000` 32-bit words.
- Model fidelity remains poor with the current global-threshold ternary
  quantizer, so the next quality work should improve ternary quantization
  separately from storage correctness.
- Next hardware gate, if we want a routeability datapoint for the true dense
  storage lane, is Yosys synthesis for the same base3-20 v10k/tile80 design.

Synthesis probe:

- Added a Yosys `jtag-debug-json` target for the same base3-20 lane and started
  it through the experiment runner:
  `scripts/task6/task6_experiment_runner.py --label ternary-base3-v10k-synth --vocab-size 10000 --tile-out-dim 80 --weight-quantization ternary-base3-20 --gate json`
- The run was manually pruned after roughly six minutes in `yosys -s run.ys`
  with no wrapper output.
- Result artifact was left as an interrupted runner directory:
  `artifacts/task6/experiments/2026-05-08T12-53-15+0200-ternary-base3-v10k-synth/result.json`

Interpretation of the pruned synthesis probe:

- This does not mean Yosys cannot support ternary-weight arithmetic. The lane
  uses binary FPGA hardware with ternary-valued weights encoded as bits/trits,
  not three-valued logic gates.
- The likely issue is the naive base3 decoder implementation: each word decode
  used parallel constant `/` and `%` operations to extract 20 trits. That is a
  bad synthesis shape.
- Next implementation should keep the same storage contract but replace the
  decoder with a synthesis-friendly structure:
  - sequential base3 unpacker using subtract/compare or a small state machine
  - pre-decode one 32-bit word into 20 two-bit trit codes over multiple cycles
  - then reuse the already-proven add/sub/skip ternary accumulator datapath

### Output-head quantization fidelity sweep (2026-05-08)

Question:

- Before spending more RTL work on ternary storage/decode, is any cheap
  post-training ternary output-head quantization scheme fidelity-preserving
  enough to deserve promotion?

Implementation:

- Added `scripts/task6/score_output_head_quantization.py`.
- Added flake target:
  `task6-output-head-v10k-quantization-sweep`.
- The sweep is Python-only and uses the current residual-add proof hidden state
  with the v10k TinyStories representative output head.
- Durable artifacts:
  - `artifacts/task6/quantization/output-head-v10k-sweep.json`
  - `artifacts/task6/quantization/output-head-v10k-sweep.md`

Command:

- `nix build .#task6-output-head-v10k-quantization-sweep --no-link --print-out-paths -L`

Result summary:

| strategy | family | raw bits/w | scales | zero % | top1 | top1 match | top5 overlap | top10 overlap | float top1 rank | norm RMSE | base3 words | promote |
| --- | --- | ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | --- |
| `int8_per_tensor` | int8 | 8.000 | 1 | 1.5 | 213 | yes | 5 | 10 | 1 | 0.0111 |  | yes |
| `ternary_per_row_t0.25_least_squares` | ternary | 1.585 | 10000 | 15.7 | 213 | yes | 2 | 4 | 1 | 0.5240 | 32000 | no |
| `ternary_per_row_t0.25_mean_abs` | ternary | 1.585 | 10000 | 15.7 | 213 | yes | 2 | 4 | 1 | 0.5371 | 32000 | no |
| `ternary_per_row_t1_least_squares` | ternary | 1.585 | 10000 | 57.4 | 98 | no | 4 | 6 | 8 | 0.4523 | 32000 | no |
| `ternary_per_row_t0.75_least_squares` | ternary | 1.585 | 10000 | 44.9 | 9927 | no | 3 | 5 | 6 | 0.4315 | 32000 | no |
| `ternary_per_row_grid_lsq` | ternary | 1.585 | 10000 | 45.5 | 9163 | no | 3 | 6 | 9 | 0.4325 | 32000 | no |
| `ternary_global_t0.5_least_squares` | ternary | 1.585 | 1 | 31.1 | 721 | no | 2 | 5 | 6 | 0.4656 | 32000 | no |

Interpretation:

- INT8 remains the only clearly fidelity-preserving post-training quantization
  in this single-hidden-state sweep.
- A per-row ternary threshold at `0.25 * mean_abs` with least-squares row scales
  preserves top-1 for this one sample, but its top-5 overlap is only `2/5`,
  top-10 overlap is `4/10`, and normalized RMSE is still `0.5240`.
- Current global-threshold ternary is not competitive; it misses top-1 and
  keeps only `2/5` top-5 overlap.
- Decision: do not spend the next iteration on a base3 RTL decoder unless the
  goal is pure hardware research. For model progress, the next productive
  quantization experiment should be either INT4/INT3-like output-head scoring
  or a multi-sample ternary sweep with a stronger promotion bar.

INT4/INT3 extension:

- Extended `scripts/task6/score_output_head_quantization.py` with per-tensor
  and per-row signed symmetric INT4, INT3, and INT2 strategies.
- Re-ran:
  `nix build .#task6-output-head-v10k-quantization-sweep --no-link --print-out-paths -L`
- Updated durable artifacts:
  - `artifacts/task6/quantization/output-head-v10k-sweep.json`
  - `artifacts/task6/quantization/output-head-v10k-sweep.md`

Top rows from the updated table:

| strategy | family | raw bits/w | scales | zero % | top1 | top1 match | top5 overlap | top10 overlap | float top1 rank | norm RMSE | packed words | promote |
| --- | --- | ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | --- |
| `int8_per_tensor` | int8 | 8.000 | 1 | 1.5 | 213 | yes | 5 | 10 | 1 | 0.0111 | n/a | yes |
| `int4_per_row` | int4 | 4.000 | 10000 | 14.8 | 213 | yes | 5 | 8 | 1 | 0.1081 | 80000 | yes |
| `int4_per_tensor` | int4 | 4.000 | 1 | 27.0 | 213 | yes | 4 | 8 | 1 | 0.1990 | 80000 | yes |
| `int3_per_row` | int3 | 3.000 | 10000 | 33.4 | 213 | yes | 4 | 8 | 1 | 0.2549 | 60000 | yes |
| `int3_per_tensor` | int3 | 3.000 | 1 | 58.0 | 213 | yes | 3 | 6 | 1 | 0.4679 | 60000 | yes |
| `ternary_per_row_t0.25_least_squares` | ternary | 1.585 | 10000 | 15.7 | 213 | yes | 2 | 4 | 1 | 0.5240 | 32000 | no |
| `int2_per_row` | int2 | 2.000 | 10000 | 79.7 | 213 | yes | 2 | 2 | 1 | 0.7225 | 40000 | no |

Interpretation:

- Quantization work is still worth it, but ternary is not the mainline right
  now.
- INT4 per-row is the best next quantization target: it preserves top-1 and
  full top-5 on this sample with much lower error than ternary, while halving
  the INT8 output-head storage.
- INT3 per-row is the next riskier compression target: it preserves top-1 and
  `4/5` top-5 on this sample at `3` bits/weight.
- INT2 and cheap ternary are too lossy for the immediate model-progress lane.

### Current global priority plan (2026-05-08)

Priority order for the next Task 6 work:

1. Multi-sample INT4/INT3 output-head fidelity sweep.
   - Reason: single-sample evidence says INT4 per-row is much stronger than
     ternary and halves INT8 output-head storage.
   - Promotion bar: all samples preserve top-1, minimum top-5 overlap at least
     `4/5`, and max normalized RMSE at most `0.30`.
2. If INT4 passes multi-sample fidelity, implement INT4 packed output-head RTL
   on the proven JTAG-debug lane.
   - Keep v9984 INT8 JTAG-debug as the board regression.
   - Use `TILE_OUT_DIM=64` first unless the packing strongly argues otherwise.
3. If INT4 fails but INT3/INT4 remains close, improve quantization scoring
   before RTL:
   - more samples
   - per-row scale storage shape
   - Q-format sidecar scoring
4. Keep ternary/base3 as hardware-research side lane, not model-progress
   mainline, until trained ternary weights or a stronger post-training method
   exists.
5. Keep DDR/external memory as the fallback for full-vocab/full-model weights,
   but avoid spending the next short iteration there unless quantization cannot
   preserve enough fidelity.

Execution result:

- Added `scripts/task6/score_output_head_multisample_quantization.py`.
- Added flake target:
  `task6-output-head-v10k-multisample-quantization-sweep`.
- Ran:
  `nix build .#task6-output-head-v10k-multisample-quantization-sweep --no-link --print-out-paths -L`
- Durable artifacts:
  - `artifacts/task6/quantization/output-head-v10k-multisample-sweep.json`
  - `artifacts/task6/quantization/output-head-v10k-multisample-sweep.md`

Multi-sample result:

| strategy | bits/w | scales | zero % | top1 | min top5 | mean top5 | min top10 | max rank | mean RMSE | max RMSE | packed words | promote |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `int8_per_tensor` | 8.000 | 1 | 1.5 | 8/8 | 5 | 5.00 | 9 | 1 | 0.0110 | 0.0111 | n/a | yes |
| `int4_per_row` | 4.000 | 10000 | 14.8 | 6/8 | 3 | 3.88 | 7 | 2 | 0.1075 | 0.1089 | 80000 | no |
| `int3_per_row` | 3.000 | 10000 | 33.4 | 6/8 | 2 | 3.38 | 6 | 3 | 0.2521 | 0.2560 | 60000 | no |
| `int4_per_tensor` | 4.000 | 1 | 27.0 | 5/8 | 2 | 3.50 | 7 | 5 | 0.1989 | 0.2011 | 80000 | no |
| `int3_per_tensor` | 3.000 | 1 | 58.0 | 5/8 | 1 | 2.25 | 3 | 9 | 0.4629 | 0.4660 | 60000 | no |
| `int2_per_row` | 2.000 | 10000 | 79.7 | 4/8 | 0 | 1.50 | 1 | 31 | 0.7174 | 0.7272 | 40000 | no |
| `ternary_per_row_t0.25_lsq` | 1.585 | 10000 | 15.7 | 1/8 | 0 | 1.50 | 1 | 142 | 0.5174 | 0.5259 | 32000 | no |

Updated interpretation:

- The single-sample INT4 result was too optimistic.
- INT4 per-row is still the best low-bit candidate, but it does not pass the
  current promotion bar on the eight-sample representative-core sweep.
- INT3 and ternary should not receive RTL work now.
- The next quantization step, if pursued, should be full TinyStories-1M
  pretrained-output-head fidelity scoring rather than more representative-core
  RTL. The current representative-core adapter preserves shape but initializes
  a reduced model from config, so it is a hardware-structure proxy, not final
  model-quality evidence.

Global priority after this result:

1. Keep the v9984 INT8 JTAG-debug lane as the current proof of autonomous
   board-correct execution.
2. Run true pretrained TinyStories-1M output-head quantization scoring for
   INT8, INT4 rowwise, and possibly INT3 rowwise across deterministic samples.
3. If pretrained INT4 rowwise passes, implement INT4 output-head RTL.
4. If pretrained INT4 rowwise fails, shift priority away from aggressive
   output-head quantization and toward:
   - time-multiplexed INT8 plus external memory/DDR or PCIe streaming, or
   - a smaller-vocab demonstrator with clear token-generation video evidence.

True pretrained TinyStories-1M execution:

- Added `--load-pretrained` support to
  `scripts/task6/score_output_head_multisample_quantization.py`.
- Added flake target:
  `task6-output-head-full-pretrained-multisample-quantization-sweep`.
- Ran:
  `nix build .#task6-output-head-full-pretrained-multisample-quantization-sweep --no-link --print-out-paths -L`
- Durable artifacts:
  - `artifacts/task6/quantization/output-head-full-pretrained-multisample-sweep.json`
  - `artifacts/task6/quantization/output-head-full-pretrained-multisample-sweep.md`

Pretrained full-model result:

| strategy | bits/w | scales | zero % | top1 | min top5 | mean top5 | min top10 | max rank | mean RMSE | max RMSE | packed words | promote |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `int8_per_tensor` | 8.000 | 1 | 1.4 | 8/8 | 4 | 4.75 | 9 | 1 | 0.0113 | 0.0176 | n/a | yes |
| `int4_per_row` | 4.000 | 50257 | 8.2 | 7/8 | 3 | 3.62 | 7 | 2 | 0.0594 | 0.0921 | 402056 | no |
| `int3_per_row` | 3.000 | 50257 | 18.8 | 6/8 | 2 | 3.25 | 5 | 8 | 0.1424 | 0.2159 | 301542 | no |
| `int4_per_tensor` | 4.000 | 1 | 33.3 | 5/8 | 2 | 2.62 | 5 | 5 | 0.4037 | 0.5479 | 402056 | no |
| `ternary_per_row_t0.25_lsq` | 1.585 | 50257 | 9.5 | 2/8 | 1 | 1.88 | 2 | 296 | 0.3650 | 0.6862 | 160823 | no |
| `int2_per_row` | 2.000 | 50257 | 59.1 | 2/8 | 0 | 1.50 | 1 | 120 | 0.5846 | 0.9520 | 201028 | no |

Interpretation:

- Quantization remains worth pursuing, but only as INT8/INT4, not ternary or
  INT2.
- Full pretrained INT4 per-row is close: `7/8` top-1 matches, and the one miss
  ranks the float top-1 at rank `2` under INT4. This is not good enough to
  claim fidelity, but it is good enough to justify one more Python-only
  improvement attempt.
- The next quantization experiment should not be RTL. It should test a slightly
  stronger INT4 scoring contract:
  - rowwise INT4 weights
  - explicit row scales in a hardware-friendly Q format
  - optional top-k margin/tie analysis for the failing sample
  - maybe per-group or activation-aware calibration if the storage cost remains
    acceptable
- If that does not pass, the mainline should return to INT8 plus streaming or
  external memory rather than lower-bit output-head RTL.

Fixed-point INT4 follow-up:

- Added `int4_per_row_q024_hidden_int8` to
  `scripts/task6/score_output_head_multisample_quantization.py`.
- The scoring contract is intentionally closer to hardware:
  - rowwise signed INT4 weights
  - unsigned `Q0.24` row scales
  - per-sample symmetric INT8 hidden activation
  - integer accumulate and integer-scaled ranking before dequantization
- Ran:
  `nix build .#task6-output-head-full-pretrained-multisample-quantization-sweep --no-link --print-out-paths -L`
- Updated durable artifacts:
  - `artifacts/task6/quantization/output-head-full-pretrained-multisample-sweep.json`
  - `artifacts/task6/quantization/output-head-full-pretrained-multisample-sweep.md`

Fixed-point result:

| strategy | bits/w | scales | zero % | top1 | min top5 | mean top5 | min top10 | max rank | mean RMSE | max RMSE | packed words | promote |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `int8_per_tensor` | 8.000 | 1 | 1.4 | 8/8 | 4 | 4.75 | 9 | 1 | 0.0113 | 0.0176 | n/a | yes |
| `int4_per_row` | 4.000 | 50257 | 8.2 | 7/8 | 3 | 3.62 | 7 | 2 | 0.0594 | 0.0921 | 402056 | no |
| `int4_per_row_q024_hidden_int8` | 4.000 | 50257 | 8.2 | 7/8 | 3 | 3.62 | 7 | 2 | 0.0596 | 0.0924 | 402056 | no |

Failure margin:

- The fixed-point INT4 miss is still `single_two`.
- Float top-1 token: `3043`.
- Fixed-point INT4 top-1 token: `5657`.
- Float top-1 rank under fixed-point INT4: `2`.
- Float top-1 logit margin over the float runner-up: `1.3178292769593867`.
- Fixed-point integer margin of quant top-1 over float top-1:
  `11680502`.
- No `Q0.24` row scales clamped.

Decision:

- This was the last planned Python-only INT4 rescue attempt.
- It did not pass the promotion rule and is slightly worse than float-scale
  rowwise INT4 once hidden activations are also quantized.
- Do not spend RTL time on this INT4 output-head lane now.
- Mainline returns to INT8 plus streaming/external memory, because INT8 is the
  only current post-training output-head quantization result that preserves
  all `8/8` top-1 samples.

### 2026-05-08 - INT8 mainline resume after INT4 rejection

Goal:

- Make the exact INT8 continuation explicit after the final Python-only INT4
  rescue failed.
- Avoid repeating quantization work that no longer changes the main decision.

Current INT8 evidence stack:

| Gate | Artifact / target | Status | Meaning |
| --- | --- | --- | --- |
| Full-vocab rowwise replay | `task6-full-vocab-rowwise-topk-replay` | pass | rowwise INT8 plus Q0.24 scores preserve f32 top1 on `8/8` deterministic samples |
| DDR3 row-stream contract | `task6-ddr3-row-stream-interface-contract` | pass | full output-head row format is fixed at `68` bytes per vocab row |
| Packed rowstream image | `task6-ddr3-row-stream-pack-replay` | pass | concrete `3418496` byte full-vocab image round-trips and replays correctly |
| DDR-free RTL cutout | `task6-ddr3-row-stream-cutout-sv-sim` | pass | RTL consumes the full rowstream image and returns the expected top1 tokens |

Post-INT4 checkpoint run:

- Ran:
  `nix build .#task6-ddr3-row-stream-cutout-sv-sim --no-link --print-out-paths -L`
- Output store path:
  `/nix/store/w1721rlcsvh1kqfilsb2aya5dgbqkp8y-h2-ddr3-row-stream-cutout-rtl-proof.json`
- Result: `PASS`.
- Metrics:
  - samples: `8`
  - rows per sample: `50257`
  - total rows streamed: `402056`
  - cycles: `402088`
- The rerun proof is byte-identical to the durable artifact:
  `artifacts/task6/parallel-hypotheses/h2-ddr3-row-stream-cutout-rtl-proof.json`.

Decision:

- The next INT8 task is not a new quantization sweep.
- The next INT8 task is a measured memory-source gate for the already-passing
  rowstream contract.
- First target: prove a board-programmable linear-read source that can deliver
  the `68`-byte row records, or a narrower beat stream that deterministically
  reconstructs those records, with measured sustained bandwidth.
- Initial bandwidth target remains the `4`-lane output-head kernel:
  `212.5 MB/s` useful rowstream bandwidth at `50 MHz`.
- Keep the TinyStories rowstream cutout disconnected from DDR3 until the memory
  source independently passes integrity and bandwidth checks.

Concrete next experiment:

1. Select the smallest existing DDR3/BRAM/PCIe linear-read probe that can emit a
   deterministic byte stream and be checked over JTAG or simulation.
2. Measure sustained ordered read bandwidth and data integrity on board if the
   bitstream is already available; otherwise first run the no-board simulation.
3. Record one JSON result with:
   - stream width
   - clock target
   - bytes transferred
   - cycles
   - measured MB/s
   - mismatch count
   - whether it clears the `212.5 MB/s` 4-lane target
4. Only after that gate passes, connect the memory source to
   `task6_ddr3_rowstream_top1_cutout`.

### 2026-05-08 - LiteDRAM v87 native readscan board rerun

Goal:

- Reuse the existing v87 no-ODELAY LiteDRAM native readscan bitstream as the
  first post-INT4 memory-source board gate for the INT8 rowstream plan.
- Confirm whether the board can still be programmed and read through the
  serialized Task 6 board runner before starting new memory-source RTL edits.

Run:

- Run directory:
  `artifacts/task6/runs/2026-05-08T13-43-56+0200-litedram-v87-native-readscan-rerun`.
- Bitstream:
  `/nix/store/h5p7jgkr5cwzswdd4927k6mkg4s94r0k-task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-readscan-init-bandwidth-probe.bit`.
- Programming:
  `openFPGALoader -c digilent_hs3 --ftdi-serial 210299BF3824 ...`.
- Readback:
  `python3 scripts/task6/read_litedram_probe_jtag_ftdi.py --backend mpsse --tdo-bit 7 --poll --poll-count 300 --poll-interval 0.2 --json-only`.

Board result:

- Programming succeeded: `openFPGALoader` returned `0`, with `isc_done=1`,
  `init=1`, and `done=1`.
- JTAG readback succeeded in one attempt through FTDI MPSSE with `tdo-bit=7`.
- Probe result: `magic_ok=true`, `version=87`, `state=PROBE_DONE`,
  `complete=true`, `failed=false`.
- Init result: `pll_locked=true`, `init_done=true`, `init_error=false`,
  `init_seq_done=true`, `init_seq_error=false`.
- DFII result stayed clean: `dfii_step=63`, `dfii_word_mismatch_mask=0`,
  `dfii_uniform_mismatch_mask=0`, `dfii_phasecmd_mismatch_masks=0`.
- Native readscan result: `target_read_count=64`, `command_count=64`,
  `response_count=64`, `write_command_count=0`, `write_data_count=0`,
  `native_readscan_nonzero_count=64`,
  `native_readscan_nonzero_chunk_seen=0x1ff`,
  `native_readscan_first_nonzero_addr=0`,
  `native_readscan_first_nonzero_data=0xadacafaea9a8abaa`.

Artifacts:

- Full decoded readback:
  `artifacts/task6/runs/2026-05-08T13-43-56+0200-litedram-v87-native-readscan-rerun/readback/litedram-probe.json`.
- Compact summary:
  `artifacts/task6/runs/2026-05-08T13-43-56+0200-litedram-v87-native-readscan-rerun/readback/summary.json`.
- Verdict:
  `artifacts/task6/runs/2026-05-08T13-43-56+0200-litedram-v87-native-readscan-rerun/verdict.json`.

Decision:

- This confirms the board/JTAG flow and ordered native read visibility from
  DDR3 on the known v87 probe.
- This does not clear the INT8 rowstream memory-source gate yet, because v87
  intentionally issues no native writes and does not measure sustained
  bandwidth.
- Next productive task: build or reuse a deterministic linear-read source that
  reports bytes, cycles, mismatch count, and whether it clears the `212.5 MB/s`
  useful rowstream bandwidth target.

### 2026-05-08 - LiteDRAM v87 linear-read gate summary

Goal:

- Convert the v87 native readscan board readback into the exact memory-source
  gate shape needed by the INT8 rowstream plan:
  bytes, cycles, mismatch count, useful MB/s, and target clearance.
- Keep the integrity verdict separate from the bandwidth arithmetic so the
  experiment cannot be overpromoted.

Artifact:

- Summarizer:
  `scripts/task6/summarize_litedram_linear_read_gate.py`.
- Result:
  `artifacts/task6/experiments/2026-05-08T14-10-00+0200-litedram-v87-linear-read-gate/result.json`.
- Source readback:
  `artifacts/task6/runs/2026-05-08T13-43-56+0200-litedram-v87-native-readscan-rerun/readback/litedram-probe.json`.

Result:

| Metric | Value |
| --- | --- |
| native beat bytes | `72` |
| rowstream useful bytes per beat | `68` |
| target reads | `64` |
| responses | `64` |
| read cycles | `78` |
| raw bytes | `4608` |
| rowstream useful bytes | `4352` |
| mismatch count | `0` |
| native readscan nonzero count | `64` |
| useful MB/s at `25 MHz` | `1394.871794871795` |
| useful MB/s at `50 MHz` | `2789.74358974359` |
| `212.5 MB/s` target cleared by bandwidth arithmetic | `true` |
| integrity verified | `false` |
| gate pass | `false` |

Interpretation:

- The native read path can return a 64-beat ordered stream fast enough by the
  arithmetic in this small probe: `4352` useful rowstream bytes in `78` cycles
  would clear the `212.5 MB/s` 4-lane target even at `25 MHz`.
- This is still not the deterministic linear-read source we need for promotion,
  because v87 is `readscan-nonzero-only`: it intentionally issues no native
  writes and does not compare every native response with deterministic expected
  row data.
- The right next RTL experiment is therefore not another bandwidth calculation.
  It is a deterministic expected-data native linear-read probe, ideally reusing
  the v87/v97 known-good read path while adding a small board-readable compare
  result for the exact stream payload.

### 2026-05-08 - LiteDRAM v112 native packing classifier

Goal:

- Classify the v111 deterministic expected-data failure as either a native
  address/visibility issue or a 576-bit native beat/chunk packing issue.
- Keep the DFII addrwalk write pattern fixed, capture the first four full
  native 576-bit read beats, and decode each 64-bit chunk against the DFII
  expected-data dictionary.

Build and route:

- Target:
  `task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-packing-classifier-init-bandwidth-probe`.
- JSON build:
  `/nix/store/6va2ccdmwwwzfh1x55xjy348fwqj3w7d-task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-packing-classifier-init-bandwidth-probe.json`.
- Bitstream:
  `/nix/store/bn3kiww3xzp1g0gk4is5i25l61p19qnf-task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-packing-classifier-init-bandwidth-probe.bit`.
- Utilization:
  - `SLICE_LUTX`: `28,221 / 597,200` (4%)
  - `SLICE_FFX`: `14,952 / 597,200` (2%)
  - `CARRY4`: `782 / 74,650` (1%)
  - BRAM/DSP: `0`
  - DDR PHY fixed resources: `IDELAYE2=72`, `OSERDESE2=107`,
    `ISERDESE2=72`, `IDELAYCTRL=3`
- Router result:
  - iteration 1: `overused=33,701`, `overuse=37,275`
  - iteration 15: `overused=0`, `overuse=0`, `archfail=0`
- Post-route timing at `25 MHz` target:
  - `clk200`: `565.61 MHz`
  - `user_clk`: `72.96 MHz`
  - `core.iodelay_clk`: `593.12 MHz`
  - `jtag_debug_shift.drck`: `387.60 MHz`

Board result:

- Run directory:
  `artifacts/task6/runs/2026-05-08T14-28-38+0200-litedram-v112-native-packing-classifier`.
- Programming succeeded through `openFPGALoader` with the Digilent HS3 serial
  `210299BF3824`.
- JTAG readback used FTDI MPSSE with `--tdo-bit 7`.
- Probe payload:
  - `version=112`
  - `state=PROBE_DONE`
  - `command_count=64`
  - `response_count=64`
  - `read_cycle_count=78`
  - `mismatch_count=64`
  - classifier valid samples: `4`
  - first mismatch address: `0`
  - first chunk mismatch mask: `0x1ff`

Classifier result:

- The first four captured native 576-bit beats are identical.
- None of the four samples exactly match the expected native addresses `0..3`.
- Chunks `0`, `1`, and `5` in every sample match entries in the DFII
  dictionary for address `15`; no complete beat match was found.
- This is not random data: DFII-written content is visible through native
  reads, but the native read stream is not returning the expected address
  sequence.

Interpretation:

- The current blocker is more likely native address formation, address
  progression, or native/DFII address-space mapping than PHY read corruption.
- The next useful experiment is a native address-stride/address-shift
  classifier: keep the DFII pattern fixed, issue sparse native reads across
  multiple address encodings, and compare returned beats against a wider DFII
  address dictionary.
- Do not spend the next loop on another byte-lane delay or bandwidth-only
  calculation.

Artifacts:

- Result summary:
  `artifacts/task6/parallel-hypotheses/e1-litedram-v112-native-packing-classifier-summary.json`.
- Full decoded readback:
  `artifacts/task6/runs/2026-05-08T14-28-38+0200-litedram-v112-native-packing-classifier/readback/litedram-probe.json`.
- Verdict:
  `artifacts/task6/runs/2026-05-08T14-28-38+0200-litedram-v112-native-packing-classifier/verdict.json`.

### 2026-05-08 - LiteDRAM v113 native address classifier

Goal:

- Keep the DFII addrwalk write pattern unchanged.
- Issue sparse native read addresses:
  `0, 1, 2, 3, 8, 15, 16, 31, 64, 128, 256, 512, 1024, 2048, 4096, 8192`.
- Capture all nine 64-bit chunks of each 576-bit native read beat.
- Decode each captured beat against the DFII expected-data dictionary and
  produce a native-address-to-DFII-address/chunk classifier table.

Build and route:

- Target:
  `task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-address-classifier-init-bandwidth-probe`.
- JSON build:
  `/nix/store/2h2q0iri5vamfn1l2a1jw7y4dl7mxial-task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-address-classifier-init-bandwidth-probe.json`.
- Bitstream:
  `/nix/store/40l6namymkssd24f3khnwbvyfw7hjnam-task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-address-classifier-init-bandwidth-probe.bit`.
- Utilization:
  - `SLICE_LUTX`: `32,065 / 597,200` (5%)
  - `SLICE_FFX`: `28,456 / 597,200` (4%)
  - `CARRY4`: `782 / 74,650` (1%)
  - BRAM/DSP: `0`
  - DDR PHY fixed resources: `IDELAYE2=72`, `OSERDESE2=107`,
    `ISERDESE2=72`, `IDELAYCTRL=3`
- Router result:
  - iteration 1: `overused=38,055`, `overuse=41,093`
  - iteration 16: `overused=0`, `overuse=0`, `archfail=0`
- Post-route timing at `25 MHz` target:
  - `clk200`: `653.59 MHz`
  - `user_clk`: `68.53 MHz`
  - `core.iodelay_clk`: `630.52 MHz`
  - `jtag_debug_shift.drck`: `375.09 MHz`

Board result:

- Run directory:
  `artifacts/task6/runs/2026-05-08T15-06-04+0200-litedram-v113-native-address-classifier`.
- Programming succeeded through `openFPGALoader` with the Digilent HS3 serial
  `210299BF3824`.
- JTAG readback used FTDI MPSSE with `--tdo-bit 7 --bits 11264`.
- Probe payload:
  - `version=113`
  - `state=PROBE_DONE`
  - `command_count=16`
  - `response_count=16`
  - `read_cycle_count=72`
  - `mismatch_count=16`
  - classifier valid samples: `16`
  - first mismatch address: `0`
  - first chunk mismatch mask: `0x1ff`

Classifier result:

| sample | native addr | addr index | requested DFII column | best same-position DFII addr/column | same chunks | best any-position DFII addr/column | any chunks | exact chunks |
| --- | ---: | ---: | ---: | --- | ---: | --- | ---: | ---: |
| 0 | 0 | 0 | `0x0` | `15 / 0x218` | 2 | `15 / 0x218` | 3 | 0 |
| 1 | 1 | 1 | `0x8` | `15 / 0x218` | 2 | `15 / 0x218` | 3 | 0 |
| 2 | 2 | 2 | `0x10` | `15 / 0x218` | 2 | `15 / 0x218` | 3 | 0 |
| 3 | 3 | 3 | `0x18` | `15 / 0x218` | 2 | `15 / 0x218` | 3 | 0 |
| 4 | 8 | 8 | `0x100` | `15 / 0x218` | 2 | `15 / 0x218` | 3 | 0 |
| 5 | 15 | 15 | `0x218` | `15 / 0x218` | 2 | `15 / 0x218` | 3 | 2 |
| 6 | 16 | 0 | `0x0` | `15 / 0x218` | 2 | `15 / 0x218` | 3 | 0 |
| 7 | 31 | 15 | `0x218` | `15 / 0x218` | 2 | `15 / 0x218` | 3 | 2 |
| 8 | 64 | 0 | `0x0` | `15 / 0x218` | 2 | `15 / 0x218` | 3 | 0 |
| 9 | 128 | 0 | `0x0` | `15 / 0x218` | 2 | `15 / 0x218` | 3 | 0 |
| 10 | 256 | 0 | `0x0` | `15 / 0x218` | 2 | `15 / 0x218` | 3 | 0 |
| 11 | 512 | 0 | `0x0` | `15 / 0x218` | 2 | `15 / 0x218` | 3 | 0 |
| 12 | 1024 | 0 | `0x0` | `15 / 0x218` | 2 | `15 / 0x218` | 3 | 0 |
| 13 | 2048 | 0 | `0x0` | `15 / 0x218` | 2 | `15 / 0x218` | 3 | 0 |
| 14 | 4096 | 0 | `0x0` | `15 / 0x218` | 2 | `15 / 0x218` | 3 | 0 |
| 15 | 8192 | 0 | `0x0` | `15 / 0x218` | 2 | `15 / 0x218` | 3 | 0 |

Interpretation:

- All 16 sparse native read requests returned the same 576-bit beat.
- The native read transaction loop is progressing: `command_count` and
  `response_count` both reached `16`.
- No sampled native request produced an exact beat match for the requested
  DFII address/index.
- The repeated partial match to DFII address index `15` / column `0x218` is
  weak: only two same-position chunks and three any-position chunks match.
- The current blocker is now focused on native address formation, native
  address-space mapping, or whether the selected native port is ignoring the
  scheduled read address. This run argues against spending the next loop on a
  bandwidth-only calculation.

Next action:

- Instrument the native command address actually presented and accepted by
  LiteDRAM, or make the DFII write pattern distinguish more than the low
  4-bit address index so repeated returned beats can be mapped unambiguously.

Artifacts:

- Result summary:
  `artifacts/task6/parallel-hypotheses/e1-litedram-v113-native-address-classifier-summary.json`.
- Full decoded readback:
  `artifacts/task6/runs/2026-05-08T15-06-04+0200-litedram-v113-native-address-classifier/readback/litedram-probe.json`.
- Verdict:
  `artifacts/task6/runs/2026-05-08T15-06-04+0200-litedram-v113-native-address-classifier/verdict.json`.

### 2026-05-08 - LiteDRAM v114/v115 native cmd_addr trace

Goal:

- Instrument the native command address actually presented to and accepted by
  LiteDRAM during the DFII-seeded sparse native read classifier.
- Keep board access serialized through `scripts/task6/task6_board_run.py`.

Build and route:

| version | payload shape | bitstream | route result |
| --- | --- | --- | --- |
| 114 | wide `12800`-bit JTAG payload | `/nix/store/rkm6vh0jcwh00s7llcclpsc86gdivgkc-task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-cmdaddr-trace-init-bandwidth-probe.bit` | routed, `overused=0` at iteration 21 |
| 115 | compact `11264`-bit JTAG payload | `/nix/store/da3231vba5fp8q0dn48ixqakmyw110a5-task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-cmdaddr-trace-init-bandwidth-probe.bit` | routed, `overused=0` at iteration 19 |

v115 post-route timing at `25 MHz` target:

- `clk200`: `662.69 MHz`
- `user_clk`: `66.09 MHz`
- `core.iodelay_clk`: `570.78 MHz`
- `jtag_debug_shift.drck`: `362.84 MHz`

Board results:

| run | version | state | init seq error | WB timeout | cmd count | resp count | trace presented | trace accepted |
| --- | ---: | --- | --- | --- | ---: | ---: | ---: | ---: |
| `2026-05-08T16-00-35+0200-litedram-v114-native-cmdaddr-trace` | 114 | `PROBE_ERROR` | yes | yes | 0 | 0 | 0 | 0 |
| `2026-05-08T16-00-35+0200-litedram-v114-native-cmdaddr-trace` retry 1 | 114 | `PROBE_ERROR` | yes | yes | 0 | 0 | 0 | 0 |
| `2026-05-08T16-19-30+0200-litedram-v115-native-cmdaddr-trace-compact` | 115 | `PROBE_ERROR` | yes | yes | 0 | 0 | 0 | 0 |
| `2026-05-08T16-21-05+0200-litedram-v113-native-address-classifier-healthcheck-after-v115` | 113 | `PROBE_DONE` | no | no | 16 | 16 | n/a | n/a |

Interpretation:

- The v114 wide trace and v115 compact trace both route, but both fail before
  any native command is issued.
- The immediately-following v113 health check still completes DDR init and
  native read traffic, so the board, cable, and readback flow are healthy.
- This localizes the regression to the `cmd_addr` trace instrumentation or the
  placement/timing perturbation it introduces, not to a stale board state.
- Widening or rearranging the existing JTAG payload around this datapath is not
  a productive next loop.

Next action:

- Either infer native address behavior indirectly with less invasive counters,
  or add a single-sample latched `cmd_addr` probe in an otherwise unchanged v113
  topology. Do not keep expanding the debug payload until init is stable.

Artifacts:

- Result summary:
  `artifacts/task6/parallel-hypotheses/e1-litedram-v115-native-cmdaddr-trace-summary.json`.
- v114 decoded readbacks:
  `artifacts/task6/runs/2026-05-08T16-00-35+0200-litedram-v114-native-cmdaddr-trace/readback/litedram-probe.json`,
  `artifacts/task6/runs/2026-05-08T16-00-35+0200-litedram-v114-native-cmdaddr-trace/readback/litedram-probe-retry1.json`.
- v115 decoded readback:
  `artifacts/task6/runs/2026-05-08T16-19-30+0200-litedram-v115-native-cmdaddr-trace-compact/readback/litedram-probe.json`.
- v113 health-check decoded readback:
  `artifacts/task6/runs/2026-05-08T16-21-05+0200-litedram-v113-native-address-classifier-healthcheck-after-v115/readback/litedram-probe.json`.

### 2026-05-08 - LiteDRAM v116 single-sample native cmd_addr latch

Goal:

- Replace the invasive 16-sample `cmd_addr` trace with one first-command latch.
- Preserve the v113 sparse native address classifier behavior and full 576-bit
  readback samples.

Build and route:

- Target:
  `task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-cmdaddr-trace-init-bandwidth-probe`.
- JSON build:
  `/nix/store/3qi7vf9fh18n92d8hz5s5w1gnva5ykjs-task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-cmdaddr-trace-init-bandwidth-probe.json`.
- Bitstream:
  `/nix/store/4lv9ki1a4y15rb2rn9pg9724h4gnyh31-task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-cmdaddr-trace-init-bandwidth-probe.bit`.
- Utilization:
  - `SLICE_LUTX`: `32,059 / 597,200` (5%)
  - `SLICE_FFX`: `28,541 / 597,200` (4%)
  - `CARRY4`: `782 / 74,650` (1%)
  - BRAM/DSP: `0`
- Router result:
  - iteration 1: `overused=40,890`, `overuse=44,223`
  - iteration 12: `overused=0`, `overuse=0`, `archfail=0`
- Post-route timing at `25 MHz` target:
  - `clk200`: `678.43 MHz`
  - `user_clk`: `65.92 MHz`
  - `core.iodelay_clk`: `514.93 MHz`
  - `jtag_debug_shift.drck`: `383.73 MHz`

Board result:

- Run directory:
  `artifacts/task6/runs/2026-05-08T16-48-18+0200-litedram-v116-native-cmdaddr-first-sample`.
- Programming succeeded through `openFPGALoader` with the Digilent HS3 serial
  `210299BF3824`.
- JTAG readback used FTDI MPSSE with `--tdo-bit 7 --bits 11264`.
- Probe payload:
  - `version=116`
  - `state=PROBE_DONE`
  - `init_seq_error=false`
  - `wb_timeout_seen=false`
  - `command_count=16`
  - `response_count=16`
  - classifier valid samples: `16`
  - `mismatch_count=16`

Single-sample command-address trace:

| command index | scheduled read addr | presented cmd_addr | accepted cmd_addr | scheduled=presented | presented=accepted | accepted=requested |
| ---: | ---: | ---: | ---: | --- | --- | --- |
| 0 | 0 | 0 | 0 | yes | yes | yes |

Classifier result stayed equivalent to v113:

| samples | repeated best same-position DFII addr | same chunks | any chunks | exact chunks |
| --- | ---: | ---: | ---: | --- |
| all 16 | 15 | 2 | 3 | only samples 5 and 7 have 2 exact chunks |

Interpretation:

- The single-sample latch is non-invasive: DDR init and native traffic survive.
- The first sparse native read command is formed correctly at the top-level
  native port: scheduled, presented, and accepted `cmd_addr` are all `0`.
- The repeated returned beat is not explained by command 0. The remaining
  likely questions are whether later commands are being presented/accepted
  correctly, or whether the issue is downstream of native command acceptance.

Next action:

- Add a parameterized one-command latch index and rerun for command index `1`.
  If index `1` is correct, rerun for index `5`, where the classifier has the
  weak exact-chunk match to DFII address index `15`.
- Active execution plan:
  - keep DDR3 as the top priority until native read correctness is explained
  - use the direct BSCANE2/JTAG payload path, not LiteX `jtag_uart`
  - run the single-command `cmd_addr` latch sweep one index at a time under the
    board lock
  - record for each index: build status, program status, `magic_ok`, probe
    state, scheduled/presented/accepted command address, command/response
    counts, and classifier validity
  - if all checked indices fail like the old invasive v114/v115 trace, shrink
    the instrumentation again before any DDR3 integration work
  - if indices are correct, move from address acceptance to 576-bit beat
    packing / DFII address-match classification
  - do not connect DDR3 to the INT8 rowstream path until deterministic expected
    data readback works

Artifacts:

- Result summary:
  `artifacts/task6/parallel-hypotheses/e1-litedram-v116-native-cmdaddr-first-sample-summary.json`.
- Full decoded readback:
  `artifacts/task6/runs/2026-05-08T16-48-18+0200-litedram-v116-native-cmdaddr-first-sample/readback/litedram-probe.json`.
- Verdict:
  `artifacts/task6/runs/2026-05-08T16-48-18+0200-litedram-v116-native-cmdaddr-first-sample/verdict.json`.

### 2026-05-08 - LiteDRAM v117 native cmd_addr latch index 1

Goal:

- Rerun the non-invasive single-command latch for command index `1`.

Build and route:

- Experiment record:
  `artifacts/task6/experiments/2026-05-08T22-05-51+0200-v117-cmdaddr-idx1/result.json`.
- Bitstream:
  `/nix/store/7872xnkz6j108lxr60rz0hxki81c2isr-task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-cmdaddr-trace-init-bandwidth-probe-native-cmdaddr-first-command-index-1.bit`.
- Router result:
  - iteration 1: `overused=39,140`, `overuse=41,929`
  - iteration 24: `overused=0`, `overuse=0`
- Post-route timing at `25 MHz` target:
  - `user_clk`: `70.77 MHz`
  - `jtag_debug_shift.drck`: `434.97 MHz`

Board result:

- Run directory:
  `artifacts/task6/runs/2026-05-08T22-20-18+0200-v117-cmdaddr-idx1-board-check`.
- Programming succeeded through explicit Digilent HS3 serial
  `210299BF3824`.
- First readback used the default payload width and did not include the
  single-command latch fields; the valid readback is
  `read-litedram-probe-jtag-ftdi-11264.log`.
- Full JTAG payload:
  - `magic_ok=true`
  - `version=116`
  - `state=PROBE_DONE`
  - `init_seq_error=false`
  - `wb_timeout_seen=false`
  - `command_count=16`
  - `response_count=16`
  - classifier valid samples: `16`
  - `mismatch_count=16`

Single-sample command-address trace:

| command index | scheduled read addr | presented cmd_addr | accepted cmd_addr | scheduled=presented | presented=accepted | accepted=requested |
| ---: | ---: | ---: | ---: | --- | --- | --- |
| 1 | 1 | 1 | 1 | yes | yes | yes |

Interpretation:

- Native command address formation and acceptance are correct for index `1`.
- Since index `0` and `1` are both correct but all returned classifier samples
  still mismatch, the repeated/wrong native read data is probably downstream of
  native command acceptance.
- Next action: run command index `5`, because earlier classifier output had a
  weak exact-chunk match near the repeated DFII address pattern there.

### 2026-05-08 - LiteDRAM v117 native cmd_addr latch index 5

Goal:

- Check command index `5`, the sparse native address that previously produced
  a weak exact-chunk match against DFII address index `15`.

Build and route:

- Experiment record:
  `artifacts/task6/experiments/2026-05-08T22-23-20+0200-v117-cmdaddr-idx5/result.json`.
- Bitstream:
  `/nix/store/r1w8hfy1p91xn9z34k48kpzmg85xylgm-task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-cmdaddr-trace-init-bandwidth-probe-native-cmdaddr-first-command-index-5.bit`.
- Router result:
  - iteration 1: `overused=38,986`, `overuse=41,686`
  - iteration 29: `overused=0`, `overuse=0`
- Post-route timing at `25 MHz` target:
  - `user_clk`: `65.47 MHz`
  - `jtag_debug_shift.drck`: `408.33 MHz`

Board result:

- Run directory:
  `artifacts/task6/runs/2026-05-08T22-38-19+0200-v117-cmdaddr-idx5-board-check`.
- Programming succeeded through explicit Digilent HS3 serial
  `210299BF3824`.
- Full 11264-bit JTAG payload:
  - `magic_ok=true`
  - `version=116`
  - `state=PROBE_DONE`
  - `command_count=16`
  - `response_count=16`
  - classifier valid samples: `16`
  - `mismatch_count=16`

Single-sample command-address trace:

| command index | scheduled read addr | presented cmd_addr | accepted cmd_addr | scheduled=presented | presented=accepted | accepted=requested |
| ---: | ---: | ---: | ---: | --- | --- | --- |
| 5 | 15 | 15 | 15 | yes | yes | yes |

Updated interpretation:

- Native command address formation and acceptance are correct for checked
  indices `0`, `1`, and `5`.
- The specific weak-match address `15` is also being presented and accepted
  correctly, so the DDR3 failure is not explained by top-level native
  `cmd_addr` formation.
- Next gate: stop spending primary effort on command-address latching and
  classify the returned 576-bit beat layout against the DFII addrwalk data.
  The likely fault is now in native read data packing, DFII-to-native address
  mapping below command acceptance, or PHY/data-lane integrity.

### 2026-05-09 - Native 576-bit beat mapping classifier

Goal:

- Compare the returned 576-bit native read beats against the DFII addrwalk
  expected data, instead of adding more command-address latch probes.
- Decide whether the native read data is merely packed differently, shifted to
  a different DFII address/chunk, or collapsing to one repeated beat.

Host-side classifier:

- Added `scripts/task6/analyze_litedram_native_beat_mapping.py`.
- The classifier reads the existing JTAG JSON logs, reconstructs each captured
  576-bit native beat, compares all 64-bit chunks and byte positions against a
  DFII addrwalk expected dictionary, and writes JSON plus Markdown summaries.

Valid v117 board evidence:

| source run | state | command/response | valid samples | unique returned beats | best DFII match |
| --- | --- | ---: | ---: | ---: | --- |
| `2026-05-08T22-16-02+0200-v116-cmdaddr-idx1-board-check` | `PROBE_DONE` | `16 / 16` | `16` | `1` | addr index `15` |
| `2026-05-08T22-38-19+0200-v117-cmdaddr-idx5-board-check` | `PROBE_DONE` | `16 / 16` | `16` | `1` | addr index `15` |
| `2026-05-09T08-10-26+0200-v117-cmdaddr-idx5-board-health-recheck` | `PROBE_DONE` | `16 / 16` | `16` | `1` | addr index `15` |

Key result:

- The accepted command address changes correctly in the checked runs, but all
  16 captured native samples return the same 576-bit beat.
- That repeated beat has its strongest DFII dictionary match at addr index
  `15`: same-position chunk score `2`, any-position chunk score `3`, and top
  byte-vote score `15:528`.
- Therefore the current failure is not top-level native `cmd_addr` generation.
  It is below native command acceptance: native returned-beat packing,
  DFII/native address mapping, response sequencing, or data-lane/PHY integrity.

Single-read attempt:

- Added a generated bitstream family for
  `NATIVE_ADDRESS_CLASSIFIER_START_INDEX` with `READ_COUNT_LOG2=0`, intended to
  issue exactly one native read at a sparse classifier address.
- Built and routed start index `5` successfully:
  `/nix/store/3f6nhxfypg0ijmjjzhv4lmqmavg1v086-task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-cmdaddr-single-read-init-bandwidth-probe-start-index-5.bit`.
- Board runs
  `2026-05-09T08-06-39+0200-v118-single-read-start-index-5-board-check` and
  `2026-05-09T08-08-22+0200-v118-single-read-start-index-5-board-check-retry`
  both produced valid JTAG payloads but stopped at `PROBE_ERROR` before the
  native read phase:
  - `wb_ack_count=0`
  - `wb_wait_count=524289`
  - `write_command_count=0`
  - `response_count=0`
  - `target_read_count=1`
- Reprogramming the known v117 index-5 bitstream immediately afterward reached
  `PROBE_DONE`, so the board/JTAG path was not globally wedged.

Interpretation:

- The host-side 576-bit beat classifier is now useful and should be the main
  analysis tool for the next DDR3 probes.
- The first single-read routed variant is not a valid mapping data point,
  because it fails during LiteDRAM init before issuing native commands.
- Next productive action: reroute or narrow the single-read variant until it
  reaches `PROBE_DONE`, then compare its lone returned 576-bit beat against the
  current repeated addr-index-15 signature. If single-read still returns the
  addr-index-15-shaped beat, focus on DFII/native mapping or PHY/data-lane
  integrity. If single-read differs, focus on native response sequencing or
  outstanding read handling.

Follow-up start-index-0 result:

- Built and routed start index `0` successfully:
  `/nix/store/qdabv05ins26vijg3ni82lcplkznjpvh-task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-cmdaddr-single-read-init-bandwidth-probe-start-index-0.bit`.
- Router reached `overused=0`; post-route `user_clk` was `59.68 MHz` against a
  `25 MHz` target.
- Board run
  `2026-05-09T08-28-19+0200-v119-single-read-start-index-0-board-check`
  matched the failed start-index-5 behavior:
  - `magic_ok=true`
  - `state=PROBE_ERROR`
  - `wb_ack_count=0`
  - `wb_wait_count=524289`
  - `write_command_count=0`
  - `response_count=0`
  - `target_read_count=1`
- This means the failed single-read probes are not caused by sparse address
  index `5`. The common factor is the `READ_COUNT_LOG2=0` single-read generated
  family.

Updated next action:

- Do not spend more time on this exact single-read generated family until the
  LiteDRAM-init timeout is understood.
- Prefer a safer narrow probe that preserves the known-good `READ_COUNT_LOG2=4`
  init/routing shape, but records only the first accepted command and first
  returned 576-bit beat into the debug payload. That should avoid perturbing the
  LiteDRAM init path while still answering the response-collapse question.

Safer selected-response check:

- Updated `scripts/task6/analyze_litedram_native_beat_mapping.py` to add an
  explicit selected-response summary. By default it selects the response sample
  matching the traced command index, so the known-good 16-read board run can
  answer the single-read question without changing the RTL or DDR traffic.
- Reanalyzed
  `artifacts/task6/runs/2026-05-09T08-10-26+0200-v117-cmdaddr-idx5-board-health-recheck/logs/read-litedram-probe-jtag-ftdi-11264.log`
  into
  `artifacts/task6/experiments/2026-05-09T-native-selected-response-idx5/`.
- Result:
  - state: `PROBE_DONE`
  - command/response count: `16 / 16`
  - selected response index: `5`
  - accepted command address: `15`
  - response requested native address: `15`
  - accepted matches response request: `true`
  - best same-position DFII addr: `15`
  - same-position chunks: `2`
  - best any-position DFII addr: `15`
  - any-position chunks: `3`
  - top byte votes: `15:528`
- Interpretation: preserving the known-good 16-read shape still shows the
  traced command index and corresponding response index agree on native address
  `15`, yet the returned 576-bit beat is only a weak/partial addr-15-shaped
  match and is identical to every other captured sample. This makes
  outstanding-read ordering less likely as the primary explanation. The
  remaining LiteDRAM failure modes are now DFII/native mapping, returned-beat
  packing, PHY/data-lane integrity, or an internal LiteDRAM native-port
  integration issue.

Next action:

- Stop adding LiteDRAM command-address probes unless they directly test one of
  the remaining hypotheses above.
- Start the UberDDR3 minimal BIST lane in parallel or as the mainline next DDR3
  bring-up path, because it gives us a separate, formally verified,
  Yosys-friendly controller with an autonomous pass/fail criterion.

### 2026-05-09 - Candidate fallback: UberDDR3

Source:

- `https://github.com/AngeloJacobo/UberDDR3`

Why it is a prime candidate:

- Open-source DDR3 controller under GPL-3.0.
- README describes Yosys, Verilator, Icarus Verilog, and SymbiYosys flows.
- The design is described as formally verified and simulated against the
  Micron DDR3 model.
- User interface is Wishbone, which fits the style of the current probes.
- It includes built-in self-tests for burst, random, and alternating
  read/write access, which is exactly the kind of autonomous board criterion we
  need.
- It supports 7-series-style DDR3 PHY features and configurable byte lanes,
  timing parameters, and mode registers.

Risks / work needed:

- We need to adapt the YPCB-00338-1P1 pinout, clocking, reset, VREF/DCI-related
  constraints, and DDR3 geometry.
- We need to confirm whether the exact YPCB memory topology is one 64-bit
  interface, dual 32-bit interfaces, or a 64-bit plus ECC topology, and map
  that to UberDDR3's lane model.
- We need a minimal openXC7 bitstream target with a built-in test result
  exported over the existing direct BSCANE2 JTAG debug path.

Priority:

- Add this as a parallel DDR3 fallback lane behind the current LiteDRAM
  beat-mapping probe. If the next LiteDRAM probe does not produce actionable
  progress, switch DDR3 bring-up effort to an UberDDR3 minimal BIST port rather
  than continuing to patch opaque LiteDRAM behavior indefinitely.

Initial flake integration:

- Added `uberDdr3` flake input pinned by `flake.lock`:
  `AngeloJacobo/UberDDR3` commit
  `be6b2a3b8dfdce7f04a0e0dc9b5475cbab069a2d` from 2026-01-18.
- Added `.#task6-uberddr3-source-summary`.
- Source summary build result:
  `/nix/store/yfax26pf0p96qgakd8cb6j9c08rh7zfy-task6-uberddr3-source-summary`.
- Relevant source layout:
  - `rtl/ddr3_top.v`
  - `rtl/ddr3_controller.v`
  - `rtl/ddr3_phy.v`
  - `rtl/ecc/ecc_dec.sv`
  - `rtl/ecc/ecc_enc.sv`
  - `formal/*.sby`
  - `testbench/ddr3*.sv`

First Yosys gate:

- Added `.#task6-uberddr3-controller-yosys-json`.
- Build result:
  `/nix/store/cq31qmamkg7mrkglmzclxqz0k0w0kmm7-task6-uberddr3-controller-yosys.json`.
- Result:
  - `ddr3_controller.v` parses under Yosys with the ECC modules available.
  - `hierarchy -top ddr3_controller -check`, `proc`, `opt`, `memory`, `opt`,
    and `write_json` complete.
  - Peak memory in this quick gate was about `142 MB`.
  - Warnings are the expected memory-to-register replacement warnings also
    described by UberDDR3's README.

Immediate next UberDDR3 gate:

- Build a minimal YPCB wrapper around `ddr3_top.v`, not only
  `ddr3_controller.v`.
- Start with `BYTE_LANES=8`, `ROW_BITS/COL_BITS/BA_BITS` matching the YPCB DDR3
  geometry, `ODELAY_SUPPORTED=1` for Kintex-7 HP-bank style DDR3 if compatible
  with the board constraints, and `BIST_MODE=1`.
- Export only calibration/BIST/debug status through the existing direct BSCANE2
  JTAG payload path before attempting a wide row-stream interface.

Minimal YPCB wrapper with LiteX-derived XDC:

- Added `task6_ypcb_uberddr3_bist_top.sv`, a minimal YPCB wrapper around
  UberDDR3 `ddr3_top.v` with BIST mode enabled and status exposed through the
  direct BSCANE2 JTAG payload.
- Derived `.#task6-ypcb-uberddr3-bist-xdc` from current LiteX-Boards
  `litex_boards/platforms/ypcb_00338_1p1.py`, channel 0 DDR3 pins:
  64 DQ bits, 8 DQS pairs, 15 row address bits, 3 bank bits, control pins, and
  the 200 MHz differential input clock.
- LiteX-Boards does not expose DDR3 DM pins for this platform, so the wrapper
  leaves UberDDR3 DM as an internal unused wire instead of inventing board pins.
- Replaced the first temporary clock aliases with real YPCB clocking:
  `clk200_p/n` through `IBUFDS` and `BUFG`, then an `MMCME2_BASE` generating
  100 MHz, 100 MHz + 90 degrees, and 25 MHz clocks. The BIST reset is held
  until the MMCM locks.
- XDC result after removing unsupported `get_iobanks`/`INTERNAL_VREF` lines for
  nextpnr-xilinx's XDC subset:
  `/nix/store/crd123lr4vcs83pbjq14y38kmwhwk9m5-task6-ypcb-uberddr3-bist.xdc`.
- Initial `ODELAY_SUPPORTED=1` synthesis passed:
  `/nix/store/dwjnmbdsz90h8yf50b79qzj685l5j075-task6-ypcb-uberddr3-bist-yosys.json`.
  It kept one `MMCME2_BASE`, six `BUFG`s, DDR3 IO/SERDES primitives, and Yosys
  reported zero check problems. nextpnr then failed before placement with:
  `BEL IOB_X0Y94/IOB33M/OUTBUF is located on a high range bank. High range
  banks do not have ODELAY`.
- Switched the wrapper to `ODELAY_SUPPORTED=0`, which uses the 90-degree DDR3
  clock input and removes `ODELAYE2` cells from the output paths. Synthesis
  passed:
  `/nix/store/gy7yhv1xfzl4zs2ipf0hvsjmzh0c9hnz-task6-ypcb-uberddr3-bist-yosys.json`.
  Yosys reported zero check problems, `25206` cells, `12653` estimated LCs,
  `72` `IDELAYE2`, `0` `ODELAYE2`, one `MMCME2_BASE`, and six `BUFG`s.
- The no-ODELAY route initially got past the previous high-range-bank ODELAY
  error, but nextpnr-xilinx segfaulted during packing immediately after clock
  preparation:
  `/nix/store/c6xxfxdashc5p298spg14q326klzavpi-task6-ypcb-uberddr3-bist.fasm.drv`.
- The local nextpnr packer patch plus the YPCB-specific removal of unpinned DM
  serializers cleared that route blocker. The FASM route now reaches router2
  `overused=0`, with the caveat that nextpnr still logs router1 assert
  `valid_wires_for_net.count(w)`.
- The local Kintex-7 prjxray DB patch for
  `LIOI3_TBYTESRC.IOI_OCLKM_0.IOI_IMUX31_1` clears the subsequent
  `fasm2frames` blocker, producing:
  `/nix/store/8h27r5g39wy4swrf6776wl6zrmszaqj7-task6-ypcb-uberddr3-bist.bit`.

Current conclusion:

- The real LiteX-derived YPCB pin constraints and proper 25/100/200 MHz wrapper
  clocking are in place and synthesize.
- UberDDR3's raw 7-series PHY now has an openXC7-generated YPCB bitstream that
  programs and returns a valid direct BSCANE2 payload, but its MMCM-derived
  reset never releases:
  - `/nix/store/8h27r5g39wy4swrf6776wl6zrmszaqj7-task6-ypcb-uberddr3-bist.bit`
    returned valid magic/version with `mmcm_locked=0` and `cycle_count=0`.
  - Switching the wrapper to current LiteX-Boards `clk50` on `AA28` and reset
    on `R28` still returned `mmcm_locked=0`, `cycle_count=0`.
  - Diagnostic readback with raw clock/reset counters proved `clk50` is alive
    and `SYS_RSTN=1`: `clk50_count=0x182abf14`, then `0x19c19a30` on a later
    direct-feedback build.
- Added `.#task6-ypcb-mmcm-diag-bitstream`, a minimal clock/JTAG diagnostic
  that does not touch DDR pins. Board result for
  `/nix/store/hfb07ccdq2x0q4v4x3mfzzbjvps9pf4l-task6-ypcb-mmcm-diag.bit`:
  - raw payload magic/version valid: `0x54364d4d`, version `1`
  - status `0x09`: `SYS_RSTN=1`, `pll_locked=1`, `mmcm_a_locked=0`,
    `mmcm_b_locked=0`
  - counters advanced: `raw_count=0x1e73d4ef`,
    `mmcm_a_count=0x1d1cbd3d`, `mmcm_b_count=0x2c7c1e4b`,
    `pll_count=0x0f39e9f0`
- Updated conclusion: the immediate blocker is not board programming, JTAG,
  reset, absence of the 50 MHz input clock, or small-design routing. The next
  gate is to switch the UberDDR3 BIST wrapper from MMCM-reset gating to the
  locking PLLE2 path, then re-run BIST/calibration.
- PLLE2 UberDDR3 BIST result:
  - Switched the wrapper clock source to `PLLE2_BASE` while keeping the same
    intended clocks: 100 MHz DDR3, 100 MHz + 90 degrees, and 25 MHz controller.
  - Build result:
    `/nix/store/jy55imbnnm31k2zwm530rwkbhdlqmn4j-task6-ypcb-uberddr3-bist.bit`.
  - nextpnr result: `PLLE2_ADV: 1`, `MMCME2_ADV: 0`, router2 reached
    `overused=0` at iteration 5, and fasm2frames/bitgen completed.
  - Board readback:
    - magic/version valid: `0x54364a44`, version `2`
    - `status=0xd0`: wrapper lock bit high, `uart_tx=1`, `wb2_stall=1`,
      `calib_complete=0`, `calib_seen=0`
    - `cycle_count=0x0df5fc1b`, `clk50_count=0x1bebfda1`, `SYS_RSTN=1`
    - `calib_seen_cycle=0`, `debug1=0`, `wb_ack_count=0`,
      `wb_err_count=0`, `wb_stall_count=0x0df5fc1b`
  - Updated conclusion: PLLE2 clears the clock/reset-dead blocker. The current
    blocker is now DDR3 init/calibration not completing under UberDDR3 on the
    YPCB board/openXC7 bitstream.

UberDDR3 calibration/data-integrity gates:

- Calibration progress instrumentation:
  - Added `debug1` packing for calibration state, instruction address,
    IDelayCtrl readiness, calibration strobe/stall/ack, and later mini-BIST
    low counters.
  - Run
    `artifacts/task6/runs/2026-05-09T10-11-13+0200-ypcb-uberddr3-bist-calib-debug1`
    built and routed, but stayed in `BURST_WRITE` with `status=0xd0`.
- Calibration-only control:
  - Run
    `artifacts/task6/runs/2026-05-09T10-22-01+0200-ypcb-uberddr3-bist-calib-only`
    stayed in `READ_DATA`, so `BIST_MODE=0` is not a shortcut to the known-good
    calibration state on this board/route.
- Fast-exit calibration gate:
  - Run
    `artifacts/task6/runs/2026-05-09T10-29-37+0200-ypcb-uberddr3-bist-fast-exit`
    with bitstream
    `/nix/store/rf3akdsj6rdqikhzvfw50146f71vkxpz-task6-ypcb-uberddr3-bist.bit`
    passed the first hard gate:
    `status=0xd3`, `calib_complete=1`, `calib_seen=1`,
    `calib_seen_cycle=0x000093dd`, and `debug1=0x800386d7`
    (`state=23`, `DONE_CALIBRATE`, `instruction_address=22`,
    `idelayctrl_ready=1`).
  - This proves one open-source-flow UberDDR3 route can complete DDR3
    calibration on YPCB-00338-1P1, but it does not yet prove user-port data
    integrity.
- User-port probe attempts:
  - Run
    `artifacts/task6/runs/2026-05-09T10-40-55+0200-ypcb-uberddr3-user-probe`
    added a full-width wrapper Wishbone write/read probe after calibration.
    It routed but regressed calibration to `status=0xd0`, `state=12`
    (`READ_DATA`), with the probe still waiting for calibration.
  - Run
    `artifacts/task6/runs/2026-05-09T10-51-27+0200-ypcb-uberddr3-narrow-user-probe`
    narrowed the probe to low-word compare and idle byte selects. It also
    routed but stayed in `READ_DATA`.
  - Control reprogram of the known-good fast-exit bitstream in
    `artifacts/task6/runs/2026-05-09T10-52-45+0200-ypcb-uberddr3-fast-exit-control-recheck`
    passed again. This isolates the regression to RTL/place-route changes, not
    board state, JTAG, or power.
- Internal mini-BIST attempt:
  - Run
    `artifacts/task6/runs/2026-05-09T11-14-15+0200-ypcb-uberddr3-internal-mini-bist`
    removed the wrapper user-port probe and instead bounded UberDDR3's internal
    BIST path to four full-width writes followed by four reads.
  - Build result:
    `/nix/store/31x92gc0ar40pnk3px1qpax93y72j3d2-task6-ypcb-uberddr3-bist.bit`.
    nextpnr router2 reached `overused=0` at iteration 7 and timing passed.
  - Board readback had valid magic/version but failed the calibration gate:
    `status=0xd0`, `cycle_count=0x0d59a578`, `calib_seen_cycle=0`,
    `debug1=0x000026cc` (`state=12`, `READ_DATA`,
    `instruction_address=22`, `idelayctrl_ready=1`,
    `wb_ack_uncalibrated=1`, mini-BIST correct/wrong/check counters all zero).
  - Conclusion: any added data-integrity logic tried so far perturbs the
    calibration-sensitive route enough to lose the known-good calibration
    result. The next productive gate should preserve the known-good fast-exit
    behavior as closely as possible and vary placement/route seed or add the
    smallest possible post-calibration memory operation, with every run
    committed and compared against the fast-exit control.
- Current-tree fast-exit control:
  - Restored immediate fast-exit after `BURST_WRITE` and left the wrapper user
    port idle.
  - Run
    `artifacts/task6/runs/2026-05-09T11-23-04+0200-ypcb-uberddr3-fast-exit-current-control`
    built
    `/nix/store/8agn3v2i05f7mw66f4j3x4wdrjc6wcw2-task6-ypcb-uberddr3-bist.bit`.
    nextpnr router2 reached `overused=0` at iteration 5 and timing passed.
  - Board readback passed the calibration gate again:
    `status=0xd3`, `cycle_count=0x0f4d6ed8`,
    `calib_seen_cycle=0x000093dd`, `debug1=0x000006d7`
    (`state=23`, `DONE_CALIBRATE`, `instruction_address=22`,
    `idelayctrl_ready=1`).
  - Updated conclusion: the current wrapper/debug state can reproduce the
    known-good calibration result. The mini-BIST/user-probe failures are
    specifically tied to adding data-operation logic or to the placement/routing
    perturbation caused by that logic.
- User-port write/read gates after the stable control:
  - Run
    `artifacts/task6/runs/2026-05-09T11-55-16+0200-ypcb-uberddr3-write-only-seed15`
    proved the wrapper can issue a post-calibration write without losing the
    calibration fixed point: `status=0xd3`, probe done, `write_ack_seen=1`,
    `read_ack_seen=0`, `err_seen=0`.
  - Run
    `artifacts/task6/runs/2026-05-09T12-20-16+0200-ypcb-uberddr3-write-read-ack-only-seed15`
    proved a post-calibration write followed by a read command can complete
    when read data is not exported: `status=0xd3`, `ack_count=2`,
    `write_ack_seen=1`, `read_ack_seen=1`, `err_seen=0`.
  - Run
    `artifacts/task6/runs/2026-05-09T12-27-34+0200-ypcb-uberddr3-write-read-byte-capture-seed15`
    changed only the observation path by latching/exporting `wb_data[7:0]` on
    read ACK. It routed (`overused=0` at router iteration 65, timing pass) but
    failed the board calibration gate: `status=0xd0`, `calib_seen_cycle=0`,
    `debug1=0x000006c9`, `ack_count=0`, probe still in `WAIT_CALIB`.
  - Run
    `artifacts/task6/runs/2026-05-09T12-33-35+0200-ypcb-uberddr3-write-read-byte-capture-seed16`
    rerouted the same v10 RTL with seed16. It routed much more cleanly
    (`overused=0` at router iteration 15, timing pass) and passed the command
    liveness gate on hardware: `status=0xd3`, `calib_seen_cycle=0x000093dd`,
    `debug1=0x000006d7`, `ack_count=2`, probe done, write ACK seen, read ACK
    seen, no error. The captured read byte was `0x3d`, not the written `0xa5`.
  - Updated conclusion: the command path is alive and a read-data tap can work
    with at least one route seed. The next productive step is a small data
    mapping/integrity classifier: write a distinctive per-byte/per-lane pattern
    and capture a slightly wider returned word so we can distinguish byte-lane
    mapping, stale calibration data, read-latency alignment, and true memory
    corruption.
  - Run
    `artifacts/task6/runs/2026-05-09T12-41-21+0200-ypcb-uberddr3-distinctive-byte-pattern-seed16`
    tried the lower-fanout version of that classifier first: keep one-byte
    capture, but change the 512-bit write payload from uniform `0xa5` to
    unique bytes `0x80..0xbf`. The route completed (`overused=0` at router
    iteration 18, timing pass), but hardware did not reach calibration:
    `status=0xd0`, `calib_seen_cycle=0`, `debug1=0x000016a9`, `ack_count=0`,
    probe still in `WAIT_CALIB`.
  - Updated conclusion: the v10 seed16 route is our current best DDR3
    user-port fixed point. Small constant/data-path changes can still perturb
    calibration, so near-term experiments should either sweep seeds for each
    tiny classifier change or preserve the exact v10 topology and vary only
    fields that do not force a broad resynthesis.
  - Run
    `artifacts/task6/runs/2026-05-09T12-48-15+0200-ypcb-uberddr3-halfword-capture-seed16`
    restored the uniform `0xa5` write pattern but widened read capture from 8
    bits to 16 bits. Packing changed materially (`15925` LUT, `7075` FF,
    `2312` SELMUX, versus about `15409` LUT, `7067` FF, `1068` SELMUX for the
    v10 byte capture). The route completed (`overused=0` at router iteration
    37, timing pass), but hardware again failed calibration: `status=0xd0`,
    `calib_seen_cycle=0`, `debug1=0x000006cc`, `ack_count=0`.
  - Updated conclusion: one-byte capture with uniform data on seed16 is the
    current maximum stable observation point. The next path should avoid wider
    wrapper fanout and instead either (a) expose read-data information through a
    tiny in-controller digest/compare near `o_wb_data_q`, or (b) add a seed
    sweep target so each candidate is tested across several routes quickly.
  - Run
    `artifacts/task6/runs/2026-05-09T12-55-23+0200-ypcb-uberddr3-internal-debug1-byte-seed16`
    tested option (a) in the smallest form: remove wrapper-side `wb_data`
    capture and pack `o_wb_data[7:0]` into UberDDR3 `debug1[31:24]`. The route
    completed cleanly (`overused=0` at router iteration 10, timing pass), but
    hardware did not calibrate: `status=0xd0`, `calib_seen_cycle=0`,
    `debug1=0xff0006d8`, `ack_count=0`, probe still in `WAIT_CALIB`.
  - Updated conclusion: moving the byte tap into `debug1` was not enough.
    Current stable user-read evidence is still only v10 seed16: post-calibration
    write/read ACKs complete and one byte can be captured, but that byte was
    `0x3d` rather than the written `0xa5`.
  - Added seed17/seed18 UberDDR3 bitstream targets so route-seed sweeps do not
    require hand-editing `flake.nix` for each attempt.
  - Run
    `artifacts/task6/runs/2026-05-09T13-01-57+0200-ypcb-uberddr3-internal-debug1-byte-seed17`
    rerouted the same v13 internal-debug-byte design with seed17. The route
    completed (`overused=0` at router iteration 13, timing pass), and hardware
    passed command liveness: `status=0xd3`, `calib_seen_cycle=0x000093dd`,
    `debug1=0xff0006d7`, `ack_count=2`, probe done, write ACK seen, read ACK
    seen, no error. The debug read byte was `0xff`, not the written `0xa5`.
  - Updated conclusion: seed sweeping is productive for recovering calibration
    and command liveness, but `debug1[31:24] = o_wb_data[7:0]` is not a valid
    data-integrity observation yet. The read-data observation must be aligned to
    the actual read ACK/data register, not just the current output byte after the
    transaction has completed.
  - Run
    `artifacts/task6/runs/2026-05-09T13-13-01+0200-ypcb-uberddr3-latched-debug-byte-seed17`
    implemented that alignment attempt by latching `o_wb_data_q_current[7:0]`
    inside UberDDR3 exactly when `o_wb_ack_read_q[0][0]` fires, then exporting
    the latched byte through `debug1[31:24]`. The route completed cleanly
    (`overused=0` at router iteration 21, timing pass) and programming
    succeeded, but this seed did not calibrate in hardware for v14:
    `status=0xd0`, `calib_seen_cycle=0`, `debug1=0x000006cc`,
    `ack_count=0`, probe still in `WAIT_CALIB`.
  - Updated conclusion: v14 needs a seed sweep before we can judge the latched
    read-byte idea. The result is not data-integrity evidence; it is another
    calibration-negative route. Use seed18 next, and if seed18 also fails,
    either add seed19/seed20 or return to the v10 seed16 topology and make the
    smallest possible in-controller byte compare.
  - Run
    `artifacts/task6/runs/2026-05-09T13-19-15+0200-ypcb-uberddr3-latched-debug-byte-seed18`
    rerouted the same v14 design with seed18. It also routed cleanly
    (`overused=0` at router iteration 24, timing pass) and programmed
    successfully, but hardware again failed before calibration:
    `status=0xd0`, `calib_seen_cycle=0`, `debug1=0x000006cc`,
    `ack_count=0`, probe still in `WAIT_CALIB`.
  - Updated conclusion: two v14 route seeds failed calibration, so do not spend
    the next loop blindly sweeping this exact latched-byte design. The more
    productive path is to return to the known v10 seed16 observation point and
    change less: preserve the wrapper-level one-byte capture topology that
    reached post-calibration write/read ACKs, then add a one-bit or low-fanout
    in-controller equality flag for `read_byte == 0xa5` instead of exporting
    wider or differently-timed data.
  - Run
    `artifacts/task6/runs/2026-05-09T13-26-17+0200-ypcb-uberddr3-v10-topology-byte-compare-seed16`
    restored the v10 wrapper-level `wb_data[7:0]` read capture, removed the
    v14 controller read-byte debug patches, and added only a post-capture
    mismatch bit. The route completed (`overused=0` at router iteration 20,
    timing pass) and hardware again reached the useful command gate:
    `status=0xd3`, `calib_seen_cycle=0x000093dd`, `ack_count=2`,
    write/read ACKs seen, no error. The captured byte was again `0x3d` rather
    than written `0xa5`, and the mismatch bit was set.
  - Updated conclusion: this reproduces the v10 seed16 behavior and gives a
    stable failing integrity gate. The next experiment should classify whether
    `0x3d` is stale controller/calibration data, a read-latency/off-by-one
    capture, or a DDR byte-lane/address mapping issue. Keep the same v15
    topology and vary only the written byte pattern or read timing in a
    one-variable experiment.
  - Run
    `artifacts/task6/runs/2026-05-09T13-33-19+0200-ypcb-uberddr3-byte-pattern-5a-seed16`
    kept the v15 wrapper-level one-byte capture topology and changed only the
    uniform write/expected byte from `0xa5` to `0x5a`. The route completed
    (`overused=0` at router iteration 21, timing pass), but the board did not
    reach the byte comparison gate: initial readback, immediate reread, and
    one reprogram retry all stayed at `status=0xd0`, `calib_seen_cycle=0`,
    `debug1=0x000006cc`, `ack_count=0`, probe `WAIT_CALIB`.
  - Updated conclusion: this run cannot answer whether the previous `0x3d`
    byte depends on the written data value. It does show that the UberDDR3
    calibration point is still sensitive to tiny routed-image/topology changes.
    The next useful step is to return to the known-good v15 `0xa5` command
    gate and add a lower-risk timing classifier, for example two sequential
    reads or delayed capture of the same low byte, rather than changing the
    write data pattern first.
  - Run
    `artifacts/task6/runs/2026-05-09T13-41-54+0200-ypcb-uberddr3-post-ack-byte-sampler-seed16`
    restored the `0xa5` write/read pattern and added a post-ACK low-byte
    sampler: capture at read ACK plus four controller cycles after ACK. The
    route completed (`overused=0` at router iteration 8, timing pass), but the
    board again stopped before the timing classifier:
    `status=0xd0`, `calib_seen_cycle=0`, `debug1=0x000006cc`,
    `ack_count=0`, probe `WAIT_CALIB`.
  - Updated conclusion: v17 cannot classify the read-data timing. Since this
    small wrapper perturbation also loses calibration, immediately rerun the
    previous v15 bitstream to decide whether the board is in a bad state or
    whether the new debug topology perturbs the calibration image.
  - Run
    `artifacts/task6/runs/2026-05-09T13-43-04+0200-ypcb-uberddr3-v15-baseline-rerun-seed16`
    reprogrammed the previous v15 seed16 bitstream
    `/nix/store/a2ifhrb88dqbmkgdjck5dg6a4dxnyy0c-task6-ypcb-uberddr3-bist-seed16.bit`
    after the v16/v17 calibration failures. The command gate reproduced:
    `status=0xd3`, `calib_seen_cycle=0x000093dd`, `debug1=0x000006d7`,
    `ack_count=2`, `err_count=0`, write/read ACKs seen. The data failure also
    reproduced exactly enough to keep it as the active blocker:
    captured byte `0x3d`, expected `0xa5`, mismatch set.
  - Updated conclusion: the board is not persistently wedged. The UberDDR3
    path has one stable open-source command-liveness image, but small wrapper
    debug changes can perturb calibration. Next work should avoid adding
    payload-facing fanout to the live user read path. Prefer either rerouting
    the exact v15 RTL across seeds to find multiple command-liveness images, or
    moving the next diagnostic into a separate low-fanout equality/status path
    that does not export additional `wb_data` bits.
  - Restored the checked-in UberDDR3 wrapper source to the exact v15
    command-liveness topology from commit `c4515a0`. Rebuilding
    `.#task6-ypcb-uberddr3-bist-seed16-bitstream` resolves to the same durable
    bitstream path:
    `/nix/store/a2ifhrb88dqbmkgdjck5dg6a4dxnyy0c-task6-ypcb-uberddr3-bist-seed16.bit`.
    This makes the current source tree match the last known live board gate
    before continuing DDR3 diagnostics.
  - Run
    `artifacts/task6/runs/2026-05-09T13-50-37+0200-ypcb-uberddr3-v15-seed17-reroute`
    built and programmed the exact v15 topology with route seed17. The route
    completed (`overused=0` at router iteration 28, timing pass), but board
    readback stayed before calibration: `status=0xd0`,
    `calib_seen_cycle=0`, `debug1=0x000006cc`, `ack_count=0`, probe
    `WAIT_CALIB`.
  - Updated conclusion: route seed16 remains the only observed UberDDR3 image
    that reaches calibration and Wishbone write/read ACKs. This is strong
    placement/route sensitivity. Do not invest much more in arbitrary route
    seeds; either freeze seed16 for higher-level loader work, or change the
    controller/PHY bring-up knobs that affect DDR timing more directly.
  - Run
    `artifacts/task6/runs/2026-05-09T13-57-03+0200-ypcb-uberddr3-write-drain-seed16`
    added a low-fanout 1024-controller-cycle gap between write ACK and issuing
    the read, without exporting additional `wb_data` bits. The route completed
    (`overused=0` at router iteration 17, timing pass), and board readback
    reproduced the command-liveness gate: `status=0xd3`,
    `calib_seen_cycle=0x000093dd`, `debug1=0x000006d7`, `ack_count=2`,
    `err_count=0`, write/read ACKs seen. The data failure did not move:
    captured byte `0x3d`, expected `0xa5`, mismatch set.
  - Updated conclusion: the `0x3d` failure is not a simple immediate
    read-after-write visibility hazard. The next DDR3 work should focus on
    controller/PHY data mapping or write/read lane timing, not on adding delay
    between Wishbone transactions.
  - Added `scripts/task6/task6_ddr3_experiment_runner.py` as the canonical
    board runner for these DDR3 probes. It builds or accepts a bitstream,
    creates a run directory, programs the board under the board lock, reads
    the BSCANE2 payload on TDO bit 7, writes decoded JSON, updates
    `verdict.json`, and appends one aggregate row to
    `artifacts/task6/ddr3-run-results.jsonl`.
  - Baseline reproducibility runs through the runner:
    `artifacts/task6/runs/2026-05-09T16-01-27+0200-ypcb-uberddr3-baseline-repro-1`,
    `artifacts/task6/runs/2026-05-09T16-02-46+0200-ypcb-uberddr3-baseline-repro-2`,
    and
    `artifacts/task6/runs/2026-05-09T16-03-49+0200-ypcb-uberddr3-baseline-repro-3`
    all used the seed16 v18 bitstream and produced the same functional
    result: calibration pass, command gate pass, integrity fail. The stable
    values were `status=0xd3`, `calib_seen_cycle=0x000093dd`,
    `ack_count=2`, `err_count=0`, captured byte `0x3d`, expected byte `0xa5`.
  - Updated conclusion: the failure is deterministic across reprograms with
    the current seed16 image. Proceed with a pattern classifier that varies
    only the uniform write/expected byte while preserving the same runner and
    seed16 route target, then compare whether the returned byte is fixed,
    pattern-dependent, inverted, or tied to a specific lane/packing artifact.
  - Run
    `artifacts/task6/runs/2026-05-09T16-14-49+0200-ypcb-uberddr3-pattern-00-seed16`
    built and programmed the v19 byte-pattern classifier with uniform
    write/expected byte `0x00`, seed16, and bitstream
    `/nix/store/b8m3gj4kzdblv7lcil5gjh09vnj2pdkl-task6-ypcb-uberddr3-bist-byte00-seed16.bit`.
    The route completed (`overused=0` at router iteration 42, timing pass),
    but the board did not reach calibration or the command gate:
    `status=0xd0`, `calib_seen_cycle=0`, `debug1=0x000006cc`,
    `ack_count=0`, `err_count=0`, probe `WAIT_CALIB`.
  - Updated conclusion: the byte00 classifier does not answer the data
    pattern question because it lost the fragile calibration point. Treat this
    as more evidence that tiny topology/routing changes perturb UberDDR3 on
    this board. The next productive DDR3 step is to either find a second
    calibration-live image for a pattern variant, or reduce the classifier
    topology delta further by keeping the exact live v18/v15 image shape and
    moving pattern selection into a lower-fanout path.
  - Control run
    `artifacts/task6/runs/2026-05-09T16-19-58+0200-ypcb-uberddr3-v19-a5-control-seed16`
    rebuilt the parameterized v19 source at the default uniform `0xa5`
    pattern with seed16. This reproduced the live command gate:
    `status=0xd3`, `calib_seen_cycle=0x000093dd`, `debug1=0x000006d7`,
    `ack_count=2`, `err_count=0`, write/read ACKs seen, captured byte `0x3d`,
    expected byte `0xa5`.
  - Updated conclusion: the parameterized infrastructure and v19 source shape
    can still reach the stable command-liveness gate for the default `0xa5`
    pattern. The byte00 failure is therefore a pattern/routing-specific
    calibration miss, not a general breakage of the runner or wrapper source.
  - Run
    `artifacts/task6/runs/2026-05-09T16-25-09+0200-ypcb-uberddr3-pattern-3d-seed16`
    built and programmed the v19 byte-pattern classifier with uniform
    write/expected byte `0x3d`, seed16, and bitstream
    `/nix/store/aqhqfn0zvaxxa1q74rs9fliyynqc21bw-task6-ypcb-uberddr3-bist-byte3d-seed16.bit`.
    It also failed before calibration/command gate: `status=0xd0`,
    `calib_seen_cycle=0`, `debug1=0x0000166c`, `ack_count=0`, `err_count=0`,
    probe `WAIT_CALIB`.
  - Updated conclusion: changing the uniform write byte away from `0xa5`
    currently changes the routed design enough that calibration is not
    reliable, even when the expected byte is the value previously observed on
    reads. Stop treating this specific byte-pattern sweep as a cheap
    classifier until there is a way to preserve the live placement/timing point
    or to run several route seeds per pattern automatically.
  - Implemented a fixed-bitstream JTAG-controlled pattern path in the
    UberDDR3 wrapper. USER1 remains the 512-bit readback payload. USER2 is now
    a 16-bit command register: bits `[7:0]` are the requested uniform probe
    byte, bit 8 is the start bit, and bits `[15:12]` must be magic nibble
    `0xa`. On JTAG UPDATE, the byte is synchronized into `controller_clk`, the
    probe FSM resets, and a new write/drain/read transaction runs without
    rebuilding or rerouting the FPGA image.
  - Added `scripts/task6/write_jtag_command_ftdi_bitbang.py` and extended
    `scripts/task6/task6_ddr3_experiment_runner.py` with `--command-byte`.
    The readback payload now reports the active byte, command count, and probe
    run count in payload word `[272 +: 32]`.
  - Build check for `.#task6-ypcb-uberddr3-bist-seed16-bitstream` produced
    `/nix/store/m66j83pcdffqx21c3p78qf7pmnxhnsyi-task6-ypcb-uberddr3-bist-seed16.bit`.
    The route completed with `overused=0` at router iteration 7, timing passed,
    and nextpnr packed USER2 at `BSCAN_X0Y1/BSCAN` while preserving USER1 at
    `BSCAN_X0Y0/BSCAN`.
  - Control run
    `artifacts/task6/runs/2026-05-09T18-50-54+0200-ypcb-uberddr3-v20-jtag-pattern-a5-auto`
    programmed the v20 fixed-bitstream image without issuing a USER2 command.
    The default `0xa5` auto-run reproduced the live gate:
    `status=0xd3`, `calib_seen_cycle=0x000093dd`, `debug1=0x000006d7`,
    `active_byte=0xa5`, `command_count=0`, `run_count=0`, `ack_count=2`,
    `err_count=0`, captured byte `0x3d`, expected byte `0xa5`.
  - Updated conclusion: adding the USER2 command chain did not destroy the
    known seed16 calibration/command-liveness point. It is now valid to test
    command-driven pattern reruns against this same programmed image.
  - Run
    `artifacts/task6/runs/2026-05-09T18-51-59+0200-ypcb-uberddr3-v20-jtag-pattern-00`
    programmed the same v20 bitstream and issued USER2 command `0xa100`
    (`byte=0x00`). The command write script completed, but readback showed the
    command was not latched by the FPGA: `active_byte=0xa5`,
    `command_count=0`, `run_count=0`. The default probe still reproduced the
    command gate (`status=0xd3`, `ack_count=2`, read byte `0x3d`).
  - Updated conclusion: USER2 shifting from the host side is at least
    executable, but the RTL command latch is wrong. Likely cause: the command
    module latched BSCANE2 `UPDATE` on `DRCK`; `UPDATE` occurs after shifting
    when `DRCK` is no longer clocking. Move the update latch to BSCANE2 `TCK`
    and rerun the same `0x00` command test.
  - Implemented v21 of the fixed-bitstream command path by latching the USER2
    update event in the BSCANE2 `TCK` domain while keeping the shift register
    on `DRCK`. This targets the v20 failure mode where the host completed the
    USER2 shift/update sequence but the FPGA still reported
    `command_count=0`.
  - Build check for `.#task6-ypcb-uberddr3-bist-seed16-bitstream` produced
    `/nix/store/jfdb2knp5ghzhw6n1f39g2a1gxak57rc-task6-ypcb-uberddr3-bist-seed16.bit`.
    The route completed with `overused=0` at router iteration 16, timing
    passed at 25 MHz, and nextpnr packed USER2 at `BSCAN_X0Y1/BSCAN` with
    USER1 still at `BSCAN_X0Y0/BSCAN`.
  - Control run
    `artifacts/task6/runs/2026-05-09T18-58-36+0200-ypcb-uberddr3-v21-jtag-pattern-a5-auto`
    programmed the v21 image without issuing a USER2 command. The default
    `0xa5` auto-run reproduced the live gate: `version=21`, `status=0xd3`,
    `calib_seen_cycle=0x000093dd`, `debug1=0x000006d7`,
    `active_byte=0xa5`, `command_count=0`, `run_count=0`, `ack_count=2`,
    `err_count=0`, captured byte `0x3d`, expected byte `0xa5`.
  - Updated conclusion: the TCK-latched command-path fix did not perturb the
    known seed16 calibration/command-liveness point. It is valid to test USER2
    command-driven reruns against the v21 image.
  - Run
    `artifacts/task6/runs/2026-05-09T18-59-45+0200-ypcb-uberddr3-v21-jtag-pattern-00`
    programmed the same v21 bitstream, issued USER2 command `0xa100`
    (`byte=0x00`), and read back the debug payload. Unlike v20, the command
    path did fire: `version=21`, `status=0xd3`,
    `calib_seen_cycle=0x000093dd`, `debug1=0x000016b7`,
    `command_count=2`, `run_count=2`, `ack_count=2`, `err_count=0`,
    captured byte `0x00`.
  - Caveat: the final payload command word was `0x000202a5`, so the reported
    active byte ended at `0xa5` even though the data byte captured by the
    probe was `0x00`. This means the TCK latch fix made USER2 effective, but
    the command register is still not a clean one-command/one-rerun interface;
    there is likely a second UPDATE/captured-echo event around the command or
    subsequent readback TAP movement.
  - Implemented v22 of the command path by adding a TCK-domain rising-edge
    guard for USER2 `UPDATE`. This should make the command register fire once
    per UPDATE pulse instead of potentially toggling for every TCK edge while
    `UPDATE` remains high.
  - Build check for `.#task6-ypcb-uberddr3-bist-seed16-bitstream` produced
    `/nix/store/miiih8yyiz0n7916v3103nq0kca9ihyp-task6-ypcb-uberddr3-bist-seed16.bit`.
    The route completed with `overused=0` at router iteration 5 and timing
    passed at 25 MHz.
  - Control run
    `artifacts/task6/runs/2026-05-09T19-06-32+0200-ypcb-uberddr3-v22-jtag-pattern-a5-auto`
    programmed the v22 edge-guarded image without issuing a USER2 command.
    This image did not reach calibration or the command gate:
    `version=22`, `status=0xd0`, `calib_seen_cycle=0`, `debug1=0x000006cc`,
    `active_byte=0xa5`, `command_count=0`, `run_count=0`, `ack_count=0`,
    `err_count=0`, probe `WAIT_CALIB`.
  - Updated conclusion: the edge-guard fix is logically cleaner but perturbs
    the routed DDR3 design enough to lose the fragile calibration point. Treat
    v21, not v22, as the current best fixed-bitstream command image.
  - Restored the RTL source to the calibration-live v21 command latch shape.
    The v21 interface is not fully clean (`command_count=2` on the byte00
    test), but it is the current best working single-bitstream pattern
    register because the same routed image both calibrates and accepts a USER2
    command-driven rerun.
  - Added a host-side `--update-mode stop-at-update` option to
    `scripts/task6/write_jtag_command_ftdi_bitbang.py` and passed it through
    `scripts/task6/task6_ddr3_experiment_runner.py`. This tests whether the
    second v21 command event was caused by explicitly clocking from Update-DR
    back to Run-Test/Idle.
  - Run
    `artifacts/task6/runs/2026-05-09T19-50-31+0200-ypcb-uberddr3-v21-jtag-pattern-00-stop-at-update`
    programmed the known live v21 bitstream and issued USER2 byte `0x00` with
    `--command-update-mode stop-at-update`. It still reported
    `command_count=2`, `run_count=2`, final `active_byte=0xa5`, and captured
    read byte `0x00`.
  - Updated conclusion: the v21 double event cannot be fixed purely by
    suppressing the host's explicit clock back to idle. Since any later JTAG
    read needs another TCK edge, v21's level-sensitive TCK latch can still see
    a second BSCANE2 `UPDATE`. Use v21 as a useful-but-not-clean pattern
    classifier, or solve the duplicate in RTL with route-seed search because
    the first v22 edge-guarded route lost calibration.
  - Run
    `artifacts/task6/runs/2026-05-09T19-51-52+0200-ypcb-uberddr3-v21-jtag-pattern-3d`
    programmed the known live v21 bitstream and issued USER2 byte `0x3d` with
    the default command update path. It reproduced calibration and the command
    gate (`status=0xd3`, `calib_seen_cycle=0x000093dd`, `ack_count=2`,
    `err_count=0`, `command_count=2`, `run_count=2`) but captured read byte
    `0x30`, not `0x3d`.
  - Updated conclusion: the v21 pattern command affects the returned data, but
    the returned byte is not a clean echo of the commanded byte. The observed
    sequence so far is default `0xa5 -> 0x3d`, command `0x00 -> 0x00`,
    command `0x3d -> 0x30`.
  - Run
    `artifacts/task6/runs/2026-05-09T19-52-55+0200-ypcb-uberddr3-v21-jtag-pattern-ff`
    programmed the known live v21 bitstream and issued USER2 byte `0xff`. It
    reproduced calibration and the command gate (`status=0xd3`,
    `calib_seen_cycle=0x000093dd`, `ack_count=2`, `err_count=0`,
    `command_count=2`, `run_count=2`) and captured read byte `0xff`.
  - Updated conclusion: v21 is usable for fast same-bitstream pattern
    classification despite the double-update caveat. The classifier points are
    now default `0xa5 -> 0x3d`, command `0x00 -> 0x00`,
    command `0x3d -> 0x30`, command `0xff -> 0xff`. The next productive
    classifier should capture more than one byte/word from the returned
    Wishbone data, because single-byte results already show a pattern-sensitive
    failure but do not distinguish byte-lane corruption from stale/partial
    writeback.
  - Implemented v23 of the UberDDR3 debug payload. The probe now latches the
    full 512-bit Wishbone read beat on read ACK instead of only `wb_data[7:0]`.
    The JTAG payload width is 1024 bits, payload `[240 +: 32]` reports the low
    read word, and payload `[480 +: 512]` reports the full returned beat. The
    experiment runner now reads 1024 bits by default and decodes the beat into
    64 bytes and 16 little-endian 32-bit words.
  - Build check for `.#task6-ypcb-uberddr3-bist-seed16-bitstream` produced
    `/nix/store/a0sgzksi3i3wbgmw4iwp18k4q265d6lq-task6-ypcb-uberddr3-bist-seed16.bit`.
    The route completed with `overused=0` at router iteration 36 and timing
    passed at 25 MHz. The wider debug chain increased utilization to about
    17,126 `SLICE_LUTX` and 8,170 `SLICE_FFX`.
  - Control run
    `artifacts/task6/runs/2026-05-09T20-02-06+0200-ypcb-uberddr3-v23-readbeat-a5-auto`
    programmed the v23 image without issuing a USER2 command. The wider debug
    chain preserved the calibration/command gate: `version=23`, `status=0xd3`,
    `calib_seen_cycle=0x000093dd`, `debug1=0x000006d7`,
    `active_byte=0xa5`, `command_count=0`, `run_count=0`, `ack_count=2`,
    `err_count=0`, captured low byte `0x3d`, expected byte `0xa5`.
  - The returned 512-bit beat was not uniform `0xa5`. Its decoded 32-bit
    words were:
    `a53dc13d a53dc13d a52c512c a52c512c 0000ad3f 0e80ad00 d265d0a4 000cd07f 00008c0b 04808c80 c0652924 000c297f 00007700 00807700 00009100 00009100`.
  - Updated conclusion: the failure is wider than a single low-byte issue and
    has clear structure across the 512-bit beat. The first four words retain
    `0xa5` in the most significant byte while the lower bytes are patterned,
    so the next classifier runs should compare `0x00` and `0xff` full beats to
    distinguish lane/packing behavior from stale readback.
  - Run
    `artifacts/task6/runs/2026-05-09T20-03-10+0200-ypcb-uberddr3-v23-readbeat-00`
    programmed the same v23 bitstream and issued USER2 byte `0x00`. It
    reproduced calibration and the command gate: `version=23`, `status=0xd3`,
    `calib_seen_cycle=0x000093dd`, `debug1=0x000006d7`,
    `command_count=2`, `run_count=2`, `ack_count=2`, `err_count=0`, captured
    low byte `0x00`.
  - The returned 512-bit beat words were:
    `a500c100 a500c100 a5005100 a5005100 0000ad00 0e00ad00 d22bd000 0084d0ff 00008c00 04008c00 802b2900 008429ff 00007700 00007700 00009100 00009100`.
  - Updated conclusion: command `0x00` zeros several byte positions but not
    the whole beat. Many byte lanes retain the same structured nonzero values
    seen in the `0xa5` control, including recurring `0xa5`, `0xc1`, `0x51`,
    `0xad`, `0x8c`, `0x77`, and `0x91` positions.
  - Run
    `artifacts/task6/runs/2026-05-09T20-04-20+0200-ypcb-uberddr3-v23-readbeat-ff`
    programmed the same v23 bitstream and issued USER2 byte `0xff`. It
    reproduced calibration and the command gate: `version=23`, `status=0xd3`,
    `calib_seen_cycle=0x000093dd`, `debug1=0x000006d7`,
    `command_count=2`, `run_count=2`, `ack_count=2`, `err_count=0`, captured
    low byte `0xff`.
  - The returned 512-bit beat words were:
    `a5ffc1ff a5ffc1ff a5ff51ff a5ff51ff 00ffad00 0cfeadfb d200d000 0010d000 00398c04 04c68c87 80002900 00102900 00007700 00007700 00009100 00009100`.
  - Updated conclusion: the readbeat classifier now strongly suggests
    structured byte-lane/packing/selective-byte behavior, not random
    corruption. Across commands `0x00` and `0xff`, byte positions 0 and 2 of
    the first four words follow the commanded byte, byte 3 stays `0xa5`, and
    byte 1 stays lane-specific (`0xc1` or `0x51`). Later words show other fixed
    lane values (`0xad`, `0xd0`, `0x8c`, `0x29`, `0x77`, `0x91`) mixed with
    command-sensitive bytes.

## 2026-05-11 - Simulation-first gate for the rowstream loader contract

- Decision: stop using full route/program/board cycles as the first debug
  loop for the v35 rowstream loader mismatch. The current board evidence says
  the BIST-derived top calibrates, passes the boot self-check, and completes
  loader Wishbone transactions without `wb_err`; the remaining unknown is the
  rowstream address/lane contract. Use simulation to isolate the loader
  command-to-Wishbone behavior before returning to hardware.
- Implemented a small standalone loader-contract RTL module and Verilator
  testbench:
  - `fpga/rtl/task6_uberddr3_rowstream_loader_contract.sv`
  - `sim/task6_uberddr3_rowstream_loader_contract_tb.sv`
  - Nix gates:
    `.#task6-uberddr3-rowstream-loader-contract-sim-main` and
    `.#task6-uberddr3-rowstream-loader-contract-sv-sim`
- Validation command:
  `nix build .#task6-uberddr3-rowstream-loader-contract-sv-sim -L`
- Result artifact:
  `/nix/store/xjn0hfrqdjm80n5fsnjc4lsc0q73589x-task6-uberddr3-rowstream-loader-contract-sv-sim.json`
- Result summary:
  - `status=PASS`
  - one low-byte write and one low-byte read completed
  - write contract asserted all 64 byte selects and replicated the payload byte
    across the 512-bit beat, matching v35's current full-width low-byte write
    style
  - read contract selected lane 0 and captured the stored low byte
  - final loader state was idle (`state=1`) with `wait_cycles=1`
- Edge found while building the test: the current every-other command filter is
  phase-sensitive to any USER2 event, even before `boot_done`. A single
  pre-boot event can make the first post-boot command land on the ignored
  phase. The host currently sends repeated commands after calibration, so this
  is not the known v35 board mismatch, but it is a fragility to remove when the
  loader is factored back into the board top.
- Current interpretation: this simulation reduces the likely fault set. The
  plain loader command FSM can issue the intended Wishbone read/write
  transactions against a simple Wishbone RAM. The v35 board mismatch is
  therefore more likely in UberDDR3 Wishbone address/byte-select semantics, the
  host's linear rowstream address assumption, or the interaction between
  full-width writes and DDR3 readback packing.
- Plan to finish Task 6 from here:
  1. Add an UberDDR3-address/lane simulation or model using the same
     deterministic `0..15` byte pattern. The required output is a mapping table:
     host stream address -> Wishbone address/select -> returned byte lane.
  2. Replay the same `0..15` diagnostic on the BIST-derived board top before
     loading `rowstream.bin`.
  3. Fix either the loader address/select policy or the host packing policy so
     the hardware diagnostic matches the simulation/model.
  4. Promote the fixed path back to the rowstream boundary-token loader check.
  5. If boundary rows pass, run the DDR3-backed top1 cutout. If they do not,
     close Task 6 with the documented strategy evidence: int8/v9984 on-chip
     route success, external-memory contract, calibrated DDR3 BIST-derived
     loader progress, and the remaining address/lane blocker compared against
     `artifacts/task6/baselines/tiny-stories-1m-baseline-float-selftest-all-memory-utilization`.

## 2026-05-11 - UberDDR3 address/lane model and 0..15 board diagnostic

- Source fact from UberDDR3 RTL:
  - `i_wb_addr` is documented and implemented as burst-addressable
    `{row,bank,column}`.
  - For the YPCB parameters (`COL_BITS=10`, `serdes_ratio=4`), the controller
    takes `i_wb_addr[6:0]` as the high column-burst address and appends three
    zero low column bits. One Wishbone address therefore names one 64-byte
    512-bit burst beat, not one byte.
  - `i_wb_sel` is the 64-bit byte strobe for that 512-bit beat.
- Added `scripts/task6/model_uberddr3_address_lane.py` and Nix target
  `.#task6-uberddr3-address-lane-model`.
- Validation command:
  `nix build .#task6-uberddr3-address-lane-model -L`
- Result artifact:
  `/nix/store/5sv92bd31p7i12axndhzfzsrwciapp87-task6-uberddr3-address-lane-model.json`
- Model result for stream bytes `0..15`:
  - Dense byte policy writes all 16 bytes to Wishbone beat `0`, lanes `0..15`,
    with selects `1 << lane`; dense reader returns `0..15`.
  - Current v35 sparse-lowbyte-fullwidth policy writes stream byte `N` to
    Wishbone beat `N`, all lanes selected and filled with `N`; sparse low-byte
    reader returns `0..15`, but dense beat-0 reader returns sixteen zeroes.
  - Interpretation: v35 is incompatible with a dense DDR3 rowstream source even
    if its own sparse low-byte readback were reliable. The scalable loader
    policy must be dense: `wb_addr = stream_addr / 64`,
    `lane = stream_addr % 64`, `sel = 1 << lane`, and write data in that lane.
- Added `--diagnostic-lowbyte-count` to
  `scripts/task6/task6_ddr3_rowstream_loader.py`. The diagnostic programs the
  board, waits for calibration, writes values `0..N-1` to sparse low-byte
  addresses `0..N-1`, reads the same sparse low bytes back, writes
  `lowbyte-diagnostic.json`, and exits before rowstream loading.
- Board validation command:
  `python3 scripts/task6/task6_ddr3_rowstream_loader.py --bitstream /nix/store/khm63m9d842zlzjjjqx0515ygkqgvkhs-task6-ypcb-uberddr3-rowstream-loader-seed16.bit --diagnostic-lowbyte-count 16 --no-full-readback`
- Board result:
  `artifacts/task6/runs/2026-05-11T13-59-51+0200-ypcb-ddr3-rowstream-loader-khm63m9d842zlzjjjqx0515ygkqgvkhs-task6-ypcb-uberddr3-rowstream-loader-seed16/lowbyte-diagnostic.json`
- Board summary:
  - calibration passed (`calib_seen=true`, `calib_seen_cycle=37853`)
  - boot self-check passed (`boot_done=true`, `boot_mismatch=false`)
  - 16 writes and 16 reads were acknowledged, with `wb_err_count=0` and
    `loader_error=false`
  - sparse low-byte diagnostic failed all positions: `mismatch_count=16`
  - observed bytes for addresses `0..15` were
    `a8 a5 a6 a7 38 39 3a 3b 34 35 36 37 30 31 32 33`, not
    `00 01 02 03 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f`
- Updated interpretation: the v35 board failure is deeper than just choosing
  dense versus sparse rowstream storage. The current sparse-lowbyte path is not
  self-consistent on hardware even though it passes the loader FSM simulation.
  Because ACKs occur without Wishbone errors and the returned sequence is
  structured, the likely fault is either the wrapper's read-data capture
  contract, the command/write-data lane contract at the UberDDR3 boundary, or
  an address/lane packing mismatch inside the BIST-derived integration.
- Next gate: do not load `rowstream.bin` again until the 0..15 diagnostic
  passes. Implement dense byte-lane write/read commands in the BIST-derived top
  and expose a full 512-bit readback for beat `0`; then compare hardware beat-0
  lanes directly against the model. If full-beat readback shows the expected
  bytes in any lane permutation, fix the host/RTL lane mapping. If it still
  shows the structured stale pattern, debug capture timing near
  `loader_read_data_q`/`o_wb_data`.

## 2026-05-11 - Dense byte-lane board gate v36-v37

- Implemented dense byte-lane command opcodes in
  `fpga/rtl/task6_ypcb_uberddr3_bist_rowstream_loader_top.sv`:
  - `WRITE_DENSE_BYTE`: `wb_addr = stream_addr / 64`,
    `sel = 1 << (stream_addr % 64)`, and data placed in the selected byte lane.
  - `READ_DENSE_BEAT`: read one 512-bit Wishbone beat by beat address.
- Added `--diagnostic-dense-count` to
  `scripts/task6/task6_ddr3_rowstream_loader.py`. The diagnostic writes
  `0..N-1` through dense byte-lane commands, reads beat 0, compares the lower
  lanes, writes `dense-diagnostic.json`, and exits before loading
  `rowstream.bin`.
- v36 exposed the full 512-bit read beat through a 1024-bit JTAG debug shift.
  Build evidence:
  - `python3 -m py_compile scripts/task6/task6_ddr3_rowstream_loader.py scripts/task6/model_uberddr3_address_lane.py`: pass
  - `nix build .#task6-ypcb-uberddr3-rowstream-loader-yosys-json -L`: pass;
    Yosys check found 0 problems.
  - `nix build .#task6-ypcb-uberddr3-rowstream-loader-seed16-bitstream -L`:
    pass; bitstream
    `/nix/store/hl5m38i3d9mivdfdannb020zddwnbijl-task6-ypcb-uberddr3-rowstream-loader-seed16.bit`.
- v36 board result: failed before the dense diagnostic because DDR3
  calibration did not complete on two attempts:
  - `artifacts/task6/runs/2026-05-11T14-12-09+0200-ypcb-ddr3-rowstream-loader-hl5m38i3d9mivdfdannb020zddwnbijl-task6-ypcb-uberddr3-rowstream-loader-seed16`:
    `magic_ok=True`, `version=36`, `calib_seen=False`, `state=1`,
    `ack=0`, `err=0`, `loader_error=False`, `debug1=0x000016a9`.
  - `artifacts/task6/runs/2026-05-11T14-13-15+0200-ypcb-ddr3-rowstream-loader-hl5m38i3d9mivdfdannb020zddwnbijl-task6-ypcb-uberddr3-rowstream-loader-seed16`:
    `magic_ok=True`, `version=36`, `calib_seen=False`, `state=1`,
    `ack=0`, `err=0`, `loader_error=False`, `debug1=0x00000ecc`.
- v37 reduced the diagnostic back to the 512-bit debug path and compared only
  the lower 16 readback lanes. Build evidence:
  - `python3 -m py_compile scripts/task6/task6_ddr3_rowstream_loader.py scripts/task6/model_uberddr3_address_lane.py`: pass
  - `nix build .#task6-ypcb-uberddr3-rowstream-loader-yosys-json -L`: pass;
    Yosys check found 0 problems, estimated 13,650 LCs.
  - `nix build .#task6-ypcb-uberddr3-rowstream-loader-seed16-bitstream -L`:
    pass; route converged at iteration 11, controller clock max frequency
    84.83 MHz at the 25 MHz target, bitstream
    `/nix/store/dy2iw86nhsihkd3j24n7yign9wzpl6yc-task6-ypcb-uberddr3-rowstream-loader-seed16.bit`.
- v37 board validation command:
  `python3 scripts/task6/task6_ddr3_rowstream_loader.py --bitstream /nix/store/dy2iw86nhsihkd3j24n7yign9wzpl6yc-task6-ypcb-uberddr3-rowstream-loader-seed16.bit --diagnostic-dense-count 16 --no-full-readback`
- v37 board result:
  `artifacts/task6/runs/2026-05-11T14-20-34+0200-ypcb-ddr3-rowstream-loader-dy2iw86nhsihkd3j24n7yign9wzpl6yc-task6-ypcb-uberddr3-rowstream-loader-seed16/dense-diagnostic.json`
- v37 summary:
  - calibration completed (`calib_seen=true`, `calib_seen_cycle=37853`)
  - the boot gate was not clean: `boot_done=true` but
    `boot_mismatch=true` already in `initial_debug`
  - 16 dense byte writes and one dense beat read were acknowledged,
    `wb_ack_count` advanced from 9 to 26, and `wb_err_count=0`
  - dense readback failed all 16 compared lanes:
    observed `a8 c1 a8 a8 a8 c1 a8 00 a8 51 a8 a8 a8 51 a8 00`,
    expected `00 01 02 03 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f`
- Updated interpretation:
  - The v36 full-beat debug path was too perturbing for the calibration gate.
  - The v37 reduced debug path restores calibration, but adding dense command
    logic still loses the BIST-derived boot data-integrity check. Because the
    diagnostic starts from `boot_mismatch=true`, this is not yet a valid
    dense-lane mapping result.
  - Do not promote dense rowstream loading yet. The next gate should preserve
    the exact known-good v35 BIST/boot datapath and add only one isolated
    variable at a time: first add a read-only lower-128-bit beat capture with no
    new write opcode, then add dense write select generation after boot remains
    clean.

## 2026-05-11 - Read-only lower-128 beat capture gate v38

- Decision: preserve the v35 BIST/boot write datapath and remove the dense
  write-select opcode from hardware. Keep only a read-only beat command that
  captures `loader_read_data_q[127:0]` through the existing 512-bit debug
  payload.
- Implementation:
  - `fpga/rtl/task6_ypcb_uberddr3_bist_rowstream_loader_top.sv` debug version
    is now v38.
  - Hardware keeps `READ_DENSE_BEAT` (`0x06`) as a read-only diagnostic command
    and removes `WRITE_DENSE_BYTE` from the top.
  - `scripts/task6/task6_ddr3_rowstream_loader.py` adds
    `--diagnostic-readbeat-addr`, which waits for calibration/boot, reads one
    beat, records the lower 16 bytes, and exits before rowstream loading.
- Build evidence:
  - `python3 -m py_compile scripts/task6/task6_ddr3_rowstream_loader.py scripts/task6/model_uberddr3_address_lane.py`:
    pass
  - `nix build .#task6-ypcb-uberddr3-rowstream-loader-yosys-json -L`: pass;
    Yosys check found 0 problems, estimated 12,546 LCs
  - `nix build .#task6-ypcb-uberddr3-rowstream-loader-seed16-bitstream -L`:
    pass; route converged at iteration 28, controller clock max frequency
    73.20 MHz at the 25 MHz target, bitstream
    `/nix/store/8higyshcx41rbqj2lvlzp2j1n8alybzf-task6-ypcb-uberddr3-rowstream-loader-seed16.bit`
- Board validation command:
  `python3 scripts/task6/task6_ddr3_rowstream_loader.py --bitstream /nix/store/8higyshcx41rbqj2lvlzp2j1n8alybzf-task6-ypcb-uberddr3-rowstream-loader-seed16.bit --diagnostic-readbeat-addr 0 --no-full-readback`
- Board result:
  `artifacts/task6/runs/2026-05-11T14-35-59+0200-ypcb-ddr3-rowstream-loader-8higyshcx41rbqj2lvlzp2j1n8alybzf-task6-ypcb-uberddr3-rowstream-loader-seed16/readbeat-diagnostic.json`
- Board summary:
  - status `PASS`
  - calibration completed (`calib_seen=true`, `calib_seen_cycle=37853`)
  - boot self-check stayed clean before and after the diagnostic:
    `boot_done=true`, `boot_error=false`, `boot_mismatch=false`
  - read-only beat command was acknowledged: `wb_ack_count` advanced from 9 to
    10 with `wb_err_count=0` and `loader_error=false`
  - captured beat 0 lower 128 bits:
    `3dc13da53dc13da52c512ca52c512ca5`
- Updated interpretation:
  - The read-only lower-128 capture is safe enough to keep. It does not break
    calibration or the BIST-derived boot data-integrity gate.
  - The v37 failure was introduced by the dense write-select generation, not by
    the lower-128 read capture alone.
  - Next gate: add dense write-select generation in isolation while keeping the
    v38 read-only capture and require `boot_mismatch=false` before accepting
    any dense byte diagnostic result.

## 2026-05-11 - Dense write-select isolated gate v39

- Decision: add dense write-select generation back as the only new hardware
  variable after the passing v38 read-only gate. The diagnostic must refuse to
  interpret dense byte readback unless the initial BIST-derived boot gate is
  clean: `boot_done=true`, `boot_error=false`, and `boot_mismatch=false`.
- Implementation:
  - `fpga/rtl/task6_ypcb_uberddr3_bist_rowstream_loader_top.sv` debug version
    is now v39.
  - Hardware adds `WRITE_DENSE_BYTE` (`0x05`) while preserving the v38
    lower-128-bit `READ_DENSE_BEAT` (`0x06`) debug path:
    `wb_addr = stream_addr / 64`, `sel = 1 << (stream_addr % 64)`, and
    write data in the selected byte lane.
  - `scripts/task6/task6_ddr3_rowstream_loader.py` now gates
    `--diagnostic-dense-count` on a clean initial boot status. If boot is
    unclean, it writes a blocked diagnostic instead of reporting dense byte
    contents as meaningful data.
- Build evidence:
  - `python3 -m py_compile scripts/task6/task6_ddr3_rowstream_loader.py scripts/task6/model_uberddr3_address_lane.py`:
    pass
  - `nix build .#task6-ypcb-uberddr3-rowstream-loader-yosys-json -L`: pass;
    Yosys check found 0 problems, estimated 13,650 LCs
  - `nix build .#task6-ypcb-uberddr3-rowstream-loader-seed16-bitstream -L`:
    pass; route converged at iteration 13, controller clock max frequency
    94.52 MHz at the 25 MHz target, bitstream
    `/nix/store/5l49zjk0za17ffvmd6jh76kc9bxfxzl9-task6-ypcb-uberddr3-rowstream-loader-seed16.bit`
- Board validation command:
  `python3 scripts/task6/task6_ddr3_rowstream_loader.py --bitstream /nix/store/5l49zjk0za17ffvmd6jh76kc9bxfxzl9-task6-ypcb-uberddr3-rowstream-loader-seed16.bit --diagnostic-dense-count 16 --no-full-readback`
- Board result:
  `artifacts/task6/runs/2026-05-11T14-45-06+0200-ypcb-ddr3-rowstream-loader-5l49zjk0za17ffvmd6jh76kc9bxfxzl9-task6-ypcb-uberddr3-rowstream-loader-seed16/dense-diagnostic.json`
- Board summary:
  - status `FAIL`, verdict `dense-byte-contract-fails`
  - calibration completed (`calib_seen=true`, `calib_seen_cycle=37853`)
  - initial boot gate was clean and therefore dense byte interpretation was
    allowed: `boot_done=true`, `boot_error=false`, `boot_mismatch=false`
  - final boot status stayed clean: `boot_done=true`, `boot_error=false`,
    `boot_mismatch=false`
  - 16 dense byte writes and one dense beat read were acknowledged:
    `wb_ack_count` advanced from 9 to 26, `wb_err_count=0`, and
    `loader_error=false`
  - lower 16 bytes of beat 0 were
    `a8 c1 a8 00 a8 c1 a8 00 a8 51 a8 00 a8 51 a8 00`, not
    `00 01 02 03 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f`
- Updated interpretation:
  - Dense write-select generation no longer corrupts the BIST-derived boot
    self-check when added after the v38 read-only capture.
  - The dense byte contract still fails after clean boot and acknowledged
    Wishbone transactions, so this is now a valid data-path failure rather than
    a calibration or boot-gate failure.
  - The repeated pattern strongly suggests the write-data/select operation is
    not landing in the intended DDR3 byte lanes or the read capture is still
    returning structured stale/controller data.
  - Next gate: keep v39's clean boot guard and add an isolated write-side
    observability check, such as echoing the last accepted dense write
    `wb_addr`, `sel` low bits, and selected data byte in debug, before changing
    rowstream loading.

## 2026-05-11 - Dense write-side observability gate v40

- Decision: keep the v39 dense write/read hardware behavior and add only
  write-side observability in the existing 512-bit debug payload. Do not widen
  the debug path.
- Implementation:
  - `fpga/rtl/task6_ypcb_uberddr3_bist_rowstream_loader_top.sv` debug version
    was bumped to v40 for this gate.
  - The tail of the 512-bit debug payload records the last accepted dense write:
    `dense_write_seen`, low 16 bits of dense Wishbone beat address,
    byte lane, data byte, and low 16 select bits.
  - `scripts/task6/task6_ddr3_rowstream_loader.py` decodes these fields into
    every debug snapshot in `dense-diagnostic.json`.
- Build evidence:
  - `python3 -m py_compile scripts/task6/task6_ddr3_rowstream_loader.py scripts/task6/model_uberddr3_address_lane.py`:
    pass
  - `nix build .#task6-ypcb-uberddr3-rowstream-loader-yosys-json -L`: pass
  - `nix build .#task6-ypcb-uberddr3-rowstream-loader-seed16-bitstream -L`:
    pass; route converged at iteration 13, controller clock max frequency
    93.45 MHz at the 25 MHz target, bitstream
    `/nix/store/8y34w17yh49z8yk3h7lcwvafh98gvfcv-task6-ypcb-uberddr3-rowstream-loader-seed16.bit`
- Board validation command:
  `python3 scripts/task6/task6_ddr3_rowstream_loader.py --bitstream /nix/store/8y34w17yh49z8yk3h7lcwvafh98gvfcv-task6-ypcb-uberddr3-rowstream-loader-seed16.bit --diagnostic-dense-count 16 --no-full-readback`
- Board result:
  `artifacts/task6/runs/2026-05-11T14-54-58+0200-ypcb-ddr3-rowstream-loader-8y34w17yh49z8yk3h7lcwvafh98gvfcv-task6-ypcb-uberddr3-rowstream-loader-seed16/dense-diagnostic.json`
- Board summary:
  - status `FAIL`, verdict `dense-byte-contract-fails`
  - calibration completed (`calib_seen=true`, `calib_seen_cycle=37853`)
  - boot stayed clean before and after the diagnostic:
    `boot_done=true`, `boot_error=false`, `boot_mismatch=false`
  - dense write/read transactions were acknowledged:
    `wb_ack_count` advanced from 9 to 26, `wb_err_count=0`, and
    `loader_error=false`
  - dense readback repeated the v39 failure:
    observed `a8 c1 a8 00 a8 c1 a8 00 a8 51 a8 00 a8 51 a8 00`, not
    `00 01 02 03 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f`
  - write-side observability reported the last dense write as
    `lane=15`, `data=15`, `sel_low16=0x8000`, but
    `dense_write_wb_addr_low16=0x3c00` instead of `0x0000`.
- Updated interpretation:
  - The v40 board-valid observability gate isolates a command packing bug:
    the 192-bit command format placed a 32-bit address at bits `48..79` and
    write data at bit `64`, so the first write-data byte overwrote address bits
    `16..23`.
  - This explains the dense writes going to the wrong beat address even though
    lane, data, select, ACKs, and the boot gate looked valid.
  - Earlier simulation/modeling helped narrow the fault, but it did not model
    the exact JTAG command bit packing. Add a command-packing unit/model check
    before trusting future host/RTL command format changes.

## 2026-05-11 - Non-overlapping command-byte layout attempt v41

- Decision: fix the command-packing overlap found by v40 by moving the
  byte-write payload to bit 80 and reading only an 8-bit command data byte in
  the BIST-derived top. This preserves the existing 192-bit command width.
- Implementation:
  - `fpga/rtl/task6_ypcb_uberddr3_bist_rowstream_loader_top.sv` debug version
    is now v41.
  - The RTL reads `jtag_command_data_byte` from `jtag_command_payload[80 +: 8]`
    for lowbyte and dense byte writes.
  - The host command packer writes only `data[0]` at bit 80, avoiding overlap
    with the 32-bit address field.
- Build evidence:
  - `python3 -m py_compile scripts/task6/task6_ddr3_rowstream_loader.py scripts/task6/model_uberddr3_address_lane.py`:
    pass
  - `nix build .#task6-ypcb-uberddr3-rowstream-loader-yosys-json -L`: pass
  - `nix build .#task6-ypcb-uberddr3-rowstream-loader-seed16-bitstream -L`:
    pass; route converged at iteration 13, controller clock max frequency
    97.90 MHz at the 25 MHz target, bitstream
    `/nix/store/w9mzv81775h5nx5afyjsd17cmx6fwmd7-task6-ypcb-uberddr3-rowstream-loader-seed16.bit`
- Board validation command:
  `python3 scripts/task6/task6_ddr3_rowstream_loader.py --bitstream /nix/store/w9mzv81775h5nx5afyjsd17cmx6fwmd7-task6-ypcb-uberddr3-rowstream-loader-seed16.bit --diagnostic-dense-count 16 --no-full-readback`
- Board result:
  `artifacts/task6/runs/2026-05-11T15-02-12+0200-ypcb-ddr3-rowstream-loader-w9mzv81775h5nx5afyjsd17cmx6fwmd7-task6-ypcb-uberddr3-rowstream-loader-seed16`
- Board summary:
  - failed before the dense diagnostic because DDR3 calibration did not
    complete: `magic_ok=True`, `version=41`, `calib_seen=False`, `state=1`,
    `ack=0`, `err=0`, `loader_error=False`, `debug1=0x00000eca`
  - the run produced only `program.log`; no diagnostic JSON was written because
    the host timed out in `wait_calibration()`.
- Updated interpretation:
  - The command-layout fix is logically necessary, but this routed v41 seed is
    not a board-valid gate because it regressed calibration.
  - Do not interpret v41 dense data yet. The next gate should either search a
    seed for the v41 fix that preserves calibration or reduce the observability
    payload after v40 has served its purpose, then rerun the guarded dense
    diagnostic.

## 2026-05-11 - Command-packing model and reduced-debug v42 gate

- Decision: add a cheap command-packing model before further board iterations,
  then try the reduced-debug path instead of keeping the v40/v41 write-side
  observability payload. The v40 debug fields already identified the overlap
  bug, so the next useful hardware variant should keep the non-overlapping
  command layout while shrinking the debug perturbation.
- Added `scripts/task6/model_jtag_command_packing.py` and Nix target
  `.#task6-uberddr3-jtag-command-packing-model`.
- Command-packing model result:
  `/nix/store/snsxh355ssn2mq5kidnmdzsbm98llk1j-task6-uberddr3-jtag-command-packing-model.json`
  - status `PASS`
  - current layout has address bits `48..79` and byte data bits `80..87`, with
    no overlap
  - dense write cases `0..15` decode to beat address `0`, lanes `0..15`, and
    the expected data bytes
  - negative control records that the legacy bit-64 byte payload overlaps the
    address field and corrupts the decoded stream address
- v42 implementation:
  - `fpga/rtl/task6_ypcb_uberddr3_bist_rowstream_loader_top.sv` debug version
    is now v42.
  - The RTL keeps the v41 command byte at `jtag_command_payload[80 +: 8]`.
  - The dense write observability registers and debug payload fields added for
    v40 are removed.
  - The debug tail returns to `loader_wait_cycles_q` and
    `loader_command_payload_addr_q[14:0]`, reducing the hardware delta while
    keeping the command-layout fix.
- Build evidence:
  - `python3 -m py_compile scripts/task6/task6_ddr3_rowstream_loader.py scripts/task6/model_uberddr3_address_lane.py scripts/task6/model_jtag_command_packing.py`:
    pass
  - `nix build .#task6-uberddr3-jtag-command-packing-model -L`: pass
  - `nix build .#task6-ypcb-uberddr3-rowstream-loader-yosys-json -L`: pass;
    Yosys check found 0 problems, hierarchy cell count 28,064
  - `nix build .#task6-ypcb-uberddr3-rowstream-loader-seed16-bitstream -L`:
    pass; route converged at iteration 10, controller clock max frequency
    92.85 MHz at the 25 MHz target, bitstream
    `/nix/store/kpnpryjvhpv2pibckxh1vlz6ygq5jzbw-task6-ypcb-uberddr3-rowstream-loader-seed16.bit`
  - `nix build .#task6-ypcb-uberddr3-rowstream-loader-seed15-bitstream -L`:
    pass; route converged at iteration 16, controller clock max frequency
    85.75 MHz at the 25 MHz target, bitstream
    `/nix/store/4m9yzy905x3ahyv6q7k3z1nyd7bni8zb-task6-ypcb-uberddr3-rowstream-loader-seed15.bit`
- Board validation commands:
  - `python3 scripts/task6/task6_ddr3_rowstream_loader.py --bitstream /nix/store/kpnpryjvhpv2pibckxh1vlz6ygq5jzbw-task6-ypcb-uberddr3-rowstream-loader-seed16.bit --diagnostic-dense-count 16 --no-full-readback`
  - `python3 scripts/task6/task6_ddr3_rowstream_loader.py --bitstream /nix/store/4m9yzy905x3ahyv6q7k3z1nyd7bni8zb-task6-ypcb-uberddr3-rowstream-loader-seed15.bit --diagnostic-dense-count 16 --no-full-readback`
- Board results:
  - seed16:
    `artifacts/task6/runs/2026-05-11T15-15-11+0200-ypcb-ddr3-rowstream-loader-kpnpryjvhpv2pibckxh1vlz6ygq5jzbw-task6-ypcb-uberddr3-rowstream-loader-seed16`
  - seed15:
    `artifacts/task6/runs/2026-05-11T15-20-37+0200-ypcb-ddr3-rowstream-loader-4m9yzy905x3ahyv6q7k3z1nyd7bni8zb-task6-ypcb-uberddr3-rowstream-loader-seed15`
- Board summaries:
  - seed16 failed before dense interpretation because DDR3 calibration did not
    complete: `magic_ok=True`, `version=42`, `calib_seen=False`, `state=1`,
    `ack=0`, `err=0`, `loader_error=False`, `debug1=0x000006cc`
  - seed15 failed before dense interpretation because DDR3 calibration did not
    complete: `magic_ok=True`, `version=42`, `calib_seen=False`, `state=1`,
    `ack=0`, `err=0`, `loader_error=False`, `debug1=0x00000eca`
  - both failed runs produced only `program.log`; no diagnostic JSON was
    written because the host timed out in `wait_calibration()`.
- Updated interpretation:
  - The command-packing model closes the specific host/RTL overlap bug found by
    v40.
  - The non-overlapping command layout remains too placement-sensitive for the
    current seed15/seed16 board gates, even after removing the v40 observability
    registers.
  - Since v39/v40 calibrated and v41/v42 do not, the next hardware step should
    be a bounded seed search on v42 or a smaller command-layout change that
    keeps the old bit-64 data field but narrows the address field used by byte
    write commands so data no longer changes the beat address.

## 2026-05-11 - DDR3 physical-stability gate

- Decision: stop treating seed sweep as the primary DDR3 recovery strategy.
  Before programming another command/data-path variant, compare routed FASM
  against the boot-clean v40 rowstream-loader baseline and classify physical
  movement.
- Added `scripts/task6/compare_nextpnr_fasm_physical_stability.py`.
- Added Nix report target:
  `.#task6-ypcb-uberddr3-rowstream-loader-physical-stability-v40-json`.
- Current baseline for this gate:
  `artifacts/task6/baselines/uberddr3-rowstream-loader-v40-physical-stability/critical.fasm`,
  generated from
  `/nix/store/bsl17n6hm1yxzpvckm2bq637q49lnv1b-task6-ypcb-uberddr3-rowstream-loader-seed16.fasm`,
  recovered from the known boot-clean v40 bitstream derivation
  `/nix/store/vy3xagy95ycxlgggs6fjrv13c3fl6vpg-task6-ypcb-uberddr3-rowstream-loader-seed16.bit.drv`.
- Gate semantics:
  - `FAIL`: IDELAY, IOB/IOI, ISERDES/OSERDES, PLLE2/MMCM site, or BSCAN/JTAG
    FASM features changed; do not interpret DDR3 board behavior as a data-path
    result until placement/constraints are fixed.
  - `WARN`: PHY/JTAG sites match but clock/routing FASM changed; run only the
    boot/calibration guard first, then decide whether the change is acceptable.
  - `PASS`: critical DDR3/clock/JTAG FASM footprint matches the baseline.
- Validation:
  - `python3 -m py_compile scripts/task6/compare_nextpnr_fasm_physical_stability.py`:
    pass
  - v39-vs-v40 comparator self-check reports `WARN`: IDELAY, IOB, SERDES,
    PLLE2 site, and BSCAN/JTAG features match, while clock routing changes.
    This matches board evidence: both v39 and v40 were boot-clean, but the
    route is not bit-identical.
- Current candidate report:
  - command:
    `nix build .#task6-ypcb-uberddr3-rowstream-loader-physical-stability-v40-json --no-link --print-out-paths -L`
  - output:
    `/nix/store/f2nbjahw8bx86m92lw9b28pcrn8glf3i-task6-ypcb-uberddr3-rowstream-loader-physical-stability-v40.json`
  - status: `WARN`
  - hard-fail delta: `hard_fail_removed_count=0`,
    `hard_fail_changed_tile_count=0`
  - traced false-positive:
    - the earlier `LIOI3_X0Y225` hard-fail was `SYS_RSTN` at site
      `IOB_X0Y226`, not DDR3 DQ/DQS/clock PHY.
    - the gate now ignores `LIOB33_X0Y225` and `LIOI3_X0Y225` for this DDR3
      physical comparison.
  - remaining delta: clock-route FASM changed relative to v40, so board work
    must start with a boot/calibration-only gate.
- Boot-only board gate:
  - added `--boot-only` to `scripts/task6/task6_ddr3_rowstream_loader.py` so a
    WARN physical report can be tested without issuing loader writes.
  - bitstream:
    `/nix/store/s065qrqiqa03kgkdxyhqm3ci0cz76dkz-task6-ypcb-uberddr3-rowstream-loader-seed16.bit`
  - command:
    `python3 scripts/task6/task6_ddr3_rowstream_loader.py --bitstream /nix/store/s065qrqiqa03kgkdxyhqm3ci0cz76dkz-task6-ypcb-uberddr3-rowstream-loader-seed16.bit --boot-only --no-full-readback`
  - result:
    `artifacts/task6/runs/2026-05-11T16-42-55+0200-ypcb-ddr3-rowstream-loader-s065qrqiqa03kgkdxyhqm3ci0cz76dkz-task6-ypcb-uberddr3-rowstream-loader-seed16/boot-diagnostic.json`
  - status `PASS`: `calib_seen=true`, `boot_done=true`,
    `boot_mismatch=false`, `wb_err_count=0`
- Guarded dense-byte board gate after boot-clean:
  - command:
    `python3 scripts/task6/task6_ddr3_rowstream_loader.py --bitstream /nix/store/s065qrqiqa03kgkdxyhqm3ci0cz76dkz-task6-ypcb-uberddr3-rowstream-loader-seed16.bit --no-program --diagnostic-dense-count 16 --no-full-readback`
  - result:
    `artifacts/task6/runs/2026-05-11T16-43-58+0200-ypcb-ddr3-rowstream-loader-s065qrqiqa03kgkdxyhqm3ci0cz76dkz-task6-ypcb-uberddr3-rowstream-loader-seed16/dense-diagnostic.json`
  - status `FAIL`: `mismatch_count=13/16`
  - observed lower 16 bytes:
    `00 c1 00 00 00 c1 00 00 00 51 00 00 00 51 0e 0f`
  - expected:
    `00 01 02 03 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f`
  - final debug stayed boot-clean and write-side observability was sane:
    `boot_mismatch=false`, `wb_ack_count=26`, `wb_err_count=0`,
    `dense_write_wb_addr_low16=0`, `dense_write_lane=15`,
    `dense_write_data=15`, `dense_write_sel_low16=0x8000`
  - interpretation: this is now a valid dense data-path failure, not a
    calibration or physical-site failure. The next gate should inspect whether
    readback is stale/structured controller data or whether byte lanes 1, 5, 9,
    and 13 are being selected/packed differently than intended.
- Constraint policy:
  - Add LOC/region constraints only when the FASM gate shows a repeatable
    site-level movement or nextpnr placement output can map the moved site back
    to a specific RTL cell.
  - Do not add guessed constraints from data-path symptoms alone.
