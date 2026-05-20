# Active Task 6 Plan (Canonical)

**Plan ID:** `plan-2026-05-21-ddr3-tinystories-anchor`
**Status:** in_progress
**Branch:** `task6`
**Current focus:** move from 1-lane DDR3 anchor reproduction to explicit 2-lane anchor replication, then complete TinyStories-1M gate execution on that same anchor.

## 1) Canonical state

- Branch is stable at the active anchor copied from RCoeurjoly/UberDDR3 (`seed16-vainilla-2026-05-20`).
- Active anchor bitstream:
  - `artifacts/task6/uberddr3-baseline-flow/seed16-vainilla-2026-05-20/ypcb-00338-1p1-ddr3-bist-2lanes-full-openxc7.bit`
- Active gate sequence:
  1. `boot-only` clean calibration
  2. `diagnostic-rtl-fullbeat` stability
  3. TinyStories rowstream + boundary readback + optional top-1 replay
- Baseline comparison target (Task 6 strategy metrics):
  - `artifacts/task6/baselines/tiny-stories-1m-baseline-float-selftest-all-memory-utilization`

## 2) Current lane plan

### Lane L0: DDR3 2-lane anchor reproducibility (Priority 0)

- Goal: reproduce the working upstream 2-lane anchor in this repo and confirm board reproducibility.
- Pass criteria:
  - `boot-only` on the active 2-lane anchor has clean calibration (`calib_seen=true`, `boot_done=true`, no errors)
  - deterministic `diagnostic-rtl-fullbeat` at base `0x20`, beat `0`
- Next action:
  1. Initialize run with `scripts/task6/task6_new_experiment.sh --plan-id plan-2026-05-21-ddr3-tinystories-anchor --hypothesis anchor-baseline ddr3 anchor-repro`
  2. Run boot-only using the 2-lane anchored bitstream.
  3. Run deterministic fullbeat sanity once boot passes.

### Lane L1: Mapping contract / rowstream deterministic checks (Priority 1)

- Goal: close deterministic lane/beat contract before attaching inference path.
- Pass criteria:
  - repeated read-only sanity
  - deterministic dense write/read behavior
- Next action:
  - Continue deterministic checks with same run metadata and record results in run summary.

### Lane L2: TinyStories inference gate (Priority 2)

- Goal: complete explicit end-to-end on-board gate.
- Pass criteria:
  - Boot gate clean
  - boundary rows (0,1,31,32,50256) match
  - full readback hash check on selected rowstream payload
  - `top1` pass + zero mismatch (or explicitly documented skip with rationale)
- Next action:
  - run `scripts/task6/task6_ypcb_tinystories_inference_gate.py --byte-lanes 2 --bitstream artifacts/task6/uberddr3-baseline-flow/seed16-vainilla-2026-05-20/ypcb-00338-1p1-ddr3-bist-2lanes-full-openxc7.bit --calib-timeout 120 --run-root <run>`
  - add `--skip-top1` first if model snapshot is not available for that run.
  - save gate summary in the run root and update `ledger.md`.

### Lane L3: Resource reduction (Priority 3)

- Only after Lane L2 produces PASS.
- Keep changes incremental: lane width experiments, constrained cuts, then throughput optimizations.
- Every candidate must preserve:
  - DDR3 anchor cleanliness
  - deterministic fullbeat
  - TinyStories gate evidence

## 3) Update protocol

- Before any new experiment:
  - read `active.md` and `ledger.md`
  - update hypothesis id if scope changes
  - initialize run dir with `task6_new_experiment.sh`
- After evidence lands:
  - record experiment in `ledger.md`
  - update status line in this file (lane and hypothesis)
  - run the full gate before any new branching
- If an experiment fails, keep plan state unchanged unless it changes the anchor contract.

## 4) Commands

- Boot-only:
  - `/usr/bin/python3 scripts/task6/task6_ddr3_rowstream_loader.py --bitstream artifacts/task6/uberddr3-baseline-flow/seed16-vainilla-2026-05-20/ypcb-00338-1p1-ddr3-bist-2lanes-full-openxc7.bit --byte-lanes 2 --program --boot-only --calib-timeout 120 --json-only`
- fullbeat gate:
  - `/usr/bin/python3 scripts/task6/task6_ddr3_rowstream_loader.py --bitstream .../ypcb-00338-1p1-ddr3-bist-2lanes-full-openxc7.bit --byte-lanes 2 --run-dir artifacts/task6/runs/<run>/diagnostic-fullbeat --diagnostic-rtl-fullbeat-base 0x20 --diagnostic-rtl-fullbeat-addr 0 --json-only`
- TinyStories gate:
  - `/usr/bin/python3 scripts/task6/task6_ypcb_tinystories_inference_gate.py --byte-lanes 2 --bitstream .../ypcb-00338-1p1-ddr3-bist-2lanes-full-openxc7.bit --calib-timeout 120 --skip-top1 --json-only`

## 5) Canonical doc map

- This file is now the canonical plan pointer for status and next steps.
- Long historical detail and numeric targets remain in:
  - `docs/task6-resource-usage-reduction-notes.md`
- Experimental run metadata is persisted in each run folder:
  - `artifacts/task6/runs/<timestamp>-task6-<lane>-<slug>/summary.json`
