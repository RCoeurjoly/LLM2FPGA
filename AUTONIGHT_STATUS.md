# AUTONIGHT_STATUS

## Last iteration
Hypothesis: Invocation 35 should continue the smallest unfinished Task 6 gate: first executable validation of the hardened Q0.24 top-k comparator cutout. If command startup recovered, Verilator would compile and run the RTL/testbench against the checked-in expected-state oracle; if startup remained blocked, the prepared-only state would be preserved and no simulator, Python, synthesis, bitstream, or hardware evidence would be promoted. Result: BLOCKED. Required evidence readback with `sed` still works, but recent-file listing and Verilator still fail before useful work with `bwrap: loopback: Failed RTM_NEWADDR: Operation not permitted`. `apply_patch` and non-interactive sed heredoc writes also failed for the new artifact, so the invocation 35 JSON artifact, run handoff JSON, and this status were written with interactive `sed -n 'w ...'`. No simulator, Python replay, synthesis, bitstream generation, or hardware evidence is promoted.

## Current best evidence
- v1k bounded int8 L2 MLP/residual-add remains the prior checked-in board anchor: simulation PASS, JTAG SELFTEST_PASS, regular bitstream programmed, 10,733 LUT, 6,530 FF, 10 DSP, and 11.0 BRAM36-equivalent.
- v4k bounded MLP/residual plus streamed tied-vocab output-head remains off-board PASS evidence: SV simulation PASS at cycle 265719, no DDR3, routed bitstream exists, 13,629 LUT, 8,845 FF, 14 DSP, 132.0 BRAM36-equivalent, and 77.99 MHz post-route Fmax against 50 MHz.
- v4k tied vocab remains on-chip sized: compact rowwise int8 token plus position storage is 287,232 bytes and 63 BRAM36 ceiling; the current 64-byte payload RTL output-head memory maps to 64 BRAM36 for token payload.
- Full TinyStories f32 tied token plus position storage is 13,390,080 bytes and 2,906 BRAM36 ceiling, so it does not fit on chip. Rowwise int8 is 3,556,740 bytes and 772 BRAM36 ceiling, about 80.84 percent of board BRAM before the rest of the model.
- Full output-head exact top-k scans 50,257 rows, 3,216,448 MACs, 3,417,540 rowwise-int8 top-k stream bytes per token, and 804,112 minimum cycles at 4 DSP lanes.
- The fixed-point top-k budget recommends low-24-bit unsigned Q0.24 sidecar scales, a 46-bit guarded output score register, lower-token-id tie break, and a two-cycle score unit that can be overlapped at 4, 8, and 16 dot-product lanes.
- The Q0.24 expected-state oracle covers 6 sequences and 11 candidate steps: scaled-score ordering, signed ordering, tie-break in both original and reversed candidate order, reserved-sidecar rejection, and conservative bound preservation.
- The Q0.24 comparator RTL/testbench remain prepared/static-readback only: 22-bit signed accumulator, low-24-bit scale sidecar, 47-bit product readback, 46-bit top-score state, lower-token-id tie break, and reserved upper-byte rejection. They still need first simulator validation.
- A v4k board-replay package already exists at `artifacts/task6/parallel-hypotheses/h2-v4k-board-replay-package-prepared.json`; do not duplicate it during no-board invocations.
- This invocation has no board access. Existing board evidence is cited only from checked-in artifacts.

## Accepted/promoted changes
- Recorded invocation 35's blocked Q0.24 validation attempt in `artifacts/task6/parallel-hypotheses/h2-q024-topk-comparator-cutout-validation-blocked-invocation35.json`.
- Updated the autonight handoff artifact at `artifacts/task6/autonight/20260430-002543-task6-codex-night/handoff.json`.
- No RTL, Python replay, synthesis, bitstream, or hardware evidence was promoted.

