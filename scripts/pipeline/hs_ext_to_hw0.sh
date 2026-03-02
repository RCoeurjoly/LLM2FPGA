#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

require_env CIRCT_OPT
input="${1:?usage: hs_ext_to_hw0.sh <input-hs-ext-mlir> <output-hw0-mlir>}"
output="${2:?usage: hs_ext_to_hw0.sh <input-hs-ext-mlir> <output-hw0-mlir>}"
require_file "$input"

run_to_output "$output" "$CIRCT_OPT" "$input" \
  -lower-handshake-to-hw \
  -canonicalize
