# Repo Guidance

- `docs/project-plan*` are reviewer-controlled. Do not edit them unless the user explicitly says reviewer approval has been obtained.
- Keep Task 6 planning details in [docs/task6-resource-usage-reduction-notes.md](docs/task6-resource-usage-reduction-notes.md), not in the project plan.
- This workspace is also being used for Task 3 cleanup. Prefer changes that keep reviewer-facing docs stable unless the user explicitly asks otherwise.
- If Task 6 work later grows beyond a short note, keep this file concise and extend the task-specific notes file instead.
- Task 6 strategy evaluations must compare against the copied baseline bundle at [artifacts/task6/baselines/tiny-stories-1m-baseline-float-selftest-all-memory-utilization](artifacts/task6/baselines/tiny-stories-1m-baseline-float-selftest-all-memory-utilization), not a Nix store path that may disappear after garbage collection.
- If Task 6 strategy work is split across parallel repos, prefer separate `git worktree`s or branches derived from `task6` over deleting and recloning the main workspace.
- This worktree is the board RAM lane. Prioritize [docs/task6-lane.md](docs/task6-lane.md) before making changes.
