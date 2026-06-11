# Task 6 M3 Plan: TinyStories-1M on YPCB

## Mission

Finish LLM2FPGA's remaining Task 6 path by reaching
`M3-full-tinystories-1m`: TinyStories-1M (`ts1m`) token-exact greedy inference
on the YPCB-00338-1P1 board with the fully open-source flow.

The path stays staged and evidence-driven:

1. keep the current v9984 int8 JTAG-debug bitstream as the golden board
   regression;
2. keep `M0-host-assisted-rowstream-top1` as the green output-head checkpoint;
3. migrate transformer math onto the board through M1, M2, then M3;
4. use DDR3 for the full-vocab/full-rowstream TinyStories path;
5. stop and fix the first failing gate before adding scope.

As of 2026-06-11, M0 is complete on hardware. That closes the old
single-token/top1 proof point, but Task 6 now remains open until M3 proves that
the board runs all TinyStories-1M transformer blocks and returns token-exact
greedy output from host-supplied token/control input.

## Finish-line success criteria

Task 6 / Task 4 finish when all of the following are true:

- The input data comes from real TinyStories-1M checkpoint-derived model
  artifacts, including the full-vocab rowstream/output-head data.
- The host supplies prompt token IDs/control and board setup only; PCIe is not
  the normal transport for per-token hidden-state vectors.
- The board executes all TinyStories-1M transformer blocks and downstream
  output-head selection for the tested greedy decode steps.
- The generated token sequence is token-exact against the fixed-point/software
  reference for the same prompt, model artifacts, and decode policy.
- The run artifacts include command logs, JSON verdicts, board output, and the
  resource comparison against the copied baseline bundle:
  `artifacts/task6/baselines/tiny-stories-1m-baseline-float-selftest-all-memory-utilization`.
- The final writeup states the resource delta from the old direct all-memory
  float baseline to the fitting int8/tiled/DDR3-backed path.

M0 remains accepted evidence that the board can consume the TinyStories-1M int8
rowstream and compute output-head top1. It is not the M3 finish line.

### Architecture lock

Task 6 is now a **compiler-contract + kernelized inference** flow, not a
full-model monolithic compile-to-RTL path.

- Torch/adapter import and metadata capture remain as the common entry point for
  PyTorch checkpoints.
- The accepted path is manifest → staged contracts → quantized weight packs →
  fixed-point lowering/replay scoring → reusable kernel selftests → PCIe/DDR3
  board gates.
- FPGA compute moves block-by-block (embedding/normalization/attention/MLP/output-head);
  host keeps control-plane responsibilities (prompt handling, tokenization,
  generation policy, orchestration, PCIe setup, references, and logging).
- This is aligned with the survey route in
  `deliverables/1a-survey.org` and `deliverables/1c-selected_route.org`:
  host software decode policy + board-accelerated transformer math.

Transferability scope:

- In scope now: GPT/Causal family, quantized-fixed-point kernels on YPCB, with
  TinyStories-1M/3M/8M parameter variants handled by regenerated manifests,
  quantization packs, and contracts.
- Out of scope now: arbitrary model families and arbitrarily different decoder
  layouts without contract/kernel updates.
- Future architecture changes must keep host-vs-board boundaries explicit in the
  contract and produce fixed-point oracle artifacts before board claims.

### Host↔FPGA responsibility contract

Task 6 now uses a staged transformer-migration contract. The host remains the
orchestrator, but the target TinyStories inference path must move transformer
math onto the YPCB board instead of permanently shuttling hidden states over
PCIe.

- Host: prompt text handling, tokenization/detokenization, generation policy,
  PCIe recovery/orchestration, artifact loading, CPU/fixed-point reference
  generation, and run logging.
- FPGA board: DDR3 model/row movement, output-head top1/top-k, and progressively
  migrated transformer compute: embeddings, layernorm, attention/KV,
  MLP/GELU/residual, and final result registers.
