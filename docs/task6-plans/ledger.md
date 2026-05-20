# Task 6 Experiment Ledger (append-only)

Each experiment entry should be added when evidence is produced. Keep this file as
the historical index and leave older rows intact.

| date (Europe/Madrid) | lane | hypothesis_id | plan_id | run_root | status | next |
|---|---|---|---|---|---|---|
| 2026-05-20 | ddr3 | anchor-baseline | plan-2026-05-21-ddr3-tinystories-anchor | artifacts/task6/uberddr3-baseline-flow/seed16-vainilla-2026-05-20/ | PASS | DDR3 baseline consumed from UberDDR3 and treated as active anchor |
| 2026-05-21 | ddr3 | anchor-baseline + fullbeat | plan-2026-05-21-ddr3-tinystories-anchor | artifacts/task6/runs/ | IN_PROGRESS | Run boot + fullbeat + TinyStories gate under active anchor, then promote to stable state if clean |

## Ledger policy

- Append one row per experiment attempt with the same hypothesis or a new hypothesis id.
- Use `status=IN_PROGRESS` until run evidence is verified, then bump to `PASS` or `FAIL`.
- Include a short `next` entry describing the next immediate action.

