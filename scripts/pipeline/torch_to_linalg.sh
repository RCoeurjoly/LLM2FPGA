#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

torch_mlir_opt="${1:?usage: torch_to_linalg.sh <torch-mlir-opt> <input-torch-mlir> <output-linalg-mlir>}"
input="${2:?usage: torch_to_linalg.sh <torch-mlir-opt> <input-torch-mlir> <output-linalg-mlir>}"
output="${3:?usage: torch_to_linalg.sh <torch-mlir-opt> <input-torch-mlir> <output-linalg-mlir>}"
require_executable "$torch_mlir_opt"
require_file "$input"

run_to_output "$output" "$torch_mlir_opt" "$input" \
  --torch-function-to-torch-backend-pipeline \
  --torch-backend-to-linalg-on-tensors-backend-pipeline \
  -canonicalize
