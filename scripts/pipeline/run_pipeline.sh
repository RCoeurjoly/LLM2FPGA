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
  ALLOW_HW_EXTERNS=1 to bypass extern-module gate (debug only)
  ALLOW_SV_BLACKBOXES=1 to bypass SV blackbox gate (debug only)
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

sv_mode="${PIPELINE_SV_MODE:-split}"
if [[ "$sv_mode" == "split" ]]; then
  SV_SPLIT_DIR="$sv_split_dir" SV_SPLIT_FILELIST="$sv_split_filelist" \
    "$SCRIPT_DIR/hw_clean_to_sv.sh" "$hw_clean" "$sv"
  sv_input="$sv_split_filelist"
else
  "$SCRIPT_DIR/hw_clean_to_sv.sh" "$hw_clean" "$sv"
  sv_input="$sv"
fi

if [[ "${ALLOW_SV_BLACKBOXES:-0}" != "1" ]]; then
  is_filelist=0
  case "$sv_input" in
    *.f|*.svf|*.lst) is_filelist=1 ;;
  esac
  if [[ "$is_filelist" == "1" ]]; then
    sv_files=()
    while IFS= read -r line; do
      [[ -z "${line//[[:space:]]/}" ]] && continue
      [[ "${line#\#}" != "$line" ]] && continue
      [[ -f "$line" ]] || continue
      sv_files+=("$line")
    done <"$sv_input"
  else
    sv_files=("$sv_input")
  fi
  if [[ "${#sv_files[@]}" -eq 0 ]]; then
    echo "[run_pipeline] ERROR: no SV files found for blackbox check." >&2
    exit 1
  fi
  if command -v rg >/dev/null 2>&1; then
    blackbox_pattern='\(\*\s*blackbox\s*\*\)'
    if rg -n "$blackbox_pattern" "${sv_files[@]}" >/dev/null; then
      echo "[run_pipeline] ERROR: SV contains blackbox attributes." >&2
      rg -n "$blackbox_pattern" "${sv_files[@]}" | sed -n '1,80p' >&2
      exit 1
    fi
  else
    if grep -nE '\(\*[[:space:]]*blackbox[[:space:]]*\*\)' "${sv_files[@]}" >/dev/null; then
      echo "[run_pipeline] ERROR: SV contains blackbox attributes." >&2
      grep -nE '\(\*[[:space:]]*blackbox[[:space:]]*\*\)' "${sv_files[@]}" | sed -n '1,80p' >&2
      exit 1
    fi
  fi
fi

"$SCRIPT_DIR/sv_to_il.sh" "$sv_input" "$il"
"$SCRIPT_DIR/sv_to_yosys_stat.sh" "$sv_input" "$yosys_stat"

echo "done: $out_dir"
