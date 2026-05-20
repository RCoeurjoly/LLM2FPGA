# Task 6 Plan (DDR3 Diagnostics, Fullbeat Timing, Resource Reduction)

Goal: keep board-safe Task 6 work moving with clear, fast gates until `diagnostic-rtl-fullbeat` is stable, then continue lane/resource optimization.

## 1) Plan scope

- Keep all high-velocity Task 6 decision notes in this file.
- Preserve long history and reviewer-facing rationale in
  `docs/task6-resource-usage-reduction-notes.md`.
- Compare strategy baselines against
  `artifacts/task6/baselines/tiny-stories-1m-baseline-float-selftest-all-memory-utilization`.
- Use absolute bitstream paths for hardware runs.
- Use `/usr/bin/python3` for loader execution.

## 2) Current status snapshot

- Consumed the working upstream UberDDR3 work from `~/UberDDR3_vainilla`.
- Active hardware anchor is now the copied one-lane full-bank BIST baseline:
  - `artifacts/task6/uberddr3-baseline-flow/seed16-vainilla-2026-05-20/`
  - `artifacts/task6/uberddr3-baseline-flow/seed16-vainilla-2026-05-20/ypcb-00338-1p1-ddr3-bist-1lane-full-openxc7.bit`
- Evidence in `~/UberDDR3_vainilla/example_demo/ypcb_00338_1p1/ypcb_status_and_plan.org` (2026-05-20):
  - `openxc7_bist_1lane_full` whole-bank pass: `wrong_low=0x00` in all samples.
  - Calibration completed (`calib_complete=1`) with final state `23` (DONE_CALIBRATE).
  - Write/read request fields indicate full one-lane range: `write_addr=0x1ffffff`, `read_addr=0x1800000`, `calib_addr=0x1ffffff`.
- The branch already contains the required flake/lock and baseline bundle updates to run this flow.

## 3) Execution lanes (order)

Lane A — board-safe DDR3 anchor gate
1. Run `boot-only` with the active one-lane full-bank baseline bitstream.
2. Confirm clean calibration (`calib_seen=true`, boot done, no loader/WB errors).
3. Run compact deterministic lane/data checks before any rowstream or tinyStories work.

Lane B — rowstream contract recovery
1. Keep data-path command wiring as-is and close the byte/beat mapping contract in RTL.
2. Use D0/D1/D2 style checks from the notes file as gating sequence:
   - boot clean
   - repeated read-only beat
   - deterministic dense-write/read

Lane C — YPCB TinyStories inference gate
1. Keep the one-lane full-bank BIST anchor as the source of truth for memory stability.
2. Run `--diagnostic-rtl-fullbeat` on a small deterministic pattern (for example `0x20` and beat `0`) and confirm readback deltas/mismatch are clean.
3. Execute a full rowstream load + low-byte full-readback path, then compute board read-back top1 against the TinyStories replay contract.
4. Treat inference as pass only when:
   - boot gate is clean,
   - boundary rows `0, 1, 31, 32, 50256` match,
   - full readback matches the rowstream,
   - top1 mismatch count is `0`.

Lane D — resource-reduction progression
1. Only after Lane C passes on the active anchor:
   1) run one-lane timing experiments
   2) connect constrained small weight cuts
   3) widen lanes only if contract remains stable.

## 4) Commands for the next safe pass

1. `openFPGALoader --scan-usb`
2. `/usr/bin/python3 scripts/task6/task6_ddr3_rowstream_loader.py --bitstream artifacts/task6/uberddr3-baseline-flow/seed16-vainilla-2026-05-20/ypcb-00338-1p1-ddr3-bist-1lane-full-openxc7.bit --program --boot-only --calib-timeout 120 --json-only`
3. If calibration repeats fail, force a board power-cycle and rerun step 2 once.
4. On a clean pass, run:
   `/usr/bin/python3 scripts/task6/task6_ddr3_rowstream_loader.py --bitstream artifacts/task6/uberddr3-baseline-flow/seed16-vainilla-2026-05-20/ypcb-00338-1p1-ddr3-bist-1lane-full-openxc7.bit --run-dir artifacts/task6/runs/$(date -Iseconds)-task6-ddr3-anchor-check --diagnostic-rtl-fullbeat-base 0x20 --diagnostic-rtl-fullbeat-addr 0 --json-only`
5. On a clean anchor and full-beat gate, run the TinyStories inference check:
   `/usr/bin/python3 scripts/task6/task6_ddr3_rowstream_loader.py --bitstream artifacts/task6/uberddr3-baseline-flow/seed16-vainilla-2026-05-20/ypcb-00338-1p1-ddr3-bist-1lane-full-openxc7.bit --run-dir artifacts/task6/runs/$(date -Iseconds)-task6-ddr3-tinystories-inference --storage-mode lowbyte --run-inference --top1-from-model --model-path /path/to/tiny-stories-1m-full-model --adapter-path /path/to/model_adapter_representative_core.py --sample-count 8 --boundary-tokens 0,1,31,32,50256 --json-only --calib-timeout 120`

## 5) Exit conditions

- `boot-only` gate is clean on the active one-lane anchor bitstream.
- `diagnostic-rtl-fullbeat` repeats cleanly without calibration regressions.
- `fullbeat_write_ack_delta` and `fullbeat_read_ack_delta` become stable and align with expected behavior.
- TinyStories inference gate pass on the one-lane anchor:
  - boot gate clean,
  - boundary rows all match,
  - full readback hashes match,
  - `top1` status is `PASS`,
  - and no new memory/mapping regressions in `summary.json`.
- Then progress to rowstream-to-DDR3 and resource-reduction edits.

## Automated inference gate launcher

- Use this one-command runner for the current YPCB TinyStories-1M DDR3 gate:
  `/usr/bin/python3 scripts/task6/task6_ypcb_tinystories_inference_gate.py --model-path /path/to/tiny-stories-1m-full-model --adapter-path TinyStories/model_adapter_representative_core.py --calib-timeout 120`
- This script runs boot-only, RTL fullbeat sanity, then full TinyStories inference in that order and writes `run_root/gate-summary.json` with per-step pass/fail payloads.

## Execution protocol (sync with task6 resource notes)

- Gate order: `boot-only → diagnostic-rtl-fullbeat → deterministic checks → TinyStories
  inference → resource gate`.
- Use `artifacts/task6/runs/<timestamp>-task6-<lane>-<slug>/` for each experiment.
- Initialize with `scripts/task6/task6_new_experiment.sh` and fill `commands.txt` +
  `summary.json` before execution.
- Keep this plan file as short-term queue and mirror all evidence/checkpoint
  updates in `docs/task6-resource-usage-reduction-notes.md`.