- PCIe: control, prompt/token IDs, model artifact loading, status, and generated
  token/result readback. It should not be the normal transport for per-token
  hidden-state vectors once the matching board stage exists.

Stage lock:

- `M0-host-assisted-rowstream-top1`: host supplies `hidden_q`; board runs DDR3
  rowstream output-head top1. This is already useful acceptance evidence, but it
  is not full transformer inference.
- `M1-transformer-boundary-mlp`: host supplies prompt-derived activation and
  residual vectors; board runs the int8 MLP/residual boundary. For
  `--engine mlp`, the reference must include per-step `activation_q`,
  `residual_q`, and `residual_add_output_q` fields.
- `M2-one-full-block`: host supplies token IDs/control; board runs one complete
  TinyStories transformer block plus downstream output-head checking.
- `M3-full-tinystories-1m`: host supplies token IDs/control; board runs all
  TinyStories-1M transformer blocks and returns token-exact greedy generation.

This split is intentionally aligned with the state-of-practice boundaries
recorded in `deliverables/1a-openflow-kintex480t-survey.org` and the broader
survey in `deliverables/1a-survey.org`: host software controls the decode loop,
while FPGA fabric and board DDR carry the compressed numeric kernels and model
movement.

## Current anchors

- Current Task 6 status:
  `M0-host-assisted-rowstream-top1` complete on hardware as of 2026-06-11.
- M0 board summary:
  `artifacts/task6/runs/2026-06-11T-task6-registered-row-output-rowstream-top1-summary.json`
- M0 flash evidence:
  `artifacts/task6/runs/2026-06-11T23-14-05+0200-task6-registered-row-output-pnr100-flash`
- M0 PCIe recovery evidence:
  `artifacts/task6/runs/2026-06-11T23-21-31+0200-task6-registered-row-output-pnr100-recover`
- Current M0 timing-clean bitstream:
  `/nix/store/4y13l7ya6qyv5pzaxm0n91z6la3spd33-task6-ypcb-pcie-uberddr3-rowstream-loader-only-top1-pnr100.bit`
- Current PCIe input:
  `pcie7x = path:/home/roland/pcie_7x`, using the reset-support branch while
  YPCB enumeration/BAR lifecycle remains part of the board loop.
- Golden regression target:
  `task6Int8V9984L2ResidualAddOutputHeadSelftestJtagDebug5MHzBitstream`
- Expected default build target:
  `nix build`
- Current DDR3 one-lane bitstream:
  `artifacts/task6/uberddr3-baseline-flow/seed16-vainilla-2026-05-20/ypcb-00338-1p1-ddr3-bist-1lane-full-openxc7.bit`
- Full-vocab size:
  `50257` tokens
- Required boundary rows:
  `0,1,31,32,50256`
- Simple run root:
  `artifacts/task6/runs/final-ts1m-inference/`

## Execution sequence

Run these gates in order. Do not advance until the current gate is green.

### 0. M0 host-assisted rowstream top1 checkpoint

Status: complete on 2026-06-11.

What it proves:

- PCIe recovery can reach `pcie_ready` with the reset-support `pcie_7x` input.
- DDR3 full rowstream load uses `packet_load_mode=pair`, `packet_count=106828`,
  and `packet_ack_fallback_count=0`.
- The registered row-output reader remains stable under backpressure in both
  64-bit and 128-bit simulations.
- Hardware top1 matches the Q0.24 TinyStories-1M int8 reference for all 8 prompt
  samples: `257, 1310, 2576, 3706, 20037, 13, 1375, 6151`.
- `mismatch_count=0`, `reserved_nonzero_count=0`, and
  `hardware_top1_used=true`.

Do not regress this gate while moving transformer stages onto the board.

### 1. v9984 regression gate

Purpose: prove the current default build, board programming, and JTAG readback
loop are still healthy before touching DDR3.

Required actions:

- Build the default package with `nix build`.
- Program the v9984 JTAG-debug bitstream.
- Read the JTAG payload.

