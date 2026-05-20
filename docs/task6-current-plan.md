# Task 6 Active Plan (Task 6-Canonical Queue)

This file is kept short. The canonical plan state is in
`docs/task6-plans/active.md`.

- Reviewer-facing strategy history and numeric targets remain in
  `docs/task6-resource-usage-reduction-notes.md`.
- Each experiment should be logged in `docs/task6-plans/ledger.md` and a matching run
  summary under `artifacts/task6/runs/<timestamp>-task6-<lane>-<slug>/summary.json`.

Current gate in this workspace:

- Anchor bitstream: `artifacts/task6/uberddr3-baseline-flow/seed16-vainilla-2026-05-20/ypcb-00338-1p1-ddr3-bist-1lane-full-openxc7.bit`
- Baseline comparison bundle: `artifacts/task6/baselines/tiny-stories-1m-baseline-float-selftest-all-memory-utilization`
- Next immediate gate order: boot-only -> diagnostic-rtl-fullbeat -> rowstream/inference checks.
- Canonical gate runner: `scripts/task6/task6_ypcb_tinystories_inference_gate.py`.

Update cadence:

1. Update `docs/task6-plans/active.md` before a lane switch.
2. Execute run with `scripts/task6/task6_new_experiment.sh` and populate `commands.txt`.
3. Update `docs/task6-plans/ledger.md` immediately after run completion.
4. Commit run artifacts + notes before starting the next experiment.
