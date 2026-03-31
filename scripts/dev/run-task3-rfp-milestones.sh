#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${1:-/tmp/task3-rfp-milestones}"

TORCH_MLIR_OPT="${TORCH_MLIR_OPT:-/home/roland/torch-mlir/build-local-devshell-2/bin/torch-mlir-opt}"
RUN_BASELINE_MILESTONES="${RUN_BASELINE_MILESTONES:-1}"
RUN_FRONTIER_SMOKE="${RUN_FRONTIER_SMOKE:-1}"

mkdir -p "$OUT_DIR"

resolve_pkg() {
  nix build ".#$1" --no-link --print-out-paths
}

record_kv() {
  local key="$1"
  local value="$2"
  printf "%s=%q\n" "$key" "$value" >>"$OUT_DIR/summary.env"
}

require_path() {
  local label="$1"
  local path="$2"
  if [[ ! -e "$path" ]]; then
    echo "missing expected path for $label: $path" >&2
    exit 1
  fi
}

: >"$OUT_DIR/summary.env"
printf '# shell-safe summary; use: source "%s"\n' "$OUT_DIR/summary.env" >>"$OUT_DIR/summary.env"

python_torchao="$(resolve_pkg python-with-torchao)"
python_tinystories_torchao="$(resolve_pkg python-with-tiny-stories-torchao)"

record_kv python_torchao "$python_torchao"
record_kv python_tinystories_torchao "$python_tinystories_torchao"
record_kv torch_mlir_opt "$TORCH_MLIR_OPT"

attention_linalg="$OUT_DIR/torchao-attention-block-linalg.mlir"
PYTHON_BIN="$python_torchao/bin/python" \
  "$ROOT_DIR/scripts/dev/build-linalg-local-from-adapter.sh" \
  "$ROOT_DIR/src/torchao_attention_block_adapter.py" \
  "$attention_linalg"

python3 "$ROOT_DIR/scripts/pipeline/mlir_op_profile.py" \
  "$attention_linalg" \
  --json-out "$OUT_DIR/torchao-attention-block-profile.json" \
  --text-out "$OUT_DIR/torchao-attention-block-profile.txt" >/dev/null

record_kv milestone_a_artifact "$attention_linalg"
record_kv milestone_a_profile_json "$OUT_DIR/torchao-attention-block-profile.json"
record_kv milestone_a_profile_text "$OUT_DIR/torchao-attention-block-profile.txt"
record_kv milestone_a_status pass
record_kv milestone_a_acceptance "mixed-int-float-linalg-profile"