Pass criteria:

- FPGA programming reports `done=1`.
- JTAG IDCODE is readable.
- Payload reports `SELFTEST_PASS`.
- Top index, accumulator, and exposed checksums match the generated reference.

If this fails, fix default/build/board plumbing first. Do not continue to DDR3.

### 2. DDR3 boot gate

Purpose: prove the one-lane DDR3 baseline is reproducible on the current board
session.

Required action:

- Run boot/calibration only with 960-bit debug decode using the current one-lane
  DDR3 bitstream.

Pass criteria:

- `calib_seen=true`
- `boot_done=true`
- no boot mismatch
- no loader error

If boot/calibration is flaky, fix one-lane reproducibility. Do not widen lanes
and do not connect TinyStories logic.

### 3. DDR3 fullbeat diagnostic gate

Purpose: prove the DDR3 read/write path moves a known fullbeat correctly before
using model rows.

Required action:

- Run the fixed fullbeat diagnostic at base `0x20`, beat `0`.

Pass criteria:

- clean fullbeat delta
- zero mismatch
- no Wishbone/loader error

If this fails, debug DDR3 transport only.

### 4. TinyStories boundary-row integrity gate

Purpose: prove real TinyStories row bytes survive DDR3 storage at critical row
positions before doing full readback or inference.

Required action:

- Load the TinyStories rowstream.
- Check rows `0,1,31,32,50256` against `rowstream.bin`.

Pass criteria:

- every selected row byte-matches the source rowstream
- no row-address aliasing
- no loader/DDR3 errors

If this fails, debug row addressing, row packing, byte-lane mapping, or rowstream
format only. Do not debug quantization or inference logic yet.

### 5. Full rowstream readback gate

Purpose: prove the complete TinyStories full-vocab rowstream is stored correctly
in DDR3.

Required action:

- Load the full rowstream into DDR3.
- Read it back and compare SHA-256 with the source `rowstream.bin`.

Pass criteria:

- full readback SHA-256 matches source rowstream SHA-256

If full readback is too slow for the deadline, use chunk hashes plus the
boundary-row gate as weaker evidence and explicitly mark it weaker in the final
artifact.

### 6. M1 transformer-boundary MLP gate

Purpose: move the prompt-derived MLP/residual boundary onto the board while
keeping the host as activation/residual provider.

Required action:

- Run `prompt-infer --engine mlp` with a reference JSON or prompt-derived
  activation/residual vectors.
- Feed `activation_q` and `residual_q` through PCIe/MMIO.
- Compare the board `residual_add_output_q`, checksums, and sample points
  against the fixed-point reference.

Pass criteria:

- Each tested prompt step matches the M1 contract fields:
  `activation_q`, `residual_q`, and `residual_add_output_q`.
- The M0 rowstream/top1 gate still passes on the same board image or a paired
  regression image.
- Run artifact records bitstream, model/reference hashes, board result, and
  command logs.

If this fails, debug the MLP/GELU/residual arithmetic boundary before moving to
one-full-block work.

### 7. M2 one-full-block gate

Purpose: run one complete TinyStories transformer block on the board from
host-supplied token IDs/control, then feed its output to downstream checking.

Required action:

- Compose embedding/position input, block-0 layernorm, attention/KV, residual,
  layernorm, MLP/GELU, and residual paths behind a board-visible M2 contract.
- Compare block output vectors and downstream top1 against the fixed-point M2
  oracle.
- Keep any replay-only lane clearly labeled as integration evidence, not live
  M2 compute.

Pass criteria:

- The live-compute block output matches the fixed-point M2 oracle within the
  documented exact/tolerance contract.
- Downstream rowstream/top1 over the M2 output matches the reference.
- M0 and M1 regressions remain green or have explicit paired artifacts.

### 8. M3 full TinyStories-1M board inference gate

Purpose: produce the Task 6 finish-line proof.

Required action:

