#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${1:-/tmp/task3-rfp-milestones}"

RUN_BASELINE_MILESTONES="${RUN_BASELINE_MILESTONES:-1}"
RUN_REDUCED_BLOCKERS="${RUN_REDUCED_BLOCKERS:-1}"

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

profile_mlir() {
  local input="$1"
  local prefix="$2"
  python3 "$ROOT_DIR/scripts/pipeline/mlir_op_profile.py" \
    "$input" \
    --json-out "$prefix.json" \
    --text-out "$prefix.txt" >/dev/null
}

record_hw0_failure() {
  local pkg="$1"
  local key_prefix="$2"
  local expected_pattern="$3"
  local log_path="$OUT_DIR/${pkg}-hw0.log"
  local drv_log_path="$OUT_DIR/${pkg}-hw0.drv.log"
  local drv=""
  local first_error=""
  set +e
  nix build ".#${pkg}-hw0" --no-link --print-out-paths >"$log_path" 2>&1
  local rc=$?
  set -e
  if [[ "$rc" -eq 0 ]]; then
    echo "expected ${pkg}-hw0 to fail, but it succeeded" >&2
    exit 1
  fi
  drv="$(grep -m1 "^error: Cannot build '/nix/store/.*${pkg}-hw0\\.mlir\\.drv'\\." "$log_path" \
    | sed -E "s/^error: Cannot build '([^']+)'.*/\\1/")"
  if [[ -n "$drv" ]]; then
    nix log "$drv" >"$drv_log_path" 2>&1 || true
  fi
  first_error="$(python3 - "$drv_log_path" <<'PY'
import re
import sys

ansi = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")
with open(sys.argv[1], "r", encoding="utf-8", errors="replace") as f:
    for line in f:
        clean = ansi.sub("", line.rstrip("\n"))
        if "error: failed to legalize operation" in clean:
            print(clean)
            break
PY
)"
  if [[ -z "$first_error" || "$first_error" != *"$expected_pattern"* ]]; then
    echo "unexpected ${pkg}-hw0 failure; expected pattern ${expected_pattern}" >&2
    exit 1
  fi
  record_kv "${key_prefix}_hw0_log" "$log_path"
  record_kv "${key_prefix}_hw0_drv_log" "$drv_log_path"
  record_kv "${key_prefix}_hw0_status" blocked
  record_kv "${key_prefix}_hw0_drv" "$drv"
  record_kv "${key_prefix}_hw0_first_error" "$first_error"
}

if [[ "$RUN_REDUCED_BLOCKERS" == "1" ]]; then
  linear_cf="$(resolve_pkg pt2e-static-quant-linear-cf)"
  layer_norm_cf="$(resolve_pkg pt2e-static-quant-layer-norm-cf)"
  softmax_cf="$(resolve_pkg pt2e-static-quant-softmax-cf)"

  profile_mlir "$linear_cf" "$OUT_DIR/pt2e-static-quant-linear-cf-profile"
  profile_mlir "$layer_norm_cf" "$OUT_DIR/pt2e-static-quant-layer-norm-cf-profile"
  profile_mlir "$softmax_cf" "$OUT_DIR/pt2e-static-quant-softmax-cf-profile"

  record_hw0_failure \
    "pt2e-static-quant-linear" \
    "milestone_a_linear" \
    "arith.divf"
  record_hw0_failure \
    "pt2e-static-quant-layer-norm" \
    "milestone_a_layer_norm" \
    "arith.addf"
  record_hw0_failure \
    "pt2e-static-quant-softmax" \
    "milestone_a_softmax" \
    "arith.maximumf"

  record_kv milestone_a_status pass
  record_kv milestone_a_acceptance "pinned-standard-path-reproducers-resolve-to-cf-and-fail-at-hw0-on-float-ops"
  record_kv milestone_a_linear_cf "$linear_cf"
  record_kv milestone_a_linear_cf_profile_json "$OUT_DIR/pt2e-static-quant-linear-cf-profile.json"
  record_kv milestone_a_linear_cf_profile_text "$OUT_DIR/pt2e-static-quant-linear-cf-profile.txt"
  record_kv milestone_a_layer_norm_cf "$layer_norm_cf"
  record_kv milestone_a_layer_norm_cf_profile_json "$OUT_DIR/pt2e-static-quant-layer-norm-cf-profile.json"
  record_kv milestone_a_layer_norm_cf_profile_text "$OUT_DIR/pt2e-static-quant-layer-norm-cf-profile.txt"
  record_kv milestone_a_softmax_cf "$softmax_cf"
  record_kv milestone_a_softmax_cf_profile_json "$OUT_DIR/pt2e-static-quant-softmax-cf-profile.json"
  record_kv milestone_a_softmax_cf_profile_text "$OUT_DIR/pt2e-static-quant-softmax-cf-profile.txt"
