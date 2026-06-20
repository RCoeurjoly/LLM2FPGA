# Agent Rules

- Make short commits for each coherent piece of work. Commit each distinct
  change before starting the next distinct change so project history stays
  traceable.
- Before editing, check `git status --short` and do not overwrite unrelated user changes.
- Keep `docs/project-plan*` unchanged unless the user says reviewer approval was obtained.
- Keep detailed Task 6 notes in `docs/task6-resource-usage-reduction-notes.md`.
- Update `docs/task6-crisp-state.org` and `docs/task6-crisp-state.json` whenever milestone, bottleneck, failure signature, or next action changes.
- If a HIL/board gate fails, first try to reproduce the same public-interface
  failure in simulation. If simulation passes while HIL fails, treat the
  simulation as incomplete or unfaithful to the implemented hardware boundary
  and extend the sim/diagnostic boundary before changing milestone status.
- Treat DDR3-backed TinyStories-1M inference as the main completion route.
- Treat BRAM-only/on-chip targets as diagnostics or regressions unless the user changes priority.
- Every final work report must include verification commands run, or explicitly say what was not run.
