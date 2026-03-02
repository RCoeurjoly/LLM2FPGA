#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

require_env MLIR_OPT
input="${1:?usage: linalg_to_cf.sh <input-linalg-mlir> <output-cf-mlir>}"
output="${2:?usage: linalg_to_cf.sh <input-linalg-mlir> <output-cf-mlir>}"
require_file "$input"

lowering="${LINALG_LOWERING:-loops}"
lower_passes=()
case "$lowering" in
  loops)
    lower_passes+=( --convert-linalg-to-loops )
    ;;
  affine)
    lower_passes+=( --convert-linalg-to-affine-loops --lower-affine )
    ;;
  *)
    echo "invalid LINALG_LOWERING='$lowering' (expected: loops|affine)" >&2
    exit 2
    ;;
esac

run_to_output "$output" "$MLIR_OPT" "$input" \
  --empty-tensor-to-alloc-tensor \
  --one-shot-bufferize="bufferize-function-boundaries" \
  --buffer-results-to-out-params \
  --bufferization-lower-deallocations \
  --convert-bufferization-to-memref \
  --memref-expand \
  -canonicalize \
  -cse \
  "${lower_passes[@]}" \
  --convert-scf-to-cf \
  -canonicalize \
  -cse
