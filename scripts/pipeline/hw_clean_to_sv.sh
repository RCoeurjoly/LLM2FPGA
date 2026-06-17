#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

circt_opt="${1:?usage: hw_clean_to_sv.sh <circt-opt> <input-hw-clean-mlir> <output-dir>}"
input="${2:?usage: hw_clean_to_sv.sh <circt-opt> <input-hw-clean-mlir> <output-dir>}"
output_dir="${3:?usage: hw_clean_to_sv.sh <circt-opt> <input-hw-clean-mlir> <output-dir>}"
require_executable "$circt_opt"
require_file "$input"

tmp_externs="$(mktemp /tmp/hw_clean_to_sv_externs_XXXXXX.txt)"
tmp_missing="$(mktemp /tmp/hw_clean_to_sv_missing_XXXXXX.txt)"
tmp_mlir="$(mktemp /tmp/hw_clean_to_sv_mlir_XXXXXX.mlir)"
tmp_mlir_clean="$(mktemp /tmp/hw_clean_to_sv_mlir_clean_XXXXXX.mlir)"
cleanup_tmp() {
  rm -f "$tmp_externs" "$tmp_missing" "$tmp_mlir" "$tmp_mlir_clean"
}
trap cleanup_tmp EXIT

run_circt() {
  local -a cmd=( "$@" )
  local rc=0

  local limit_kb="${CIRCT_LOWER_SV_MEM_LIMIT_KB:-}"
  if [[ -n "$limit_kb" ]]; then
    if [[ ! "$limit_kb" =~ ^[0-9]+$ ]]; then
      echo "[hw_clean_to_sv] ERROR: CIRCT_LOWER_SV_MEM_LIMIT_KB must be a decimal number of KiB." >&2
      exit 2
    fi
    ulimit -v "$limit_kb"
  fi

  set +e
  "${cmd[@]}"
  rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    if [[ "$rc" -eq 137 || "$rc" -eq 9 ]]; then
      echo "[hw_clean_to_sv] ERROR: circt-opt was killed while exporting split SV (exit $rc)." >&2
      echo "[hw_clean_to_sv] This usually indicates OOM pressure in this step." >&2
      echo "[hw_clean_to_sv] Try rebuilding on a higher-memory machine or on a host with fewer concurrent builds." >&2
      if [[ -z "$limit_kb" ]]; then
        echo "[hw_clean_to_sv] Optional debug/retry knob: set CIRCT_LOWER_SV_MEM_LIMIT_KB to the process'"'"'s KiB limit." >&2
      fi
    fi
    exit "$rc"
  fi
}

if command -v rg >/dev/null 2>&1; then
  rg -No 'hw\.module\.extern\s+@([A-Za-z_][A-Za-z0-9_]*)' "$input" \
    | sed -E 's/.*@([A-Za-z_][A-Za-z0-9_]*).*/\1/' \
    | sort -u >"$tmp_externs" || true
else
  grep -oE 'hw\.module\.extern[[:space:]]+@([A-Za-z_][A-Za-z0-9_]*)' "$input" \
    | sed -E 's/.*@([A-Za-z_][A-Za-z0-9_]*).*/\1/' \
    | sort -u >"$tmp_externs" || true
fi

if [[ -s "$tmp_externs" ]]; then
  if [[ "${ALLOW_HW_EXTERNS:-0}" != "1" ]]; then
    echo "[hw_clean_to_sv] ERROR: extern modules found in '$input'." >&2
    echo "[hw_clean_to_sv] Eliminate hw.module.extern before SV export." >&2
    cat "$tmp_externs" >&2
    exit 1
  fi

  if [[ -z "${FP_PRIMS_SV:-}" ]]; then
    echo "[hw_clean_to_sv] ERROR: ALLOW_HW_EXTERNS=1 requires FP_PRIMS_SV." >&2
    echo "[hw_clean_to_sv] Missing implementations for these externs:" >&2
    cat "$tmp_externs" >&2
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
  done <"$tmp_externs"
  if [[ -s "$tmp_missing" ]]; then
    echo "[hw_clean_to_sv] ERROR: FP_PRIMS_SV does not define all extern modules." >&2
    cat "$tmp_missing" >&2
    exit 1
  fi
fi

mkdir -p "$output_dir/sv"
run_circt \
  "$circt_opt" "$input" \
  -lower-seq-hlmem \
  -lower-seq-fifo \
  -lower-seq-shiftreg \
  -canonicalize \
  -cse \
  -o "$tmp_mlir"

run_to_output "$tmp_mlir_clean" "$circt_opt" "$tmp_mlir" \
  -lower-seq-to-sv \
  -lower-hw-to-sv \
  -canonicalize \
  -cse \
  --export-split-verilog="dir-name=$output_dir/sv" \
  -o /dev/null

require_file "$output_dir/sv/main.sv"

find "$output_dir/sv" -type f -name '*.sv' | sort >"$output_dir/sources.f"

if [[ -s "$tmp_externs" ]]; then
  fp_sv="$output_dir/sv/zz_circt_fp_primitives.sv"
  cp "$FP_PRIMS_SV" "$fp_sv"
  printf '%s\n' "$fp_sv" >>"$output_dir/sources.f"
fi
