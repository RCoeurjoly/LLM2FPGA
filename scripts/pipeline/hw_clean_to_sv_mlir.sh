#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

circt_opt="${1:?usage: hw_clean_to_sv_mlir.sh <circt-opt> <input-hw-clean-mlir> <output-dir>}"
input="${2:?usage: hw_clean_to_sv_mlir.sh <circt-opt> <input-hw-clean-mlir> <output-dir>}"
output_dir="${3:?usage: hw_clean_to_sv_mlir.sh <circt-opt> <input-hw-clean-mlir> <output-dir>}"
require_executable "$circt_opt"
require_file "$input"

tmp_seq_mlir="$(mktemp /tmp/hw_clean_to_sv_seq_XXXXXX.mlir)"
cleanup_tmp() {
  rm -f "$tmp_seq_mlir"
}
trap cleanup_tmp EXIT

run_circt_stage() {
  local stage="$1"
  shift
  local -a cmd=( "$@" )
  local rc=0

  local limit_kb="${CIRCT_LOWER_SV_MEM_LIMIT_KB:-}"
  if [[ -n "$limit_kb" ]]; then
    if [[ ! "$limit_kb" =~ ^[0-9]+$ ]]; then
      echo "[hw_clean_to_sv_mlir] ERROR: CIRCT_LOWER_SV_MEM_LIMIT_KB must be a decimal number of KiB." >&2
      exit 2
    fi
    ulimit -v "$limit_kb"
  fi

  echo "[hw_clean_to_sv_mlir] running $stage" >&2
  set +e
  "${cmd[@]}"
  rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    if [[ "$rc" -eq 137 || "$rc" -eq 9 ]]; then
      echo "[hw_clean_to_sv_mlir] ERROR: circt-opt was killed during $stage (exit $rc)." >&2
      echo "[hw_clean_to_sv_mlir] This usually indicates OOM pressure in this step." >&2
      if [[ -z "$limit_kb" ]]; then
        echo "[hw_clean_to_sv_mlir] Optional debug/retry knob: set CIRCT_LOWER_SV_MEM_LIMIT_KB to the process KiB limit." >&2
      fi
    fi
    exit "$rc"
  fi
}

mkdir -p "$output_dir"

if command -v rg >/dev/null 2>&1; then
  rg -No 'hw\.module\.extern\s+@([A-Za-z_][A-Za-z0-9_]*)' "$input" \
    | sed -E 's/.*@([A-Za-z_][A-Za-z0-9_]*).*/\1/' \
    | sort -u >"$output_dir/hw_externs.txt" || true
else
  grep -oE 'hw\.module\.extern[[:space:]]+@([A-Za-z_][A-Za-z0-9_]*)' "$input" \
    | sed -E 's/.*@([A-Za-z_][A-Za-z0-9_]*).*/\1/' \
    | sort -u >"$output_dir/hw_externs.txt" || true
fi

run_circt_stage lower-seq-storage \
  "$circt_opt" "$input" \
  -lower-seq-hlmem \
  -lower-seq-fifo \
  -lower-seq-shiftreg \
  -canonicalize \
  -cse \
  -o "$tmp_seq_mlir"

run_circt_stage lower-to-sv-dialect \
  "$circt_opt" "$tmp_seq_mlir" \
  -lower-seq-to-sv \
  -lower-hw-to-sv \
  -canonicalize \
  -cse \
  -o "$output_dir/model.sv.mlir"

require_file "$output_dir/model.sv.mlir"
