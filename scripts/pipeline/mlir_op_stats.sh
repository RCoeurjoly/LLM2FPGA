#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

tool="${1:?usage: mlir_op_stats.sh <tool> <input-mlir> <output-stats>}"
input="${2:?usage: mlir_op_stats.sh <tool> <input-mlir> <output-stats>}"
output="${3:?usage: mlir_op_stats.sh <tool> <input-mlir> <output-stats>}"
require_executable "$tool"
require_file "$input"

"$tool" "$input" --print-op-stats -o /dev/null >"$output" 2>&1
