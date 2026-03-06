#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

require_env CIRCT_OPT
input="${1:?usage: hw_clean_to_sv.sh <input-hw-clean-mlir> <output-sv>}"
output="${2:?usage: hw_clean_to_sv.sh <input-hw-clean-mlir> <output-sv>}"
require_file "$input"

tmp_externs="$(mktemp /tmp/hw_clean_to_sv_externs_XXXXXX.txt)"
cleanup_tmp() {
  rm -f "$tmp_externs"
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
  # Default hard gate: extern modules are not allowed.
  if [[ "${ALLOW_HW_EXTERNS:-0}" != "1" ]]; then
    echo "[hw_clean_to_sv] ERROR: extern modules found in '$input'." >&2
    echo "[hw_clean_to_sv] Eliminate hw.module.extern before SV export." >&2
    cat "$tmp_externs" >&2
    exit 1
  fi

  # If externs are explicitly allowed, require a concrete implementation file
  # and verify that every extern module has a matching definition.
  if [[ -z "${FP_PRIMS_SV:-}" ]]; then
    echo "[hw_clean_to_sv] ERROR: ALLOW_HW_EXTERNS=1 requires FP_PRIMS_SV." >&2
    echo "[hw_clean_to_sv] Missing implementations for these externs:" >&2
    cat "$tmp_externs" >&2
    exit 1
  fi
  require_file "$FP_PRIMS_SV"

  tmp_missing="$(mktemp /tmp/hw_clean_to_sv_missing_XXXXXX.txt)"
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
    rm -f "$tmp_missing"
    exit 1
  fi
  rm -f "$tmp_missing"
fi

# Optional split-SV outputs to reduce frontend memory pressure.
# If SV_SPLIT_DIR is set, a second circt-opt invocation emits one module per
# file and a sorted filelist at SV_SPLIT_FILELIST (or <SV_SPLIT_DIR>/sources.f).
sv_split_dir="${SV_SPLIT_DIR:-}"
sv_split_filelist="${SV_SPLIT_FILELIST:-}"

common_passes=(
  -lower-seq-hlmem
  -lower-seq-fifo
  -lower-seq-shiftreg
  -lower-seq-to-sv
  -canonicalize
  -cse
  -lower-hw-to-sv
  -canonicalize
  -cse
)

"$CIRCT_OPT" "$input" \
  "${common_passes[@]}" \
  -export-verilog \
  -o /dev/null >"$output"

# When externs are allowed and covered, append their concrete implementations
# directly to the emitted SV to keep the artifact self-contained.
if [[ -s "$tmp_externs" ]]; then
  {
    echo ""
    echo "// ---- BEGIN LLM2FPGA FP primitive implementations ----"
    cat "$FP_PRIMS_SV"
    echo "// ---- END LLM2FPGA FP primitive implementations ----"
  } >>"$output"
fi

if [[ -n "$sv_split_dir" ]]; then
  mkdir -p "$sv_split_dir"
  "$CIRCT_OPT" "$input" \
    "${common_passes[@]}" \
    --export-split-verilog="dir-name=$sv_split_dir" \
    -o /dev/null

  if [[ -z "$sv_split_filelist" ]]; then
    sv_split_filelist="$sv_split_dir/sources.f"
  fi
  find "$sv_split_dir" -type f -name '*.sv' | sort >"$sv_split_filelist"
fi
