#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

circt_opt="${1:?usage: handshake_to_hs_ext.sh <circt-opt> <input-handshake-mlir> <output-hs-ext-mlir>}"
input="${2:?usage: handshake_to_hs_ext.sh <circt-opt> <input-handshake-mlir> <output-hs-ext-mlir>}"
output="${3:?usage: handshake_to_hs_ext.sh <circt-opt> <input-handshake-mlir> <output-hs-ext-mlir>}"
require_executable "$circt_opt"
require_file "$input"

run_to_output "$output" "$circt_opt" "$input" \
  -handshake-lower-extmem-to-hw \
  -handshake-materialize-forks-sinks \
  -canonicalize \
  -cse