else
  record_kv milestone_a_status skipped
  record_kv milestone_a_acceptance "reduced-blockers-disabled"
fi

if [[ "$RUN_BASELINE_MILESTONES" == "1" ]]; then
  snapshot_path="$(resolve_pkg tiny-stories-1m-snapshot)"
  cf_path="$(resolve_pkg tiny-stories-1m-cf)"
  sv_path="$(resolve_pkg tiny-stories-1m-sv)"
  il_path="$(resolve_pkg tiny-stories-1m-il)"
  util_log="$OUT_DIR/tiny-stories-1m-utilization.log"
  util_json_log="$OUT_DIR/tiny-stories-1m-utilization-json.log"
  set +e
  util_path="$(nix build .#tiny-stories-1m-utilization --no-link --print-out-paths >"$util_log" 2>&1)"
  util_rc=$?
  util_json_path="$(nix build .#tiny-stories-1m-utilization-json --no-link --print-out-paths >"$util_json_log" 2>&1)"
  util_json_rc=$?
  set -e

  require_path "deliverable 3a snapshot" "$snapshot_path"
  require_path "deliverable 3b pre-CIRCT MLIR" "$cf_path"
  require_path "deliverable 3c SystemVerilog bundle" "$sv_path"
  require_path "deliverable 3d RTLIL" "$il_path"
  require_path "deliverable 3a config" "$snapshot_path/config.json"
  require_path "deliverable 3a weights" "$snapshot_path/pytorch_model.bin"
  require_path "deliverable 3c main.sv" "$sv_path/sv/main.sv"
  require_path "deliverable 3c sources.f" "$sv_path/sources.f"
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
  record_kv deliverable_3e_utilization_log "$util_log"
  record_kv deliverable_3e_mapped_json_log "$util_json_log"

  if [[ "$util_rc" -eq 0 && "$util_json_rc" -eq 0 ]]; then
    require_path "deliverable 3e utilization report" "$util_path"
    require_path "deliverable 3e mapped json" "$util_json_path"
    require_path "deliverable 3e summary.txt" "$util_path/summary.txt"
    require_path "deliverable 3e summary.json" "$util_path/summary.json"
    require_path "deliverable 3e stat.json" "$util_path/stat.json"

    record_kv milestone_b_status pass
    record_kv milestone_b_acceptance "resolved-store-paths-for-3a-through-3e"
    record_kv deliverable_3e_status pass
    record_kv deliverable_3e_utilization_dir "$util_path"
    record_kv deliverable_3e_summary_txt "$util_path/summary.txt"
    record_kv deliverable_3e_summary_json "$util_path/summary.json"
    record_kv deliverable_3e_stat_json "$util_path/stat.json"
    record_kv deliverable_3e_mapped_json "$util_json_path"
  else
    record_kv milestone_b_status blocked-at-3e
    record_kv milestone_b_acceptance "resolved-store-paths-for-3a-through-3d-and-captured-3e-gate-failure"
    record_kv deliverable_3e_status blocked
  fi
else
  snapshot_path="$(resolve_pkg tiny-stories-1m-snapshot)"
  record_kv milestone_b_status skipped
  record_kv milestone_b_acceptance "baseline-disabled"
fi

cat >"$OUT_DIR/README.md" <<EOF
# Task 3 / RfP milestone run

This directory was produced by \`scripts/dev/run-task3-rfp-milestones.sh\`.

## Milestone A: pinned standard-path reduced blockers

- Status: \`$(grep -m1 '^milestone_a_status=' "$OUT_DIR/summary.env" | cut -d= -f2-)\`
- Purpose: reproduce the three pinned standard-path blockers that explain the current canonical gate failure:
  - generic PT2E static quantization boundary legalization
  - layer norm float residue
  - softmax float residue

## Milestone B: pinned baseline deliverables

- Artifact manifest: \`$OUT_DIR/summary.env\`
- Deliverable map: \`3a -> deliverable_3a_*\`, \`3b -> deliverable_3b_*\`, \`3c -> deliverable_3c_*\`, \`3d -> deliverable_3d_*\`, \`3e -> deliverable_3e_*\`
- Status: \`$(grep -m1 '^milestone_b_status=' "$OUT_DIR/summary.env" | cut -d= -f2-)\`
- Purpose: reproduce the current pinned 3a/3b/3c/3d outputs from the flake and record the current canonical \`3e\` gate status for \`tiny-stories-1m-utilization\`.
EOF

printf '%s\n' "$OUT_DIR"
