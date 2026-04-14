#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

mlir_opt="${1:?usage: cf_stats.sh <mlir-opt> <input-cf-mlir> <output-stats>}"
input="${2:?usage: cf_stats.sh <mlir-opt> <input-cf-mlir> <output-stats>}"
output="${3:?usage: cf_stats.sh <mlir-opt> <input-cf-mlir> <output-stats>}"
require_executable "$mlir_opt"
require_file "$input"

"$mlir_opt" "$input" --print-op-stats -o /dev/null >"$output"
