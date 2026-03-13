# Hugging Face Model Triage Harness

This folder contains scripts to triage stage failures across many Hugging Face
text-generation models.

## 1) Build a model list (top 100 by downloads)

```bash
python scripts/triage/fetch_top_hf_textgen.py \
  --limit 100 \
  --output /tmp/hf-top100-textgen.tsv
```

The output file is a TSV with `model_id` and pinned `revision` (commit SHA).
It does not include Nix content hashes.

## 1b) Generate a build matrix JSON

```bash
python scripts/triage/generate_build_matrix.py \
  --models scripts/triage/data/hf-top100-textgen.tsv \
  --output scripts/triage/data/hf-top100-build-matrix.json
```

The output is a GitHub Actions-style matrix:

- `include[].name`: stable job-friendly identifier.
- `include[].model_id`: Hugging Face model id.
- `include[].revision`: pinned commit SHA.

The same TSV is consumed by [`nix/models.nix`](../../nix/models.nix) to
auto-generate per-model derivations. After updating the TSV, run:

```bash
nix flake show | rg hf-textgen-
```

You should see hundreds of `hf-textgen-...` package entries (one model across
multiple pipeline stages).

## 1c) Pinned snapshot hash lock

Pinned offline snapshots are described in
[`hf-pinned-snapshots.tsv`](./data/hf-pinned-snapshots.tsv) with columns:

- `model_id`
- `revision`
- `file`
- `hash`

[`nix/hf-pinned-snapshots.nix`](../../nix/hf-pinned-snapshots.nix) consumes this
lock file and constructs `hfPinnedSnapshots` used by the model registry.

## 2) Run stage-by-stage pipeline triage

Run inside the project dev shell:

```bash
nix develop
python scripts/triage/run_hf_pipeline_triage.py \
  --models /tmp/hf-top100-textgen.tsv \
  --out /tmp/hf-triage \
  --stop-stage handshake \
  --timeout-seconds 1800
```

Default stop stage is `handshake`, which is the current known bottleneck for
many larger models. For deeper triage, use `--stop-stage yosys_stat`.

## Artifacts

- `/tmp/hf-triage/summary.jsonl`: full structured per-model results.
- `/tmp/hf-triage/summary.csv`: flattened table for quick sorting/filtering.
- `/tmp/hf-triage/models/<idx>-<model>/result.json`: per-model result.
- `/tmp/hf-triage/models/<idx>-<model>/logs/*.log`: stage logs.

## Resume behavior

`run_hf_pipeline_triage.py` resumes by default and skips models already present
in `summary.jsonl`. Use `--no-resume` to re-run everything.