if [[ "$RUN_BASELINE_MILESTONES" == "1" ]]; then
  snapshot_path="$(resolve_pkg tiny-stories-1m-snapshot)"
  cf_path="$(resolve_pkg tiny-stories-1m-cf)"
  sv_path="$(resolve_pkg tiny-stories-1m-sv)"
  il_path="$(resolve_pkg tiny-stories-1m-il)"
  util_path="$(resolve_pkg tiny-stories-1m-utilization)"
  util_json_path="$(resolve_pkg tiny-stories-1m-utilization-json)"

  require_path "deliverable 3a snapshot" "$snapshot_path"
  require_path "deliverable 3b pre-CIRCT MLIR" "$cf_path"
  require_path "deliverable 3c SystemVerilog bundle" "$sv_path"
  require_path "deliverable 3d RTLIL" "$il_path"
  require_path "deliverable 3e utilization report" "$util_path"
  require_path "deliverable 3e mapped json" "$util_json_path"
  require_path "deliverable 3a config" "$snapshot_path/config.json"
  require_path "deliverable 3a weights" "$snapshot_path/pytorch_model.bin"
  require_path "deliverable 3c main.sv" "$sv_path/sv/main.sv"
  require_path "deliverable 3c sources.f" "$sv_path/sources.f"
  require_path "deliverable 3e summary.txt" "$util_path/summary.txt"
  require_path "deliverable 3e summary.json" "$util_path/summary.json"
  require_path "deliverable 3e stat.json" "$util_path/stat.json"

  record_kv milestone_b_status pass
  record_kv milestone_b_acceptance "resolved-store-paths-for-3a-through-3e"
  record_kv deliverable_3a_gate "nix build .#tiny-stories-1m-snapshot -L"
  record_kv deliverable_3a_snapshot "$snapshot_path"
  record_kv deliverable_3a_config "$snapshot_path/config.json"
  record_kv deliverable_3a_weights "$snapshot_path/pytorch_model.bin"
  record_kv deliverable_3b_gate "nix build .#tiny-stories-1m-cf -L"
  record_kv deliverable_3b_mlir "$cf_path"
  record_kv deliverable_3c_gate "nix build .#tiny-stories-1m-sv -L"
  record_kv deliverable_3c_sv_dir "$sv_path"
  record_kv deliverable_3c_main_sv "$sv_path/sv/main.sv"
  record_kv deliverable_3c_sources_f "$sv_path/sources.f"
  record_kv deliverable_3d_gate "nix build .#tiny-stories-1m-il -L"
  record_kv deliverable_3d_il "$il_path"
  record_kv deliverable_3e_gate "nix build .#tiny-stories-1m-utilization -L"
  record_kv deliverable_3e_utilization_dir "$util_path"
  record_kv deliverable_3e_summary_txt "$util_path/summary.txt"
  record_kv deliverable_3e_summary_json "$util_path/summary.json"
  record_kv deliverable_3e_stat_json "$util_path/stat.json"
  record_kv deliverable_3e_mapped_json "$util_json_path"
else
  snapshot_path="$(resolve_pkg tiny-stories-1m-snapshot)"
  record_kv milestone_b_status skipped
  record_kv milestone_b_acceptance "baseline-disabled"
fi

frontier_status="skipped"
frontier_reason=""
if [[ "$RUN_FRONTIER_SMOKE" == "1" ]]; then
  if [[ -x "$TORCH_MLIR_OPT" ]]; then
    mlir_pkg="$(resolve_pkg torch-mlir-mlir)"
    circt_pkg="$(resolve_pkg circt)"

    tinystories_linalg="$OUT_DIR/tiny-stories-1m-torchao-linalg.mlir"
    tinystories_cf="$OUT_DIR/tiny-stories-1m-torchao-cf.mlir"
    tinystories_handshake="$OUT_DIR/tiny-stories-1m-torchao-handshake.mlir"
    tinystories_hs_ext="$OUT_DIR/tiny-stories-1m-torchao-hs-ext.mlir"
    tinystories_hw0="$OUT_DIR/tiny-stories-1m-torchao-hw0.mlir"
    tinystories_hw0_stderr="$OUT_DIR/tiny-stories-1m-torchao-hw0.stderr.txt"

    PYTHON_BIN="$python_tinystories_torchao/bin/python" MODEL_PATH="$snapshot_path" \
      "$ROOT_DIR/scripts/dev/build-linalg-local-from-adapter.sh" \
      "$ROOT_DIR/TinyStories/model_adapter_torchao.py" \
      "$tinystories_linalg"

    "$ROOT_DIR/scripts/pipeline/linalg_to_cf.sh" \
      "$mlir_pkg/bin/mlir-opt" \
      "$tinystories_linalg" \
      "$tinystories_cf"

    "$ROOT_DIR/scripts/pipeline/cf_to_handshake.sh" \
      "$circt_pkg/bin/circt-opt" \
      "$mlir_pkg/bin/mlir-opt" \
      "$tinystories_cf" \
      "$tinystories_handshake"

    "$ROOT_DIR/scripts/pipeline/handshake_to_hs_ext.sh" \
      "$circt_pkg/bin/circt-opt" \
      "$tinystories_handshake" \
      "$tinystories_hs_ext"

    python3 "$ROOT_DIR/scripts/pipeline/mlir_op_profile.py" \
      "$tinystories_hs_ext" \
      --json-out "$OUT_DIR/tiny-stories-1m-torchao-hs-ext-profile.json" \
      --text-out "$OUT_DIR/tiny-stories-1m-torchao-hs-ext-profile.txt" >/dev/null

    set +e
    "$ROOT_DIR/scripts/pipeline/hs_ext_to_hw0.sh" \
      "$circt_pkg/bin/circt-opt" \
      "$tinystories_hs_ext" \
      "$tinystories_hw0" 2>"$tinystories_hw0_stderr"
    hw0_rc=$?
    set -e

    if [[ "$hw0_rc" -eq 0 ]]; then
      frontier_status="unexpected-success"
      frontier_reason="hs-ext_to_hw0 completed successfully"
      record_kv tiny_stories_torchao_hw0 "$tinystories_hw0"
      record_kv milestone_c_status unexpected-success
      record_kv milestone_c_acceptance "frontier-advanced-past-hw0"
    else
      frontier_status="expected-hw0-failure"
      frontier_reason="$(grep -m1 -E "error:|failed" "$tinystories_hw0_stderr" || true)"
      record_kv milestone_c_status pass
      record_kv milestone_c_acceptance "reached-hs-ext-and-failed-at-hw0-on-float-residue"
    fi

    record_kv tiny_stories_torchao_linalg "$tinystories_linalg"
    record_kv tiny_stories_torchao_cf "$tinystories_cf"
    record_kv tiny_stories_torchao_handshake "$tinystories_handshake"
    record_kv tiny_stories_torchao_hs_ext "$tinystories_hs_ext"
    record_kv tiny_stories_torchao_hs_ext_profile_json "$OUT_DIR/tiny-stories-1m-torchao-hs-ext-profile.json"
    record_kv tiny_stories_torchao_hs_ext_profile_text "$OUT_DIR/tiny-stories-1m-torchao-hs-ext-profile.txt"
    record_kv tiny_stories_torchao_hw0_stderr "$tinystories_hw0_stderr"
  else
    frontier_reason="local TORCH_MLIR_OPT not found: $TORCH_MLIR_OPT"
    record_kv milestone_c_status skipped
    record_kv milestone_c_acceptance "local-torch-mlir-opt-missing"
  fi
