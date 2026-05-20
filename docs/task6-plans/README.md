# Task 6 Plan System

This folder is the canonical in-repo control plane for Task 6 work.

## Files

- `active.md` is the single source of truth for the current plan.
- `ledger.md` is the append-only experimental ledger.

## How to use

1. Edit `active.md` when switching direction or after each lane decision.
2. Record every executed/observed experiment in `ledger.md`.
3. Use `scripts/task6/task6_new_experiment.sh` for every new run directory so each run
   captures:
   - lane
   - hypothesis id
   - plan id
   - command log pointer
   - gate-by-gate status placeholders
4. Prefer keeping `active.md` and `ledger.md` up to date before the next hardware or
   synthesis action, and never the opposite.