- Run the full TinyStories-1M transformer stack on the board for the tested
  greedy decode steps.
- Host supplies token IDs/control, model artifact loading, PCIe recovery, and
  logging; board carries transformer math and output-head selection.
- Compare generated tokens against the fixed-point/software reference.

Pass criteria:

- The board-generated greedy continuation is token-exact for the recorded prompt
  and step count.
- Run artifact records bitstream, rowstream/model hashes, prompt tokens, decode
  policy, software reference, board result, and command logs.
- The final writeup clearly distinguishes completed M0/M1/M2/M3 evidence.

If this fails after M2 is green, debug inter-block state movement, final
layernorm/output-head handoff, and decode-loop control before changing DDR3.

Preferred M0 regression command:

```sh
scripts/task6/task6_pcie_user_gate.sh rowstream-top1 0000:42:00.0 \
  --sample-count 8 \
  --reference-json artifacts/task6/parallel-hypotheses/h2-tinystories-1m-prompt-output-head-q024-reference.json \
  --json-out artifacts/task6/runs/<label>/rowstream-top1-board-summary.json
```

For interactive use, the same command supports `--answer-only` to print just the board-computed continuation and keep output suitable for a prompt CLI loop.
For an actual shell prompt loop, use:

```sh
scripts/task6/task6_prompt_cli.py
```

By default that launches interactive mode and pipes each prompt through a deterministic
host-assisted `rowstream-top1` pass. A single-shot invocation is also supported:

```sh
scripts/task6/task6_prompt_cli.py --engine top1 "Once upon a time there was"
```

`--reference-json` is a single-shot mode for `task6_prompt_cli.py` and should be
used without interactive input.

Use `--engine mlp` and `--mlp-answer-format {checksum,output,both}` for the
reusable MLP boundary lane.

`prompt-infer --engine top1` is the user-facing M0 regression command: host
computes prompt `hidden_q` from reference, FPGA runs `rowstream-top1` for each
step.

The stable CPU-vs-board comparison CLIs are:

```sh
scripts/task6/llm2fpga_cpu_generate.py --steps 8 "Once upon a time there was"
scripts/task6/llm2fpga_board_generate.py --steps 8 "Once upon a time there was"
```

For the current `M0`/`M1` stages, these remain deterministic comparison
front-ends over the fixed-point CPU reference and the board-visible staged
accelerators. They become full TinyStories board generation commands only after
the `M3-full-tinystories-1m` gate passes.

### Reusable MLP boundary lane command

Milestone `M1-transformer-boundary-mlp` is intentionally staged and host-assisted:

```sh
scripts/task6/task6_pcie_user_gate.sh prompt-infer 0000:42:00.0 \
  --engine mlp \
  --reference-json artifacts/task6/parallel-hypotheses/h2-tinystories-1m-prompt-output-head-q024-reference.json \
  --steps 8 \
  --json-out artifacts/task6/runs/<label>/mlp-accel-board-summary.json
```

```sh
scripts/task6/task6_pcie_user_gate.sh prompt-infer 0000:42:00.0 \
  --engine mlp \
  --prompt "Once upon a time there was" \
  --model-path TinyStories \
  --tokenizer-vocab TinyStories/gpt2-vocab.json \
  --tokenizer-merges TinyStories/gpt2-merges.txt \
  --steps 8 \
  --json-out artifacts/task6/runs/<label>/mlp-accel-board-summary.json
```

This command reuses the same reference contract, sends prompt-derived
`activation_q`/`residual_q` vectors into the accelerator lane, and validates the
`residual_add_output_q`, checksums, and sample points from PCIe/MMIO exposure.

### 9. Package Task 6 and Task 4 evidence

Purpose: turn the board result into deliverable evidence.

Required action:

- Update Task 6 notes/status with the final result.
- Keep reviewer-controlled `docs/project-plan*` files unchanged unless explicit
  reviewer approval is available.
- Write a compact final artifact summary under `artifacts/task6/`.

