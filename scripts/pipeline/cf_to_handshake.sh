#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

require_env CIRCT_OPT
input="${1:?usage: cf_to_handshake.sh <input-cf-mlir> <output-handshake-mlir>}"
output="${2:?usage: cf_to_handshake.sh <input-cf-mlir> <output-handshake-mlir>}"
require_file "$input"

insert_buffers="${HANDSHAKE_INSERT_BUFFERS:-1}"
extra=()
if [[ "$insert_buffers" == "1" || "$insert_buffers" == "true" || "$insert_buffers" == "yes" ]]; then
  extra+=( -handshake-insert-buffers )
fi

tmp_legal="$(mktemp /tmp/cf_to_handshake_legal_XXXXXX.mlir)"
tmp_norm="$(mktemp /tmp/cf_to_handshake_norm_XXXXXX.mlir)"
cleanup_tmp() {
  rm -f "$tmp_legal" "$tmp_norm"
}
trap cleanup_tmp EXIT

# Stage 1: Lower to CF+memref form expected by handshake legalization.
run_to_output "$tmp_legal" "$CIRCT_OPT" "$input" \
  -flatten-memref \
  -flatten-memref-calls \
  -canonicalize \
  -cse \
  -handshake-legalize-memrefs \
  -canonicalize \
  -cse

# Stage 2: Normalize SCF to CF if MLIR_OPT is available.
# Some CIRCT builds reject scf.for that appears after memref legalization.
pre_input="$tmp_legal"
if [[ -n "${MLIR_OPT:-}" ]]; then
  run_to_output "$tmp_norm" "$MLIR_OPT" "$tmp_legal" \
    -convert-scf-to-cf \
    -canonicalize \
    -cse
  pre_input="$tmp_norm"
else
  echo "[warn] MLIR_OPT not set; skipping SCF-to-CF normalization" >&2
fi

# Stage 3: Lower normalized CF to Handshake.
run_to_output "$output" "$CIRCT_OPT" "$pre_input" \
  --lower-cf-to-handshake \
  "${extra[@]}" \
  -canonicalize \
  -cse
