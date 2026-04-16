#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

mlir_opt="${1:?usage: linalg_to_cf.sh <mlir-opt> <input-linalg-mlir> <output-cf-mlir>}"
input="${2:?usage: linalg_to_cf.sh <mlir-opt> <input-linalg-mlir> <output-cf-mlir>}"
output="${3:?usage: linalg_to_cf.sh <mlir-opt> <input-linalg-mlir> <output-cf-mlir>}"
require_executable "$mlir_opt"
require_file "$input"

run_to_output "$output" "$mlir_opt" "$input" \
  --empty-tensor-to-alloc-tensor \
  --one-shot-bufferize="bufferize-function-boundaries" \
  --buffer-results-to-out-params \
  --bufferization-lower-deallocations \
  --convert-bufferization-to-memref \
  --memref-expand \
  -canonicalize \
  -cse \
  --convert-linalg-to-loops \
  --convert-scf-to-cf \
  -canonicalize \
  -cse
