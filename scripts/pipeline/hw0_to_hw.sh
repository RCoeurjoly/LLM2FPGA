#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

circt_opt="${1:?usage: hw0_to_hw.sh <circt-opt> <input-hw0-mlir> <output-hw-mlir>}"
input="${2:?usage: hw0_to_hw.sh <circt-opt> <input-hw0-mlir> <output-hw-mlir>}"
output="${3:?usage: hw0_to_hw.sh <circt-opt> <input-hw0-mlir> <output-hw-mlir>}"
require_executable "$circt_opt"
require_file "$input"

run_to_output "$output" "$circt_opt" "$input" \
  -lower-esi-types \
  -lower-esi-ports \
  -lower-esi-to-hw \
  -canonicalize
