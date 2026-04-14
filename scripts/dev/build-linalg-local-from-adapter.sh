#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

usage() {
  echo "usage: build-linalg-local-from-adapter.sh <adapter.py> [output-linalg-mlir]" >&2
  echo "set PYTHON_BIN to a torch/torchao-capable interpreter" >&2
  echo "set TORCH_MLIR_PYTHONPATH to a torch_mlir Python package path" >&2
  echo "set TORCH_MLIR_OPT to override the local torch-mlir-opt path" >&2
  echo "set MODEL_PATH for adapters that require --model-path" >&2
  exit 1
}

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  usage
fi

adapter="$1"
output="${2:-/tmp/$(basename "$adapter" .py)-local-linalg.mlir}"
raw_output="${output%.mlir}-raw.mlir"

python_bin="${PYTHON_BIN:-/nix/store/y47zygpwmnwrif1jdrk9hvv4mxr4g2a8-python3-3.11.14-env/bin/python}"
nix_torch_mlir_pythonpath="/nix/store/yx9r50wrmybslj058jdnh8l8g0x0xyyj-torch-mlir-0-unstable-2026-02-12/python-packages/torch_mlir"
local_torch_mlir_pythonpath="/home/roland/torch-mlir/python"
default_torch_mlir_pythonpath="$nix_torch_mlir_pythonpath"
if [ -d "$local_torch_mlir_pythonpath" ]; then
  default_torch_mlir_pythonpath="$local_torch_mlir_pythonpath:$nix_torch_mlir_pythonpath"
fi
torch_mlir_pythonpath="${TORCH_MLIR_PYTHONPATH:-$default_torch_mlir_pythonpath}"
torch_mlir_opt="${TORCH_MLIR_OPT:-/home/roland/torch-mlir/build-local-devshell-2/bin/torch-mlir-opt}"

[ -x "$python_bin" ] || { echo "python not found: $python_bin" >&2; exit 1; }
[ -x "$torch_mlir_opt" ] || { echo "torch-mlir-opt not found: $torch_mlir_opt" >&2; exit 1; }
[ -f "$adapter" ] || { echo "adapter not found: $adapter" >&2; exit 1; }

mkdir -p "$(dirname "$output")"

compile_args=(
  "$REPO_ROOT/scripts/compile-pytorch.py"
  --adapter "$adapter"
  --output-type raw
  --out "$raw_output"
)

if [ -n "${MODEL_PATH:-}" ]; then
  compile_args+=(--model-path "$MODEL_PATH")
fi

PYTHONPATH="$torch_mlir_pythonpath${PYTHONPATH:+:$PYTHONPATH}" \
  "$python_bin" "${compile_args[@]}" >/dev/null

"$torch_mlir_opt" "$raw_output" \
  --torch-match-quantized-custom-ops \
  --torch-fuse-quantized-ops \
  --torchdynamo-export-to-torch-backend-pipeline \
  --torch-function-to-torch-backend-pipeline \
  --torch-backend-to-linalg-on-tensors-backend-pipeline \
  -canonicalize >"$output"

echo "$output"
