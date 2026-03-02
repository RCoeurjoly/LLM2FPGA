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