## Rejected attempts
- Rejected promotion of the hardened Q0.24 comparator to simulator PASS because Verilator could not start.
- `find artifacts/task6/autonight -maxdepth 3 -type f -printf '%T@ %p\n' | sort -nr | head -40` failed with exit code 1: `bwrap: loopback: Failed RTM_NEWADDR: Operation not permitted`.
- `verilator --binary --timing -Wall rtl/task6/task6_q024_topk_score_compare.sv rtl/task6/task6_q024_topk_score_compare_tb.sv` failed with exit code 1: same bwrap loopback error.
- `apply_patch` add of `h2-q024-topk-comparator-cutout-validation-blocked-invocation35.json` failed with exit code 1: `Failed to write file .../h2-q024-topk-comparator-cutout-validation-blocked-invocation35.json`.
- Non-interactive sed heredoc write of the invocation 35 artifact failed with exit code 1: same bwrap loopback error.
- Rejected Python replay, Yosys, synthesis, bitstream generation, board replay, OpenFPGALoader, JTAG, FTDI/MPSSE polling, and any new hardware execution in this no-board run.

## Commands run
- `sed -n '1,220p' AUTONIGHT_STATUS.md`: PASS.
- `sed` reads of `h2-int8-l2-selftest-board-comparison.json`, `h2-v4k-scale-up-summary.json`, and `h2-vocab-memory-surface-score.json`: PASS.
- `find artifacts/task6/autonight -maxdepth 3 -type f -printf '%T@ %p\n' | sort -nr | head -40`: FAIL, exit code 1, bwrap loopback error.
- `sed` reads of prior handoff, invocation34 blocked artifact, Q0.24 expected-state artifact, Q0.24 RTL, and Q0.24 testbench: PASS.
- `verilator --binary --timing -Wall rtl/task6/task6_q024_topk_score_compare.sv rtl/task6/task6_q024_topk_score_compare_tb.sv`: FAIL, exit code 1, bwrap loopback error.
- `apply_patch` add of invocation35 blocked artifact: FAIL, file write failure.
- Non-interactive `sed -n 'w ...'` heredoc write of invocation35 blocked artifact: FAIL, exit code 1, bwrap loopback error.
- Interactive `sed -n 'w artifacts/task6/parallel-hypotheses/h2-q024-topk-comparator-cutout-validation-blocked-invocation35.json'`: PASS.
- Interactive `sed -n 'w artifacts/task6/autonight/20260430-002543-task6-codex-night/handoff.json'`: PASS.
- Interactive `sed -n 'w AUTONIGHT_STATUS.md'`: PASS.

## Files changed
- `AUTONIGHT_STATUS.md`.
- `artifacts/task6/parallel-hypotheses/h2-q024-topk-comparator-cutout-validation-blocked-invocation35.json`.
- `artifacts/task6/autonight/20260430-002543-task6-codex-night/handoff.json`.

## Open risks
- The hardened Q0.24 comparator RTL and testbench remain prepared-only. They have not been compiled, simulated, synthesized, or run on hardware.
- Python, Git, normal listing/glob commands, Verilator, Yosys, `apply_patch`, and non-interactive write commands remain blocked or unreliable under the sandbox loopback/file-write failures.
- Because `git status` is blocked, unrelated user changes may exist and could not be inspected.
- The explicit 47-bit multiply/readback hardening still needs real simulator lint/behavior confirmation.
- Q0.24 sidecar precision still needs real rowwise scale distribution and top-k margin replay across multiple prompts.
- DDR3 bandwidth numbers remain planning estimates; actual usable bandwidth and burst turnaround need controller-specific measurement later.

## Next recommended step
Recover command startup or switch to a cleaner workspace shell. First run `verilator --binary --timing -Wall rtl/task6/task6_q024_topk_score_compare.sv rtl/task6/task6_q024_topk_score_compare_tb.sv` and then `./obj_dir/Vtask6_q024_topk_score_compare_tb`. If it fails, fix only the tiny Q0.24 comparator/testbench and rerun. If it passes, emit `artifacts/task6/parallel-hypotheses/h2-q024-topk-comparator-cutout-result.json`, copy/update the autonight handoff artifact, then add the Python expected-state checker or continue to an 8-sample full-vocab rowwise top-k replay. Do not start DDR3 integration, full TinyStories synthesis, OpenFPGALoader, JTAG, FTDI, or MPSSE commands inside a no-board loop.
