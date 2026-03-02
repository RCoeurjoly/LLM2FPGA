#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

require_env MLIR_OPT
input="${1:?usage: cf_stats.sh <input-cf-mlir> <output-stats>}"
output="${2:?usage: cf_stats.sh <input-cf-mlir> <output-stats>}"
require_file "$input"

"$MLIR_OPT" "$input" --print-op-stats -o /dev/null >"$output"
