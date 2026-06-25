#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

circt_opt="${1:?usage: sv_mlir_to_sv.sh <circt-opt> <input-sv-mlir-dir> <output-dir>}"
input_dir="${2:?usage: sv_mlir_to_sv.sh <circt-opt> <input-sv-mlir-dir> <output-dir>}"
output_dir="${3:?usage: sv_mlir_to_sv.sh <circt-opt> <input-sv-mlir-dir> <output-dir>}"
input="$input_dir/model.sv.mlir"
externs="$input_dir/hw_externs.txt"
require_executable "$circt_opt"
require_file "$input"
require_file "$externs"

tmp_missing="$(mktemp /tmp/sv_mlir_to_sv_missing_XXXXXX.txt)"
cleanup_tmp() {
  rm -f "$tmp_missing"
}
trap cleanup_tmp EXIT

run_circt_stage() {
  local stage="$1"
  shift
  local -a cmd=( "$@" )
  local rc=0

  local limit_kb="${CIRCT_EXPORT_SV_MEM_LIMIT_KB:-${CIRCT_LOWER_SV_MEM_LIMIT_KB:-}}"
  if [[ -n "$limit_kb" ]]; then
    if [[ ! "$limit_kb" =~ ^[0-9]+$ ]]; then
      echo "[sv_mlir_to_sv] ERROR: CIRCT_EXPORT_SV_MEM_LIMIT_KB must be a decimal number of KiB." >&2
      exit 2
    fi
    ulimit -v "$limit_kb"
  fi

  echo "[sv_mlir_to_sv] running $stage" >&2
  set +e
  "${cmd[@]}"
  rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    if [[ "$rc" -eq 137 || "$rc" -eq 9 ]]; then
      echo "[sv_mlir_to_sv] ERROR: circt-opt was killed during $stage (exit $rc)." >&2
      echo "[sv_mlir_to_sv] This usually indicates OOM pressure in this step." >&2
      if [[ -z "$limit_kb" ]]; then
        echo "[sv_mlir_to_sv] Optional debug/retry knob: set CIRCT_EXPORT_SV_MEM_LIMIT_KB to the process KiB limit." >&2
      fi
    fi
    exit "$rc"
  fi
}

run_circt_stage_to_file() {
  local stage="$1"
  local stdout_file="$2"
  shift 2
  local -a cmd=( "$@" )
  local rc=0

  local limit_kb="${CIRCT_EXPORT_SV_MEM_LIMIT_KB:-${CIRCT_LOWER_SV_MEM_LIMIT_KB:-}}"
  if [[ -n "$limit_kb" ]]; then
    if [[ ! "$limit_kb" =~ ^[0-9]+$ ]]; then
      echo "[sv_mlir_to_sv] ERROR: CIRCT_EXPORT_SV_MEM_LIMIT_KB must be a decimal number of KiB." >&2
      exit 2
    fi
    ulimit -v "$limit_kb"
  fi

  echo "[sv_mlir_to_sv] running $stage" >&2
  set +e
  "${cmd[@]}" >"$stdout_file"
  rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    if [[ "$rc" -eq 137 || "$rc" -eq 9 ]]; then
      echo "[sv_mlir_to_sv] ERROR: circt-opt was killed during $stage (exit $rc)." >&2
      echo "[sv_mlir_to_sv] This usually indicates OOM pressure in this step." >&2
      if [[ -z "$limit_kb" ]]; then
        echo "[sv_mlir_to_sv] Optional debug/retry knob: set CIRCT_EXPORT_SV_MEM_LIMIT_KB to the process KiB limit." >&2
      fi
    fi
    exit "$rc"
  fi
}

if [[ -s "$externs" ]]; then
  if [[ "${ALLOW_HW_EXTERNS:-0}" != "1" ]]; then
    echo "[sv_mlir_to_sv] ERROR: extern modules found in '$input_dir'." >&2
    echo "[sv_mlir_to_sv] Eliminate hw.module.extern before SV export." >&2
    cat "$externs" >&2
    exit 1
  fi

  if [[ -z "${FP_PRIMS_SV:-}" ]]; then
    echo "[sv_mlir_to_sv] ERROR: ALLOW_HW_EXTERNS=1 requires FP_PRIMS_SV." >&2
    echo "[sv_mlir_to_sv] Missing implementations for these externs:" >&2
    cat "$externs" >&2
    exit 1
  fi
  require_file "$FP_PRIMS_SV"

  : >"$tmp_missing"
  while IFS= read -r mod; do
    has_impl_cmd=(
      grep -nE
      '(^module[[:space:]]+'"${mod}"'\b|^`[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\([[:space:]]*'"${mod}"'\b)'
      "$FP_PRIMS_SV"
    )
    if ! "${has_impl_cmd[@]}" >/dev/null 2>&1; then
      echo "$mod" >>"$tmp_missing"
    fi
  done <"$externs"
  if [[ -s "$tmp_missing" ]]; then
    echo "[sv_mlir_to_sv] ERROR: FP_PRIMS_SV does not define all extern modules." >&2
    cat "$tmp_missing" >&2
    exit 1
  fi
fi

mkdir -p "$output_dir/sv"
case "${CIRCT_SV_EXPORT_MODE:-single}" in
  single)
    strip_suffix="${CIRCT_STRIP_DEBUGINFO_SUFFIX:-.mlir}"
    run_circt_stage_to_file export-verilog "$output_dir/sv/main.sv" \
      "$circt_opt" "$input" \
      --strip-debuginfo-with-pred="drop-suffix=$strip_suffix" \
      --export-verilog \
      -o /dev/null
    ;;
  split)
    run_circt_stage export-split-verilog \
      "$circt_opt" "$input" \
      --export-split-verilog="dir-name=$output_dir/sv" \
      -o /dev/null
    ;;
  *)
    echo "[sv_mlir_to_sv] ERROR: CIRCT_SV_EXPORT_MODE must be 'single' or 'split'." >&2
    exit 2
    ;;
esac

require_file "$output_dir/sv/main.sv"

find "$output_dir/sv" -type f -name '*.sv' | sort >"$output_dir/sources.f"

if [[ -s "$externs" ]]; then
  fp_sv="$output_dir/sv/zz_circt_fp_primitives.sv"
  cp "$FP_PRIMS_SV" "$fp_sv"
  printf '%s\n' "$fp_sv" >>"$output_dir/sources.f"
fi
