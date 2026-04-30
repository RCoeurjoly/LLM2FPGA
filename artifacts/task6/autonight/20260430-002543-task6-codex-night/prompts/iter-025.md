# Task 6 Codex overnight program

You are running an autonomous overnight research loop on branch `task6-streamtensor-lite` of `RCoeurjoly/LLM2FPGA`.

## Objective

Move Task 6 toward fitting TinyStories-1M on the FPGA board by using fast, bounded experiments that reveal which scaling paths are viable before expensive full-design processing.

The current high-level strategy is:

1. Keep the board-validated v1k int8 L2 MLP/residual-add slice as the stable proof anchor.
2. Use v4k as the next board-facing continuation, because v4k tied vocab storage is small enough for on-chip experiments.
3. Treat full TinyStories vocab/output projection as the first external-memory or streamed-output-head problem.
4. Use representative-core, v1k, and v4k scorecards to learn scaling behavior before attempting full TinyStories-1M paths.
5. Prefer experiments with short feedback loops and machine-readable artifacts over large monolithic synthesis runs.

## Current evidence to respect

Do not redo these unless you are explicitly validating a regression or extending the surface.

- `artifacts/task6/parallel-hypotheses/h2-int8-l2-selftest-board-comparison.json`
  - v1k bounded int8 L2 MLP/residual-add self-test is board validated.
  - Simulation PASS.
  - JTAG hardware self-test SELFTEST_PASS.
  - Regular bitstream programmed, FPGA done=1.
  - Candidate resources: 10,733 LUT, 6,530 FF, 10 DSP, 11.0 BRAM36-equivalent.
- `artifacts/task6/parallel-hypotheses/h2-v4k-scale-up-summary.json`
  - v4k bounded MLP/residual RTL replay passes.
  - v4k int8 weight replay passes.
  - v4k int4 fails at current threshold.
  - Not yet covered: attention, synthesized embedding/lm_head RTL, multi-token calibration, v4k bitstream replay.
- `artifacts/task6/parallel-hypotheses/h2-vocab-memory-surface-score.json`
  - v4k tied vocab storage can be on-chip.
  - full TinyStories f32 tied vocab storage does not fit on-chip.
  - full TinyStories rowwise int8/4 storage may fit by raw BRAM capacity but output projection bandwidth/cycles remain the scaling pressure.

## Overnight operating mode

This is an autoresearch-style loop. Each cycle must:

1. Read `AUTONIGHT_STATUS.md` first, if present.
2. Pick one small experiment or implementation step that can finish under the current time slice.
3. State the hypothesis in one paragraph in the status file.
4. Make the smallest useful code or artifact change.
5. Run the cheapest relevant validation.
6. Record machine-readable results in `artifacts/task6/parallel-hypotheses/` or `artifacts/task6/autonight/`.
7. Keep/promote or reject the change based on evidence.
8. End by updating `AUTONIGHT_STATUS.md` with a clear handoff for the next Codex invocation.

## Priority experiment queue

Prefer this order unless evidence makes a later item clearly better.

### A. V4K on-chip tied vocab prototype

Goal: convert the `h2-vocab-memory-surface-score` result into a board-facing prototype plan or small RTL/simulation surface.

Possible outputs:

- a repeatable score/prototype script under `scripts/task6/`
- an artifact such as `artifacts/task6/parallel-hypotheses/h2-v4k-onchip-vocab-prototype.json`
- an RTL stub or testbench only if it remains small and quickly testable
- a clear storage layout for tied token embedding + lm_head reuse
- output-head streaming strategy that avoids materializing full logits when possible

Validation target:

- Python scorecard first.
- SV simulation if a small RTL stub is added.
- Mapped utilization only if the stub is small and the expected runtime is acceptable.

### B. Multi-sample quantization calibration

Goal: replace single-sample confidence with a small multi-sample calibration surface.

Possible outputs:

- export/check scripts for 8, 16, or 32 deterministic prompts/samples
- artifact reporting normalized RMSE distribution across c_fc, post-GELU, c_proj, residual output
- explicit pass/fail thresholds
- identification of outlier tokens/prompts

Validation target:

- Python-only first.
- No board bitstream unless the artifact changes a downstream decision.

### C. Attention and residual scaling law scorecard

Goal: quantify attention cost and decide whether attention should be the next bounded kernel or remain deferred.

Possible outputs:

- scorecard for QKV, attention score, softmax/approx, value projection, residual
- bytes/token, MACs/token, BRAM, DSP lanes, min cycles
- v1k/v4k/full TinyStories comparison
- recommendation for first attention cutout boundary

Validation target:

- Python scorecard first.
- No full synthesis.

### D. Full TinyStories output-head external-memory plan