else
  record_kv milestone_c_status skipped
  record_kv milestone_c_acceptance "frontier-disabled"
fi

record_kv frontier_status "$frontier_status"
record_kv frontier_reason "$frontier_reason"

cat >"$OUT_DIR/README.md" <<EOF
# Task 3 / RfP milestone run

This directory was produced by \`scripts/dev/run-task3-rfp-milestones.sh\`.

## Milestone A: local fast-loop TorchAO attention block

- Artifact: \`$attention_linalg\`
- Op profile: \`$OUT_DIR/torchao-attention-block-profile.txt\`
- Status: \`pass\`
- Purpose: reproduce the current small-model fast loop that still isolates the remaining float-heavy families.

## Milestone B: pinned baseline deliverables

- Artifact manifest: \`$OUT_DIR/summary.env\`
- Deliverable map: \`3a -> deliverable_3a_*\`, \`3b -> deliverable_3b_*\`, \`3c -> deliverable_3c_*\`, \`3d -> deliverable_3d_*\`, \`3e -> deliverable_3e_*\`
- Purpose: reproduce the current pinned 3a/3b/3c/3d/3e Task 3 outputs from the flake, with \`3e\` anchored to the canonical Yosys-backed \`tiny-stories-1m-utilization\` path.

## Milestone C: local TinyStories TorchAO downstream smoke

- Status: \`$frontier_status\`
- Detail: \`$frontier_reason\`
- HS-ext profile: \`$OUT_DIR/tiny-stories-1m-torchao-hs-ext-profile.txt\`
- Purpose: with a local patched \`torch-mlir-opt\`, confirm whether the TinyStories TorchAO path reaches \`hs-ext\` and whether \`hs-ext -> hw0\` still fails on float-heavy residue.
EOF

printf '%s\n' "$OUT_DIR"
