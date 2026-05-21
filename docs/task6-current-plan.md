# Task 6 Canonical Plan (ts1m to YPCB)

## Mission

Bring **TinyStories-1M** (`ts1m`) inference to YPCB in one coherent production path:
- int8 quantization
- StreamTensor-lite runtime extraction
- externalized DDR3 rowstream transport
- deterministic boot + diagnostics contract
- complete on-board inference gate

Completing this closes Task 6 and closes the practical Task 4 gap in this branch.

## Current state (2026-05-21)

- Canonical branch: `task6-ddr3`
- Live anchor: `artifacts/task6/uberddr3-baseline-flow/seed16-vainilla-2026-05-20/ypcb-00338-1p1-ddr3-bist-1lane-full-openxc7.bit`
- Baseline bundle for comparison: `artifacts/task6/baselines/tiny-stories-1m-baseline-float-selftest-all-memory-utilization`
- Known-good board signal: boot-only with 960-bit decode (`boot_done=True`, `boot_mismatch=False`, `calib_seen=True`).

## What is complete

1. int8 quantization path is in place and used as the active execution format.
2. StreamTensor-lite execution flow is operational.
3. DDR3 externalization and rowstream transport are reproducing and committed.

## Exact sequence to finish (in order)

1. `boot-only`
2. `diagnostic-rtl-fullbeat` (base 0x20, beat 0)
3. `tiny-stories-boundary`
4. `tiny-stories-top1`

Do not advance to the next gate until the current gate is PASS.

## Commands to use now

- `python3 scripts/task6/task6_new_experiment.sh --simple ts1m-inference-bootstrap`
- `python3 scripts/task6/task6_ddr3_rowstream_loader.py --bitstream <bit> --boot-only --debug-bits 960 --run-dir artifacts/task6/runs/<run>/boot-only`
- `python3 scripts/task6/task6_ddr3_rowstream_loader.py --bitstream <bit> --run-dir artifacts/task6/runs/<run>/fullbeat --diagnostic-rtl-fullbeat-base 0x20 --diagnostic-rtl-fullbeat-addr 0 --json-only`
- `python3 scripts/task6/task6_ypcb_tinystories_inference_gate.py --byte-lanes 1 --bitstream <bit> --run-dir artifacts/task6/runs/<run> --run-inference`

## Sources of truth

- Current plan and immediate next action: this file (`docs/task6-current-plan.md`)
- Experiment history (append-only): `docs/task6-plans/ledger.md`
- Metrics + baseline context: `docs/task6-resource-usage-reduction-notes.md`
- Build/run artifacts: `artifacts/task6/`

## Plan rules

- One active hypothesis/strategy at a time.
- Record every failed/successful gate in `docs/task6-plans/ledger.md`.
- Keep one lane (`byte-lanes=1`) for now; expand after all gates are PASS.
- Keep every hardware command deterministic and logged in run `commands.txt`.