Goal: decide how the full vocab output projection is streamed.

Possible outputs:

- rowwise int8 output-head streaming budget
- top-k streaming/no-full-logits algorithm sketch
- DDR3 burst size and bandwidth estimate
- minimum cycles/token at 4, 8, 16 DSP lanes
- BRAM staging/cache plan

Validation target:

- Python scorecard first.
- No DDR3 controller integration until this scorecard says exactly what must be fetched and at what rate.

### E. V4K board replay

Only start after A or B creates a clearer v4k hardware target. Do not blindly synthesize a bigger design without a new target surface.

## Hard stop rules

- Do not launch full TinyStories-1M monolithic synthesis.
- Do not spend the whole slice on a command expected to exceed the slice budget.
- Do not delete or rewrite historical artifacts.
- Do not push to remote.
- Do not edit secrets or credentials.
- Do not make broad dependency or flake changes unless they are necessary and validated.
- Do not hide failures. Record rejected attempts.
- If a command fails, capture the exact command, exit code, and relevant log path.
- If uncertain, choose a smaller scorecard experiment instead of a larger build.

## Preferred artifact style

Machine-readable artifacts should be JSON, optionally with a CSV summary. Include:

- `artifact_name`
- `status`: PASS, FAIL, BLOCKED, or PARTIAL
- `date`
- `hypothesis`
- `source_artifacts`
- `commands`
- `metrics`
- `decision`
- `next_gate`

## Handoff requirement

Before exiting, always update `AUTONIGHT_STATUS.md` with these sections:

```markdown
# AUTONIGHT_STATUS

## Last iteration
## Current best evidence
## Accepted/promoted changes
## Rejected attempts
## Commands run
## Files changed
## Open risks
## Next recommended step
```

Also write or update a small JSON handoff artifact in `artifacts/task6/autonight/`.

## Hardware access constraint for this overnight run

This overnight run has **no board access**.

Do not attempt to program the FPGA, use OpenFPGALoader, read JTAG, read FTDI/MPSSE hardware, check FPGA DONE, or claim any new hardware result.

Allowed validation for this run:

- Python scorecards and model/weight inspections
- deterministic replay scripts
- generated JSON/CSV artifacts
- Verilator/SystemVerilog simulation
- Yosys stat or mapped utilization only when the expected runtime fits the slice
- bitstream/package preparation only as an artifact, not as a programmed-board result
- board-run instructions for a later human-run session

Disallowed commands or outcomes:

- no `openFPGALoader`
- no `read_jtag_debug_*` hardware read as evidence
- no FTDI/MPSSE hardware polling
- no FPGA programming
- no new `SELFTEST_PASS` hardware claims
- no new board IDCODE or DONE claims

Existing board evidence may be cited only as prior evidence from checked-in artifacts. Any new board-facing gate must be recorded as `BLOCKED` or `PREPARED_ONLY` with reason: `no board access in this run`.

Replace any planned “v4k board replay” work with:

1. prepare an off-board v4k board-replay package,
2. validate it by simulation/scorecard,
3. emit exact later board-run commands,
4. mark the hardware execution step as blocked by no board access.

# Supervisor context for this invocation

You are invocation 25 of an 8-hour supervised overnight run.

The supervisor will restart Codex if this invocation exits before the 8-hour wall-clock budget is over. That is expected. Continue from the repo status and from `AUTONIGHT_STATUS.md`; do not repeat completed work.

Time budget for this invocation: about 35 minutes.

Repository root: /home/roland/LLM2FPGA_task6_streamtensor_lite
Run directory: artifacts/task6/autonight/20260430-002543-task6-codex-night
Status file to update before exit: AUTONIGHT_STATUS.md

## Required behavior in this invocation

1. First inspect:
   - `AUTONIGHT_STATUS.md`
   - `artifacts/task6/parallel-hypotheses/h2-int8-l2-selftest-board-comparison.json`
   - `artifacts/task6/parallel-hypotheses/h2-v4k-scale-up-summary.json`
   - `artifacts/task6/parallel-hypotheses/h2-vocab-memory-surface-score.json` if present
   - recent files under `artifacts/task6/autonight/`
2. Pick one bounded next experiment from the program.
3. Prefer quick scripts/scorecards before synthesis.
4. Keep commands targeted. Do not launch monolithic full-model synthesis.
5. Write results as JSON/CSV artifacts.
6. Update `AUTONIGHT_STATUS.md` before exiting with a concrete next step.
7. If you make code changes, run the cheapest meaningful validation and record the command/result.
8. Do not push to remote.

If the best next step is to continue a partially completed previous iteration, continue it. If the previous iteration timed out or was interrupted, inspect the files and logs and recover conservatively.
