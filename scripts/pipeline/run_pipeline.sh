#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/pipeline/run_pipeline.sh <torch-input-mlir> <out-dir>

Required tools via env:
  TORCH_MLIR_OPT, MLIR_OPT, CIRCT_OPT, YOSYS

Optional env:
  HANDSHAKE_INSERT_BUFFERS=1|0 (default: 1)
  PIPELINE_SV_MODE=single|split (default: split)
  YOSYS_LIGHT_MODE=1 to reduce peak memory in sv_to_il/sv_to_yosys_stat
  SKIP_FP_COVERAGE_CHECK=1 to bypass circt_fp_* definition gate
USAGE
}

if [[ $# -ne 2 ]]; then
  usage >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

require_env TORCH_MLIR_OPT
require_env MLIR_OPT
require_env CIRCT_OPT
require_env YOSYS

input="$1"
out_dir="$2"
require_file "$input"
mkdir -p "$out_dir"

linalg="$out_dir/01-linalg.mlir"
cf="$out_dir/02-cf.mlir"
cf_stats="$out_dir/03-cf.stats"
handshake="$out_dir/04-handshake.mlir"
hs_ext="$out_dir/05-hs-ext.mlir"
hw0="$out_dir/06-hw0.mlir"
hw="$out_dir/07-hw.mlir"
hw_clean="$out_dir/08-hw-clean.mlir"
sv="$out_dir/09-output.sv"
sv_split_dir="$out_dir/09-output.split"
sv_split_filelist="$out_dir/09-output.split.f"
fp_prims_auto="$out_dir/09-fp-prims-auto.sv"
il="$out_dir/10-output.il"
yosys_stat="$out_dir/11-yosys-stat.json"

"$SCRIPT_DIR/torch_to_linalg.sh" "$input" "$linalg"
"$SCRIPT_DIR/linalg_to_cf.sh" "$linalg" "$cf"
"$SCRIPT_DIR/cf_stats.sh" "$cf" "$cf_stats"
"$SCRIPT_DIR/cf_to_handshake.sh" "$cf" "$handshake"
"$SCRIPT_DIR/handshake_to_hs_ext.sh" "$handshake" "$hs_ext"
"$SCRIPT_DIR/hs_ext_to_hw0.sh" "$hs_ext" "$hw0"
"$SCRIPT_DIR/hw0_to_hw.sh" "$hw0" "$hw"
"$SCRIPT_DIR/hw_to_hw_clean.sh" "$hw" "$hw_clean"

# Generate auto stubs for circt_fp_* extern modules discovered in the lowered
# HW-clean MLIR. Downstream Yosys steps consume these unless FP_PRIMS_SV is
# explicitly set by the caller.
if [[ -z "${FP_PRIMS_SV:-}" ]]; then
  "$SCRIPT_DIR/gen_fp_stubs_from_mlir.py" "$hw_clean" "$fp_prims_auto"
  export FP_PRIMS_SV="$fp_prims_auto"
fi

sv_mode="${PIPELINE_SV_MODE:-split}"
if [[ "$sv_mode" == "split" ]]; then
  SV_SPLIT_DIR="$sv_split_dir" SV_SPLIT_FILELIST="$sv_split_filelist" \
    "$SCRIPT_DIR/hw_clean_to_sv.sh" "$hw_clean" "$sv"
  sv_input="$sv_split_filelist"
else
  "$SCRIPT_DIR/hw_clean_to_sv.sh" "$hw_clean" "$sv"
  sv_input="$sv"
fi

# Ensure all referenced circt_fp_* cells have module definitions before Yosys.
if [[ "${SKIP_FP_COVERAGE_CHECK:-0}" != "1" ]]; then
  "$SCRIPT_DIR/check_fp_primitive_coverage.sh" "$sv_input"
fi

"$SCRIPT_DIR/sv_to_il.sh" "$sv_input" "$il"
"$SCRIPT_DIR/sv_to_yosys_stat.sh" "$sv_input" "$yosys_stat"

echo "done: $out_dir"
