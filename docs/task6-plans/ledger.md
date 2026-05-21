# Task 6 Experiment Ledger (append-only)

Current live plan is in `docs/task6-current-plan.md`. This file is historical, append-only evidence only.

Each experiment entry should be added when evidence is produced. Keep this file as
the historical index and leave older rows intact.

| date (Europe/Madrid) | lane | hypothesis_id | plan_id | run_root | status | next |
|---|---|---|---|---|---|---|
| 2026-05-20 | ddr3 | anchor-baseline | plan-2026-05-21-ddr3-tinystories-anchor | artifacts/task6/uberddr3-baseline-flow/seed16-vainilla-2026-05-20/ | PASS | DDR3 baseline consumed from UberDDR3 and treated as active anchor |
| 2026-05-21 | ddr3 | anchor-baseline | plan-2026-05-21-ddr3-tinystories-anchor | artifacts/task6/runs/20260521T120000-task6-ddr3-2lane-repro | FAIL | Boot gate timed out waiting for DDR3 calib on bytelanes=2; power-cycle board and retry with same 2-lane bitstream + 240s timeout. |
| 2026-05-21 | ddr3 | anchor-baseline | plan-2026-05-21-ddr3-tinystories-anchor | artifacts/task6/runs/20260520T194357-task6-ddr3-anchor-repro | FAIL | Board reachable via openFPGALoader, but DDR3 calibration timed out twice. Power-cycle board and rerun this run path. |
| 2026-05-21 | ddr3 | ddr3-1lane-clocked-333mhz | plan-2026-05-21-ddr3-tinystories-anchor | artifacts/task6/runs/20260521T000000-ddr3-333fix | BLOCKED | Program step reached 100% but openFPGALoader could not claim USB FTDI device; retry once USB/JTAG ownership is clear. |

## Ledger policy

- Append one row per experiment attempt with the same hypothesis or a new hypothesis id.
- Use `status=IN_PROGRESS` until run evidence is verified, then bump to `PASS` or `FAIL`.
- Include a short `next` entry describing the next immediate action.
