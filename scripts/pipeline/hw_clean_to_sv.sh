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
cleanup_tmp() {
  rm -f "$tmp_externs" "$tmp_missing"
}
trap cleanup_tmp EXIT

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
    if command -v rg >/dev/null 2>&1; then
      has_impl_cmd=(rg -n "^module[[:space:]]+${mod}\\b" "$FP_PRIMS_SV")
    else
      has_impl_cmd=(grep -nE "^module[[:space:]]+${mod}\\b" "$FP_PRIMS_SV")
    fi
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
"$circt_opt" "$input" \
  -lower-seq-hlmem \
  -lower-seq-fifo \
  -lower-seq-shiftreg \
  -lower-seq-to-sv \
  -canonicalize \
  -cse \
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