Required claims:

- Direct float all-memory baseline does not fit: about `13535%` LUT and `9724%`
  FF on XC7K480T.
- New path fits by changing strategy: int8 quantization, tiling, StreamTensor-lite
  execution, and DDR3-backed full-vocab rowstreaming.
- Board evidence proves TinyStories-1M token-exact greedy inference on YPCB,
  with M0/M1/M2 called out as intermediate gates.

### 10. Task 5 scaling analysis

Start only after the `M3-full-tinystories-1m` board gate passes.

Required action:

- Produce a simple scaling matrix for other TinyStories sizes.
- For each model size, report dimensions, estimated storage, BRAM/DDR need,
  expected output-head cycles, and whether the current architecture should fit.

No full implementation of every size is required unless one is cheap and useful
for the funding narrative.

## PCIe recovery safety protocol

The default autonomous recovery path is host-safe first:

- Run lifecycle probes without BAR MMIO first: `scripts/task6/task6_pcie_user_gate.sh lifecycle 0000:42:00.0`.
- Treat `missing_endpoint` as eligible for one rootless bridge rescan.
- Treat clean `missing_resource0` as eligible for one delegated endpoint recovery.
- Treat `stale_bar_all_ones`, corrupt config, repeated `missing_resource0`, or repeated `missing_endpoint` as requiring chassis re-enumeration. Prefer the Tapo P115 chassis power cycle for that.
- Do not run BAR, debug, rowstream, MLP, or top1 gates until lifecycle is `pcie_ready`.
- Do not enable `--allow-bar-probe` in `task6_pcie_recovery_orchestrator.py` unless deliberately testing BAR behavior after clean config-space enumeration.
- Do not enable `--allow-root-recovery` for normal Task 6 iteration. The root PCIe/Thunderbolt reset ladder can wedge the laptop; use it only as a bounded recovery experiment with no long-running FPGA/PCIe jobs active.

For hands-off iteration, the preferred recovery escalation is:

1. config-space lifecycle probe;
2. one bridge rescan only if endpoint is absent;
3. one delegated recover only if endpoint identity is clean but BAR0 is missing;
4. Tapo P115 chassis power cycle;
5. rerun non-BAR lifecycle;
6. only then run BAR/rowstream/top1 gates.

### Host-freeze incident signature

On 2026-06-09 the laptop froze after PCIe recovery around the YPCB endpoint.
The previous boot journal showed the relevant signature:

- `15:31:09`: `0000:42:00.0` re-enumerated as Xilinx `10ee:0480`.
- BAR0 initially appeared as `0x00000000`.
- The kernel logged `BAR 0 ... not claimed; can't enable device`.
- The kernel then reassigned BAR0 to `0x74000000`.
- Shortly afterward, the kernel logged repeated
  `workqueue: pci_pme_list_scan hogged CPU` warnings.

Task 6 artifacts matched the same transition:

- `2026-06-09T15-21-34+0200-pcie-top1-pnr100-known-byteorder-sram-plugdev`:
  `pcie_ready`, BAR0 `74000000`.
- `2026-06-09T15-31-00+0200-pcie-top1-pnr100-noreverse-sram-after-rescan`:
  `missing_resource0`, clean endpoint identity but BAR0 `00000000`.
- `2026-06-09T15-31-32+0200-pcie-top1-pnr100-noreverse-sram-after-recover`:
  `pcie_ready`, BAR0 `74000000`.

Treat this as PCIe/Thunderbolt hotplug/resource fragility, not a DDR3 failure.
If the lifecycle snapshot shows clean identity but BAR0 is `00000000`, or if
the kernel has logged `BAR 0 ... not claimed; can't enable device`, stop BAR
MMIO and top1/rowstream gates. Do not continue with root/Thunderbolt reset
ladders or repeated BAR probes. Power-cycle the chassis through the Tapo P115,
rerun a non-BAR lifecycle probe, and only resume board gates after `pcie_ready`
is stable.

