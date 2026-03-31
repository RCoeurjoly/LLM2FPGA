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
