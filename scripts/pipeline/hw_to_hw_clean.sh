#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

require_env CIRCT_OPT
input="${1:?usage: hw_to_hw_clean.sh <input-hw-mlir> <output-hw-clean-mlir>}"
output="${2:?usage: hw_to_hw_clean.sh <input-hw-mlir> <output-hw-clean-mlir>}"
require_file "$input"

run_to_output "$output" "$CIRCT_OPT" "$input" \
  -firrtl-inner-symbol-dce \
  -symbol-dce \
  -canonicalize \
  -cse
