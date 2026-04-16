#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

circt_opt="${1:?usage: hs_ext_to_hw0.sh <circt-opt> <input-hs-ext-mlir> <output-hw0-mlir>}"
input="${2:?usage: hs_ext_to_hw0.sh <circt-opt> <input-hs-ext-mlir> <output-hw0-mlir>}"
output="${3:?usage: hs_ext_to_hw0.sh <circt-opt> <input-hs-ext-mlir> <output-hw0-mlir>}"
require_executable "$circt_opt"
require_file "$input"

run_to_output "$output" "$circt_opt" "$input" \
  -lower-handshake-to-hw \
  -canonicalize
