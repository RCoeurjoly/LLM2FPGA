#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

require_env MLIR_OPT
input="${1:?usage: linalg_to_cf.sh <input-linalg-mlir> <output-cf-mlir>}"
output="${2:?usage: linalg_to_cf.sh <input-linalg-mlir> <output-cf-mlir>}"
require_file "$input"

lowering="${LINALG_LOWERING:-loops}"
lower_passes=()
case "$lowering" in
  loops)
    lower_passes+=( --convert-linalg-to-loops )
    ;;
  affine)
    lower_passes+=( --convert-linalg-to-affine-loops --lower-affine )
    ;;
  *)
    echo "invalid LINALG_LOWERING='$lowering' (expected: loops|affine)" >&2
    exit 2
    ;;
esac

run_to_output "$output" "$MLIR_OPT" "$input" \
  --empty-tensor-to-alloc-tensor \
  --one-shot-bufferize="bufferize-function-boundaries" \
  --buffer-results-to-out-params \
  --bufferization-lower-deallocations \
  --convert-bufferization-to-memref \
  --memref-expand \
  -canonicalize \
  -cse \
  "${lower_passes[@]}" \
  --convert-scf-to-cf \
  -canonicalize \
  -cse

# Optional gate for quantized flows: reject CF IR that still contains float/math
# operations. This enforces a true integer pipeline before CIRCT handoff.
if [[ "${CF_REQUIRE_NO_FLOAT:-0}" == "1" ]]; then
  if grep -nE 'arith\.[A-Za-z0-9_]*f[A-Za-z0-9_]*|math\.[A-Za-z0-9_]+' "$output" >/dev/null; then
    echo "[linalg_to_cf] ERROR: float/math ops detected in CF output '$output'." >&2
    echo "[linalg_to_cf] This model is configured with CF_REQUIRE_NO_FLOAT=1." >&2
    echo "[linalg_to_cf] Top offending ops (count op):" >&2
    grep -Eo 'arith\.[A-Za-z0-9_]+|math\.[A-Za-z0-9_]+' "$output" \
      | awk '/^math\./ { print; next } /^arith\./ { if ($0 ~ /f/) print }' \
      | sort | uniq -c | sort -nr | sed -n '1,40p' >&2
    echo "[linalg_to_cf] First offending lines:" >&2
    grep -nE 'arith\.[A-Za-z0-9_]*f[A-Za-z0-9_]*|math\.[A-Za-z0-9_]+' "$output" \
      | sed -n '1,80p' >&2
    exit 1
  fi
fi
