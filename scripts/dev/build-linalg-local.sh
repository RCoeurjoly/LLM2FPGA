#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

usage() {
  echo "usage: build-linalg-local.sh <model-name> [output-linalg-mlir]" >&2
  echo "example: build-linalg-local.sh pt2e-static-quant-embedding-composable /tmp/embed.mlir" >&2
  echo "set TORCH_MLIR_OPT to override the local torch-mlir-opt path" >&2
  exit 1
}

default_torch_mlir_opt="/home/roland/torch-mlir/build-local-devshell-2/bin/torch-mlir-opt"
torch_mlir_opt="${TORCH_MLIR_OPT:-$default_torch_mlir_opt}"

[ "$#" -ge 1 ] && [ "$#" -le 2 ] || usage

model_name="$1"
output="${2:-/tmp/${model_name}-local-linalg.mlir}"

if [ ! -x "$torch_mlir_opt" ]; then
  echo "torch-mlir-opt not found or not executable: $torch_mlir_opt" >&2
  echo "build it locally and/or set TORCH_MLIR_OPT to the local executable path" >&2
  exit 1
fi

torch_artifact="$(cd "$REPO_ROOT" && nix build --print-out-paths --no-link ".#${model_name}-torch")"

mkdir -p "$(dirname "$output")"

TORCH_MLIR_OPT="$torch_mlir_opt" \
  "$REPO_ROOT/scripts/pipeline/torch_to_linalg.sh" \
  "$torch_artifact" \
  "$output"

echo "$output"
