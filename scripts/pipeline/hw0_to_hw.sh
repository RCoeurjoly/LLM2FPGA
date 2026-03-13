#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

require_env CIRCT_OPT
input="${1:?usage: hw0_to_hw.sh <input-hw0-mlir> <output-hw-mlir>}"
output="${2:?usage: hw0_to_hw.sh <input-hw0-mlir> <output-hw-mlir>}"
require_file "$input"

run_to_output "$output" "$CIRCT_OPT" "$input" \
  -lower-esi-types \
  -lower-esi-ports \
  -lower-esi-to-hw \
  -canonicalize
