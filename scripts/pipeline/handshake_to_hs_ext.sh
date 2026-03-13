#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

require_env CIRCT_OPT
input="${1:?usage: handshake_to_hs_ext.sh <input-handshake-mlir> <output-hs-ext-mlir>}"
output="${2:?usage: handshake_to_hs_ext.sh <input-handshake-mlir> <output-hs-ext-mlir>}"
require_file "$input"

run_to_output "$output" "$CIRCT_OPT" "$input" \
  -handshake-lower-extmem-to-hw \
  -handshake-materialize-forks-sinks \
  -canonicalize \
  -cse
