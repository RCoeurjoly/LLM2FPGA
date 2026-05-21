# Active Task 6 Plan (Canonical)

**Plan ID:** `plan-2026-05-21-ddr3-tinystories-anchor`
**Status:** in_progress
**Branch:** `task6`
**Current focus:** finalize the 1-lane DDR3 clock-domain alignment variant and then validate board reproducibility, with 2-lane anchor as fallback.

## 1) Canonical state

- Branch is stable at the active anchor copied from RCoeurjoly/UberDDR3 (`seed16-vainilla-2026-05-20`).
- Active anchor bitstreams:
  - `2-lane`: `artifacts/task6/uberddr3-baseline-flow/seed16-vainilla-2026-05-20/ypcb-00338-1p1-ddr3-bist-2lanes-full-openxc7.bit`
  - `1-lane clocked candidate`: `/nix/store/c9sn6zp8530sn5m3bxnxbq4b97yy2kiz-task6-ypcb-uberddr3-rowstream-loader-1lane-seed16-clocked.bit`
- Latest 1-lane run root:
  - `artifacts/task6/runs/20260521T000000-ddr3-333fix` (program loaded, FTDI open-device claim currently failing; no gate summary yet)
- Active gate sequence:
  1. `boot-only` clean calibration
  2. `diagnostic-rtl-fullbeat` stability
  3. TinyStories rowstream + boundary readback + optional top-1 replay
- Baseline comparison target (Task 6 strategy metrics):
  - `artifacts/task6/baselines/tiny-stories-1m-baseline-float-selftest-all-memory-utilization`

## 2) Current lane plan

### Lane L0: DDR3 1-lane clock-domain alignment (Priority 0)

- Goal: produce a reproducible 1-lane DDR3 anchor with explicit 333 MHz DDR3 clocking behavior and confirm board boot stability.
- Pass criteria:
  - `boot-only` on the 1-lane clocked bitstream has clean calibration (`calib_seen=true`, `boot_done=true`, no errors)
  - deterministic `diagnostic-rtl-fullbeat` at base `0x20`, beat `0`
- Next action:
  1. Retry board run with current 1-lane clocked bitstream as soon as FTDI becomes available:
     - `python3 scripts/task6/task6_ypcb_tinystories_inference_gate.py --byte-lanes 1 --bitstream /nix/store/c9sn6zp8530sn5m3bxnxbq4b97yy2kiz-task6-ypcb-uberddr3-rowstream-loader-1lane-seed16-clocked.bit --serial 210299BF3824 --jtag-cable digilent_hs3 --calib-timeout 240 --run-root artifacts/task6/runs/<new-run> --plan-id plan-2026-05-21-ddr3-tinystories-anchor --hypothesis-id ddr3-1lane-clocked-333mhz`

### Lane L1: DDR3 2-lane anchor reproducibility (Priority 1)

- Goal: keep the working upstream 2-lane baseline reproducible in this repo and confirm board state.
- Pass criteria:
  - `boot-only` on the active 2-lane anchor has clean calibration (`calib_seen=true`, `boot_done=true`, no errors)
  - deterministic `diagnostic-rtl-fullbeat` at base `0x20`, beat `0`
- Next action:
  1. Initialize run with `scripts/task6/task6_new_experiment.sh --plan-id plan-2026-05-21-ddr3-tinystories-anchor --hypothesis anchor-baseline ddr3 anchor-repro`
  2. Run boot-only using the 2-lane anchored bitstream.
  3. Run deterministic fullbeat sanity once boot passes.

### Lane L2: Mapping contract / rowstream deterministic checks (Priority 2)

- Goal: close deterministic lane/beat contract before attaching inference path.
- Pass criteria:
  - repeated read-only sanity
  - deterministic dense write/read behavior
- Next action:
  - Continue deterministic checks with same run metadata and record results in run summary.

### Lane L3: TinyStories inference gate (Priority 3)

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

### Lane L4: Resource reduction (Priority 4)

- Only after Lane L3 produces PASS.
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
- 1-lane clocked boot-only candidate:
  - `/usr/bin/python3 scripts/task6/task6_ypcb_tinystories_inference_gate.py --byte-lanes 1 --bitstream /nix/store/c9sn6zp8530sn5m3bxnxbq4b97yy2kiz-task6-ypcb-uberddr3-rowstream-loader-1lane-seed16-clocked.bit --serial 210299BF3824 --jtag-cable digilent_hs3 --calib-timeout 240 --run-root artifacts/task6/runs/<run> --plan-id plan-2026-05-21-ddr3-tinystories-anchor --hypothesis-id ddr3-1lane-clocked-333mhz --skip-fullbeat --skip-inference`
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
