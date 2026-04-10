# LLM2FPGA Agent Guide

Use this file as the durable default for repo-local Codex work.

## Repo layout

- `docs/`: project plans, Task 3 contract notes, reviewer docs
- `nix/`: model registry and pipeline derivations
- `scripts/pipeline/`: stage-by-stage lowering helpers
- `TinyStories/` and `src/`: model adapters and frontend code
- `rtl/`: handwritten or appended SV support files

If a plain-text and Org copy of the same planning doc both exist, update both:
- `docs/project-plan_v2.org`
- `docs/project-plan_v2`

## Task 3 source of truth

Use these files first:
- `docs/task3-brief-2026-04-10.org`
- `docs/task3-reviewer-checklist-2026-04-10.org`

Older Task 3 docs may contain historical detail, but they should not override
the brief above. If a Task 3 claim changes, update the brief, the checklist,
and any README text that points reviewers at the current flow.

## Task 3 working rules

- Keep the core path within standard, explainable PyTorch and compiler flows.
- Prefer `torch.export.export(...)` plus `torch_mlir.fx.export_and_import(...)`.
- Use real passes from `torch-mlir`, `mlir`, `circt`, and `yosys`.
- Do not use `perl`, `sed`, or ad hoc text rewriting in the canonical path.
- Temporary stubs or externs are acceptable only if they are explicit,
  documented, and not counted as final completion unless implemented or
  rejected with a precise error.
- Oversized designs and Yosys capacity limits are valid Task 3 findings.
  Partitioned execution strategy belongs to later tasks unless the task
  definition is explicitly changed.

## Common commands

- `nix build .#tiny-stories-1m-baseline-float-sv -L`
- `nix build .#tiny-stories-1m-baseline-float-il -L --no-link`
- `nix build .#tiny-stories-1m-baseline-float-yosys-stat -L --no-link`
- `bash -n scripts/pipeline/common.sh`
- `bash -n scripts/pipeline/sv_to_il.sh`
- `bash -n scripts/pipeline/sv_to_yosys_stat.sh`

## Done means

For Task 3 work, do not stop at code changes alone. Update the Task 3 brief or
checklist when the reviewer-facing claim changes, run the relevant build or
shell checks, and record whether the result is:
- a successful artifact, or
- an explicit reproducible blocker

The important failure mode is a hidden or ambiguous failure. The acceptable
failure mode is a clear, reproducible blocker tied to a specific stage.
