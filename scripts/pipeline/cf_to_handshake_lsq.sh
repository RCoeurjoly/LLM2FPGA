#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

circt_opt="${1:?usage: cf_to_handshake_lsq.sh <circt-opt> <mlir-opt> <input-cf-mlir> <output-handshake-mlir>}"
mlir_opt="${2:?usage: cf_to_handshake_lsq.sh <circt-opt> <mlir-opt> <input-cf-mlir> <output-handshake-mlir>}"
input="${3:?usage: cf_to_handshake_lsq.sh <circt-opt> <mlir-opt> <input-cf-mlir> <output-handshake-mlir>}"
output="${4:?usage: cf_to_handshake_lsq.sh <circt-opt> <mlir-opt> <input-cf-mlir> <output-handshake-mlir>}"
require_executable "$circt_opt"
require_executable "$mlir_opt"
require_file "$input"

tmp_legal="$(mktemp /tmp/cf_to_handshake_lsq_legal_XXXXXX.mlir)"
tmp_norm="$(mktemp /tmp/cf_to_handshake_lsq_norm_XXXXXX.mlir)"
trap 'rm -f "$tmp_legal" "$tmp_norm"' EXIT

"$circt_opt" "$input" \
  -flatten-memref \
  -flatten-memref-calls \
  -canonicalize \
  -cse \
  -handshake-legalize-memrefs \
  -canonicalize \
  -cse >"$tmp_legal"

"$mlir_opt" "$tmp_legal" \
  -convert-scf-to-cf \
  -canonicalize \
  -cse >"$tmp_norm"

run_to_output "$output" "$circt_opt" "$tmp_norm" \
  --lower-cf-to-handshake=lsq \
  -handshake-insert-buffers \
  -canonicalize \
  -cse
