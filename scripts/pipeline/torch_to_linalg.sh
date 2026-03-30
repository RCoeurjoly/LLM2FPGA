#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
  echo "usage: torch_to_linalg.sh [<torch-mlir-opt>] <input-torch-mlir> <output-linalg-mlir>" >&2
  echo "or set TORCH_MLIR_OPT and call: torch_to_linalg.sh <input-torch-mlir> <output-linalg-mlir>" >&2
  exit 1
}

if [ "$#" -eq 3 ]; then
  torch_mlir_opt="$1"
  input="$2"
  output="$3"
elif [ "$#" -eq 2 ]; then
  torch_mlir_opt="${TORCH_MLIR_OPT:-}"
  input="$1"
  output="$2"
  [ -n "$torch_mlir_opt" ] || usage
else
  usage
fi

require_executable "$torch_mlir_opt"
require_file "$input"

run_to_output "$output" "$torch_mlir_opt" "$input" \
  --torch-function-to-torch-backend-pipeline \
  --torch-backend-to-linalg-on-tensors-backend-pipeline \
  -canonicalize