## Work rules

- One active path only:
  `M0 regression -> M1 MLP/residual -> M2 one full block -> M3 full TinyStories-1M`.
- Use one simple run root: `artifacts/task6/runs/final-ts1m-inference/`.
- No broad experiment naming scheme.
- No lane widening until the active milestone passes its board gate.
- No architecture search unless a named gate fails.
- No full-generation claim before M3 passes.
- Every board run must leave command logs, JSON verdicts, and key output.
- Commit after major green gates, not after every tiny attempt.

## Fallbacks

- If v9984 regression fails: fix build/default/board plumbing first.
- If DDR3 boot fails: fix one-lane calibration reproducibility.
- If fullbeat fails: debug DDR3 transport below TinyStories.
- If boundary rows fail: debug rowstream packing/addressing/byte lanes.
- If full readback fails: use chunk hashes only if deadline pressure requires it,
  and label the evidence weaker.
- If M0 top1 regresses after row integrity passes: debug fixed-point
  sidecar/compare and top1 logic.
- If M1 fails: debug MLP/GELU/residual arithmetic and PCIe-visible contract
  fields before adding more transformer scope.
- If M2 fails: debug live block arithmetic/state movement against the fixed-point
  one-block oracle before composing more blocks.
- If M3 fails: debug inter-block handoff, final layernorm/output-head handoff,
  and decode control before changing storage.
- If route/timing fails after connecting inference: reduce frequency first and
  keep one lane.

## Assumptions

- Finish-line inference means token-exact greedy M3 generation from host-supplied
  token IDs/control, not host-supplied hidden-state top1.
- TinyStories-1M full vocabulary is `50257` tokens.
- Full-vocab float/on-chip direct lowering is not a viable path.
- DDR3 is required for the full-vocab/full-rowstream path, while v9984 remains
  the on-chip golden regression.
- Task 5 is a post-M3 scaling analysis, not part of the Task 6 critical path.

## 2026-05-21 execution update: DDR3 route adjustment

The current DDR3 evidence changes the next step:

- v63 seed18 rowstream-loader boot is clean and command/fullbeat transport works.
- Fullbeat readback does not preserve all lanes.
- Stable useful bytes appear at `lane % 4 == 3` across at least two base/address probes.
- Therefore the next fast route is lane-sparse DDR3 storage, not dense DDR3 storage.

Next immediate gate:

1. Map logical rowstream byte `i` to physical DDR byte `4*i + 3`.
2. Prove boundary rows `0,1,31,32,50256` against `rowstream.bin`.
3. Then add a board-side 16-byte-to-stable-lanes writer for full rowstream load.

This uses more DDR3 capacity but avoids spending time on unstable byte lanes. The
4x expansion is acceptable for TinyStories-1M rowstream size.

## 2026-05-21 update

The DDR3 externalization route is now narrowed:
- Use old v63 seed18 as the calibration reference.
- Reliable storage is currently one logical byte per physical 64-byte DDR3 beat, lane 15 only: 64x expansion, about 219 MB for the TinyStories rowstream.
- Low-window sparse writes/readbacks pass, but full representative boundary rows fail on old v63 because dense-byte writes truncate the physical address to low 16 byte-address bits.
- Direct full-address, reduced 22-bit address, and paged upper-address RTL variants build and meet timing, but currently fail DDR3 calibration.

Next step is not more broad experimentation. The next safe step is to preserve the known-good DDR3 placement more tightly while adding upper-address support, then gate every candidate by boot-only calibration before any rowstream test.

## 2026-05-22 immediate execution protocol

Commit each logical change separately.

Current next route:
1. Preserve the known-good v63 DDR3 placement as tightly as possible.
2. Add upper-address support with minimal disturbance to the low 16-bit dense-byte write path.
3. Gate every new bitstream by boot-only calibration before any rowstream or boundary-row test.

No boundary-row test is valid until boot-only calibration passes on the candidate bitstream.
