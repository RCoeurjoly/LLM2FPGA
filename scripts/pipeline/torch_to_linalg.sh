#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

require_env TORCH_MLIR_OPT
input="${1:?usage: torch_to_linalg.sh <input-torch-mlir> <output-linalg-mlir>}"
output="${2:?usage: torch_to_linalg.sh <input-torch-mlir> <output-linalg-mlir>}"
require_file "$input"

run_to_output "$output" "$TORCH_MLIR_OPT" "$input" \
  --torch-function-to-torch-backend-pipeline \
  --torch-backend-to-linalg-on-tensors-backend-pipeline \
  -canonicalize
