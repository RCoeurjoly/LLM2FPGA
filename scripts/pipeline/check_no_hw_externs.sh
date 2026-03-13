#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
usage: check_no_hw_externs.sh <input-hw-clean-mlir>

Fails if the MLIR contains any `hw.module.extern` declarations.
USAGE
}

if [[ $# -ne 1 ]]; then
  usage >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

input="$1"
require_file "$input"

if [[ "${ALLOW_HW_EXTERNS:-0}" == "1" ]]; then
  echo "[check_no_hw_externs] ALLOW_HW_EXTERNS=1 set; skipping extern check." >&2
  exit 0
fi

tmp="$(mktemp /tmp/no_hw_externs_XXXXXX.txt)"
trap 'rm -f "$tmp"' EXIT

rg -No 'hw\.module\.extern\s+@([A-Za-z_][A-Za-z0-9_]*)' "$input" \
  | sed -E 's/.*@([A-Za-z_][A-Za-z0-9_]*).*/\1/' \
  | sort -u >"$tmp" || true

if [[ ! -s "$tmp" ]]; then
  echo "[check_no_hw_externs] passed: no hw.module.extern declarations found."
  exit 0
fi

echo "[check_no_hw_externs] ERROR: extern modules found in '$input'." >&2
echo "These must be eliminated for complete FPGA-realizable SV:" >&2
cat "$tmp" >&2
exit 1
